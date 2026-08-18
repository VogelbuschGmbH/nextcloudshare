[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$activeSetupGuid = '{8A55C457-62A4-4ED5-90F3-884DA52DBF10}'
$programFilesRoot = if (-not [string]::IsNullOrWhiteSpace($env:ProgramW6432)) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installDirectory = Join-Path $programFilesRoot 'NextcloudShare'
$dataDirectory = Join-Path $env:ProgramData 'NextcloudShare'
$logPath = Join-Path $dataDirectory 'Uninstall.log'

function Write-UninstallLog {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $dataDirectory)) {
            New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
        }
        [IO.File]::AppendAllText($logPath, "$(Get-Date -Format s) $Message`r`n", [Text.Encoding]::UTF8)
    }
    catch { }
}

trap {
    Write-UninstallLog ("FEHLER: " + ($_ | Out-String).Trim())
    exit 1
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Die computerweite Deinstallation muss als Administrator oder SYSTEM ausgeführt werden.'
}

Write-UninstallLog "Deinstallation gestartet. Konto=$($identity.Name)"
$registryView = if ([Environment]::Is64BitOperatingSystem) {
    [Microsoft.Win32.RegistryView]::Registry64
}
else {
    [Microsoft.Win32.RegistryView]::Registry32
}
$localMachine = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $registryView)
try {
    foreach ($keyPath in @(
        'Software\Classes\*\shell\NextcloudShare',
        'Software\Classes\*\shell\NextcloudShareOptions',
        "Software\Microsoft\Active Setup\Installed Components\$activeSetupGuid",
        'Software\NextcloudShare'
    )) {
        try { $localMachine.DeleteSubKeyTree($keyPath, $false) } catch { }
    }
}
finally {
    $localMachine.Dispose()
}

$shortcutPath = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Nextcloud-Freigabe konfigurieren.lnk'
if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }

# Benutzerbezogene, DPAPI-geschützte Konfigurationen werden absichtlich nicht
# aus den Profilen entfernt. Sie können bei einer späteren Installation wiederverwendet werden.
if (Test-Path -LiteralPath $installDirectory) {
    try {
        Remove-Item -LiteralPath $installDirectory -Recurse -Force
    }
    catch {
        Write-UninstallLog "Programmverzeichnis konnte während der laufenden Deinstallation nicht vollständig entfernt werden: $($_.Exception.Message)"
    }
}

Write-UninstallLog 'Deinstallation erfolgreich abgeschlossen.'
exit 0
