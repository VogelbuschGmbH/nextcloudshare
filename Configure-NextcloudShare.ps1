Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'NextcloudShare.Core.psm1') -Force -DisableNameChecking

$logDirectory = Join-Path $env:LOCALAPPDATA 'NextcloudShare'
$logPath = Join-Path $logDirectory 'NextcloudShare.log'
function Write-ConfigurationLog {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }
        [IO.File]::AppendAllText($logPath, "$(Get-Date -Format s) Konfiguration: $Message`r`n", [Text.Encoding]::UTF8)
    }
    catch { }
}

try {
    Write-ConfigurationLog 'Dialog gestartet.'
    $saved = Show-ConfigurationDialog
    if ($saved) { Write-ConfigurationLog 'Erfolgreich gespeichert.' }
    else { Write-ConfigurationLog 'Ohne Änderung geschlossen.' }
}
catch {
    Write-ConfigurationLog ("FEHLER: " + ($_ | Out-String).Trim())
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Nextcloud-Freigabe – Fehler', 'OK', 'Error') | Out-Null
    exit 1
}
