[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Diagnostic,
    [string]$ConfigurationPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$productVersion = '2.0.0'
$activeSetupGuid = '{8A55C457-62A4-4ED5-90F3-884DA52DBF10}'
$programFilesRoot = if (-not [string]::IsNullOrWhiteSpace($env:ProgramW6432)) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installDirectory = Join-Path $programFilesRoot 'NextcloudShare'
$dataDirectory = Join-Path $env:ProgramData 'NextcloudShare'
$logPath = Join-Path $dataDirectory 'Install.log'
$files = @(
    'NextcloudShare.Core.psm1',
    'NextcloudShare.ps1',
    'NextcloudShare.vbs',
    'Configure-NextcloudShare.ps1',
    'Migrate-NextcloudShareUser.ps1',
    'Uninstall-NextcloudShare.ps1'
)
$optionalFiles = @(
    'NextcloudShare.config.example.json',
    'LICENSE',
    'README.md'
)
$registryView = if ([Environment]::Is64BitOperatingSystem) {
    [Microsoft.Win32.RegistryView]::Registry64
}
else {
    [Microsoft.Win32.RegistryView]::Registry32
}

function Write-InstallLog {
    param([string]$Message)

    try {
        if (-not (Test-Path -LiteralPath $dataDirectory)) {
            New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
        }
        [IO.File]::AppendAllText($logPath, "$(Get-Date -Format s) $Message`r`n", [Text.Encoding]::UTF8)
    }
    catch { }
    if ($Diagnostic) { Write-Host $Message }
}

function Test-CurrentInstallation {
    param([Parameter(Mandatory = $true)][Microsoft.Win32.RegistryKey]$RegistryRoot)

    if (-not (Test-Path -LiteralPath (Join-Path $installDirectory "installed-$productVersion") -PathType Leaf)) {
        Write-InstallLog 'Installationsprüfung: Versionsmarker fehlt.'
        return $false
    }
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath (Join-Path $installDirectory $file) -PathType Leaf)) {
            Write-InstallLog "Installationsprüfung: Datei '$file' fehlt."
            return $false
        }
    }

    $shortcutPath = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Nextcloud-Freigabe konfigurieren.lnk'
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        Write-InstallLog 'Installationsprüfung: Startmenü-Verknüpfung fehlt.'
        return $false
    }

    $productKey = $RegistryRoot.OpenSubKey('Software\NextcloudShare')
    if ($null -eq $productKey) {
        Write-InstallLog 'Installationsprüfung: Produkt-Registrierung fehlt.'
        return $false
    }
    try {
        if ([string]($productKey.GetValue('Version', '')) -ne $productVersion -or
            [string]($productKey.GetValue('InstallPath', '')) -ne $installDirectory) {
            Write-InstallLog 'Installationsprüfung: Produktversion oder Installationspfad stimmt nicht.'
            return $false
        }
    }
    finally {
        $productKey.Dispose()
    }

    foreach ($entry in @(
        @{ Name = 'NextcloudShare'; Mode = 'Quick' },
        @{ Name = 'NextcloudShareOptions'; Mode = 'Options' }
    )) {
        $verbKey = $RegistryRoot.OpenSubKey("Software\Classes\*\shell\$($entry.Name)")
        if ($null -eq $verbKey) {
            Write-InstallLog "Installationsprüfung: Explorer-Befehl '$($entry.Name)' fehlt."
            return $false
        }
        try {
            if ([string]($verbKey.GetValue('MultiSelectModel', '')) -ne 'Player') {
                Write-InstallLog "Installationsprüfung: Explorer-Befehl '$($entry.Name)' unterstützt keine Mehrfachauswahl."
                return $false
            }
            $commandKey = $verbKey.OpenSubKey('command')
            if ($null -eq $commandKey) {
                Write-InstallLog "Installationsprüfung: Explorer-Kommando '$($entry.Name)' fehlt."
                return $false
            }
            try {
                $command = [string]($commandKey.GetValue('', ''))
                if ($command.IndexOf((Join-Path $installDirectory 'NextcloudShare.vbs'), [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
                    $command.IndexOf([string]$entry.Mode, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    Write-InstallLog "Installationsprüfung: Explorer-Befehl '$($entry.Name)' ist veraltet."
                    return $false
                }
            }
            finally {
                $commandKey.Dispose()
            }
        }
        finally {
            $verbKey.Dispose()
        }
    }

    $activeSetup = $RegistryRoot.OpenSubKey("Software\Microsoft\Active Setup\Installed Components\$activeSetupGuid")
    if ($null -eq $activeSetup) {
        Write-InstallLog 'Installationsprüfung: Active-Setup-Eintrag fehlt.'
        return $false
    }
    try {
        if ([string]($activeSetup.GetValue('Version', '')) -ne '2,0,0,0') {
            Write-InstallLog 'Installationsprüfung: Active-Setup-Version ist veraltet.'
            return $false
        }
    }
    finally {
        $activeSetup.Dispose()
    }

    return $true
}

function Set-MachineShellVerb {
    param(
        [Parameter(Mandatory = $true)][Microsoft.Win32.RegistryKey]$RegistryRoot,
        [Parameter(Mandatory = $true)][string]$KeyName,
        [Parameter(Mandatory = $true)][string]$Caption,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $keyPath = "Software\Classes\*\shell\$KeyName"
    $key = $RegistryRoot.CreateSubKey($keyPath)
    if ($null -eq $key) { throw "Der Registry-Schlüssel '$keyPath' konnte nicht erstellt werden." }
    try {
        $key.SetValue('MUIVerb', $Caption, [Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('Icon', 'shell32.dll,167', [Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('MultiSelectModel', 'Player', [Microsoft.Win32.RegistryValueKind]::String)
        $commandKey = $key.CreateSubKey('command')
        if ($null -eq $commandKey) { throw 'Der Registry-Befehl konnte nicht erstellt werden.' }
        try {
            $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
            $launcherPath = Join-Path $installDirectory 'NextcloudShare.vbs'
            $command = '"{0}" "{1}" {2} "%1"' -f $wscriptPath, $launcherPath, $Mode
            $commandKey.SetValue('', $command, [Microsoft.Win32.RegistryValueKind]::String)
        }
        finally {
            $commandKey.Dispose()
        }
    }
    finally {
        $key.Dispose()
    }
}

trap {
    Write-InstallLog ("FEHLER: " + ($_ | Out-String).Trim())
    exit 1
}

Write-InstallLog "Installation $productVersion gestartet. Konto=$([Security.Principal.WindowsIdentity]::GetCurrent().Name); Quelle=$PSScriptRoot"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Die computerweite Installation muss als Administrator oder SYSTEM ausgeführt werden.'
}

$checkRoot = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $registryView)
try {
    $alreadyInstalled = (-not $Force) -and
        [string]::IsNullOrWhiteSpace($ConfigurationPath) -and
        (Test-CurrentInstallation -RegistryRoot $checkRoot)
}
finally {
    $checkRoot.Dispose()
}
if ($alreadyInstalled) {
    Write-InstallLog "Version $productVersion ist bereits vollständig installiert. Keine Änderungen erforderlich."
    exit 0
}

if ($Force) { Write-InstallLog 'Erzwungene Neuinstallation wurde angefordert.' }
else { Write-InstallLog 'Installation oder Reparatur ist erforderlich.' }

if (-not [string]::IsNullOrWhiteSpace($ConfigurationPath) -and
    -not (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf)) {
    throw "Die zentrale Konfigurationsdatei '$ConfigurationPath' wurde nicht gefunden."
}

foreach ($file in $files) {
    $source = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Die Installationsdatei '$file' fehlt in '$PSScriptRoot'."
    }
}

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
foreach ($file in ($files + $optionalFiles)) {
    $source = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        if ($optionalFiles -contains $file) {
            Write-InstallLog "Optionale Datei '$file' fehlt in '$PSScriptRoot' und wird übersprungen."
            continue
        }
        throw "Die Installationsdatei '$file' fehlt in '$PSScriptRoot'."
    }
    $destination = Join-Path $installDirectory $file
    if (-not [string]::Equals([IO.Path]::GetFullPath($source), [IO.Path]::GetFullPath($destination), [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
}

$localMachine = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $registryView)
try {
    Set-MachineShellVerb -RegistryRoot $localMachine -KeyName 'NextcloudShare' -Caption 'Über Nextcloud teilen' -Mode 'Quick'
    Set-MachineShellVerb -RegistryRoot $localMachine -KeyName 'NextcloudShareOptions' -Caption 'Über Nextcloud teilen (mit Optionen) ...' -Mode 'Options'

    $activeSetupPath = "Software\Microsoft\Active Setup\Installed Components\$activeSetupGuid"
    $activeSetup = $localMachine.CreateSubKey($activeSetupPath)
    if ($null -eq $activeSetup) { throw 'Der Active-Setup-Schlüssel konnte nicht erstellt werden.' }
    try {
        $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $migrationPath = Join-Path $installDirectory 'Migrate-NextcloudShareUser.ps1'
        $stubPath = '"{0}" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}"' -f $powershellPath, $migrationPath
        $activeSetup.SetValue('', 'NextcloudShare Benutzer-Migration', [Microsoft.Win32.RegistryValueKind]::String)
        $activeSetup.SetValue('Version', '2,0,0,0', [Microsoft.Win32.RegistryValueKind]::String)
        $activeSetup.SetValue('IsInstalled', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $activeSetup.SetValue('StubPath', $stubPath, [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally {
        $activeSetup.Dispose()
    }

    $productKey = $localMachine.CreateSubKey('Software\NextcloudShare')
    if ($null -eq $productKey) { throw 'Der Produkt-Registry-Schlüssel konnte nicht erstellt werden.' }
    try {
        $productKey.SetValue('Version', $productVersion, [Microsoft.Win32.RegistryValueKind]::String)
        $productKey.SetValue('InstallPath', $installDirectory, [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally {
        $productKey.Dispose()
    }
}
finally {
    $localMachine.Dispose()
}

if (-not [string]::IsNullOrWhiteSpace($ConfigurationPath)) {
    New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
    try {
        Get-Content -LiteralPath $ConfigurationPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
    }
    catch {
        throw "Die zentrale Konfigurationsdatei enthält kein gültiges JSON: $($_.Exception.Message)"
    }
    Copy-Item -LiteralPath $ConfigurationPath -Destination (Join-Path $dataDirectory 'NextcloudShare.config.json') -Force
    Write-InstallLog "Zentrale Konfiguration wurde übernommen: $ConfigurationPath"
}

$commonStartMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
New-Item -ItemType Directory -Path $commonStartMenu -Force | Out-Null
$shortcutPath = Join-Path $commonStartMenu 'Nextcloud-Freigabe konfigurieren.lnk'
$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershellPath
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -File "{0}"' -f (Join-Path $installDirectory 'Configure-NextcloudShare.ps1')
$shortcut.WorkingDirectory = $installDirectory
$shortcut.IconLocation = 'shell32.dll,167'
$shortcut.Save()

Get-ChildItem -LiteralPath $installDirectory -Filter 'installed-*' -File -ErrorAction SilentlyContinue | Remove-Item -Force
[void](New-Item -ItemType File -Path (Join-Path $installDirectory "installed-$productVersion") -Force)
Write-InstallLog "Installation $productVersion erfolgreich abgeschlossen. Ziel=$installDirectory"
exit 0
