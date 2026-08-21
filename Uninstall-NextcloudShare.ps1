[CmdletBinding()]
param(
    [switch]$RemoveUserData
)

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

function Test-UninstallIsInteractive {
    if (-not [Environment]::UserInteractive) { return $false }
    foreach ($arg in [Environment]::GetCommandLineArgs()) {
        if ($arg -like '-NonInteractive*' -or $arg -eq '-noni') { return $false }
    }
    try {
        if ([Console]::IsInputRedirected) { return $false }
    }
    catch {
        return $false
    }
    return $true
}

function Get-NextcloudShareUserDataDirectories {
    param([Microsoft.Win32.RegistryView]$RegistryView)

    $found = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'NextcloudShare'))
    }

    $localMachine = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $RegistryView)
    try {
        $profileList = $localMachine.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList')
        if ($null -ne $profileList) {
            try {
                foreach ($sid in $profileList.GetSubKeyNames()) {
                    if ($sid -match '^S-1-5-(18|19|20)$') { continue }
                    $profile = $profileList.OpenSubKey($sid)
                    if ($null -eq $profile) { continue }
                    try {
                        $profilePath = [Environment]::ExpandEnvironmentVariables([string]$profile.GetValue('ProfileImagePath', ''))
                        if ([string]::IsNullOrWhiteSpace($profilePath)) { continue }
                        if (-not (Test-Path -LiteralPath $profilePath -PathType Container)) { continue }
                        $candidates.Add((Join-Path $profilePath 'AppData\Local\NextcloudShare'))
                    }
                    finally {
                        $profile.Dispose()
                    }
                }
            }
            finally {
                $profileList.Dispose()
            }
        }
    }
    finally {
        $localMachine.Dispose()
    }

    foreach ($path in $candidates) {
        try {
            $full = [IO.Path]::GetFullPath($path)
        }
        catch {
            continue
        }
        if ($seen.Add($full) -and (Test-Path -LiteralPath $full)) {
            $found.Add($full)
        }
    }

    return $found
}

function Remove-NextcloudShareDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    catch {
        Write-UninstallLog "Verzeichnis konnte nicht sofort entfernt werden ($Path): $($_.Exception.Message)"
    }
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

$shouldRemoveUserData = $false
if ($PSBoundParameters.ContainsKey('RemoveUserData')) {
    $shouldRemoveUserData = [bool]$RemoveUserData
}
elseif (Test-UninstallIsInteractive) {
    Write-Host ''
    Write-Host 'NextcloudShare speichert Anmeldedaten und Protokolle je Benutzer unter:'
    Write-Host '  %LOCALAPPDATA%\NextcloudShare'
    Write-Host ''
    Write-Host 'Bei Ja werden diese Ordner in allen Benutzerprofilen auf diesem Computer gelöscht.'
    try {
        $answer = Read-Host 'Benutzerdaten ebenfalls entfernen? [J/N] (Standard: N)'
        $shouldRemoveUserData = $answer -match '^(j|ja|y|yes)$'
    }
    catch {
        Write-UninstallLog 'Keine interaktive Eingabe möglich; Benutzerdaten bleiben erhalten.'
        $shouldRemoveUserData = $false
    }
}

$userDataDirectories = @()
if ($shouldRemoveUserData) {
    $userDataDirectories = @(Get-NextcloudShareUserDataDirectories -RegistryView $registryView)
    Write-UninstallLog ("Benutzerdaten werden entfernt. Anzahl=$($userDataDirectories.Count)")
}
else {
    Write-UninstallLog 'Benutzerdaten unter %LOCALAPPDATA%\NextcloudShare bleiben erhalten.'
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

Write-UninstallLog 'Deinstallation erfolgreich abgeschlossen.'

Remove-NextcloudShareDirectory -Path $installDirectory
foreach ($userDataDirectory in $userDataDirectories) {
    Remove-NextcloudShareDirectory -Path $userDataDirectory
}
# ProgramData zuletzt löschen, damit das Uninstall-Protokoll noch geschrieben werden kann.
Remove-NextcloudShareDirectory -Path $dataDirectory

$remaining = @($installDirectory, $dataDirectory) + @($userDataDirectories)
$remaining = @($remaining | Where-Object { Test-Path -LiteralPath $_ })
if ($remaining.Count -gt 0) {
    # Das Skript liegt unter Program Files; Windows kann den Ordner erst nach Prozessende löschen.
    $quoted = ($remaining | ForEach-Object { 'rmdir /s /q "' + $_ + '"' }) -join ' & '
    Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/c timeout /t 3 /nobreak >nul & $quoted" -WindowStyle Hidden
}

exit 0
