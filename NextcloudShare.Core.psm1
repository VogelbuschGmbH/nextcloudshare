Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ProductVersion = '2.0.1'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

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

function Get-NextcloudShareAdminConfig {
    $path = Get-NextcloudShareAdminConfigPath
    $config = Get-NextcloudShareDefaultConfig
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $config }

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

    $Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Get-NextcloudShareConfigPath) -Encoding UTF8
}

function Test-NextcloudShareConfig {
    param([Parameter(Mandatory = $true)]$Config)

    if ([string]::IsNullOrWhiteSpace($Config.ServerUrl)) { throw 'Die Nextcloud-URL fehlt.' }
    $uri = $null
    if (-not [Uri]::TryCreate($Config.ServerUrl, [UriKind]::Absolute, [ref]$uri)) { throw 'Die Nextcloud-URL ist ungültig.' }
    if ($uri.Scheme -ne 'https' -and $uri.Host -notin @('localhost', '127.0.0.1')) {
        throw 'Aus Sicherheitsgründen ist für Nextcloud HTTPS erforderlich.'
    }
    if ([string]::IsNullOrWhiteSpace($Config.Username)) { throw 'Der Nextcloud-Benutzername fehlt.' }
    if ([string]::IsNullOrWhiteSpace($Config.EncryptedAppPassword)) { throw 'Der Nextcloud-Zugriffstoken fehlt.' }
    $localRoot = if ($Config.PSObject.Properties.Name -contains 'LocalNextcloudRoot') {
        [string]$Config.LocalNextcloudRoot
    }
    else { '' }
    if (-not [string]::IsNullOrWhiteSpace($localRoot) -and
        -not (Test-Path -LiteralPath $localRoot -PathType Container)) {
        throw 'Der konfigurierte lokale Nextcloud-Ordner existiert nicht. Bitte wählen Sie einen vorhandenen Ordner oder lassen Sie das Feld leer.'
    }
    if ([string]::IsNullOrWhiteSpace($Config.RemoteUploadFolder)) { throw 'Der Upload-Ordner fehlt.' }
    if ($Config.DefaultMode -notin @('Public', 'Internal')) { throw 'Der Standard-Freigabemodus ist ungültig.' }
}

function Test-NextcloudServerUrl {
    param([Parameter(Mandatory = $true)][string]$ServerUrl)

    if ([string]::IsNullOrWhiteSpace($ServerUrl)) { throw 'Die Nextcloud-URL fehlt.' }
    $uri = $null
    if (-not [Uri]::TryCreate($ServerUrl, [UriKind]::Absolute, [ref]$uri)) { throw 'Die Nextcloud-URL ist ungültig.' }
    if ($uri.Scheme -ne 'https' -and $uri.Host -notin @('localhost', '127.0.0.1')) {
        throw 'Aus Sicherheitsgründen ist für Nextcloud HTTPS erforderlich.'
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
            throw 'Eine Nextcloud-Anmeldung ist bereits geöffnet. Bitte schließen Sie den vorhandenen Browser-Dialog oder warten Sie kurz.'
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
        if ($StatusCallback) { & $StatusCallback 'Nextcloud-Anmeldung wird vorbereitet ...' }
        $startResponse = Invoke-HttpRequest -Client $client -Method 'POST' -Uri "$baseUrl/index.php/login/v2"
        if (-not $startResponse.IsSuccess) {
            throw "Der Nextcloud Login Flow konnte nicht gestartet werden: $(Get-HttpErrorText $startResponse)"
        }

        try { $flow = $startResponse.Body | ConvertFrom-Json }
        catch { throw 'Nextcloud hat keine gültige Login-Flow-Antwort geliefert.' }
        if ([string]::IsNullOrWhiteSpace($flow.login) -or
            [string]::IsNullOrWhiteSpace($flow.poll.token) -or
            [string]::IsNullOrWhiteSpace($flow.poll.endpoint)) {
            throw 'Die Login-Flow-Antwort von Nextcloud ist unvollständig.'
        }

        if ($StatusCallback) { & $StatusCallback 'Browser wurde geöffnet. Bitte Zugriff in Nextcloud erlauben ...' }
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
                if ($StatusCallback) { & $StatusCallback 'Warte auf Freigabe im Browser ...' }
                continue
            }
            if (-not $pollResponse.IsSuccess) {
                throw "Die Nextcloud-Anmeldung ist fehlgeschlagen: $(Get-HttpErrorText $pollResponse)"
            }

            try { $credentials = $pollResponse.Body | ConvertFrom-Json }
            catch { throw 'Nextcloud hat keine gültigen Anmeldedaten geliefert.' }
            if ([string]::IsNullOrWhiteSpace($credentials.server) -or
                [string]::IsNullOrWhiteSpace($credentials.loginName) -or
                [string]::IsNullOrWhiteSpace($credentials.appPassword)) {
                throw 'Die von Nextcloud gelieferten Anmeldedaten sind unvollständig.'
            }

            if ($StatusCallback) { & $StatusCallback "Verbunden als $($credentials.loginName)." }
            return [pscustomobject]@{
                ServerUrl   = ([string]$credentials.server).TrimEnd('/')
                Username    = [string]$credentials.loginName
                AppPassword = [string]$credentials.appPassword
            }
        }
        throw "Die Nextcloud-Anmeldung wurde nicht innerhalb von $TimeoutMinutes Minuten abgeschlossen."
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
    $baseName = 'Freigabe-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
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
            throw "Die Datei konnte nicht nach Nextcloud hochgeladen werden: $(Get-HttpErrorText $response)"
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

    $exception = [InvalidOperationException]::new("Der Freigabelink konnte nicht erzeugt werden: $Message")
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
        throw "Die E-Mail-Benachrichtigungen konnten nicht aktiviert werden: $(Get-HttpErrorText $response)"
    }

    try { $result = $response.Body | ConvertFrom-Json }
    catch { throw 'Die App Abonnieren hat beim Aktivieren der E-Mail-Benachrichtigungen keine gültige JSON-Antwort geliefert.' }
    if (-not (Test-OcsSuccess $result) -or $result.ocs.data.enabled -ne $true -or [int]$result.ocs.data.eventMask -ne $EventMask) {
        throw "Die E-Mail-Benachrichtigungen konnten nicht aktiviert werden: $($result.ocs.meta.message)"
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

function Get-InternalFileLink {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RemotePath
    )

    $xml = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns"><d:prop><oc:fileid /></d:prop></d:propfind>'
    $content = [System.Net.Http.StringContent]::new($xml, [Text.Encoding]::UTF8, 'application/xml')
    $response = Invoke-HttpRequest -Client $Client -Method 'PROPFIND' -Uri (Get-WebDavUri $Config $RemotePath) -Content $content -Headers @{ 'Depth' = '0' }
    if (-not $response.IsSuccess) { throw "Der interne Link konnte nicht ermittelt werden: $(Get-HttpErrorText $response)" }

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

    $form = New-Object Windows.Forms.Form
    $form.Text = 'Über Nextcloud teilen'
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
        "$($LocalPaths.Count) Dateien – gemeinsamer Link zu einem neuen Ordner"
    }
    $fileLabel.Font = New-Object Drawing.Font($fileLabel.Font, [Drawing.FontStyle]::Bold)
    $form.Controls.Add($fileLabel)

    $modeLabel = New-Object Windows.Forms.Label
    $modeLabel.Location = New-Object Drawing.Point(18, 70)
    $modeLabel.Size = New-Object Drawing.Size(150, 22)
    $modeLabel.Text = 'Freigabeart:'
    $form.Controls.Add($modeLabel)

    $mode = New-Object Windows.Forms.ComboBox
    $mode.Location = New-Object Drawing.Point(175, 67)
    $mode.Size = New-Object Drawing.Size(310, 24)
    $mode.DropDownStyle = 'DropDownList'
    [void]$mode.Items.Add('Externer Link')
    [void]$mode.Items.Add('Interner Link (Berechtigung erforderlich)')
    $mode.SelectedIndex = if ($Config.DefaultMode -eq 'Internal') { 1 } else { 0 }
    $form.Controls.Add($mode)

    $permissionLabel = New-Object Windows.Forms.Label
    $permissionLabel.Location = New-Object Drawing.Point(18, 112)
    $permissionLabel.Size = New-Object Drawing.Size(150, 22)
    $permissionLabel.Text = 'Berechtigung:'
    $form.Controls.Add($permissionLabel)

    $permission = New-Object Windows.Forms.ComboBox
    $permission.Location = New-Object Drawing.Point(175, 109)
    $permission.Size = New-Object Drawing.Size(310, 24)
    $permission.DropDownStyle = 'DropDownList'
    [void]$permission.Items.Add('Nur lesen')
    [void]$permission.Items.Add('Lesen und bearbeiten')
    [void]$permission.Items.Add('Lesen, bearbeiten, erstellen und löschen')
    $permission.SelectedIndex = 0
    $form.Controls.Add($permission)

    $expiryLabel = New-Object Windows.Forms.Label
    $expiryLabel.Location = New-Object Drawing.Point(18, 151)
    $expiryLabel.Size = New-Object Drawing.Size(150, 22)
    $expiryLabel.Text = 'Gültig in Tagen:'
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
    $passwordLabel.Text = 'Optionales Passwort:'
    $form.Controls.Add($passwordLabel)

    $password = New-Object Windows.Forms.TextBox
    $password.Location = New-Object Drawing.Point(175, 187)
    $password.Size = New-Object Drawing.Size(310, 24)
    $password.UseSystemPasswordChar = $true
    $form.Controls.Add($password)

    $notificationLabel = New-Object Windows.Forms.Label
    $notificationLabel.Location = New-Object Drawing.Point(18, 226)
    $notificationLabel.Size = New-Object Drawing.Size(150, 44)
    $notificationLabel.Text = 'Benachrichtigen bei:'
    $form.Controls.Add($notificationLabel)

    $notifyOnDownload = New-Object Windows.Forms.CheckBox
    $notifyOnDownload.Location = New-Object Drawing.Point(175, 223)
    $notifyOnDownload.Size = New-Object Drawing.Size(130, 24)
    $notifyOnDownload.Text = 'Download'
    $notifyOnDownload.Checked = $false
    $form.Controls.Add($notifyOnDownload)

    $notifyOnUpload = New-Object Windows.Forms.CheckBox
    $notifyOnUpload.Location = New-Object Drawing.Point(330, 223)
    $notifyOnUpload.Size = New-Object Drawing.Size(130, 24)
    $notifyOnUpload.Text = 'Upload'
    $notifyOnUpload.Checked = $false
    $form.Controls.Add($notifyOnUpload)

    $notifyOnModification = New-Object Windows.Forms.CheckBox
    $notifyOnModification.Location = New-Object Drawing.Point(175, 251)
    $notifyOnModification.Size = New-Object Drawing.Size(130, 24)
    $notifyOnModification.Text = 'Änderung'
    $notifyOnModification.Checked = $false
    $form.Controls.Add($notifyOnModification)

    $notifyOnDeletion = New-Object Windows.Forms.CheckBox
    $notifyOnDeletion.Location = New-Object Drawing.Point(330, 251)
    $notifyOnDeletion.Size = New-Object Drawing.Size(130, 24)
    $notifyOnDeletion.Text = 'Löschung'
    $notifyOnDeletion.Checked = $false
    $form.Controls.Add($notifyOnDeletion)

    $hint = New-Object Windows.Forms.Label
    $hint.Location = New-Object Drawing.Point(18, 292)
    $hint.Size = New-Object Drawing.Size(465, 44)
    $hint.Text = 'Die Auswahl erstellt oder aktualisiert das Abonnement für diese Datei beziehungsweise diesen Ordner.'
    $form.Controls.Add($hint)

    $ok = New-Object Windows.Forms.Button
    $ok.Location = New-Object Drawing.Point(300, 370)
    $ok.Size = New-Object Drawing.Size(88, 28)
    $ok.Text = 'Teilen'
    $ok.DialogResult = [Windows.Forms.DialogResult]::OK
    $form.Controls.Add($ok)
    $form.AcceptButton = $ok

    $cancel = New-Object Windows.Forms.Button
    $cancel.Location = New-Object Drawing.Point(397, 370)
    $cancel.Size = New-Object Drawing.Size(88, 28)
    $cancel.Text = 'Abbrechen'
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $form.CancelButton = $cancel

    $updateControls = {
        $external = $mode.SelectedIndex -eq 0
        $selectedPermissions = @(1, 3, 15)[$permission.SelectedIndex]
        $shareIsFolder = $LocalPaths.Count -gt 1
        $permission.Enabled = $external
        $expiry.Enabled = $external
        $password.Enabled = $external
        $subscriptionsEnabled = -not ($Config.PSObject.Properties.Name -contains 'SubscriptionsEnabled') -or [bool]$Config.SubscriptionsEnabled
        $notifyOnDownload.Enabled = ($external -and $subscriptionsEnabled)
        $notifyOnUpload.Enabled = ($external -and $subscriptionsEnabled -and $shareIsFolder -and (($selectedPermissions -band 4) -ne 0))
        $notifyOnModification.Enabled = ($external -and $subscriptionsEnabled -and (($selectedPermissions -band 2) -ne 0))
        $notifyOnDeletion.Enabled = ($external -and $subscriptionsEnabled -and $shareIsFolder -and (($selectedPermissions -band 8) -ne 0))
        if (-not $notifyOnDownload.Enabled) { $notifyOnDownload.Checked = $false }
        if (-not $notifyOnUpload.Enabled) { $notifyOnUpload.Checked = $false }
        if (-not $notifyOnModification.Enabled) { $notifyOnModification.Checked = $false }
        if (-not $notifyOnDeletion.Enabled) { $notifyOnDeletion.Checked = $false }
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
    if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
    $sharePermissions = if ($mode.SelectedIndex -eq 0) { @(1, 3, 15)[$permission.SelectedIndex] } else { 1 }
    $notificationEvents = 0
    if ($mode.SelectedIndex -eq 0) {
        if ($notifyOnUpload.Checked) { $notificationEvents = $notificationEvents -bor 1 }
        if ($notifyOnModification.Checked) { $notificationEvents = $notificationEvents -bor 2 }
        if ($notifyOnDeletion.Checked) { $notificationEvents = $notificationEvents -bor 4 }
        if ($notifyOnDownload.Checked) { $notificationEvents = $notificationEvents -bor 8 }
    }
    return [pscustomobject]@{
        Mode        = if ($mode.SelectedIndex -eq 1) { 'Internal' } else { 'Public' }
        ExpiryDays  = [int]$expiry.Value
        Password    = $password.Text
        Permissions = [int]$sharePermissions
        NotificationEvents = [int]$notificationEvents
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
    $form.Text = 'Passwort für öffentlichen Nextcloud-Link'
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
    $hint.Text = 'Der Nextcloud-Server verlangt für öffentliche Links ein Passwort. Ein sicheres Passwort wurde automatisch erzeugt.'
    $form.Controls.Add($hint)

    $password = New-Object Windows.Forms.TextBox
    $password.Location = New-Object Drawing.Point(18, 100)
    $password.Size = New-Object Drawing.Size(390, 24)
    $password.Text = New-RandomSharePassword
    $form.Controls.Add($password)

    $regenerate = New-Object Windows.Forms.Button
    $regenerate.Location = New-Object Drawing.Point(420, 98)
    $regenerate.Size = New-Object Drawing.Size(108, 27)
    $regenerate.Text = 'Neu erzeugen'
    $regenerate.Add_Click({ $password.Text = New-RandomSharePassword })
    $form.Controls.Add($regenerate)

    $copyHint = New-Object Windows.Forms.Label
    $copyHint.Location = New-Object Drawing.Point(18, 135)
    $copyHint.Size = New-Object Drawing.Size(510, 30)
    $copyHint.Text = 'Nach erfolgreicher Freigabe werden Link und Passwort gemeinsam in die Zwischenablage kopiert.'
    $form.Controls.Add($copyHint)

    $ok = New-Object Windows.Forms.Button
    $ok.Location = New-Object Drawing.Point(326, 174)
    $ok.Size = New-Object Drawing.Size(105, 28)
    $ok.Text = 'Link erstellen'
    $ok.Add_Click({
        if ([string]::IsNullOrWhiteSpace($password.Text)) {
            [Windows.Forms.MessageBox]::Show($form, 'Bitte geben Sie ein Passwort ein.', 'Nextcloud-Freigabe', 'OK', 'Warning') | Out-Null
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
    $cancel.Text = 'Abbrechen'
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
    $form.Text = 'Nextcloud-Freigabe konfigurieren'
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
        @{ Key='ServerUrl'; Label='Nextcloud-URL'; Value=if($existing){$existing.ServerUrl}else{$admin.ServerUrl} },
        @{ Key='Username'; Label='Nextcloud-Benutzer'; Value=if($existing){$existing.Username}else{[Environment]::UserName} },
        @{ Key='LocalRoot'; Label='Lokaler Nextcloud-Ordner (optional)'; Value=$defaultLocalRoot },
        @{ Key='RemoteRoot'; Label='Serverpfad des lokalen Ordners'; Value=if($existing){$existing.RemoteSyncRoot}else{$admin.RemoteSyncRoot} },
        @{ Key='UploadFolder'; Label='Upload-Ordner'; Value=if($existing){$existing.RemoteUploadFolder}else{$admin.RemoteUploadFolder} }
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
    $browse.Text = 'Durchsuchen'
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
    $modeLabel.Text = 'Standard-Freigabeart'
    $form.Controls.Add($modeLabel)

    $mode = New-Object Windows.Forms.ComboBox
    $mode.Location = New-Object Drawing.Point(235, 257)
    $mode.Size = New-Object Drawing.Size(360, 24)
    $mode.DropDownStyle = 'DropDownList'
    [void]$mode.Items.Add('Externer Link')
    [void]$mode.Items.Add('Interner Link')
    $mode.SelectedIndex = if ($existing -and $existing.DefaultMode -eq 'Internal') { 1 } else { 0 }
    $mode.Enabled = [bool]$admin.AllowShareDefaultsOverride
    $form.Controls.Add($mode)

    $daysLabel = New-Object Windows.Forms.Label
    $daysLabel.Location = New-Object Drawing.Point(18, 307)
    $daysLabel.Size = New-Object Drawing.Size(210, 22)
    $daysLabel.Text = 'Standard-Ablaufzeit (Tage)'
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
    $statusTitle.Text = 'Nextcloud-Verbindung'
    $form.Controls.Add($statusTitle)

    $status = New-Object Windows.Forms.Label
    $status.Location = New-Object Drawing.Point(235, 352)
    $status.Size = New-Object Drawing.Size(360, 42)
    $status.Text = if ($hasLoginFlowCredentials) { "Verbunden als $($existing.Username)" } else { 'Noch nicht verbunden' }
    $form.Controls.Add($status)

    $connect = New-Object Windows.Forms.Button
    $connect.Location = New-Object Drawing.Point(235, 400)
    $connect.Size = New-Object Drawing.Size(190, 30)
    $connect.Text = 'Mit Nextcloud verbinden'
    $form.Controls.Add($connect)

    $security = New-Object Windows.Forms.Label
    $security.Location = New-Object Drawing.Point(18, 447)
    $security.Size = New-Object Drawing.Size(575, 42)
    $security.Text = 'Die Anmeldung wird im Standardbrowser durchgeführt. Nach „Grant access“ speichert Windows den von Nextcloud ausgestellten Zugriffstoken verschlüsselt mit DPAPI.'
    $form.Controls.Add($security)

    $save = New-Object Windows.Forms.Button
    $save.Location = New-Object Drawing.Point(410, 498)
    $save.Size = New-Object Drawing.Size(88, 28)
    $save.Text = 'Speichern'
    $save.Enabled = [bool]$hasLoginFlowCredentials
    $form.Controls.Add($save)

    $cancel = New-Object Windows.Forms.Button
    $cancel.Location = New-Object Drawing.Point(507, 498)
    $cancel.Size = New-Object Drawing.Size(88, 28)
    $cancel.Text = 'Abbrechen'
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
                throw 'Der angegebene lokale Nextcloud-Ordner existiert nicht. Bitte wählen Sie einen vorhandenen Ordner oder lassen Sie das Feld leer.'
            }

            $credentials = Start-NextcloudLoginFlow -ServerUrl $fields.ServerUrl.Text -StatusCallback {
                param($message)
                if ($form.IsDisposed) { throw 'Die Nextcloud-Anmeldung wurde abgebrochen.' }
                $status.Text = $message
                [Windows.Forms.Application]::DoEvents()
            }
            $fields.ServerUrl.Text = $credentials.ServerUrl
            $fields.Username.Text = $credentials.Username
            $encrypted = Protect-AppPassword $credentials.AppPassword
            $config = & $buildConfig $credentials.ServerUrl $credentials.Username $encrypted
            Test-NextcloudShareConfig $config
            $status.Text = 'WebDAV-Benutzer-ID wird ermittelt ...'
            [Windows.Forms.Application]::DoEvents()
            $config = Initialize-NextcloudWebDavIdentity -Config $config -Force
            $form.DialogResult = [Windows.Forms.DialogResult]::OK
            $form.Close()
        }
        catch {
            if (-not $form.IsDisposed) {
                $form.TopMost = $true
                $status.Text = 'Verbindung fehlgeschlagen'
                [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Nextcloud-Anmeldung', 'OK', 'Error') | Out-Null
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
            [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Nextcloud-Konfiguration', 'OK', 'Error') | Out-Null
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
    $form.Text = 'Nextcloud-Freigabe'
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
    $form.Text = 'Nextcloud-Freigabe erstellt'
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
    $label.Text = 'Die Freigabe wurde erfolgreich erstellt, aber die Windows-Zwischenablage ist momentan blockiert. Markieren Sie den Text und kopieren Sie ihn mit Strg+C oder versuchen Sie es erneut.'
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
    $status.Text = 'Link und gegebenenfalls Passwort bleiben hier sichtbar.'
    $form.Controls.Add($status)

    $retry = New-Object Windows.Forms.Button
    $retry.Location = New-Object Drawing.Point(410, 190)
    $retry.Size = New-Object Drawing.Size(130, 30)
    $retry.Text = 'Erneut kopieren'
    $retry.Add_Click({
        if (Set-ClipboardTextWithRetry -Text $value.Text) {
            $form.DialogResult = [Windows.Forms.DialogResult]::OK
            $form.Close()
        }
        else {
            $status.Text = 'Zwischenablage weiterhin blockiert. Bitte Strg+C verwenden.'
            $value.SelectAll()
            $value.Focus()
        }
    })
    $form.Controls.Add($retry)

    $close = New-Object Windows.Forms.Button
    $close.Location = New-Object Drawing.Point(550, 190)
    $close.Size = New-Object Drawing.Size(98, 30)
    $close.Text = 'Schließen'
    $close.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($close)
    $form.CancelButton = $close

    $form.Add_Shown({ $value.SelectAll(); $value.Focus() })
    [void]$form.ShowDialog()
    $form.Dispose()
}

function Show-SuccessNotification {
    param([string]$Link, [string]$Password)
    $clipboardText = $Link
    $notificationText = 'Der Link wurde in die Zwischenablage kopiert.'
    if (-not [string]::IsNullOrWhiteSpace($Password)) {
        $clipboardText = "Link: $Link`r`nPasswort: $Password"
        $notificationText = 'Link und Passwort wurden in die Zwischenablage kopiert.'
    }
    if (-not (Set-ClipboardTextWithRetry -Text $clipboardText)) {
        Show-ClipboardFallbackDialog -Text $clipboardText
        return
    }
    $notify = New-Object Windows.Forms.NotifyIcon
    try {
        $notify.Icon = [Drawing.SystemIcons]::Information
        $notify.Visible = $true
        $notify.BalloonTipTitle = 'Nextcloud-Freigabe'
        $notify.BalloonTipText = $notificationText
        $notify.ShowBalloonTip(3500)
        Start-Sleep -Milliseconds 1200
    }
    finally {
        $notify.Dispose()
    }
}

Export-ModuleMember -Function *
