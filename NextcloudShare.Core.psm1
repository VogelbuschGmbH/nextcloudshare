Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ProductVersion = '2.2.1'
$script:UiLanguage = $null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

if (-not ('NextcloudShare.Sharee' -as [type])) {
    Add-Type -TypeDefinition @'
namespace NextcloudShare {
    public class Sharee {
        public string ShareWith { get; set; }
        public string Label { get; set; }
        public string Display { get; set; }
        public override string ToString() {
            return string.IsNullOrWhiteSpace(Display) ? ShareWith : Display;
        }
    }
}
'@
}

function Get-NextcloudShareDataDirectory {
    $path = Join-Path $env:LOCALAPPDATA 'NextcloudShare'
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    return $path
}

function Get-NextcloudShareConfigPath {
    Join-Path (Get-NextcloudShareDataDirectory) 'user.json'
}

function Get-NextcloudShareAdminConfigPath {
    Join-Path (Join-Path $env:ProgramData 'NextcloudShare') 'NextcloudShare.config.json'
}

function Get-NextcloudShareDefaultConfig {
    [pscustomobject]@{
        SchemaVersion        = 1
        ServerUrl           = ''
        Username            = ''
        EncryptedAppPassword = ''
        AuthMethod          = ''
        LocalNextcloudRoot  = ''
        RemoteUploadFolder  = '/NextcloudShare'
        RemoteSyncRoot      = '/'
        DefaultMode         = 'Public'
        DefaultExpiryDays   = 14
        SubscriptionsEnabled = $true
        AllowServerUrlOverride = $true
        AllowRemoteUploadFolderOverride = $true
        AllowShareDefaultsOverride = $true
    }
}

function Get-NextcloudShareLanguageFromCulture {
    try {
        $name = [string](Get-UICulture).Name
        if ($name -like 'de*') { return 'de' }
    }
    catch { }
    return 'en'
}

$script:NextcloudShareText = @{
    de = @{
        AppTitle                    = 'Nextcloud-Freigabe'
        ErrorTitle                  = 'Nextcloud-Freigabe – Fehler'
        ShareDialogTitle            = 'Über Nextcloud teilen'
        ShareTypeLabel              = 'Freigabeart:'
        ShareTypePublic             = 'Externer Link'
        ShareTypeInternal           = 'Interner Link (Berechtigung erforderlich)'
        ShareTypeInternalShort      = 'Interner Link'
        PermissionLabel             = 'Berechtigung:'
        PermissionRead              = 'Nur lesen'
        PermissionReadWrite         = 'Lesen und bearbeiten'
        PermissionFull              = 'Lesen, bearbeiten, erstellen und löschen'
        ExpiryLabel                 = 'Gültig in Tagen:'
        PasswordLabel               = 'Optionales Passwort:'
        NotifyLabel                 = 'Benachrichtigen bei:'
        NotifyDownload              = 'Download'
        NotifyUpload                = 'Upload'
        NotifyModify                = 'Änderung'
        NotifyDelete                = 'Löschung'
        UsersLabel                  = 'Benutzer:'
        RemoveUser                  = 'Entfernen'
        ShareButton                 = 'Teilen'
        CancelButton                = 'Abbrechen'
        SelectUserRequired          = 'Bitte wählen Sie mindestens einen Benutzer aus, der Zugriff erhalten soll.'
        ShareHintPublic             = 'Die Auswahl erstellt oder aktualisiert das Abonnement für diese Datei beziehungsweise diesen Ordner.'
        ShareHintInternal           = 'Die ausgewählten Benutzer erhalten Zugriff mit der oben gewählten Berechtigung und Ablaufzeit. Der interne Link wird in die Zwischenablage kopiert und alle Benutzer per E-Mail benachrichtigt.'
        SearchUsersTip              = 'Name oder Benutzername eingeben'
        UserSearchTitle             = 'Benutzersuche'
        SharedFilesFolder           = '{0} Dateien – gemeinsamer Link zu einem neuen Ordner'
        ItemCountFiles              = '{0} Dateien'
        PasswordDialogTitle         = 'Passwort für öffentlichen Nextcloud-Link'
        PasswordRequiredHint        = 'Der Nextcloud-Server verlangt für öffentliche Links ein Passwort. Ein sicheres Passwort wurde automatisch erzeugt.'
        RegeneratePassword          = 'Neu erzeugen'
        PasswordCopyHint            = 'Nach erfolgreicher Freigabe werden Link und Passwort gemeinsam in die Zwischenablage kopiert.'
        CreateLink                  = 'Link erstellen'
        PasswordRequired            = 'Bitte geben Sie ein Passwort ein.'
        ConfigureTitle              = 'Nextcloud-Freigabe konfigurieren'
        LabelServerUrl              = 'Nextcloud-URL'
        LabelUsername               = 'Nextcloud-Benutzer'
        LabelLocalRoot              = 'Lokaler Nextcloud-Ordner (optional)'
        LabelRemoteRoot             = 'Serverpfad des lokalen Ordners'
        LabelUploadFolder           = 'Upload-Ordner'
        Browse                      = 'Durchsuchen'
        DefaultShareType            = 'Standard-Freigabeart'
        DefaultExpiry               = 'Standard-Ablaufzeit (Tage)'
        ConnectionLabel             = 'Nextcloud-Verbindung'
        ConnectedAs                 = 'Verbunden als {0}'
        NotConnected                = 'Noch nicht verbunden'
        ConnectNextcloud            = 'Mit Nextcloud verbinden'
        LoginSecurityHint           = 'Die Anmeldung wird im Standardbrowser durchgeführt. Nach „Grant access“ speichert Windows den von Nextcloud ausgestellten Zugriffstoken verschlüsselt mit DPAPI.'
        Save                        = 'Speichern'
        LocalFolderMissing          = 'Der angegebene lokale Nextcloud-Ordner existiert nicht. Bitte wählen Sie einen vorhandenen Ordner oder lassen Sie das Feld leer.'
        LoginCancelled              = 'Die Nextcloud-Anmeldung wurde abgebrochen.'
        ResolvingWebDav             = 'WebDAV-Benutzer-ID wird ermittelt ...'
        ConnectionFailed            = 'Verbindung fehlgeschlagen'
        LoginDialogTitle            = 'Nextcloud-Anmeldung'
        ConfigDialogTitle           = 'Nextcloud-Konfiguration'
        LoginAlreadyOpen            = 'Eine Nextcloud-Anmeldung ist bereits geöffnet. Bitte schließen Sie den vorhandenen Browser-Dialog oder warten Sie kurz.'
        LoginPreparing              = 'Nextcloud-Anmeldung wird vorbereitet ...'
        LoginBrowserOpened          = 'Browser wurde geöffnet. Bitte Zugriff in Nextcloud erlauben ...'
        LoginWaiting                = 'Warte auf Freigabe im Browser ...'
        LoginFailed                 = 'Die Nextcloud-Anmeldung ist fehlgeschlagen: {0}'
        LoginTimeout                = 'Die Nextcloud-Anmeldung wurde nicht innerhalb von {0} Minuten abgeschlossen.'
        LoginFlowStartFailed        = 'Der Nextcloud Login Flow konnte nicht gestartet werden: {0}'
        MissingServerUrl            = 'Die Nextcloud-URL fehlt.'
        InvalidServerUrl            = 'Die Nextcloud-URL ist ungültig.'
        HttpsRequired               = 'Aus Sicherheitsgründen ist für Nextcloud HTTPS erforderlich.'
        MissingUsername             = 'Der Nextcloud-Benutzername fehlt.'
        MissingToken                = 'Der Nextcloud-Zugriffstoken fehlt.'
        ConfiguredFolderMissing     = 'Der konfigurierte lokale Nextcloud-Ordner existiert nicht. Bitte wählen Sie einen vorhandenen Ordner oder lassen Sie das Feld leer.'
        MissingUploadFolder         = 'Der Upload-Ordner fehlt.'
        InvalidShareMode            = 'Der Standard-Freigabemodus ist ungültig.'
        SelectFile                  = 'Bitte wählen Sie mindestens eine Datei im Windows-Explorer aus.'
        FileUnavailable             = 'Die ausgewählte Datei ist nicht mehr verfügbar: {0}'
        FileNotSynced               = 'Die Datei ist noch nicht auf dem Nextcloud-Server vorhanden. Bitte warten Sie auf die Synchronisierung und versuchen Sie es erneut.'
        MultiSelectFailed           = 'Die Mehrfachauswahl konnte nicht gesammelt werden. Bitte versuchen Sie es erneut.'
        MultiSelectIncomplete       = 'Die Mehrfachauswahl konnte nicht abgeschlossen werden. Bitte versuchen Sie es erneut.'
        ProgressConnecting          = 'Verbindung mit Nextcloud wird hergestellt ...'
        ProgressCreateFolder        = 'Zielordner wird in Nextcloud angelegt ...'
        ProgressUploadFile          = 'Datei {0} von {1} wird hochgeladen ...'
        ProgressUpload              = 'Datei wird nach Nextcloud hochgeladen ...'
        ProgressSyncCheck           = 'Synchronisierte Datei wird geprüft ...'
        ProgressCreateLink          = 'Freigabelink wird erzeugt ...'
        ProgressUserShares          = 'Benutzerfreigaben werden erstellt ...'
        ProgressNotifications       = 'E-Mail-Benachrichtigungen werden aktiviert ...'
        ProgressInternalLink        = 'Interner Link wird erzeugt ...'
        ProgressPasswordLink        = 'Passwortgeschützter Freigabelink wird erzeugt ...'
        NotificationsNoShareId      = 'Die E-Mail-Benachrichtigungen konnten nicht aktiviert werden, weil keine Freigabe-ID ermittelt wurde. Bereits erstellte Benutzerfreigaben wurden automatisch zurückgenommen.'
        UserSharesRolledBack        = '{0} Bereits erstellte Benutzerfreigaben wurden automatisch zurückgenommen.'
        PublicShareRolledBack       = '{0} Die unvollständige Freigabe wurde automatisch zurückgenommen.'
        PublicShareRollbackFailed   = '{0} Die Freigabe konnte anschließend nicht automatisch zurückgenommen werden: {1}'
        ClipboardBlocked            = 'Die Freigabe wurde erfolgreich erstellt, aber die Windows-Zwischenablage ist momentan blockiert. Markieren Sie den Text und kopieren Sie ihn mit Strg+C oder versuchen Sie es erneut.'
        ClipboardHint               = 'Link und gegebenenfalls Passwort bleiben hier sichtbar.'
        CopyAgain                   = 'Erneut kopieren'
        ClipboardStillBlocked       = 'Zwischenablage weiterhin blockiert. Bitte Strg+C verwenden.'
        Close                       = 'Schließen'
        ClipboardDialogTitle        = 'Nextcloud-Freigabe erstellt'
        SuccessLinkCopied           = 'Der Link wurde in die Zwischenablage kopiert.'
        SuccessLinkAndPassword      = 'Link und Passwort wurden in die Zwischenablage kopiert.'
        SuccessInternalNotified     = 'Der Link wurde in die Zwischenablage kopiert und alle Benutzer per E-Mail benachrichtigt.'
        ClipboardLinkPassword       = "Link: {0}`r`nPasswort: {1}"
        ShellShare                  = 'Über Nextcloud teilen'
        ShellShareOptions           = 'Über Nextcloud teilen (mit Optionen) ...'
        ConfigureShortcutName       = 'Nextcloud-Freigabe konfigurieren.lnk'
        BatchFolderPrefix           = 'Freigabe-'
        NotificationsFailed         = 'Die E-Mail-Benachrichtigungen konnten nicht aktiviert werden: {0}'
        ShareCreateFailed           = 'Der Freigabelink konnte nicht erzeugt werden: {0}'
        UserShareFailed             = 'Die Freigabe für den Benutzer konnte nicht erzeugt werden: {0}'
        UserSearchFailed            = 'Die Benutzersuche ist fehlgeschlagen: {0}'
        InternalLinkFailed          = 'Der interne Link konnte nicht ermittelt werden: {0}'
        UploadFailed                = 'Die Datei konnte nicht nach Nextcloud hochgeladen werden: {0}'
    }
    en = @{
        AppTitle                    = 'Nextcloud Share'
        ErrorTitle                  = 'Nextcloud Share – Error'
        ShareDialogTitle            = 'Share via Nextcloud'
        ShareTypeLabel              = 'Share type:'
        ShareTypePublic             = 'Public link'
        ShareTypeInternal           = 'Internal link (permission required)'
        ShareTypeInternalShort      = 'Internal link'
        PermissionLabel             = 'Permission:'
        PermissionRead              = 'Read only'
        PermissionReadWrite         = 'Read and edit'
        PermissionFull              = 'Read, edit, create and delete'
        ExpiryLabel                 = 'Valid for days:'
        PasswordLabel               = 'Optional password:'
        NotifyLabel                 = 'Notify on:'
        NotifyDownload              = 'Download'
        NotifyUpload                = 'Upload'
        NotifyModify                = 'Modification'
        NotifyDelete                = 'Deletion'
        UsersLabel                  = 'Users:'
        RemoveUser                  = 'Remove'
        ShareButton                 = 'Share'
        CancelButton                = 'Cancel'
        SelectUserRequired          = 'Please select at least one user who should receive access.'
        ShareHintPublic             = 'This selection creates or updates the subscription for this file or folder.'
        ShareHintInternal           = 'Selected users receive access with the permission and expiry chosen above. The internal link is copied to the clipboard and all users are notified by email.'
        SearchUsersTip              = 'Enter a name or username'
        UserSearchTitle             = 'User search'
        SharedFilesFolder           = '{0} files – shared link to a new folder'
        ItemCountFiles              = '{0} files'
        PasswordDialogTitle         = 'Password for public Nextcloud link'
        PasswordRequiredHint        = 'The Nextcloud server requires a password for public links. A secure password was generated automatically.'
        RegeneratePassword          = 'Generate new'
        PasswordCopyHint            = 'After a successful share, the link and password are copied to the clipboard together.'
        CreateLink                  = 'Create link'
        PasswordRequired            = 'Please enter a password.'
        ConfigureTitle              = 'Configure Nextcloud Share'
        LabelServerUrl              = 'Nextcloud URL'
        LabelUsername               = 'Nextcloud user'
        LabelLocalRoot              = 'Local Nextcloud folder (optional)'
        LabelRemoteRoot             = 'Server path of the local folder'
        LabelUploadFolder           = 'Upload folder'
        Browse                      = 'Browse'
        DefaultShareType            = 'Default share type'
        DefaultExpiry               = 'Default expiry (days)'
        ConnectionLabel             = 'Nextcloud connection'
        ConnectedAs                 = 'Connected as {0}'
        NotConnected                = 'Not connected yet'
        ConnectNextcloud            = 'Connect to Nextcloud'
        LoginSecurityHint           = 'Sign-in opens in your default browser. After “Grant access”, Windows stores the Nextcloud app password encrypted with DPAPI.'
        Save                        = 'Save'
        LocalFolderMissing          = 'The specified local Nextcloud folder does not exist. Please choose an existing folder or leave the field empty.'
        LoginCancelled              = 'Nextcloud sign-in was cancelled.'
        ResolvingWebDav             = 'Determining WebDAV user ID ...'
        ConnectionFailed            = 'Connection failed'
        LoginDialogTitle            = 'Nextcloud sign-in'
        ConfigDialogTitle           = 'Nextcloud configuration'
        LoginAlreadyOpen            = 'A Nextcloud sign-in is already open. Please close the existing browser dialog or wait a moment.'
        LoginPreparing              = 'Preparing Nextcloud sign-in ...'
        LoginBrowserOpened          = 'The browser was opened. Please grant access in Nextcloud ...'
        LoginWaiting                = 'Waiting for approval in the browser ...'
        LoginFailed                 = 'Nextcloud sign-in failed: {0}'
        LoginTimeout                = 'Nextcloud sign-in was not completed within {0} minutes.'
        LoginFlowStartFailed        = 'The Nextcloud login flow could not be started: {0}'
        MissingServerUrl            = 'The Nextcloud URL is missing.'
        InvalidServerUrl            = 'The Nextcloud URL is invalid.'
        HttpsRequired               = 'HTTPS is required for Nextcloud for security reasons.'
        MissingUsername             = 'The Nextcloud user name is missing.'
        MissingToken                = 'The Nextcloud access token is missing.'
        ConfiguredFolderMissing     = 'The configured local Nextcloud folder does not exist. Please choose an existing folder or leave the field empty.'
        MissingUploadFolder         = 'The upload folder is missing.'
        InvalidShareMode            = 'The default share mode is invalid.'
        SelectFile                  = 'Please select at least one file in Windows Explorer.'
        FileUnavailable             = 'The selected file is no longer available: {0}'
        FileNotSynced               = 'The file is not yet on the Nextcloud server. Please wait for synchronization and try again.'
        MultiSelectFailed           = 'The multiple selection could not be collected. Please try again.'
        MultiSelectIncomplete       = 'The multiple selection could not be completed. Please try again.'
        ProgressConnecting          = 'Connecting to Nextcloud ...'
        ProgressCreateFolder        = 'Creating the destination folder in Nextcloud ...'
        ProgressUploadFile          = 'Uploading file {0} of {1} ...'
        ProgressUpload              = 'Uploading the file to Nextcloud ...'
        ProgressSyncCheck           = 'Checking the synchronized file ...'
        ProgressCreateLink          = 'Creating the share link ...'
        ProgressUserShares          = 'Creating user shares ...'
        ProgressNotifications       = 'Enabling email notifications ...'
        ProgressInternalLink        = 'Creating the internal link ...'
        ProgressPasswordLink        = 'Creating the password-protected share link ...'
        NotificationsNoShareId      = 'Email notifications could not be enabled because no share ID was returned. User shares created so far were rolled back automatically.'
        UserSharesRolledBack        = '{0} User shares created so far were rolled back automatically.'
        PublicShareRolledBack       = '{0} The incomplete share was rolled back automatically.'
        PublicShareRollbackFailed   = '{0} The share could not be rolled back automatically afterwards: {1}'
        ClipboardBlocked            = 'The share was created successfully, but the Windows clipboard is currently blocked. Select the text and copy it with Ctrl+C, or try again.'
        ClipboardHint               = 'The link and password, if any, remain visible here.'
        CopyAgain                   = 'Copy again'
        ClipboardStillBlocked       = 'Clipboard still blocked. Please use Ctrl+C.'
        Close                       = 'Close'
        ClipboardDialogTitle        = 'Nextcloud share created'
        SuccessLinkCopied           = 'The link was copied to the clipboard.'
        SuccessLinkAndPassword      = 'The link and password were copied to the clipboard.'
        SuccessInternalNotified     = 'The link was copied to the clipboard and all users were notified by email.'
        ClipboardLinkPassword       = "Link: {0}`r`nPassword: {1}"
        ShellShare                  = 'Share via Nextcloud'
        ShellShareOptions           = 'Share via Nextcloud (options) ...'
        ConfigureShortcutName       = 'Configure Nextcloud Share.lnk'
        BatchFolderPrefix           = 'Share-'
        NotificationsFailed         = 'Email notifications could not be enabled: {0}'
        ShareCreateFailed           = 'The share link could not be created: {0}'
        UserShareFailed             = 'The user share could not be created: {0}'
        UserSearchFailed            = 'User search failed: {0}'
        InternalLinkFailed          = 'The internal link could not be determined: {0}'
        UploadFailed                = 'The file could not be uploaded to Nextcloud: {0}'
    }
}

function Get-NextcloudShareUiLanguage {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:UiLanguage)) {
        return [string]$script:UiLanguage
    }
    $script:UiLanguage = Get-NextcloudShareLanguageFromCulture
    return $script:UiLanguage
}

function Get-NextcloudShareText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$FormatArgs
    )

    $lang = Get-NextcloudShareUiLanguage
    $table = $script:NextcloudShareText[$lang]
    if ($null -eq $table -or -not $table.ContainsKey($Key)) {
        $table = $script:NextcloudShareText['de']
    }
    $text = [string]$table[$Key]
    if ([string]::IsNullOrWhiteSpace($text)) { $text = $Key }
    if ($null -ne $FormatArgs -and @($FormatArgs).Count -gt 0) {
        return ($text -f $FormatArgs)
    }
    return $text
}

function Get-NextcloudShareAdminConfig {
    $path = Get-NextcloudShareAdminConfigPath
    $config = Get-NextcloudShareDefaultConfig
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $config
    }

    try {
        $admin = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($name in @('SchemaVersion', 'ServerUrl', 'RemoteUploadFolder', 'RemoteSyncRoot', 'SubscriptionsEnabled')) {
            if ($admin.PSObject.Properties.Name -contains $name) {
                Add-Member -InputObject $config -MemberType NoteProperty -Name $name -Value $admin.$name -Force
            }
        }
        if ($admin.PSObject.Properties.Name -contains 'Defaults') {
            if ($admin.Defaults.PSObject.Properties.Name -contains 'ShareMode') { $config.DefaultMode = [string]$admin.Defaults.ShareMode }
            if ($admin.Defaults.PSObject.Properties.Name -contains 'ExpiryDays') { $config.DefaultExpiryDays = [int]$admin.Defaults.ExpiryDays }
        }
        if ($admin.PSObject.Properties.Name -contains 'UserOverrides') {
            if ($admin.UserOverrides.PSObject.Properties.Name -contains 'ServerUrl') { $config.AllowServerUrlOverride = [bool]$admin.UserOverrides.ServerUrl }
            if ($admin.UserOverrides.PSObject.Properties.Name -contains 'RemoteUploadFolder') { $config.AllowRemoteUploadFolderOverride = [bool]$admin.UserOverrides.RemoteUploadFolder }
            if ($admin.UserOverrides.PSObject.Properties.Name -contains 'ShareDefaults') { $config.AllowShareDefaultsOverride = [bool]$admin.UserOverrides.ShareDefaults }
        }
        return $config
    }
    catch {
        throw "Die zentrale Konfiguration '$path' konnte nicht gelesen werden: $($_.Exception.Message)"
    }
}

function Get-NextcloudClientSyncRoot {
    param([string]$ServerUrl = '')

    $configPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $configPaths += Join-Path $env:APPDATA 'Nextcloud\nextcloud.cfg'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $configPaths += Join-Path $env:LOCALAPPDATA 'Nextcloud\nextcloud.cfg'
    }

    $configuredFolders = @()
    foreach ($configPath in ($configPaths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { continue }
        try {
            $accountUrls = @{}
            $folderEntries = @()
            foreach ($line in (Get-Content -LiteralPath $configPath -Encoding UTF8 -ErrorAction Stop)) {
                if ($line -match '^\s*(\d+)\\url=(.*?)\s*$') {
                    $accountUrls[$matches[1]] = $matches[2].Trim().TrimEnd('/')
                }
                elseif ($line -match '^\s*(\d+)\\Folders\\\d+\\localPath=(.*?)\s*$') {
                    $folderEntries += [pscustomobject]@{
                        Account = $matches[1]
                        Path    = $matches[2].Trim()
                    }
                }
            }

            foreach ($entry in $folderEntries) {
                $candidate = ([Environment]::ExpandEnvironmentVariables([string]$entry.Path)).TrimEnd('/', '\').Replace('/', '\')
                if ([string]::IsNullOrWhiteSpace($candidate) -or
                    -not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
                $accountUrl = if ($accountUrls.ContainsKey([string]$entry.Account)) { [string]$accountUrls[[string]$entry.Account] } else { '' }
                $configuredFolders += [pscustomobject]@{
                    Path        = $candidate
                    ServerMatch = -not [string]::IsNullOrWhiteSpace($ServerUrl) -and
                        [string]::Equals($accountUrl, $ServerUrl.Trim().TrimEnd('/'), [StringComparison]::OrdinalIgnoreCase)
                }
            }
        }
        catch {
            # Eine unlesbare Client-Konfiguration verhindert die Freigabe nicht.
        }
    }

    $match = $configuredFolders | Where-Object ServerMatch | Select-Object -First 1
    if ($null -ne $match) { return [string]$match.Path }
    $first = $configuredFolders | Select-Object -First 1
    if ($null -ne $first) { return [string]$first.Path }

    $defaultPath = Join-Path $env:USERPROFILE 'Nextcloud'
    if (Test-Path -LiteralPath $defaultPath -PathType Container) { return $defaultPath }
    return ''
}

function Protect-AppPassword {
    param([Parameter(Mandatory = $true)][string]$PlainText)

    $secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
    return ConvertFrom-SecureString -SecureString $secure
}

function Unprotect-AppPassword {
    param([Parameter(Mandatory = $true)][string]$CipherText)

    $secure = ConvertTo-SecureString -String $CipherText
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Get-NextcloudShareConfig {
    $path = Get-NextcloudShareConfigPath
    $admin = Get-NextcloudShareAdminConfig
    if (-not (Test-Path -LiteralPath $path)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$admin.ServerUrl)) { return $admin }
        return $null
    }

    try {
        $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $userServerUrl = if ($config.PSObject.Properties.Name -contains 'ServerUrl') {
            [string]$config.ServerUrl
        }
        else { '' }
        $changed = $false
        foreach ($property in $admin.PSObject.Properties) {
            if (-not ($config.PSObject.Properties.Name -contains $property.Name)) {
                Add-Member -InputObject $config -MemberType NoteProperty -Name $property.Name -Value $property.Value -Force
            }
        }
        if (-not $admin.AllowServerUrlOverride -or [string]::IsNullOrWhiteSpace([string]$config.ServerUrl)) {
            $config.ServerUrl = [string]$admin.ServerUrl
        }
        if (-not $admin.AllowRemoteUploadFolderOverride) {
            $config.RemoteUploadFolder = [string]$admin.RemoteUploadFolder
        }
        if (-not $admin.AllowShareDefaultsOverride) {
            $config.DefaultMode = [string]$admin.DefaultMode
            $config.DefaultExpiryDays = [int]$admin.DefaultExpiryDays
        }
        $config.SubscriptionsEnabled = [bool]$admin.SubscriptionsEnabled
        if ($config.PSObject.Properties.Name -contains 'Language') {
            $config.PSObject.Properties.Remove('Language')
        }
        $authenticatedServerUrl = if ($config.PSObject.Properties.Name -contains 'AuthenticatedServerUrl') {
            [string]$config.AuthenticatedServerUrl
        }
        else { $userServerUrl }
        if (-not [string]::IsNullOrWhiteSpace($authenticatedServerUrl) -and
            -not [string]::Equals(
                $authenticatedServerUrl.TrimEnd('/'),
                ([string]$config.ServerUrl).TrimEnd('/'),
                [StringComparison]::OrdinalIgnoreCase
            )) {
            $config.EncryptedAppPassword = ''
            $config.AuthMethod = ''
            $changed = $true
        }
        $configuredLocalRoot = if ($config.PSObject.Properties.Name -contains 'LocalNextcloudRoot') {
            [string]$config.LocalNextcloudRoot
        }
        else { '' }
        if ([string]::IsNullOrWhiteSpace($configuredLocalRoot) -or
            -not (Test-Path -LiteralPath $configuredLocalRoot -PathType Container)) {
            $detectedLocalRoot = Get-NextcloudClientSyncRoot -ServerUrl ([string]$config.ServerUrl)
            if (-not [string]::Equals($configuredLocalRoot, $detectedLocalRoot, [StringComparison]::OrdinalIgnoreCase)) {
                Add-Member -InputObject $config -MemberType NoteProperty -Name LocalNextcloudRoot -Value $detectedLocalRoot -Force
                $changed = $true
            }
        }
        if ($changed) { Save-NextcloudShareConfig $config }
        return $config
    }
    catch {
        throw "Die Konfiguration '$path' konnte nicht gelesen werden: $($_.Exception.Message)"
    }
}

function Save-NextcloudShareConfig {
    param([Parameter(Mandatory = $true)]$Config)

    if ($Config.PSObject.Properties.Name -contains 'Language') {
        $Config.PSObject.Properties.Remove('Language')
    }
    $Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Get-NextcloudShareConfigPath) -Encoding UTF8
}

function Test-NextcloudShareConfig {
    param([Parameter(Mandatory = $true)]$Config)

    if ([string]::IsNullOrWhiteSpace($Config.ServerUrl)) { throw (Get-NextcloudShareText 'MissingServerUrl') }
    $uri = $null
    if (-not [Uri]::TryCreate($Config.ServerUrl, [UriKind]::Absolute, [ref]$uri)) { throw (Get-NextcloudShareText 'InvalidServerUrl') }
    if ($uri.Scheme -ne 'https' -and $uri.Host -notin @('localhost', '127.0.0.1')) {
        throw (Get-NextcloudShareText 'HttpsRequired')
    }
    if ([string]::IsNullOrWhiteSpace($Config.Username)) { throw (Get-NextcloudShareText 'MissingUsername') }
    if ([string]::IsNullOrWhiteSpace($Config.EncryptedAppPassword)) { throw (Get-NextcloudShareText 'MissingToken') }
    $localRoot = if ($Config.PSObject.Properties.Name -contains 'LocalNextcloudRoot') {
        [string]$Config.LocalNextcloudRoot
    }
    else { '' }
    if (-not [string]::IsNullOrWhiteSpace($localRoot) -and
        -not (Test-Path -LiteralPath $localRoot -PathType Container)) {
        throw (Get-NextcloudShareText 'ConfiguredFolderMissing')
    }
    if ([string]::IsNullOrWhiteSpace($Config.RemoteUploadFolder)) { throw (Get-NextcloudShareText 'MissingUploadFolder') }
    if ($Config.DefaultMode -notin @('Public', 'Internal')) { throw (Get-NextcloudShareText 'InvalidShareMode') }
}

function Test-NextcloudServerUrl {
    param([Parameter(Mandatory = $true)][string]$ServerUrl)

    if ([string]::IsNullOrWhiteSpace($ServerUrl)) { throw (Get-NextcloudShareText 'MissingServerUrl') }
    $uri = $null
    if (-not [Uri]::TryCreate($ServerUrl, [UriKind]::Absolute, [ref]$uri)) { throw (Get-NextcloudShareText 'InvalidServerUrl') }
    if ($uri.Scheme -ne 'https' -and $uri.Host -notin @('localhost', '127.0.0.1')) {
        throw (Get-NextcloudShareText 'HttpsRequired')
    }
}

function ConvertTo-EncodedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $parts = $Path.Trim('/') -split '/'
    return ($parts | Where-Object { $_ -ne '' } | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
}

function Get-WebDavUri {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemotePath
    )

    $base = $Config.ServerUrl.TrimEnd('/')
    $encoded = ConvertTo-EncodedPath $RemotePath

    $endpointMode = 'Modern'
    if ($Config.PSObject.Properties.Name -contains 'WebDavEndpoint') {
        $endpointMode = [string]$Config.WebDavEndpoint
    }
    if ($endpointMode -eq 'Legacy') {
        if ($encoded) { return "$base/remote.php/webdav/$encoded" }
        return "$base/remote.php/webdav/"
    }

    $webDavUserId = [string]$Config.Username
    if ($Config.PSObject.Properties.Name -contains 'WebDavUserId' -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.WebDavUserId)) {
        $webDavUserId = [string]$Config.WebDavUserId
    }
    $user = [Uri]::EscapeDataString($webDavUserId)
    if ($encoded) { return "$base/remote.php/dav/files/$user/$encoded" }
    return "$base/remote.php/dav/files/$user/"
}

function New-NextcloudHttpClient {
    param([Parameter(Mandatory = $true)]$Config)

    $password = Unprotect-AppPassword $Config.EncryptedAppPassword
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes("$($Config.Username):$password")
        $token = [Convert]::ToBase64String($bytes)
    }
    finally {
        $password = $null
    }

    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromHours(4)
    $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Basic', $token)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("NextcloudShare/$script:ProductVersion")
    return $client
}

function Invoke-HttpRequest {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [System.Net.Http.HttpContent]$Content,
        [hashtable]$Headers
    )

    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Uri)
    try {
        if ($null -ne $Content) { $request.Content = $Content }
        if ($Headers) {
            foreach ($name in $Headers.Keys) {
                $null = $request.Headers.TryAddWithoutValidation($name, [string]$Headers[$name])
            }
        }
        $response = $Client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            return [pscustomobject]@{
                IsSuccess  = $response.IsSuccessStatusCode
                StatusCode = [int]$response.StatusCode
                Reason     = $response.ReasonPhrase
                Body       = $body
            }
        }
        finally {
            $response.Dispose()
        }
    }
    finally {
        $request.Dispose()
    }
}

function Start-NextcloudLoginFlow {
    param(
        [Parameter(Mandatory = $true)][string]$ServerUrl,
        [scriptblock]$StatusCallback,
        [int]$TimeoutMinutes = 20
    )

    Test-NextcloudServerUrl $ServerUrl
    $baseUrl = $ServerUrl.TrimEnd('/')
    $mutex = [Threading.Mutex]::new($false, 'Local\NextcloudShare.LoginFlow')
    $ownsMutex = $false
    try {
        try { $ownsMutex = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) {
            throw (Get-NextcloudShareText 'LoginAlreadyOpen')
        }
    }
    catch {
        $mutex.Dispose()
        throw
    }

    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("NextcloudShare/$script:ProductVersion")
    try {
        if ($StatusCallback) { & $StatusCallback (Get-NextcloudShareText 'LoginPreparing') }
        $startResponse = Invoke-HttpRequest -Client $client -Method 'POST' -Uri "$baseUrl/index.php/login/v2"
        if (-not $startResponse.IsSuccess) {
            throw (Get-NextcloudShareText 'LoginFlowStartFailed' -FormatArgs @(Get-HttpErrorText $startResponse))
        }

        try { $flow = $startResponse.Body | ConvertFrom-Json }
        catch { throw 'Nextcloud hat keine gültige Login-Flow-Antwort geliefert.' }
        if ([string]::IsNullOrWhiteSpace($flow.login) -or
            [string]::IsNullOrWhiteSpace($flow.poll.token) -or
            [string]::IsNullOrWhiteSpace($flow.poll.endpoint)) {
            throw 'Die Login-Flow-Antwort von Nextcloud ist unvollständig.'
        }

        if ($StatusCallback) { & $StatusCallback (Get-NextcloudShareText 'LoginBrowserOpened') }
        Start-Process -FilePath ([string]$flow.login) | Out-Null

        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        while ((Get-Date) -lt $deadline) {
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 1000

            $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
            $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('token', [string]$flow.poll.token))
            $content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
            $pollResponse = Invoke-HttpRequest -Client $client -Method 'POST' -Uri ([string]$flow.poll.endpoint) -Content $content

            if ($pollResponse.StatusCode -eq 404) {
                if ($StatusCallback) { & $StatusCallback (Get-NextcloudShareText 'LoginWaiting') }
                continue
            }
            if (-not $pollResponse.IsSuccess) {
                throw (Get-NextcloudShareText 'LoginFailed' -FormatArgs @(Get-HttpErrorText $pollResponse))
            }

            try { $credentials = $pollResponse.Body | ConvertFrom-Json }
            catch { throw 'Nextcloud hat keine gültigen Anmeldedaten geliefert.' }
            if ([string]::IsNullOrWhiteSpace($credentials.server) -or
                [string]::IsNullOrWhiteSpace($credentials.loginName) -or
                [string]::IsNullOrWhiteSpace($credentials.appPassword)) {
                throw 'Die von Nextcloud gelieferten Anmeldedaten sind unvollständig.'
            }

            if ($StatusCallback) { & $StatusCallback (Get-NextcloudShareText 'ConnectedAs' -FormatArgs @($credentials.loginName)) }
            return [pscustomobject]@{
                ServerUrl   = ([string]$credentials.server).TrimEnd('/')
                Username    = [string]$credentials.loginName
                AppPassword = [string]$credentials.appPassword
            }
        }
        throw (Get-NextcloudShareText 'LoginTimeout' -FormatArgs @($TimeoutMinutes))
    }
    finally {
        $client.Dispose()
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Get-HttpErrorText {
    param($Response)

    if (-not [string]::IsNullOrWhiteSpace($Response.Body)) {
        try {
            $json = $Response.Body | ConvertFrom-Json
            if ($json.ocs.meta.message) { return [string]$json.ocs.meta.message }
        }
        catch { }
        if ($Response.Body.Length -le 500 -and $Response.Body -notmatch '<html') { return $Response.Body }
    }
    return "HTTP $($Response.StatusCode) $($Response.Reason)"
}

function Test-OcsSuccess {
    param([Parameter(Mandatory = $true)]$Result)

    $status = ''
    $statusCode = 0
    if ($Result.ocs.meta.PSObject.Properties.Name -contains 'status') {
        $status = [string]$Result.ocs.meta.status
    }
    if ($Result.ocs.meta.PSObject.Properties.Name -contains 'statuscode') {
        $statusCode = [int]$Result.ocs.meta.statuscode
    }
    return $status.Equals('ok', [StringComparison]::OrdinalIgnoreCase) -or $statusCode -in @(100, 200)
}

function Get-NextcloudCurrentUserId {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config
    )

    $uri = Get-OcsUri $Config 'cloud/user?format=json'
    $response = Invoke-HttpRequest -Client $Client -Method 'GET' -Uri $uri -Headers @{
        'OCS-APIRequest' = 'true'
        'Accept' = 'application/json'
    }
    if (-not $response.IsSuccess) {
        throw "Die Nextcloud-Benutzer-ID konnte nicht ermittelt werden: $(Get-HttpErrorText $response)"
    }

    try { $result = $response.Body | ConvertFrom-Json }
    catch { throw 'Nextcloud hat keine gültigen Benutzerdaten geliefert.' }
    if (-not (Test-OcsSuccess $result) -or
        [string]::IsNullOrWhiteSpace([string]$result.ocs.data.id)) {
        throw "Die Nextcloud-Benutzer-ID konnte nicht ermittelt werden: $($result.ocs.meta.message)"
    }
    return [string]$result.ocs.data.id
}

function Test-NextcloudWebDavRoot {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config
    )

    $response = Invoke-HttpRequest -Client $Client -Method 'PROPFIND' -Uri (Get-WebDavUri $Config '/') -Headers @{ 'Depth' = '0' }
    if (-not $response.IsSuccess) {
        throw "Das Nextcloud-Dateiverzeichnis konnte nicht geöffnet werden: $(Get-HttpErrorText $response)"
    }
}

function Initialize-NextcloudWebDavIdentity {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [switch]$Force
    )

    $hasUserId = $Config.PSObject.Properties.Name -contains 'WebDavUserId' -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.WebDavUserId)
    $hasEndpoint = $Config.PSObject.Properties.Name -contains 'WebDavEndpoint' -and
        [string]$Config.WebDavEndpoint -in @('Modern', 'Legacy')
    if (-not $Force -and $hasUserId -and $hasEndpoint) { return $Config }

    $client = New-NextcloudHttpClient $Config
    try {
        $modernError = $null
        try {
            $userId = Get-NextcloudCurrentUserId -Client $client -Config $Config
            Add-Member -InputObject $Config -MemberType NoteProperty -Name WebDavUserId -Value $userId -Force
            Add-Member -InputObject $Config -MemberType NoteProperty -Name WebDavEndpoint -Value 'Modern' -Force
            Test-NextcloudWebDavRoot -Client $client -Config $Config
        }
        catch {
            $modernError = $_.Exception.Message
            Add-Member -InputObject $Config -MemberType NoteProperty -Name WebDavUserId -Value ([string]$Config.Username) -Force
            Add-Member -InputObject $Config -MemberType NoteProperty -Name WebDavEndpoint -Value 'Legacy' -Force
            try {
                Test-NextcloudWebDavRoot -Client $client -Config $Config
            }
            catch {
                throw "Das Nextcloud-Dateiverzeichnis ist weder über die ermittelte Benutzer-ID noch über den kompatiblen WebDAV-Endpunkt erreichbar.`r`n`r`nModerner Endpunkt: $modernError`r`nKompatibler Endpunkt: $($_.Exception.Message)"
            }
        }
    }
    finally {
        $client.Dispose()
    }

    Save-NextcloudShareConfig $Config
    return $Config
}

function Test-RemoteExists {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemotePath
    )

    $response = Invoke-HttpRequest -Client $Client -Method 'HEAD' -Uri (Get-WebDavUri $Config $RemotePath)
    if ($response.StatusCode -eq 404) { return $false }
    if (-not $response.IsSuccess) { throw "Nextcloud konnte nicht erreicht werden: $(Get-HttpErrorText $response)" }
    return $true
}

function Ensure-RemoteFolder {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemoteFolder
    )

    $current = ''
    foreach ($part in ($RemoteFolder.Trim('/') -split '/')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $current += "/$part"
        $response = Invoke-HttpRequest -Client $Client -Method 'MKCOL' -Uri (Get-WebDavUri $Config $current)
        if (-not $response.IsSuccess -and $response.StatusCode -ne 405) {
            throw "Der Nextcloud-Ordner '$current' konnte nicht angelegt werden: $(Get-HttpErrorText $response)"
        }
    }
}

function Join-RemotePath {
    param([string]$Left, [string]$Right)
    return '/' + (($Left.Trim('/') + '/' + $Right.Trim('/')).Trim('/'))
}

function Get-UniqueRemotePathInFolder {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemoteFolder,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $candidate = Join-RemotePath $RemoteFolder $FileName
    if (-not (Test-RemoteExists -Client $Client -Config $Config -RemotePath $candidate)) { return $candidate }

    $base = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [IO.Path]::GetExtension($FileName)
    for ($number = 2; $number -le 9999; $number++) {
        $candidate = Join-RemotePath $RemoteFolder ("{0}-{1}{2}" -f $base, $number, $extension)
        if (-not (Test-RemoteExists -Client $Client -Config $Config -RemotePath $candidate)) { return $candidate }
    }
    throw "Für die Datei '$FileName' konnte kein eindeutiger Name im Nextcloud-Zielordner erzeugt werden."
}

function New-RemoteUploadBatchFolder {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config
    )

    $monthFolder = Join-RemotePath ([string]$Config.RemoteUploadFolder) (Get-Date -Format 'yyyy-MM')
    Ensure-RemoteFolder -Client $Client -Config $Config -RemoteFolder $monthFolder
    $baseName = (Get-NextcloudShareText 'BatchFolderPrefix') + (Get-Date -Format 'yyyyMMdd-HHmmss')
    for ($number = 1; $number -le 9999; $number++) {
        $folderName = if ($number -eq 1) { $baseName } else { "$baseName-$number" }
        $candidate = Join-RemotePath $monthFolder $folderName
        if (-not (Test-RemoteExists -Client $Client -Config $Config -RemotePath $candidate)) {
            Ensure-RemoteFolder -Client $Client -Config $Config -RemoteFolder $candidate
            return $candidate
        }
    }
    throw 'Für die Mehrfachauswahl konnte kein eindeutiger Nextcloud-Zielordner erzeugt werden.'
}

function Get-RemotePathForLocalItem {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )

    $localRoot = if ($Config.PSObject.Properties.Name -contains 'LocalNextcloudRoot') {
        [string]$Config.LocalNextcloudRoot
    }
    else { '' }
    if ([string]::IsNullOrWhiteSpace($localRoot) -or
        -not (Test-Path -LiteralPath $localRoot -PathType Container)) {
        return $null
    }

    $root = [IO.Path]::GetFullPath($localRoot).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($LocalPath)
    if ($full.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { return [string]$Config.RemoteSyncRoot }
    if (-not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { return $null }

    $relative = $full.Substring($root.Length).TrimStart('\').Replace('\', '/')
    return Join-RemotePath ([string]$Config.RemoteSyncRoot) $relative
}

function Get-UniqueRemoteUploadPath {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $folder = Join-RemotePath ([string]$Config.RemoteUploadFolder) (Get-Date -Format 'yyyy-MM')
    Ensure-RemoteFolder -Client $Client -Config $Config -RemoteFolder $folder
    $candidate = Join-RemotePath $folder $FileName
    if (-not (Test-RemoteExists -Client $Client -Config $Config -RemotePath $candidate)) { return $candidate }

    $base = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [IO.Path]::GetExtension($FileName)
    return Join-RemotePath $folder ("{0}-{1}{2}" -f $base, (Get-Date -Format 'yyyyMMdd-HHmmss'), $extension)
}

function Send-FileToNextcloud {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath
    )

    $stream = [IO.File]::OpenRead($LocalPath)
    try {
        $content = [System.Net.Http.StreamContent]::new($stream)
        $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        $response = Invoke-HttpRequest -Client $Client -Method 'PUT' -Uri (Get-WebDavUri $Config $RemotePath) -Content $content
        if (-not $response.IsSuccess) {
            throw (Get-NextcloudShareText 'UploadFailed' -FormatArgs @(Get-HttpErrorText $response))
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-OcsUri {
    param([Parameter(Mandatory = $true)]$Config, [Parameter(Mandatory = $true)][string]$Relative)
    return $Config.ServerUrl.TrimEnd('/') + '/ocs/v2.php/' + $Relative.TrimStart('/')
}

function Throw-NextcloudPublicShareError {
    param([Parameter(Mandatory = $true)][string]$Message)

    $exception = [InvalidOperationException]::new((Get-NextcloudShareText 'ShareCreateFailed' -FormatArgs @($Message)))
    $normalized = $Message.ToLowerInvariant()
    if (($normalized -match 'password|passw') -and
        ($normalized -match 'enforc|required|erzwung|erforder')) {
        $exception.Data['NextcloudShareError'] = 'PasswordRequired'
    }
    throw $exception
}

function Get-PublicShareLinkFromData {
    param(
        [Parameter(Mandatory = $true)]$Config,
        $Data
    )

    if ($null -eq $Data) { return $null }
    foreach ($item in @($Data)) {
        if ($null -eq $item) { continue }
        if ($item -is [string] -and ([string]$item -match '^https?://')) { return [string]$item }
        $properties = @($item.PSObject.Properties.Name)
        if ($properties -contains 'url' -and -not [string]::IsNullOrWhiteSpace([string]$item.url)) {
            return [string]$item.url
        }
        if ($properties -contains 'token' -and -not [string]::IsNullOrWhiteSpace([string]$item.token)) {
            return $Config.ServerUrl.TrimEnd('/') + '/s/' + [Uri]::EscapeDataString([string]$item.token)
        }
    }
    return $null
}

function Get-ShareIdFromData {
    param($Data)

    if ($null -eq $Data) { return $null }
    if (($Data -is [ValueType] -or $Data -is [string]) -and ([string]$Data -match '^\d+$')) {
        return [string]$Data
    }
    foreach ($item in @($Data)) {
        if ($null -eq $item) { continue }
        $properties = @($item.PSObject.Properties.Name)
        if ($properties -contains 'id' -and ([string]$item.id -match '^\d+$')) {
            return [string]$item.id
        }
    }
    return $null
}

function Get-PublicShareById {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ShareId
    )

    $uri = Get-OcsUri $Config ("apps/files_sharing/api/v1/shares/{0}?format=json" -f [Uri]::EscapeDataString($ShareId))
    $response = Invoke-HttpRequest -Client $Client -Method 'GET' -Uri $uri -Headers @{ 'OCS-APIRequest' = 'true'; 'Accept' = 'application/json' }
    if (-not $response.IsSuccess) {
        throw "Die erzeugte Freigabe konnte nicht gelesen werden: $(Get-HttpErrorText $response)"
    }
    try { $result = $response.Body | ConvertFrom-Json }
    catch { throw 'Nextcloud hat für die erzeugte Freigabe keine gültige JSON-Antwort geliefert.' }
    if (-not (Test-OcsSuccess $result)) {
        throw "Die erzeugte Freigabe konnte nicht gelesen werden: $($result.ocs.meta.message)"
    }
    $link = Get-PublicShareLinkFromData -Config $Config -Data $result.ocs.data
    if ([string]::IsNullOrWhiteSpace($link)) {
        throw "Nextcloud hat für die erzeugte Freigabe $ShareId weder URL noch Token geliefert."
    }
    return [pscustomobject]@{
        Link    = $link
        ShareId = $ShareId
    }
}

function Get-PublicShareLinkById {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ShareId
    )

    return (Get-PublicShareById -Client $Client -Config $Config -ShareId $ShareId).Link
}

function New-PublicShare {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [int]$ExpiryDays = 14,
        [string]$Password,
        [ValidateSet(1, 3, 15)][int]$Permissions = 1
    )

    # Nextcloud-Berechtigungen sind eine Bitmaske:
    # 1 = Lesen, 2 = Aktualisieren, 4 = Erstellen, 8 = Löschen. Weiterfreigeben (16) bleibt ausgeschlossen.
    $sharePermissions = [string]$Permissions
    $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
    $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('path', $RemotePath))
    $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('shareType', '3'))
    $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('permissions', $sharePermissions))
    $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('label', 'NextcloudShare'))
    if ($ExpiryDays -gt 0) { $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('expireDate', (Get-Date).AddDays($ExpiryDays).ToString('yyyy-MM-dd'))) }
    if (-not [string]::IsNullOrWhiteSpace($Password)) { $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('password', $Password)) }

    $content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
    $response = Invoke-HttpRequest -Client $Client -Method 'POST' -Uri (Get-OcsUri $Config 'apps/files_sharing/api/v1/shares') -Content $content -Headers @{ 'OCS-APIRequest' = 'true'; 'Accept' = 'application/json' }
    if (-not $response.IsSuccess) { Throw-NextcloudPublicShareError (Get-HttpErrorText $response) }

    try { $result = $response.Body | ConvertFrom-Json }
    catch { throw 'Nextcloud hat beim Erstellen des Freigabelinks keine gültige JSON-Antwort geliefert.' }
    if (-not (Test-OcsSuccess $result)) {
        Throw-NextcloudPublicShareError ([string]$result.ocs.meta.message)
    }
    $shareId = Get-ShareIdFromData -Data $result.ocs.data
    if ([string]::IsNullOrWhiteSpace($shareId)) {
        throw 'Nextcloud meldet eine erfolgreiche Freigabe, hat aber keine Freigabe-ID geliefert.'
    }
    $link = Get-PublicShareLinkFromData -Config $Config -Data $result.ocs.data
    if (-not [string]::IsNullOrWhiteSpace($link)) {
        return [pscustomobject]@{
            Link    = $link
            ShareId = $shareId
        }
    }

    return Get-PublicShareById -Client $Client -Config $Config -ShareId $shareId
}

function New-PublicShareLink {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [int]$ExpiryDays = 14,
        [string]$Password,
        [ValidateSet(1, 3, 15)][int]$Permissions = 1
    )

    return (New-PublicShare -Client $Client -Config $Config -RemotePath $RemotePath -ExpiryDays $ExpiryDays -Password $Password -Permissions $Permissions).Link
}

function Enable-PublicShareNotifications {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ShareId,
        [Parameter(Mandatory = $true)][ValidateRange(1, 15)][int]$EventMask
    )

    $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
    $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('shareId', $ShareId))
    $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('eventMask', [string]$EventMask))
    $content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
    $response = Invoke-HttpRequest -Client $Client -Method 'POST' -Uri (Get-OcsUri $Config 'apps/abonnieren/api/v1/share-notifications') -Content $content -Headers @{ 'OCS-APIRequest' = 'true'; 'Accept' = 'application/json' }
    if (-not $response.IsSuccess) {
        throw (Get-NextcloudShareText 'NotificationsFailed' -FormatArgs @(Get-HttpErrorText $response))
    }

    try { $result = $response.Body | ConvertFrom-Json }
    catch { throw 'Die App Abonnieren hat beim Aktivieren der E-Mail-Benachrichtigungen keine gültige JSON-Antwort geliefert.' }
    if (-not (Test-OcsSuccess $result) -or $result.ocs.data.enabled -ne $true -or [int]$result.ocs.data.eventMask -ne $EventMask) {
        throw (Get-NextcloudShareText 'NotificationsFailed' -FormatArgs @($result.ocs.meta.message))
    }
}

function Remove-PublicShare {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ShareId
    )

    $uri = Get-OcsUri $Config ("apps/files_sharing/api/v1/shares/{0}" -f [Uri]::EscapeDataString($ShareId))
    $response = Invoke-HttpRequest -Client $Client -Method 'DELETE' -Uri $uri -Headers @{ 'OCS-APIRequest' = 'true'; 'Accept' = 'application/json' }
    if (-not $response.IsSuccess) {
        throw "Die unvollständige Freigabe konnte nicht zurückgenommen werden: $(Get-HttpErrorText $response)"
    }

    try { $result = $response.Body | ConvertFrom-Json }
    catch { throw 'Nextcloud hat beim Zurücknehmen der unvollständigen Freigabe keine gültige JSON-Antwort geliefert.' }
    if (-not (Test-OcsSuccess $result)) {
        throw "Die unvollständige Freigabe konnte nicht zurückgenommen werden: $($result.ocs.meta.message)"
    }
}

function ConvertTo-NextcloudSharee {
    param($Entry)

    if ($null -eq $Entry) { return $null }
    $names = @($Entry.PSObject.Properties.Name)
    $shareWith = $null
    $label = $null
    if ($names -contains 'label' -and -not [string]::IsNullOrWhiteSpace([string]$Entry.label)) {
        $label = [string]$Entry.label
    }
    if ($names -contains 'value' -and $null -ne $Entry.value) {
        $valueNames = @($Entry.value.PSObject.Properties.Name)
        if ($valueNames -contains 'shareType' -and [int]$Entry.value.shareType -ne 0) {
            return $null
        }
        if ($valueNames -contains 'shareWith') {
            $shareWith = [string]$Entry.value.shareWith
        }
    }
    if ([string]::IsNullOrWhiteSpace($shareWith) -and $names -contains 'shareWith') {
        $shareWith = [string]$Entry.shareWith
    }
    if ([string]::IsNullOrWhiteSpace($shareWith)) { return $null }
    if ([string]::IsNullOrWhiteSpace($label)) { $label = $shareWith }
    $display = if ([string]::Equals($label, $shareWith, [StringComparison]::OrdinalIgnoreCase)) {
        $label
    }
    else {
        "$label ($shareWith)"
    }
    $sharee = New-Object NextcloudShare.Sharee
    $sharee.ShareWith = $shareWith
    $sharee.Label = $label
    $sharee.Display = $display
    return $sharee
}

function Search-NextcloudSharees {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Search,
        [ValidateSet('file', 'folder')][string]$ItemType = 'file'
    )

    $relative = 'apps/files_sharing/api/v1/sharees?format=json&lookup=false&perPage=20&shareType=0&itemType={0}&search={1}' -f [Uri]::EscapeDataString($ItemType), [Uri]::EscapeDataString($Search)
    $response = Invoke-HttpRequest -Client $Client -Method 'GET' -Uri (Get-OcsUri $Config $relative) -Headers @{ 'OCS-APIRequest' = 'true'; 'Accept' = 'application/json' }
    if (-not $response.IsSuccess) {
        throw (Get-NextcloudShareText 'UserSearchFailed' -FormatArgs @(Get-HttpErrorText $response))
    }
    try { $result = $response.Body | ConvertFrom-Json }
    catch { throw 'Nextcloud hat für die Benutzersuche keine gültige JSON-Antwort geliefert.' }
    if (-not (Test-OcsSuccess $result)) {
        throw (Get-NextcloudShareText 'UserSearchFailed' -FormatArgs @($result.ocs.meta.message))
    }

    $found = New-Object 'System.Collections.Generic.List[NextcloudShare.Sharee]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $groups = New-Object 'System.Collections.Generic.List[object]'
    $data = $result.ocs.data
    if ($null -ne $data) {
        $dataNames = @($data.PSObject.Properties.Name)
        if ($dataNames -contains 'exact' -and $null -ne $data.exact) {
            $exactNames = @($data.exact.PSObject.Properties.Name)
            if ($exactNames -contains 'users') { $groups.Add($data.exact.users) }
        }
        if ($dataNames -contains 'users') { $groups.Add($data.users) }
    }
    foreach ($group in $groups) {
        foreach ($entry in @($group)) {
            $user = ConvertTo-NextcloudSharee $entry
            if ($null -eq $user) { continue }
            if ($seen.Add($user.ShareWith)) { $found.Add($user) }
        }
    }
    return $found
}

function Test-AlreadySharedError {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    $normalized = $Message.ToLowerInvariant()
    return ($normalized -match 'already shared') -or
        ($normalized -match 'bereits (geteilt|freigegeben)') -or
        ($normalized -match 'path is already shared')
}

function New-UserShare {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$ShareWith,
        [int]$ExpiryDays = 14,
        [ValidateSet(1, 3, 15)][int]$Permissions = 1
    )

    $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
    $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('path', $RemotePath))
    $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('shareType', '0'))
    $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('shareWith', $ShareWith))
    $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('permissions', [string]$Permissions))
    if ($ExpiryDays -gt 0) { $pairs.Add([Collections.Generic.KeyValuePair[string,string]]::new('expireDate', (Get-Date).AddDays($ExpiryDays).ToString('yyyy-MM-dd'))) }

    $content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
    $response = Invoke-HttpRequest -Client $Client -Method 'POST' -Uri (Get-OcsUri $Config 'apps/files_sharing/api/v1/shares') -Content $content -Headers @{ 'OCS-APIRequest' = 'true'; 'Accept' = 'application/json' }
    if (-not $response.IsSuccess) {
        $errorText = Get-HttpErrorText $response
        if (Test-AlreadySharedError $errorText) {
            return [pscustomobject]@{
                ShareId       = $null
                AlreadyShared = $true
                ShareWith     = $ShareWith
            }
        }
        throw (Get-NextcloudShareText 'UserShareFailed' -FormatArgs @($errorText))
    }

    try { $result = $response.Body | ConvertFrom-Json }
    catch { throw 'Nextcloud hat beim Erstellen der Benutzerfreigabe keine gültige JSON-Antwort geliefert.' }
    if (-not (Test-OcsSuccess $result)) {
        $message = [string]$result.ocs.meta.message
        if (Test-AlreadySharedError $message) {
            return [pscustomobject]@{
                ShareId       = $null
                AlreadyShared = $true
                ShareWith     = $ShareWith
            }
        }
        throw (Get-NextcloudShareText 'UserShareFailed' -FormatArgs @($message))
    }
    $shareId = Get-ShareIdFromData -Data $result.ocs.data
    return [pscustomobject]@{
        ShareId       = $shareId
        AlreadyShared = $false
        ShareWith     = $ShareWith
    }
}

function Get-NextcloudShareIdsForPath {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemotePath
    )

    $uri = Get-OcsUri $Config ('apps/files_sharing/api/v1/shares?format=json&reshares=false&path={0}' -f [Uri]::EscapeDataString($RemotePath))
    $response = Invoke-HttpRequest -Client $Client -Method 'GET' -Uri $uri -Headers @{ 'OCS-APIRequest' = 'true'; 'Accept' = 'application/json' }
    if (-not $response.IsSuccess) { return @() }
    try { $result = $response.Body | ConvertFrom-Json }
    catch { return @() }
    if (-not (Test-OcsSuccess $result)) { return @() }

    $ids = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in @($result.ocs.data)) {
        $shareId = Get-ShareIdFromData -Data $item
        if (-not [string]::IsNullOrWhiteSpace($shareId)) { $ids.Add($shareId) }
    }
    return $ids
}

function Get-InternalFileLink {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemotePath
    )

    $xml = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns"><d:prop><oc:fileid /></d:prop></d:propfind>'
    $content = [System.Net.Http.StringContent]::new($xml, [Text.Encoding]::UTF8, 'application/xml')
    $response = Invoke-HttpRequest -Client $Client -Method 'PROPFIND' -Uri (Get-WebDavUri $Config $RemotePath) -Content $content -Headers @{ 'Depth' = '0' }
    if (-not $response.IsSuccess) { throw (Get-NextcloudShareText 'InternalLinkFailed' -FormatArgs @(Get-HttpErrorText $response)) }

    try {
        [xml]$document = $response.Body
        $ns = New-Object Xml.XmlNamespaceManager($document.NameTable)
        $ns.AddNamespace('oc', 'http://owncloud.org/ns')
        $node = $document.SelectSingleNode('//oc:fileid', $ns)
        if ($null -eq $node -or [string]::IsNullOrWhiteSpace($node.InnerText)) { throw 'Datei-ID fehlt.' }
        return $Config.ServerUrl.TrimEnd('/') + '/index.php/f/' + $node.InnerText
    }
    catch {
        throw "Nextcloud hat keine verwertbare Datei-ID geliefert: $($_.Exception.Message)"
    }
}

function Set-FormPositionAtCursorScreen {
    param([Parameter(Mandatory = $true)][Windows.Forms.Form]$Form)

    $workingArea = [Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position).WorkingArea
    $x = $workingArea.Left + [Math]::Max(0, [int](($workingArea.Width - $Form.Width) / 2))
    $y = $workingArea.Top + [Math]::Max(0, [int](($workingArea.Height - $Form.Height) / 2))
    $Form.StartPosition = [Windows.Forms.FormStartPosition]::Manual
    $Form.Location = New-Object Drawing.Point($x, $y)
}

function Show-ShareOptionsDialog {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string[]]$LocalPaths
    )

    $state = @{
        SearchClient      = $null
        SearchErrorShown  = $false
        SelectedUsers     = New-Object 'System.Collections.Generic.List[NextcloudShare.Sharee]'
    }
    $searchTimer = New-Object Windows.Forms.Timer
    $searchTimer.Interval = 300

    $form = New-Object Windows.Forms.Form
    $form.Text = Get-NextcloudShareText 'ShareDialogTitle'
    $form.Size = New-Object Drawing.Size(520, 452)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ShowInTaskbar = $true

    $fileLabel = New-Object Windows.Forms.Label
    $fileLabel.Location = New-Object Drawing.Point(18, 18)
    $fileLabel.Size = New-Object Drawing.Size(470, 38)
    $fileLabel.Text = if ($LocalPaths.Count -eq 1) {
        [IO.Path]::GetFileName($LocalPaths[0])
    }
    else {
        (Get-NextcloudShareText 'SharedFilesFolder' -FormatArgs @($LocalPaths.Count))
    }
    $fileLabel.Font = New-Object Drawing.Font($fileLabel.Font, [Drawing.FontStyle]::Bold)
    $form.Controls.Add($fileLabel)

    $modeLabel = New-Object Windows.Forms.Label
    $modeLabel.Location = New-Object Drawing.Point(18, 70)
    $modeLabel.Size = New-Object Drawing.Size(150, 22)
    $modeLabel.Text = Get-NextcloudShareText 'ShareTypeLabel'
    $form.Controls.Add($modeLabel)

    $mode = New-Object Windows.Forms.ComboBox
    $mode.Location = New-Object Drawing.Point(175, 67)
    $mode.Size = New-Object Drawing.Size(310, 24)
    $mode.DropDownStyle = 'DropDownList'
    [void]$mode.Items.Add((Get-NextcloudShareText 'ShareTypePublic'))
    [void]$mode.Items.Add((Get-NextcloudShareText 'ShareTypeInternal'))
    $mode.SelectedIndex = if ($Config.DefaultMode -eq 'Internal') { 1 } else { 0 }
    $form.Controls.Add($mode)

    $permissionLabel = New-Object Windows.Forms.Label
    $permissionLabel.Location = New-Object Drawing.Point(18, 112)
    $permissionLabel.Size = New-Object Drawing.Size(150, 22)
    $permissionLabel.Text = Get-NextcloudShareText 'PermissionLabel'
    $form.Controls.Add($permissionLabel)

    $permission = New-Object Windows.Forms.ComboBox
    $permission.Location = New-Object Drawing.Point(175, 109)
    $permission.Size = New-Object Drawing.Size(310, 24)
    $permission.DropDownStyle = 'DropDownList'
    [void]$permission.Items.Add((Get-NextcloudShareText 'PermissionRead'))
    [void]$permission.Items.Add((Get-NextcloudShareText 'PermissionReadWrite'))
    [void]$permission.Items.Add((Get-NextcloudShareText 'PermissionFull'))
    $permission.SelectedIndex = 0
    $form.Controls.Add($permission)

    $expiryLabel = New-Object Windows.Forms.Label
    $expiryLabel.Location = New-Object Drawing.Point(18, 151)
    $expiryLabel.Size = New-Object Drawing.Size(150, 22)
    $expiryLabel.Text = Get-NextcloudShareText 'ExpiryLabel'
    $form.Controls.Add($expiryLabel)

    $expiry = New-Object Windows.Forms.NumericUpDown
    $expiry.Location = New-Object Drawing.Point(175, 148)
    $expiry.Size = New-Object Drawing.Size(90, 24)
    $expiry.Minimum = 1
    $expiry.Maximum = 365
    $expiry.Value = [Math]::Min(365, [Math]::Max(1, [int]$Config.DefaultExpiryDays))
    $form.Controls.Add($expiry)

    $passwordLabel = New-Object Windows.Forms.Label
    $passwordLabel.Location = New-Object Drawing.Point(18, 190)
    $passwordLabel.Size = New-Object Drawing.Size(150, 22)
    $passwordLabel.Text = Get-NextcloudShareText 'PasswordLabel'
    $form.Controls.Add($passwordLabel)

    $password = New-Object Windows.Forms.TextBox
    $password.Location = New-Object Drawing.Point(175, 187)
    $password.Size = New-Object Drawing.Size(310, 24)
    $password.UseSystemPasswordChar = $true
    $form.Controls.Add($password)

    $notificationLabel = New-Object Windows.Forms.Label
    $notificationLabel.Location = New-Object Drawing.Point(18, 226)
    $notificationLabel.Size = New-Object Drawing.Size(150, 44)
    $notificationLabel.Text = Get-NextcloudShareText 'NotifyLabel'
    $form.Controls.Add($notificationLabel)

    $notifyOnDownload = New-Object Windows.Forms.CheckBox
    $notifyOnDownload.Location = New-Object Drawing.Point(175, 223)
    $notifyOnDownload.Size = New-Object Drawing.Size(130, 24)
    $notifyOnDownload.Text = Get-NextcloudShareText 'NotifyDownload'
    $notifyOnDownload.Checked = $false
    $form.Controls.Add($notifyOnDownload)

    $notifyOnUpload = New-Object Windows.Forms.CheckBox
    $notifyOnUpload.Location = New-Object Drawing.Point(330, 223)
    $notifyOnUpload.Size = New-Object Drawing.Size(130, 24)
    $notifyOnUpload.Text = Get-NextcloudShareText 'NotifyUpload'
    $notifyOnUpload.Checked = $false
    $form.Controls.Add($notifyOnUpload)

    $notifyOnModification = New-Object Windows.Forms.CheckBox
    $notifyOnModification.Location = New-Object Drawing.Point(175, 251)
    $notifyOnModification.Size = New-Object Drawing.Size(130, 24)
    $notifyOnModification.Text = Get-NextcloudShareText 'NotifyModify'
    $notifyOnModification.Checked = $false
    $form.Controls.Add($notifyOnModification)

    $notifyOnDeletion = New-Object Windows.Forms.CheckBox
    $notifyOnDeletion.Location = New-Object Drawing.Point(330, 251)
    $notifyOnDeletion.Size = New-Object Drawing.Size(130, 24)
    $notifyOnDeletion.Text = Get-NextcloudShareText 'NotifyDelete'
    $notifyOnDeletion.Checked = $false
    $form.Controls.Add($notifyOnDeletion)

    $userLabel = New-Object Windows.Forms.Label
    $userLabel.Location = New-Object Drawing.Point(18, 292)
    $userLabel.Size = New-Object Drawing.Size(150, 22)
    $userLabel.Text = Get-NextcloudShareText 'UsersLabel'
    $form.Controls.Add($userLabel)

    $userSearch = New-Object Windows.Forms.TextBox
    $userSearch.Location = New-Object Drawing.Point(175, 289)
    $userSearch.Size = New-Object Drawing.Size(310, 24)
    $form.Controls.Add($userSearch)
    $searchTip = New-Object Windows.Forms.ToolTip
    $searchTip.SetToolTip($userSearch, (Get-NextcloudShareText 'SearchUsersTip'))

    $selectedUsers = New-Object Windows.Forms.ListBox
    $selectedUsers.Location = New-Object Drawing.Point(175, 319)
    $selectedUsers.Size = New-Object Drawing.Size(310, 96)
    $selectedUsers.IntegralHeight = $false
    $form.Controls.Add($selectedUsers)

    $removeUser = New-Object Windows.Forms.Button
    $removeUser.Location = New-Object Drawing.Point(175, 421)
    $removeUser.Size = New-Object Drawing.Size(110, 26)
    $removeUser.Text = Get-NextcloudShareText 'RemoveUser'
    $form.Controls.Add($removeUser)

    $suggestions = New-Object Windows.Forms.ListBox
    $suggestions.Location = New-Object Drawing.Point(175, 313)
    $suggestions.Size = New-Object Drawing.Size(310, 120)
    $suggestions.IntegralHeight = $false
    $suggestions.Visible = $false
    $form.Controls.Add($suggestions)
    $suggestions.BringToFront()

    $hint = New-Object Windows.Forms.Label
    $hint.Location = New-Object Drawing.Point(18, 292)
    $hint.Size = New-Object Drawing.Size(465, 44)
    $form.Controls.Add($hint)

    $ok = New-Object Windows.Forms.Button
    $ok.Location = New-Object Drawing.Point(300, 370)
    $ok.Size = New-Object Drawing.Size(88, 28)
    $ok.Text = Get-NextcloudShareText 'ShareButton'
    $ok.DialogResult = [Windows.Forms.DialogResult]::None
    $form.Controls.Add($ok)
    $form.AcceptButton = $ok

    $cancel = New-Object Windows.Forms.Button
    $cancel.Location = New-Object Drawing.Point(397, 370)
    $cancel.Size = New-Object Drawing.Size(88, 28)
    $cancel.Text = Get-NextcloudShareText 'CancelButton'
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $form.CancelButton = $cancel

    $hideSuggestions = {
        $suggestions.Visible = $false
        $suggestions.Items.Clear()
    }

    $addSelectedSharee = {
        param($Sharee)
        if ($null -eq $Sharee) { return }
        foreach ($existing in $state.SelectedUsers) {
            if ([string]::Equals($existing.ShareWith, $Sharee.ShareWith, [StringComparison]::OrdinalIgnoreCase)) {
                return
            }
        }
        $state.SelectedUsers.Add($Sharee)
        [void]$selectedUsers.Items.Add($Sharee)
        $userSearch.Text = ''
        & $hideSuggestions
        $userSearch.Focus()
    }

    $searchTimer.Add_Tick({
        $searchTimer.Stop()
        try {
            $query = $userSearch.Text.Trim()
            if ($query.Length -lt 1 -or $mode.SelectedIndex -ne 1) {
                & $hideSuggestions
                return
            }
            if ($null -eq $state.SearchClient) {
                try {
                    $state.SearchClient = New-NextcloudHttpClient $Config
                }
                catch {
                    if (-not $state.SearchErrorShown) {
                        $state.SearchErrorShown = $true
                        [Windows.Forms.MessageBox]::Show(
                            $_.Exception.Message,
                            (Get-NextcloudShareText 'UserSearchTitle'),
                            'OK',
                            'Warning'
                        ) | Out-Null
                    }
                    return
                }
            }
            $itemType = if ($LocalPaths.Count -gt 1) { 'folder' } else { 'file' }
            $results = @(Search-NextcloudSharees -Client $state.SearchClient -Config $Config -Search $query -ItemType $itemType)
            $suggestions.BeginUpdate()
            try {
                $suggestions.Items.Clear()
                foreach ($user in $results) {
                    $alreadySelected = $false
                    foreach ($existing in $state.SelectedUsers) {
                        if ([string]::Equals($existing.ShareWith, $user.ShareWith, [StringComparison]::OrdinalIgnoreCase)) {
                            $alreadySelected = $true
                            break
                        }
                    }
                    if ($alreadySelected) { continue }
                    if (-not [string]::IsNullOrWhiteSpace([string]$Config.Username) -and
                        [string]::Equals($user.ShareWith, [string]$Config.Username, [StringComparison]::OrdinalIgnoreCase)) {
                        continue
                    }
                    [void]$suggestions.Items.Add($user)
                }
            }
            finally {
                $suggestions.EndUpdate()
            }
            if ($suggestions.Items.Count -gt 0) {
                $suggestions.SelectedIndex = 0
                $suggestions.Visible = $true
                $suggestions.BringToFront()
            }
            else {
                $suggestions.Visible = $false
            }
        }
        catch {
            & $hideSuggestions
        }
    })

    $userSearch.Add_TextChanged({
        $searchTimer.Stop()
        if ($userSearch.Text.Trim().Length -lt 1) {
            & $hideSuggestions
            return
        }
        $searchTimer.Start()
    })
    $userSearch.Add_KeyDown({
        if ($_.KeyCode -eq 'Enter') {
            $_.SuppressKeyPress = $true
            $_.Handled = $true
            if ($suggestions.Visible -and $suggestions.Items.Count -gt 0) {
                $item = $suggestions.SelectedItem
                if ($null -eq $item) { $item = $suggestions.Items[0] }
                & $addSelectedSharee $item
            }
        }
        elseif ($_.KeyCode -eq 'Down' -and $suggestions.Visible -and $suggestions.Items.Count -gt 0) {
            $_.Handled = $true
            $suggestions.Focus()
            if ($suggestions.SelectedIndex -lt 0) { $suggestions.SelectedIndex = 0 }
        }
        elseif ($_.KeyCode -eq 'Escape' -and $suggestions.Visible) {
            $_.Handled = $true
            & $hideSuggestions
        }
    })
    $suggestions.Add_Click({
        if ($null -ne $suggestions.SelectedItem) {
            & $addSelectedSharee $suggestions.SelectedItem
        }
    })
    $suggestions.Add_KeyDown({
        if ($_.KeyCode -eq 'Enter' -and $null -ne $suggestions.SelectedItem) {
            $_.SuppressKeyPress = $true
            $_.Handled = $true
            & $addSelectedSharee $suggestions.SelectedItem
        }
        elseif ($_.KeyCode -eq 'Escape') {
            $_.Handled = $true
            & $hideSuggestions
            $userSearch.Focus()
        }
    })
    $removeUser.Add_Click({
        $index = $selectedUsers.SelectedIndex
        if ($index -lt 0) { return }
        $state.SelectedUsers.RemoveAt($index)
        $selectedUsers.Items.RemoveAt($index)
        if ($selectedUsers.Items.Count -gt 0) {
            $selectedUsers.SelectedIndex = [Math]::Min($index, $selectedUsers.Items.Count - 1)
        }
    })
    $selectedUsers.Add_KeyDown({
        if ($_.KeyCode -eq 'Delete') {
            $removeUser.PerformClick()
            $_.Handled = $true
        }
    })

    $ok.Add_Click({
        if ($mode.SelectedIndex -eq 1 -and $state.SelectedUsers.Count -lt 1) {
            [Windows.Forms.MessageBox]::Show(
                (Get-NextcloudShareText 'SelectUserRequired'),
                (Get-NextcloudShareText 'ShareDialogTitle'),
                'OK',
                'Information'
            ) | Out-Null
            $userSearch.Focus()
            return
        }
        $form.DialogResult = [Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $updateControls = {
        $external = $mode.SelectedIndex -eq 0
        $selectedPermissions = @(1, 3, 15)[$permission.SelectedIndex]
        $shareIsFolder = $LocalPaths.Count -gt 1
        $permission.Enabled = $true
        $expiry.Visible = $true
        $expiryLabel.Visible = $true
        $password.Visible = $true
        $passwordLabel.Visible = $true
        $notificationLabel.Visible = $true
        $notifyOnDownload.Visible = $true
        $notifyOnUpload.Visible = $true
        $notifyOnModification.Visible = $true
        $notifyOnDeletion.Visible = $true
        $expiry.Enabled = $true
        $password.Enabled = $external
        if (-not $external) { $password.Text = '' }
        $userLabel.Visible = -not $external
        $userSearch.Visible = -not $external
        $selectedUsers.Visible = -not $external
        $removeUser.Visible = -not $external
        if ($external) { & $hideSuggestions }
        $subscriptionsEnabled = -not ($Config.PSObject.Properties.Name -contains 'SubscriptionsEnabled') -or [bool]$Config.SubscriptionsEnabled
        $notifyOnDownload.Enabled = $subscriptionsEnabled
        $notifyOnUpload.Enabled = ($subscriptionsEnabled -and $shareIsFolder -and (($selectedPermissions -band 4) -ne 0))
        $notifyOnModification.Enabled = ($subscriptionsEnabled -and (($selectedPermissions -band 2) -ne 0))
        $notifyOnDeletion.Enabled = ($subscriptionsEnabled -and $shareIsFolder -and (($selectedPermissions -band 8) -ne 0))
        if (-not $notifyOnDownload.Enabled) { $notifyOnDownload.Checked = $false }
        if (-not $notifyOnUpload.Enabled) { $notifyOnUpload.Checked = $false }
        if (-not $notifyOnModification.Enabled) { $notifyOnModification.Checked = $false }
        if (-not $notifyOnDeletion.Enabled) { $notifyOnDeletion.Checked = $false }
        if ($external) {
            $hint.Text = Get-NextcloudShareText 'ShareHintPublic'
            $hint.Location = New-Object Drawing.Point(18, 292)
            $form.ClientSize = New-Object Drawing.Size(504, 412)
            $ok.Location = New-Object Drawing.Point(300, 370)
            $cancel.Location = New-Object Drawing.Point(397, 370)
        }
        else {
            $hint.Text = Get-NextcloudShareText 'ShareHintInternal'
            $hint.Location = New-Object Drawing.Point(18, 456)
            $form.ClientSize = New-Object Drawing.Size(504, 560)
            $ok.Location = New-Object Drawing.Point(300, 516)
            $cancel.Location = New-Object Drawing.Point(397, 516)
        }
        $ok.BringToFront()
        $cancel.BringToFront()
    }
    $mode.Add_SelectedIndexChanged($updateControls)
    $permission.Add_SelectedIndexChanged($updateControls)
    & $updateControls

    Set-FormPositionAtCursorScreen $form
    $form.Add_Shown({
        $form.WindowState = [Windows.Forms.FormWindowState]::Normal
        $form.TopMost = $true
        $form.Activate()
        $form.BringToFront()
    })
    try {
        if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
        $sharePermissions = @(1, 3, 15)[$permission.SelectedIndex]
        $notificationEvents = 0
        if ($notifyOnUpload.Checked) { $notificationEvents = $notificationEvents -bor 1 }
        if ($notifyOnModification.Checked) { $notificationEvents = $notificationEvents -bor 2 }
        if ($notifyOnDeletion.Checked) { $notificationEvents = $notificationEvents -bor 4 }
        if ($notifyOnDownload.Checked) { $notificationEvents = $notificationEvents -bor 8 }
        $shareWith = @($state.SelectedUsers | ForEach-Object { $_.ShareWith })
        if ($mode.SelectedIndex -ne 1) { $shareWith = @() }
        return [pscustomobject]@{
            Mode               = if ($mode.SelectedIndex -eq 1) { 'Internal' } else { 'Public' }
            ExpiryDays         = [int]$expiry.Value
            Password           = if ($mode.SelectedIndex -eq 0) { $password.Text } else { '' }
            Permissions        = [int]$sharePermissions
            NotificationEvents = [int]$notificationEvents
            ShareWith          = $shareWith
        }
    }
    finally {
        $searchTimer.Stop()
        $searchTimer.Dispose()
        if ($null -ne $state.SearchClient) { $state.SearchClient.Dispose() }
        $form.Dispose()
    }
}

function New-RandomSharePassword {
    param([int]$Length = 20)

    if ($Length -lt 12) { $Length = 12 }
    $categories = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',
        'abcdefghijkmnopqrstuvwxyz',
        '23456789',
        '!@$%*-_+'
    )
    $alphabet = ($categories -join '')
    $buffer = New-Object byte[] 1
    $characters = New-Object 'System.Collections.Generic.List[char]'
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $randomIndex = {
            param([int]$Maximum)
            $limit = 256 - (256 % $Maximum)
            do { $rng.GetBytes($buffer) } while ([int]$buffer[0] -ge $limit)
            return [int]$buffer[0] % $Maximum
        }
        foreach ($category in $categories) {
            [void]$characters.Add($category[(& $randomIndex $category.Length)])
        }
        while ($characters.Count -lt $Length) {
            [void]$characters.Add($alphabet[(& $randomIndex $alphabet.Length)])
        }
        for ($i = $characters.Count - 1; $i -gt 0; $i--) {
            $j = & $randomIndex ($i + 1)
            $temporary = $characters[$i]
            $characters[$i] = $characters[$j]
            $characters[$j] = $temporary
        }
        return -join $characters
    }
    finally {
        $rng.Dispose()
    }
}

function Show-RequiredSharePasswordDialog {
    param([Parameter(Mandatory = $true)][string]$ItemDescription)

    $form = New-Object Windows.Forms.Form
    $form.Text = Get-NextcloudShareText 'PasswordDialogTitle'
    $form.Size = New-Object Drawing.Size(560, 250)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ShowInTaskbar = $true

    $fileLabel = New-Object Windows.Forms.Label
    $fileLabel.Location = New-Object Drawing.Point(18, 16)
    $fileLabel.Size = New-Object Drawing.Size(510, 24)
    $fileLabel.Text = $ItemDescription
    $fileLabel.Font = New-Object Drawing.Font($fileLabel.Font, [Drawing.FontStyle]::Bold)
    $form.Controls.Add($fileLabel)

    $hint = New-Object Windows.Forms.Label
    $hint.Location = New-Object Drawing.Point(18, 48)
    $hint.Size = New-Object Drawing.Size(510, 42)
    $hint.Text = Get-NextcloudShareText 'PasswordRequiredHint'
    $form.Controls.Add($hint)

    $password = New-Object Windows.Forms.TextBox
    $password.Location = New-Object Drawing.Point(18, 100)
    $password.Size = New-Object Drawing.Size(390, 24)
    $password.Text = New-RandomSharePassword
    $form.Controls.Add($password)

    $regenerate = New-Object Windows.Forms.Button
    $regenerate.Location = New-Object Drawing.Point(420, 98)
    $regenerate.Size = New-Object Drawing.Size(108, 27)
    $regenerate.Text = Get-NextcloudShareText 'RegeneratePassword'
    $regenerate.Add_Click({ $password.Text = New-RandomSharePassword })
    $form.Controls.Add($regenerate)

    $copyHint = New-Object Windows.Forms.Label
    $copyHint.Location = New-Object Drawing.Point(18, 135)
    $copyHint.Size = New-Object Drawing.Size(510, 30)
    $copyHint.Text = Get-NextcloudShareText 'PasswordCopyHint'
    $form.Controls.Add($copyHint)

    $ok = New-Object Windows.Forms.Button
    $ok.Location = New-Object Drawing.Point(326, 174)
    $ok.Size = New-Object Drawing.Size(105, 28)
    $ok.Text = Get-NextcloudShareText 'CreateLink'
    $ok.Add_Click({
        if ([string]::IsNullOrWhiteSpace($password.Text)) {
            [Windows.Forms.MessageBox]::Show($form, (Get-NextcloudShareText 'PasswordRequired'), (Get-NextcloudShareText 'AppTitle'), 'OK', 'Warning') | Out-Null
            return
        }
        $form.DialogResult = [Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($ok)
    $form.AcceptButton = $ok

    $cancel = New-Object Windows.Forms.Button
    $cancel.Location = New-Object Drawing.Point(440, 174)
    $cancel.Size = New-Object Drawing.Size(88, 28)
    $cancel.Text = Get-NextcloudShareText 'CancelButton'
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $form.CancelButton = $cancel

    $form.Add_Shown({ $password.SelectAll(); $password.Focus() })
    if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
    return $password.Text
}

function Show-ConfigurationDialog {
    $admin = Get-NextcloudShareAdminConfig
    $existing = Get-NextcloudShareConfig
    $existingAuthMethod = ''
    if ($existing -and $existing.PSObject.Properties.Name -contains 'AuthMethod') {
        $existingAuthMethod = [string]$existing.AuthMethod
    }
    $hasLoginFlowCredentials = $existing -and
        $existingAuthMethod -eq 'LoginFlowV2' -and
        -not [string]::IsNullOrWhiteSpace([string]$existing.EncryptedAppPassword)

    $form = New-Object Windows.Forms.Form
    $form.Text = Get-NextcloudShareText 'ConfigureTitle'
    $form.Size = New-Object Drawing.Size(640, 570)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ShowInTaskbar = $true

    $fields = @{}
    $defaultLocalRoot = if ($existing -and $existing.PSObject.Properties.Name -contains 'LocalNextcloudRoot') {
        [string]$existing.LocalNextcloudRoot
    }
    else {
        Get-NextcloudClientSyncRoot -ServerUrl ([string]$admin.ServerUrl)
    }
    $rows = @(
        @{ Key='ServerUrl'; Label=(Get-NextcloudShareText 'LabelServerUrl'); Value=if($existing){$existing.ServerUrl}else{$admin.ServerUrl} },
        @{ Key='Username'; Label=(Get-NextcloudShareText 'LabelUsername'); Value=if($existing){$existing.Username}else{[Environment]::UserName} },
        @{ Key='LocalRoot'; Label=(Get-NextcloudShareText 'LabelLocalRoot'); Value=$defaultLocalRoot },
        @{ Key='RemoteRoot'; Label=(Get-NextcloudShareText 'LabelRemoteRoot'); Value=if($existing){$existing.RemoteSyncRoot}else{$admin.RemoteSyncRoot} },
        @{ Key='UploadFolder'; Label=(Get-NextcloudShareText 'LabelUploadFolder'); Value=if($existing){$existing.RemoteUploadFolder}else{$admin.RemoteUploadFolder} }
    )

    $y = 24
    foreach ($row in $rows) {
        $label = New-Object Windows.Forms.Label
        $label.Location = New-Object Drawing.Point(18, $y)
        $label.Size = New-Object Drawing.Size(210, 22)
        $label.Text = $row.Label
        $form.Controls.Add($label)

        $box = New-Object Windows.Forms.TextBox
        $box.Location = New-Object Drawing.Point(235, ($y - 3))
        $box.Size = New-Object Drawing.Size(360, 24)
        $box.Text = [string]$row.Value
        if ($row.Key -eq 'Username' -or
            ($row.Key -eq 'ServerUrl' -and -not $admin.AllowServerUrlOverride) -or
            ($row.Key -eq 'UploadFolder' -and -not $admin.AllowRemoteUploadFolderOverride)) {
            $box.ReadOnly = $true
        }
        $form.Controls.Add($box)
        $fields[$row.Key] = $box
        $y += 47
    }

    $browse = New-Object Windows.Forms.Button
    $browse.Location = New-Object Drawing.Point(495, 112)
    $browse.Size = New-Object Drawing.Size(100, 25)
    $browse.Text = Get-NextcloudShareText 'Browse'
    $browse.Add_Click({
        $dialog = New-Object Windows.Forms.FolderBrowserDialog
        $dialog.SelectedPath = $fields.LocalRoot.Text
        if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $fields.LocalRoot.Text = $dialog.SelectedPath }
    })
    $form.Controls.Add($browse)
    $fields.LocalRoot.Size = New-Object Drawing.Size(250, 24)

    $modeLabel = New-Object Windows.Forms.Label
    $modeLabel.Location = New-Object Drawing.Point(18, 260)
    $modeLabel.Size = New-Object Drawing.Size(210, 22)
    $modeLabel.Text = Get-NextcloudShareText 'DefaultShareType'
    $form.Controls.Add($modeLabel)

    $mode = New-Object Windows.Forms.ComboBox
    $mode.Location = New-Object Drawing.Point(235, 257)
    $mode.Size = New-Object Drawing.Size(360, 24)
    $mode.DropDownStyle = 'DropDownList'
    [void]$mode.Items.Add((Get-NextcloudShareText 'ShareTypePublic'))
    [void]$mode.Items.Add((Get-NextcloudShareText 'ShareTypeInternalShort'))
    $mode.SelectedIndex = if ($existing -and $existing.DefaultMode -eq 'Internal') { 1 } else { 0 }
    $mode.Enabled = [bool]$admin.AllowShareDefaultsOverride
    $form.Controls.Add($mode)

    $daysLabel = New-Object Windows.Forms.Label
    $daysLabel.Location = New-Object Drawing.Point(18, 307)
    $daysLabel.Size = New-Object Drawing.Size(210, 22)
    $daysLabel.Text = Get-NextcloudShareText 'DefaultExpiry'
    $form.Controls.Add($daysLabel)

    $days = New-Object Windows.Forms.NumericUpDown
    $days.Location = New-Object Drawing.Point(235, 304)
    $days.Size = New-Object Drawing.Size(90, 24)
    $days.Minimum = 1
    $days.Maximum = 365
    $days.Value = if($existing){[Math]::Min(365,[Math]::Max(1,[int]$existing.DefaultExpiryDays))}else{14}
    $days.Enabled = [bool]$admin.AllowShareDefaultsOverride
    $form.Controls.Add($days)

    $statusTitle = New-Object Windows.Forms.Label
    $statusTitle.Location = New-Object Drawing.Point(18, 352)
    $statusTitle.Size = New-Object Drawing.Size(210, 22)
    $statusTitle.Text = Get-NextcloudShareText 'ConnectionLabel'
    $form.Controls.Add($statusTitle)

    $status = New-Object Windows.Forms.Label
    $status.Location = New-Object Drawing.Point(235, 352)
    $status.Size = New-Object Drawing.Size(360, 42)
    $status.Text = if ($hasLoginFlowCredentials) { Get-NextcloudShareText 'ConnectedAs' -FormatArgs @($existing.Username) } else { Get-NextcloudShareText 'NotConnected' }
    $form.Controls.Add($status)

    $connect = New-Object Windows.Forms.Button
    $connect.Location = New-Object Drawing.Point(235, 400)
    $connect.Size = New-Object Drawing.Size(190, 30)
    $connect.Text = Get-NextcloudShareText 'ConnectNextcloud'
    $form.Controls.Add($connect)

    $security = New-Object Windows.Forms.Label
    $security.Location = New-Object Drawing.Point(18, 447)
    $security.Size = New-Object Drawing.Size(575, 42)
    $security.Text = Get-NextcloudShareText 'LoginSecurityHint'
    $form.Controls.Add($security)

    $save = New-Object Windows.Forms.Button
    $save.Location = New-Object Drawing.Point(410, 498)
    $save.Size = New-Object Drawing.Size(88, 28)
    $save.Text = Get-NextcloudShareText 'Save'
    $save.Enabled = [bool]$hasLoginFlowCredentials
    $form.Controls.Add($save)

    $cancel = New-Object Windows.Forms.Button
    $cancel.Location = New-Object Drawing.Point(507, 498)
    $cancel.Size = New-Object Drawing.Size(88, 28)
    $cancel.Text = Get-NextcloudShareText 'CancelButton'
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $form.CancelButton = $cancel

    $buildConfig = {
        param([string]$ServerUrl, [string]$Username, [string]$EncryptedPassword)
        $config = [pscustomobject]@{
            ServerUrl            = $ServerUrl.Trim().TrimEnd('/')
            Username             = $Username.Trim()
            EncryptedAppPassword = $EncryptedPassword
            AuthMethod           = 'LoginFlowV2'
            AuthenticatedAt      = (Get-Date).ToString('o')
            AuthenticatedServerUrl = $ServerUrl.Trim().TrimEnd('/')
            LocalNextcloudRoot   = $fields.LocalRoot.Text.Trim().TrimEnd('\')
            RemoteSyncRoot       = '/' + $fields.RemoteRoot.Text.Trim().Trim('/')
            RemoteUploadFolder   = '/' + $fields.UploadFolder.Text.Trim().Trim('/')
            DefaultMode          = if ($mode.SelectedIndex -eq 1) { 'Internal' } else { 'Public' }
            DefaultExpiryDays    = [int]$days.Value
            SubscriptionsEnabled = [bool]$admin.SubscriptionsEnabled
            SchemaVersion        = 1
        }
        if ($config.RemoteSyncRoot -eq '//') { $config.RemoteSyncRoot = '/' }
        if ($existing -and $existing.PSObject.Properties.Name -contains 'WebDavUserId') {
            Add-Member -InputObject $config -MemberType NoteProperty -Name WebDavUserId -Value ([string]$existing.WebDavUserId) -Force
        }
        if ($existing -and $existing.PSObject.Properties.Name -contains 'WebDavEndpoint') {
            Add-Member -InputObject $config -MemberType NoteProperty -Name WebDavEndpoint -Value ([string]$existing.WebDavEndpoint) -Force
        }
        return $config
    }

    $connect.Add_Click({
        try {
            $connect.Enabled = $false
            $save.Enabled = $false
            $cancel.Enabled = $false
            $form.TopMost = $false
            Test-NextcloudServerUrl $fields.ServerUrl.Text
            if (-not [string]::IsNullOrWhiteSpace($fields.LocalRoot.Text) -and
                -not (Test-Path -LiteralPath $fields.LocalRoot.Text -PathType Container)) {
                throw (Get-NextcloudShareText 'LocalFolderMissing')
            }

            $credentials = Start-NextcloudLoginFlow -ServerUrl $fields.ServerUrl.Text -StatusCallback {
                param($message)
                if ($form.IsDisposed) { throw (Get-NextcloudShareText 'LoginCancelled') }
                $status.Text = $message
                [Windows.Forms.Application]::DoEvents()
            }
            $fields.ServerUrl.Text = $credentials.ServerUrl
            $fields.Username.Text = $credentials.Username
            $encrypted = Protect-AppPassword $credentials.AppPassword
            $config = & $buildConfig $credentials.ServerUrl $credentials.Username $encrypted
            Test-NextcloudShareConfig $config
            $status.Text = Get-NextcloudShareText 'ResolvingWebDav'
            [Windows.Forms.Application]::DoEvents()
            $config = Initialize-NextcloudWebDavIdentity -Config $config -Force
            $form.DialogResult = [Windows.Forms.DialogResult]::OK
            $form.Close()
        }
        catch {
            if (-not $form.IsDisposed) {
                $form.TopMost = $true
                $status.Text = Get-NextcloudShareText 'ConnectionFailed'
                [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, (Get-NextcloudShareText 'LoginDialogTitle'), 'OK', 'Error') | Out-Null
            }
        }
        finally {
            if (-not $form.IsDisposed) {
                $connect.Enabled = $true
                $cancel.Enabled = $true
                $save.Enabled = [bool]$hasLoginFlowCredentials
            }
        }
    })

    $save.Add_Click({
        try {
            $config = & $buildConfig ([string]$existing.ServerUrl) ([string]$existing.Username) ([string]$existing.EncryptedAppPassword)
            Test-NextcloudShareConfig $config
            Save-NextcloudShareConfig $config
            $form.DialogResult = [Windows.Forms.DialogResult]::OK
            $form.Close()
        }
        catch {
            [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, (Get-NextcloudShareText 'ConfigDialogTitle'), 'OK', 'Error') | Out-Null
        }
    })

    $form.Add_Shown({
        $form.Activate()
        $form.BringToFront()
        if (-not $hasLoginFlowCredentials) { $connect.PerformClick() }
    })
    return $form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK
}

function Show-ProgressWindow {
    param([string]$Text)
    $form = New-Object Windows.Forms.Form
    $form.Text = Get-NextcloudShareText 'AppTitle'
    $form.Size = New-Object Drawing.Size(440, 125)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.ControlBox = $false
    $form.TopMost = $true
    $form.ShowInTaskbar = $true
    $label = New-Object Windows.Forms.Label
    $label.Name = 'StatusLabel'
    $label.Location = New-Object Drawing.Point(16, 14)
    $label.Size = New-Object Drawing.Size(395, 24)
    $label.Text = $Text
    $form.Controls.Add($label)
    $bar = New-Object Windows.Forms.ProgressBar
    $bar.Location = New-Object Drawing.Point(16, 50)
    $bar.Size = New-Object Drawing.Size(395, 18)
    $bar.Style = 'Marquee'
    $form.Controls.Add($bar)
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    return $form
}

function Set-ProgressText {
    param([Windows.Forms.Form]$Form, [string]$Text)
    $Form.Controls['StatusLabel'].Text = $Text
    [Windows.Forms.Application]::DoEvents()
}

function Set-ClipboardTextWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [int]$Attempts = 12,
        [int]$DelayMilliseconds = 150
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            # SetDataObject besitzt zusätzlich eine interne Wiederholungslogik für
            # eine kurzzeitig durch andere Programme gesperrte Zwischenablage.
            [Windows.Forms.Clipboard]::SetDataObject($Text, $true, 5, 100)
            return $true
        }
        catch {
            if ($attempt -lt $Attempts) {
                [Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds $DelayMilliseconds
            }
        }
    }
    return $false
}

function Show-ClipboardFallbackDialog {
    param([Parameter(Mandatory = $true)][string]$Text)

    $form = New-Object Windows.Forms.Form
    $form.Text = Get-NextcloudShareText 'ClipboardDialogTitle'
    $form.Size = New-Object Drawing.Size(680, 280)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ShowInTaskbar = $true
    Set-FormPositionAtCursorScreen $form

    $label = New-Object Windows.Forms.Label
    $label.Location = New-Object Drawing.Point(18, 18)
    $label.Size = New-Object Drawing.Size(630, 44)
    $label.Text = Get-NextcloudShareText 'ClipboardBlocked'
    $form.Controls.Add($label)

    $value = New-Object Windows.Forms.TextBox
    $value.Location = New-Object Drawing.Point(18, 72)
    $value.Size = New-Object Drawing.Size(630, 100)
    $value.Multiline = $true
    $value.ReadOnly = $true
    $value.ScrollBars = 'Vertical'
    $value.Text = $Text
    $form.Controls.Add($value)

    $status = New-Object Windows.Forms.Label
    $status.Location = New-Object Drawing.Point(18, 182)
    $status.Size = New-Object Drawing.Size(365, 34)
    $status.Text = Get-NextcloudShareText 'ClipboardHint'
    $form.Controls.Add($status)

    $retry = New-Object Windows.Forms.Button
    $retry.Location = New-Object Drawing.Point(410, 190)
    $retry.Size = New-Object Drawing.Size(130, 30)
    $retry.Text = Get-NextcloudShareText 'CopyAgain'
    $retry.Add_Click({
        if (Set-ClipboardTextWithRetry -Text $value.Text) {
            $form.DialogResult = [Windows.Forms.DialogResult]::OK
            $form.Close()
        }
        else {
            $status.Text = Get-NextcloudShareText 'ClipboardStillBlocked'
            $value.SelectAll()
            $value.Focus()
        }
    })
    $form.Controls.Add($retry)

    $close = New-Object Windows.Forms.Button
    $close.Location = New-Object Drawing.Point(550, 190)
    $close.Size = New-Object Drawing.Size(98, 30)
    $close.Text = Get-NextcloudShareText 'Close'
    $close.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($close)
    $form.CancelButton = $close

    $form.Add_Shown({ $value.SelectAll(); $value.Focus() })
    [void]$form.ShowDialog()
    $form.Dispose()
}

function Show-SuccessNotification {
    param(
        [string]$Link,
        [string]$Password,
        [string]$Mode
    )
    $clipboardText = $Link
    $notificationText = Get-NextcloudShareText 'SuccessLinkCopied'
    if ($Mode -eq 'Internal') {
        $notificationText = Get-NextcloudShareText 'SuccessInternalNotified'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Password)) {
        $clipboardText = Get-NextcloudShareText 'ClipboardLinkPassword' -FormatArgs @($Link, $Password)
        $notificationText = Get-NextcloudShareText 'SuccessLinkAndPassword'
    }
    if (-not (Set-ClipboardTextWithRetry -Text $clipboardText)) {
        Show-ClipboardFallbackDialog -Text $clipboardText
        return
    }
    $notify = New-Object Windows.Forms.NotifyIcon
    try {
        $notify.Icon = [Drawing.SystemIcons]::Information
        $notify.Visible = $true
        $notify.BalloonTipTitle = Get-NextcloudShareText 'AppTitle'
        $notify.BalloonTipText = $notificationText
        $notify.ShowBalloonTip(3500)
        Start-Sleep -Milliseconds 1200
    }
    finally {
        $notify.Dispose()
    }
}

Export-ModuleMember -Function *
