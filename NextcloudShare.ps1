[CmdletBinding()]
param(
    [ValidateSet('Quick', 'Options', 'Configure')]
    [string]$Mode = 'Quick',
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$diagnosticDirectory = Join-Path $env:LOCALAPPDATA 'NextcloudShare'
$diagnosticLogPath = Join-Path $diagnosticDirectory 'NextcloudShare.log'
$logRotationChecked = $false

function Write-NextcloudShareLog {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $diagnosticDirectory)) {
            New-Item -ItemType Directory -Path $diagnosticDirectory -Force | Out-Null
        }
        if (-not $script:logRotationChecked) {
            $script:logRotationChecked = $true
            if ((Test-Path -LiteralPath $diagnosticLogPath -PathType Leaf) -and
                (Get-Item -LiteralPath $diagnosticLogPath).Length -gt 2097152) {
                $oldLogPath = $diagnosticLogPath + '.old'
                if (Test-Path -LiteralPath $oldLogPath) { Remove-Item -LiteralPath $oldLogPath -Force }
                Move-Item -LiteralPath $diagnosticLogPath -Destination $oldLogPath -Force
            }
        }
        [IO.File]::AppendAllText($diagnosticLogPath, "$(Get-Date -Format s) $Message`r`n", [Text.Encoding]::UTF8)
    }
    catch { }
}

function Join-NextcloudShareExplorerBatch {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$SelectedPath
    )

    if (-not (Test-Path -LiteralPath $diagnosticDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $diagnosticDirectory -Force | Out-Null
    }

    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $mutexName = "Local\NextcloudShare.Batch.$sid.$Mode"
    $batchPath = Join-Path $diagnosticDirectory ("ExplorerBatch-{0}.txt" -f $Mode)
    $mutex = [Threading.Mutex]::new($false, $mutexName)
    $ownsMutex = $false
    $isLeader = $false

    try {
        try { $ownsMutex = $mutex.WaitOne(5000) }
        catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { throw 'Die Mehrfachauswahl konnte nicht gesammelt werden. Bitte versuchen Sie es erneut.' }

        $useExistingBatch = $false
        if (Test-Path -LiteralPath $batchPath -PathType Leaf) {
            $age = [DateTime]::UtcNow - (Get-Item -LiteralPath $batchPath).LastWriteTimeUtc
            $useExistingBatch = $age.TotalSeconds -le 5
        }

        if ($useExistingBatch) {
            [IO.File]::AppendAllText($batchPath, $SelectedPath + "`r`n", [Text.Encoding]::UTF8)
        }
        else {
            [IO.File]::WriteAllText($batchPath, $SelectedPath + "`r`n", [Text.Encoding]::UTF8)
            $isLeader = $true
        }
    }
    finally {
        if ($ownsMutex) { $mutex.ReleaseMutex(); $ownsMutex = $false }
    }

    if (-not $isLeader) {
        $mutex.Dispose()
        return [pscustomobject]@{ IsLeader = $false; Paths = @() }
    }

    # Explorer startet Legacy-Verben je nach Windows-Version einmal oder mehrfach.
    # Das kurze Zeitfenster fasst die Aufrufe derselben Auswahl zu einem Vorgang zusammen.
    Start-Sleep -Milliseconds 700
    try {
        try { $ownsMutex = $mutex.WaitOne(5000) }
        catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { throw 'Die Mehrfachauswahl konnte nicht abgeschlossen werden. Bitte versuchen Sie es erneut.' }

        $collected = if (Test-Path -LiteralPath $batchPath -PathType Leaf) {
            @([IO.File]::ReadAllLines($batchPath, [Text.Encoding]::UTF8))
        }
        else { @($SelectedPath) }
        if (Test-Path -LiteralPath $batchPath -PathType Leaf) {
            Remove-Item -LiteralPath $batchPath -Force
        }
    }
    finally {
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $paths = New-Object 'Collections.Generic.List[string]'
    foreach ($candidate in $collected) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($seen.Add($candidate)) { $paths.Add($candidate) }
    }
    return [pscustomobject]@{ IsLeader = $true; Paths = [string[]]$paths.ToArray() }
}

try {
    Write-NextcloudShareLog "Start: Mode=$Mode"
    Import-Module (Join-Path $PSScriptRoot 'NextcloudShare.Core.psm1') -Force -DisableNameChecking
    Write-NextcloudShareLog 'Modul geladen.'
    if ($Mode -eq 'Configure') {
        Show-ConfigurationDialog | Out-Null
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Bitte wählen Sie mindestens eine Datei im Windows-Explorer aus.'
    }

    $batch = Join-NextcloudShareExplorerBatch -Mode $Mode -SelectedPath $Path
    if (-not $batch.IsLeader) {
        Write-NextcloudShareLog 'Explorer-Aufruf wurde einer Mehrfachauswahl hinzugefügt.'
        exit 0
    }
    [string[]]$paths = @($batch.Paths)
    foreach ($selectedPath in $paths) {
        if (-not (Test-Path -LiteralPath $selectedPath -PathType Leaf)) {
            throw "Die ausgewählte Datei ist nicht mehr verfügbar: $selectedPath"
        }
    }
    $itemCount = $paths.Count
    $itemDescription = if ($itemCount -eq 1) { [IO.Path]::GetFileName($paths[0]) } else { "$itemCount Dateien" }
    Write-NextcloudShareLog "Explorer-Auswahl gesammelt. Anzahl=$itemCount"

    $config = Get-NextcloudShareConfig
    $usesLoginFlow = $false
    if ($null -ne $config -and $config.PSObject.Properties.Name -contains 'AuthMethod') {
        $usesLoginFlow = ($config.AuthMethod -eq 'LoginFlowV2')
    }
    if ($null -eq $config -or -not $usesLoginFlow) {
        if (-not (Show-ConfigurationDialog)) { exit 1 }
        $config = Get-NextcloudShareConfig
    }
    Test-NextcloudShareConfig $config
    $config = Initialize-NextcloudWebDavIdentity -Config $config
    $hasLocalSync = -not [string]::IsNullOrWhiteSpace([string]$config.LocalNextcloudRoot)
    Write-NextcloudShareLog "Konfiguration geprüft. Server=$($config.ServerUrl); Modus=$($config.DefaultMode); Lokale Synchronisation=$hasLocalSync"

    $choice = if ($Mode -eq 'Options') {
        Write-NextcloudShareLog 'Optionsdialog wird geöffnet.'
        $optionsResult = Show-ShareOptionsDialog -Config $config -LocalPaths $paths
        Write-NextcloudShareLog "Optionsdialog geschlossen: Auswahl vorhanden=$($null -ne $optionsResult)"
        $optionsResult
    }
    else {
        [pscustomobject]@{ Mode = $config.DefaultMode; ExpiryDays = [int]$config.DefaultExpiryDays; Password = ''; Permissions = 1; NotificationEvents = 0 }
    }
    if ($null -eq $choice) { exit 0 }
    $sharePassword = [string]$choice.Password

    $progress = Show-ProgressWindow 'Verbindung mit Nextcloud wird hergestellt ...'
    $client = $null
    try {
        $client = New-NextcloudHttpClient $config
        if ($itemCount -gt 1) {
            Write-NextcloudShareLog 'Mehrfachauswahl wird in einen neuen Nextcloud-Ordner hochgeladen.'
            Set-ProgressText $progress 'Zielordner wird in Nextcloud angelegt ...'
            $remotePath = New-RemoteUploadBatchFolder -Client $client -Config $config
            for ($index = 0; $index -lt $itemCount; $index++) {
                $currentPath = $paths[$index]
                Set-ProgressText $progress ("Datei {0} von {1} wird hochgeladen ..." -f ($index + 1), $itemCount)
                $remoteFilePath = Get-UniqueRemotePathInFolder -Client $client -Config $config -RemoteFolder $remotePath -FileName ([IO.Path]::GetFileName($currentPath))
                Send-FileToNextcloud -Client $client -Config $config -LocalPath $currentPath -RemotePath $remoteFilePath
            }
            Write-NextcloudShareLog "Mehrfachupload erfolgreich abgeschlossen. Anzahl=$itemCount"
        }
        else {
            $remotePath = Get-RemotePathForLocalItem -Config $config -LocalPath $paths[0]
            if ($null -eq $remotePath) {
                Write-NextcloudShareLog 'Datei liegt außerhalb eines lokalen Syncordners und wird per WebDAV hochgeladen.'
                Set-ProgressText $progress 'Datei wird nach Nextcloud hochgeladen ...'
                $remotePath = Get-UniqueRemoteUploadPath -Client $client -Config $config -FileName ([IO.Path]::GetFileName($paths[0]))
                Send-FileToNextcloud -Client $client -Config $config -LocalPath $paths[0] -RemotePath $remotePath
                Write-NextcloudShareLog 'WebDAV-Upload erfolgreich abgeschlossen.'
            }
            else {
                Write-NextcloudShareLog 'Datei liegt in einem lokalen Syncordner; Serverdatei wird geprüft.'
                Set-ProgressText $progress 'Synchronisierte Datei wird geprüft ...'
                $found = $false
                for ($attempt = 0; $attempt -lt 6; $attempt++) {
                    if (Test-RemoteExists -Client $client -Config $config -RemotePath $remotePath) { $found = $true; break }
                    Start-Sleep -Milliseconds 500
                    [Windows.Forms.Application]::DoEvents()
                }
                if (-not $found) { throw 'Die Datei ist noch nicht auf dem Nextcloud-Server vorhanden. Bitte warten Sie auf die Synchronisierung und versuchen Sie es erneut.' }
            }
        }

        Set-ProgressText $progress 'Freigabelink wird erzeugt ...'
        Write-NextcloudShareLog "Freigabe wird erstellt. Typ=$($choice.Mode); AblaufTage=$($choice.ExpiryDays); Berechtigungen=$([int]$choice.Permissions); Benachrichtigungsmaske=$([int]$choice.NotificationEvents)"
        if ($choice.Mode -eq 'Internal') {
            $link = Get-InternalFileLink -Client $client -Config $config -RemotePath $remotePath
        }
        else {
            try {
                $publicShare = New-PublicShare -Client $client -Config $config -RemotePath $remotePath -ExpiryDays $choice.ExpiryDays -Password $sharePassword -Permissions ([int]$choice.Permissions)
            }
            catch {
                if ($_.Exception.Data['NextcloudShareError'] -ne 'PasswordRequired') { throw }
                if ($null -ne $progress) {
                    $progress.Close()
                    $progress.Dispose()
                    $progress = $null
                }
                $sharePassword = Show-RequiredSharePasswordDialog -ItemDescription $itemDescription
                if ([string]::IsNullOrWhiteSpace($sharePassword)) { exit 0 }
                $progress = Show-ProgressWindow 'Passwortgeschützter Freigabelink wird erzeugt ...'
                $publicShare = New-PublicShare -Client $client -Config $config -RemotePath $remotePath -ExpiryDays $choice.ExpiryDays -Password $sharePassword -Permissions ([int]$choice.Permissions)
            }
            $link = [string]$publicShare.Link

            if ([int]$choice.NotificationEvents -gt 0) {
                Set-ProgressText $progress 'E-Mail-Benachrichtigungen werden aktiviert ...'
                try {
                    Enable-PublicShareNotifications -Client $client -Config $config -ShareId ([string]$publicShare.ShareId) -EventMask ([int]$choice.NotificationEvents)
                    Write-NextcloudShareLog "E-Mail-Benachrichtigungen für die Freigabe aktiviert. Maske=$([int]$choice.NotificationEvents)"
                }
                catch {
                    $activationError = $_.Exception.Message
                    try {
                        Remove-PublicShare -Client $client -Config $config -ShareId ([string]$publicShare.ShareId)
                        Write-NextcloudShareLog 'Freigabe nach fehlgeschlagener Aktivierung der E-Mail-Benachrichtigungen zurückgenommen.'
                    }
                    catch {
                        throw "$activationError Die Freigabe konnte anschließend nicht automatisch zurückgenommen werden: $($_.Exception.Message)"
                    }
                    throw "$activationError Die unvollständige Freigabe wurde automatisch zurückgenommen."
                }
            }
        }
        Write-NextcloudShareLog 'Freigabelink erfolgreich erstellt.'
    }
    finally {
        if ($null -ne $client) { $client.Dispose() }
        if ($null -ne $progress) { $progress.Close(); $progress.Dispose() }
    }

    Show-SuccessNotification -Link $link -Password $sharePassword
    Write-NextcloudShareLog 'Freigabevorgang erfolgreich abgeschlossen.'
}
catch {
    Write-NextcloudShareLog ("Fehler: " + ($_ | Out-String))
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Nextcloud-Freigabe – Fehler', 'OK', 'Error') | Out-Null
    }
    catch { }
    exit 1
}
