[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$logDirectory = Join-Path $env:LOCALAPPDATA 'NextcloudShare'
$logPath = Join-Path $logDirectory 'NextcloudShare.log'
$adminConfigPath = Join-Path (Join-Path $env:ProgramData 'NextcloudShare') 'NextcloudShare.config.json'

function Write-MigrationLog {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }
        [IO.File]::AppendAllText($logPath, "$(Get-Date -Format s) Migration: $Message`r`n", [Text.Encoding]::UTF8)
    }
    catch { }
}

trap {
    Write-MigrationLog ("FEHLER: " + ($_ | Out-String).Trim())
    exit 1
}

Write-MigrationLog "Benutzermigration gestartet. Konto=$([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

if (Test-Path -LiteralPath $adminConfigPath -PathType Leaf) {
    $admin = Get-Content -LiteralPath $adminConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($admin.PSObject.Properties.Name -contains 'Migration') {
        $migration = $admin.Migration
        $legacySubpath = if ($migration.PSObject.Properties.Name -contains 'LegacyUserDataSubpath') {
            [string]$migration.LegacyUserDataSubpath
        } else { '' }
        $legacyFileName = if ($migration.PSObject.Properties.Name -contains 'LegacyConfigFileName') {
            [string]$migration.LegacyConfigFileName
        } else { 'config.json' }

        if (-not [string]::IsNullOrWhiteSpace($legacySubpath)) {
            $legacyDirectory = Join-Path $env:LOCALAPPDATA $legacySubpath
            $legacyConfig = Join-Path $legacyDirectory $legacyFileName
            $newConfig = Join-Path $logDirectory 'user.json'
            if ((Test-Path -LiteralPath $legacyConfig -PathType Leaf) -and
                -not (Test-Path -LiteralPath $newConfig -PathType Leaf)) {
                Copy-Item -LiteralPath $legacyConfig -Destination $newConfig -Force
                Write-MigrationLog 'Eine vorhandene Benutzerkonfiguration wurde übernommen.'
            }
        }

        if ($migration.PSObject.Properties.Name -contains 'LegacyShellKeys') {
            $currentUser = [Microsoft.Win32.Registry]::CurrentUser
            foreach ($keyName in @($migration.LegacyShellKeys)) {
                if ([string]::IsNullOrWhiteSpace([string]$keyName)) { continue }
                try { $currentUser.DeleteSubKeyTree("Software\Classes\*\shell\$keyName", $false) } catch { }
            }
        }
    }
}

$oldShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Nextcloud-Freigabe konfigurieren.lnk'
if (Test-Path -LiteralPath $oldShortcut) {
    Remove-Item -LiteralPath $oldShortcut -Force
}

Write-MigrationLog 'Benutzermigration erfolgreich abgeschlossen.'
exit 0
