# Review source only.  A separately trusted static host must hash-verify and
# stage these exact bytes below the protected LocalApplicationData service root
# before this file can run.  Checkout execution stops before it prompts, reads
# a private manifest or DPAPI artifact, or contacts Discord.

param([string]$Mode)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LauncherScriptPath = $MyInvocation.MyCommand.Path
$script:LauncherScriptDirectory = Split-Path -Path $script:LauncherScriptPath -Parent
$script:LauncherFileName = 'CodyManualCanaryLauncher.ps1'
$script:LauncherSchemaVersion = 'hermes-agents-discord-cody-aru-cody-manual-canary-launcher/v1'
$script:OutputSchemaVersion = 'hermes-agents-discord-cody-aru-cody-manual-canary-output/v1'
$script:BootstrapSchemaVersion = 'hermes-agents-discord-cody-aru-cody-token-dpapi-bootstrap/v1'
$script:NamespaceDirectoryName = 'HermesAgents'
$script:ServiceDirectoryName = 'discord-cody-aru-direct-bridge'
$script:ProvisionerDirectoryName = 'provisioner'
$script:LauncherDirectoryName = 'manual-canary-launcher'
$script:BootstrapFileName = 'CodyTokenDpapiBootstrap.ps1'
$script:ArtifactName = 'cody-bot-token.currentuser.dpapi.json'
$script:PrivateManifestName = 'cody-runtime-manifest.local.json'
$script:PrivateManifestSchemaVersions = @(
    'hermes-agents-discord-cody-aru-direct-bridge-cody-private-runtime/v1',
    'hermes-agents-discord-cody-aru-cody-private-runtime/v1'
)
$script:LatchDirectoryName = 'manual-canary-latches'
$script:StateDirectoryName = 'manual-canary-state'
$script:LatchSchemaVersion = 'hermes-agents-discord-cody-aru-cody-manual-canary-latch/v1'
$script:StateSchemaVersion = 'hermes-agents-discord-cody-aru-cody-manual-canary-start-state/v1'
$script:MaximumArtifactBytes = 16KB
$script:MaximumManifestBytes = 8KB
$script:MaximumStateBytes = 8KB
$script:MaximumResponseBytes = 32KB
$script:MinimumTokenBytes = 20
$script:MaximumTokenBytes = 4096
$script:DiscordApiRoot = 'https://discord.com/api/v10'
$script:LastActionLatchState = 'not_acquired'

function Throw-CodyManualCanaryLauncherError {
    param([Parameter(Mandatory)][string]$Code)
    throw [System.InvalidOperationException]::new($Code)
}

function Get-CodyManualCanaryLauncherErrorCode {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match '^DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_[A-Z_]+$') { return $message }
    return 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED'
}

function Get-CodyManualCanaryLauncherLocalAppDataRoot {
    $value = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($value)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
    }
    return $value
}

function Get-CodyManualCanaryLauncherNormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        if ($fullPath -notmatch '^[A-Za-z]:\\' -or $fullPath.StartsWith('\\')) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
        }
        $volumeRoot = [System.IO.Path]::GetPathRoot($fullPath)
        if ([string]::IsNullOrWhiteSpace($volumeRoot)) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
        }
        if ($fullPath.Length -gt $volumeRoot.Length) {
            $fullPath = $fullPath.TrimEnd([char[]]@(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ))
        }
        return $fullPath
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
    }
}

function Test-CodyManualCanaryLauncherPathWithin {
    param([Parameter(Mandatory)][string]$Candidate, [Parameter(Mandatory)][string]$Root)
    $candidatePath = Get-CodyManualCanaryLauncherNormalizedPath $Candidate
    $rootPath = Get-CodyManualCanaryLauncherNormalizedPath $Root
    if ($candidatePath.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidatePath.StartsWith("$rootPath$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-CodyManualCanaryLauncherFixedLocalPath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $normalized = Get-CodyManualCanaryLauncherNormalizedPath $Path
        if ([System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($normalized)).DriveType -ne [System.IO.DriveType]::Fixed) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
        }
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
    }
}

function Assert-CodyManualCanaryLauncherNoReparsePointAncestors {
    param([Parameter(Mandatory)][string]$Path)
    $probe = Get-CodyManualCanaryLauncherNormalizedPath $Path
    try {
        while (-not (Test-Path -LiteralPath $probe)) {
            $parent = Split-Path -Path $probe -Parent
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($probe, [System.StringComparison]::OrdinalIgnoreCase)) {
                Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
            }
            $probe = $parent
        }
        while ($true) {
            $item = Get-Item -LiteralPath $probe -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
            }
            $parent = Split-Path -Path $probe -Parent
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($probe, [System.StringComparison]::OrdinalIgnoreCase)) { break }
            $probe = $parent
        }
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
    }
}

function Get-CodyManualCanaryLauncherCurrentUserSid {
    try {
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ([string]::IsNullOrWhiteSpace($sid)) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_DACL_REJECTED'
        }
        return $sid
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_DACL_REJECTED'
    }
}

function Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][bool]$IsDirectory)
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $sid = [System.Security.Principal.SecurityIdentifier]::new((Get-CodyManualCanaryLauncherCurrentUserSid))
        $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if (-not $owner.Equals($sid.Value, [System.StringComparison]::OrdinalIgnoreCase) -or -not $acl.AreAccessRulesProtected) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_DACL_REJECTED'
        }
        $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        $inheritance = if ($IsDirectory) {
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        } else { [System.Security.AccessControl.InheritanceFlags]::None }
        if ($rules.Count -ne 1 -or $rules[0].IsInherited -or
            -not $rules[0].IdentityReference.Value.Equals($sid.Value, [System.StringComparison]::OrdinalIgnoreCase) -or
            $rules[0].AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or
            $rules[0].FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl -or
            $rules[0].InheritanceFlags -ne $inheritance -or
            $rules[0].PropagationFlags -ne [System.Security.AccessControl.PropagationFlags]::None) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_DACL_REJECTED'
        }
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_DACL_REJECTED'
    }
}

function Set-CodyManualCanaryLauncherCurrentUserOnlyDacl {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][bool]$IsDirectory)
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $sid = [System.Security.Principal.SecurityIdentifier]::new((Get-CodyManualCanaryLauncherCurrentUserSid))
        $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if (-not $owner.Equals($sid.Value, [System.StringComparison]::OrdinalIgnoreCase)) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_DACL_REJECTED'
        }
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRuleAll($rule) }
        $inheritance = if ($IsDirectory) {
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        } else { [System.Security.AccessControl.InheritanceFlags]::None }
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
            $sid, [System.Security.AccessControl.FileSystemRights]::FullControl, $inheritance,
            [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow
        ))
        Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
        Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $Path $IsDirectory
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_DACL_REJECTED'
    }
}

function Assert-CodyManualCanaryLauncherRegularFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][int]$MaximumBytes, [Parameter(Mandatory)][string]$ErrorCode)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) -or $item.Length -le 0 -or $item.Length -gt $MaximumBytes) {
            Throw-CodyManualCanaryLauncherError $ErrorCode
        }
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError $ErrorCode
    }
}

function Get-CodyManualCanaryLauncherSha256FromFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][int]$MaximumBytes, [Parameter(Mandatory)][string]$ErrorCode)
    $stream = $null
    $sha256 = $null
    try {
        Assert-CodyManualCanaryLauncherRegularFile $Path $MaximumBytes $ErrorCode
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError $ErrorCode
    } finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-CodyManualCanaryLauncherTrustedLayout {
    $localAppDataRoot = Get-CodyManualCanaryLauncherNormalizedPath (Get-CodyManualCanaryLauncherLocalAppDataRoot)
    $namespaceRoot = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $localAppDataRoot $script:NamespaceDirectoryName)
    $serviceRoot = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $namespaceRoot $script:ServiceDirectoryName)
    $launcherRoot = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $serviceRoot $script:LauncherDirectoryName)
    $stageRoot = Get-CodyManualCanaryLauncherNormalizedPath $script:LauncherScriptDirectory
    $launcherPath = Get-CodyManualCanaryLauncherNormalizedPath $script:LauncherScriptPath
    $stageHash = Split-Path -Path $stageRoot -Leaf
    $stageParent = Get-CodyManualCanaryLauncherNormalizedPath (Split-Path -Path $stageRoot -Parent)
    $expectedLauncherPath = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $stageRoot $script:LauncherFileName)
    Assert-CodyManualCanaryLauncherFixedLocalPath $localAppDataRoot
    Assert-CodyManualCanaryLauncherNoReparsePointAncestors $localAppDataRoot
    if (-not (Test-CodyManualCanaryLauncherPathWithin $namespaceRoot $localAppDataRoot) -or
        -not (Test-CodyManualCanaryLauncherPathWithin $serviceRoot $namespaceRoot) -or
        -not (Test-CodyManualCanaryLauncherPathWithin $launcherRoot $serviceRoot) -or
        -not (Test-CodyManualCanaryLauncherPathWithin $stageRoot $launcherRoot) -or
        -not (Test-CodyManualCanaryLauncherPathWithin $launcherPath $stageRoot) -or
        -not $stageParent.Equals($launcherRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $stageHash -notmatch '^[a-f0-9]{64}$' -or
        -not $launcherPath.Equals($expectedLauncherPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_TRUSTED_STAGE_REQUIRED'
    }
    foreach ($path in @($namespaceRoot, $serviceRoot, $launcherRoot, $stageRoot, $launcherPath)) {
        Assert-CodyManualCanaryLauncherNoReparsePointAncestors $path
    }
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $namespaceRoot $true
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $serviceRoot $true
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $launcherRoot $true
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $stageRoot $true
    Assert-CodyManualCanaryLauncherRegularFile $launcherPath 256KB 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_REJECTED'
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $launcherPath $false
    if ((Get-CodyManualCanaryLauncherSha256FromFile $launcherPath 256KB 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_REJECTED') -ne $stageHash) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_REJECTED'
    }
    return [pscustomobject]@{
        service_root = $serviceRoot
        provisioner_root = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $serviceRoot $script:ProvisionerDirectoryName)
        secrets_root = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $serviceRoot 'secrets')
        artifact_path = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path (Join-Path $serviceRoot 'secrets') $script:ArtifactName)
        manifest_path = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $serviceRoot $script:PrivateManifestName)
        latch_root = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $serviceRoot $script:LatchDirectoryName)
        state_root = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $serviceRoot $script:StateDirectoryName)
    }
}

function ConvertFrom-CodyManualCanaryLauncherUtf8JsonObject {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$MaximumBytes,
        [Parameter(Mandatory)][string[]]$RequiredKeys,
        [Parameter(Mandatory)][string]$ErrorCode
    )
    $bytes = $null
    try {
        Assert-CodyManualCanaryLauncherRegularFile $Path $MaximumBytes $ErrorCode
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -le 0 -or $bytes.Length -gt $MaximumBytes) { Throw-CodyManualCanaryLauncherError $ErrorCode }
        $value = ([System.Text.UTF8Encoding]::new($false, $true).GetString($bytes) | ConvertFrom-Json -ErrorAction Stop)
        if ($null -eq $value -or $value.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') {
            Throw-CodyManualCanaryLauncherError $ErrorCode
        }
        $properties = @($value.PSObject.Properties)
        if ($properties.Count -ne $RequiredKeys.Count) { Throw-CodyManualCanaryLauncherError $ErrorCode }
        foreach ($key in $RequiredKeys) {
            $matches = @($properties | Where-Object { $_.Name -ceq $key -and $_.MemberType -eq 'NoteProperty' })
            if ($matches.Count -ne 1) { Throw-CodyManualCanaryLauncherError $ErrorCode }
        }
        return $value
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError $ErrorCode
    } finally {
        if ($null -ne $bytes) { [System.Array]::Clear($bytes, 0, $bytes.Length) }
    }
}

function Test-CodyManualCanaryLauncherSnowflake {
    param([AllowNull()][object]$Value)
    return $Value -is [string] -and $Value -match '^[1-9][0-9]{15,19}$'
}

function Test-CodyManualCanaryLauncherOpaqueReference {
    param([AllowNull()][object]$Value)
    return $Value -is [string] -and $Value -match '^[A-Za-z0-9._-]{8,160}$'
}

function Read-CodyManualCanaryLauncherPrivateManifest {
    param([Parameter(Mandatory)][pscustomobject]$Layout)
    Assert-CodyManualCanaryLauncherNoReparsePointAncestors $Layout.manifest_path
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $Layout.manifest_path $false
    $manifest = ConvertFrom-CodyManualCanaryLauncherUtf8JsonObject -Path $Layout.manifest_path -MaximumBytes $script:MaximumManifestBytes -RequiredKeys @('schema_version', 'discord_channel_id', 'cody_bot_user_id', 'aru_bot_user_id', 'user_approval_reference') -ErrorCode 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_MANIFEST_REJECTED'
    if ($script:PrivateManifestSchemaVersions -cnotcontains $manifest.schema_version -or
        -not (Test-CodyManualCanaryLauncherSnowflake $manifest.discord_channel_id) -or
        -not (Test-CodyManualCanaryLauncherSnowflake $manifest.cody_bot_user_id) -or
        -not (Test-CodyManualCanaryLauncherSnowflake $manifest.aru_bot_user_id) -or
        @(@($manifest.discord_channel_id, $manifest.cody_bot_user_id, $manifest.aru_bot_user_id) | Select-Object -Unique).Count -ne 3 -or
        -not (Test-CodyManualCanaryLauncherOpaqueReference $manifest.user_approval_reference)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_MANIFEST_REJECTED'
    }
    return [pscustomobject]@{
        discord_channel_id = $manifest.discord_channel_id
        cody_bot_user_id = $manifest.cody_bot_user_id
        aru_bot_user_id = $manifest.aru_bot_user_id
        user_approval_reference = $manifest.user_approval_reference
    }
}

function Read-CodyManualCanaryLauncherArtifactMetadata {
    param([Parameter(Mandatory)][pscustomobject]$Layout)
    Assert-CodyManualCanaryLauncherNoReparsePointAncestors $Layout.secrets_root
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $Layout.secrets_root $true
    Assert-CodyManualCanaryLauncherNoReparsePointAncestors $Layout.artifact_path
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $Layout.artifact_path $false
    $record = ConvertFrom-CodyManualCanaryLauncherUtf8JsonObject -Path $Layout.artifact_path -MaximumBytes $script:MaximumArtifactBytes -RequiredKeys @('schema_version', 'protection_scope', 'bootstrap_sha256', 'ciphertext_base64') -ErrorCode 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_ARTIFACT_REJECTED'
    if ($record.schema_version -cne $script:BootstrapSchemaVersion -or
        $record.protection_scope -cne 'CurrentUser' -or
        $record.bootstrap_sha256 -isnot [string] -or $record.bootstrap_sha256 -notmatch '^[a-f0-9]{64}$' -or
        $record.ciphertext_base64 -isnot [string] -or $record.ciphertext_base64.Length -lt 4 -or
        $record.ciphertext_base64.Length -gt $script:MaximumArtifactBytes -or
        $record.ciphertext_base64 -notmatch '^[A-Za-z0-9+/]+={0,2}$') {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_ARTIFACT_REJECTED'
    }
    return [pscustomobject]@{ bootstrap_sha256 = $record.bootstrap_sha256; ciphertext_base64 = $record.ciphertext_base64 }
}

function Assert-CodyManualCanaryLauncherBootstrapStage {
    param([Parameter(Mandatory)][pscustomobject]$Layout, [Parameter(Mandatory)][string]$BootstrapSha256)
    $stageRoot = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $Layout.provisioner_root $BootstrapSha256)
    $bootstrapPath = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $stageRoot $script:BootstrapFileName)
    if (-not (Test-CodyManualCanaryLauncherPathWithin $stageRoot $Layout.provisioner_root) -or
        -not (Test-CodyManualCanaryLauncherPathWithin $bootstrapPath $stageRoot)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_BOOTSTRAP_STAGE_REJECTED'
    }
    foreach ($path in @($Layout.provisioner_root, $stageRoot, $bootstrapPath)) {
        Assert-CodyManualCanaryLauncherNoReparsePointAncestors $path
    }
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $Layout.provisioner_root $true
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $stageRoot $true
    Assert-CodyManualCanaryLauncherRegularFile $bootstrapPath 128KB 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_BOOTSTRAP_STAGE_REJECTED'
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $bootstrapPath $false
    if ((Get-CodyManualCanaryLauncherSha256FromFile $bootstrapPath 128KB 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_BOOTSTRAP_STAGE_REJECTED') -cne $BootstrapSha256) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_BOOTSTRAP_STAGE_REJECTED'
    }
}

function Get-CodyManualCanaryLauncherEntropy {
    param([Parameter(Mandatory)][string]$ServiceRoot, [Parameter(Mandatory)][string]$BootstrapSha256)
    $material = [System.Text.Encoding]::UTF8.GetBytes("$script:BootstrapSchemaVersion|$ServiceRoot|$BootstrapSha256")
    $sha256 = $null
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        return $sha256.ComputeHash($material)
    } finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        [System.Array]::Clear($material, 0, $material.Length)
    }
}

function ConvertFrom-CodyManualCanaryLauncherProtectedToken {
    param([Parameter(Mandatory)][string]$CiphertextBase64, [Parameter(Mandatory)][byte[]]$Entropy)
    $ciphertext = $null
    try {
        if ($null -eq ('System.Security.Cryptography.ProtectedData' -as [type])) { Add-Type -AssemblyName System.Security -ErrorAction Stop }
        if ($null -eq ('System.Security.Cryptography.ProtectedData' -as [type])) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_TOKEN_REJECTED'
        }
        $ciphertext = [System.Convert]::FromBase64String($CiphertextBase64)
        if ($ciphertext.Length -le 0 -or $ciphertext.Length -gt $script:MaximumArtifactBytes) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_TOKEN_REJECTED'
        }
        return [System.Security.Cryptography.ProtectedData]::Unprotect(
            $ciphertext, $Entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_TOKEN_REJECTED'
    } finally {
        if ($null -ne $ciphertext) { [System.Array]::Clear($ciphertext, 0, $ciphertext.Length) }
    }
}

function Assert-CodyManualCanaryLauncherTokenBytes {
    param([Parameter(Mandatory)][byte[]]$TokenBytes)
    if ($TokenBytes.Length -lt $script:MinimumTokenBytes -or $TokenBytes.Length -gt $script:MaximumTokenBytes) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_TOKEN_REJECTED'
    }
    foreach ($value in $TokenBytes) {
        if (($value -lt 0x21) -or ($value -gt 0x7e) -or -not ([char]$value -match '[A-Za-z0-9._-]')) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_TOKEN_REJECTED'
        }
    }
}

function ConvertTo-CodyManualCanaryLauncherCanonicalJson {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) { return (ConvertTo-Json -InputObject $Value -Compress) }
    if ($Value -is [int] -or $Value -is [long]) { return ([System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)) }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)
        $parts = foreach ($key in $keys) {
            "$(ConvertTo-CodyManualCanaryLauncherCanonicalJson $key):$(ConvertTo-CodyManualCanaryLauncherCanonicalJson $Value[$key])"
        }
        return "{$($parts -join ',')}"
    }
    if ($Value -is [System.Array]) {
        $parts = foreach ($item in $Value) { ConvertTo-CodyManualCanaryLauncherCanonicalJson $item }
        return "[$($parts -join ',')]"
    }
    Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_PREPARATION_REJECTED'
}

function Get-CodyManualCanaryLauncherSha256Utf8 {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha256 = $null
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        [System.Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Get-CodyManualCanaryLauncherBindingDigest {
    param([Parameter(Mandatory)][string]$Kind, [Parameter(Mandatory)][string]$DiscordId)
    if ($Kind -cnotin @('destination', 'cody_identity', 'aru_identity') -or -not (Test-CodyManualCanaryLauncherSnowflake $DiscordId)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_PREPARATION_REJECTED'
    }
    return Get-CodyManualCanaryLauncherSha256Utf8 (ConvertTo-CodyManualCanaryLauncherCanonicalJson ([ordered]@{
        schema_version = 'hermes-agents-discord-cody-aru-direct-bridge-binding/v1'
        transport = 'discord'
        binding_kind = $Kind
        discord_id = $DiscordId
    }))
}

function Get-CodyManualCanaryLauncherMessageReferenceDigest {
    param([Parameter(Mandatory)][string]$ChannelId, [Parameter(Mandatory)][string]$MessageId)
    if (-not (Test-CodyManualCanaryLauncherSnowflake $ChannelId) -or -not (Test-CodyManualCanaryLauncherSnowflake $MessageId)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STATE_REJECTED'
    }
    $destinationBinding = Get-CodyManualCanaryLauncherBindingDigest 'destination' $ChannelId
    return Get-CodyManualCanaryLauncherSha256Utf8 (ConvertTo-CodyManualCanaryLauncherCanonicalJson ([ordered]@{
        schema_version = 'hermes-agents-discord-cody-aru-direct-bridge-message-reference/v1'
        transport = 'discord'
        destination_binding_digest = $destinationBinding
        private_message_id = $MessageId
    }))
}

function Get-CodyManualCanaryLauncherCanaryMaterial {
    param([Parameter(Mandatory)][pscustomobject]$Manifest, [Parameter(Mandatory)][string]$WireApprovalReference)
    if (-not (Test-CodyManualCanaryLauncherOpaqueReference $WireApprovalReference)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_APPROVAL_REFERENCE_REJECTED'
    }
    $runtimeManifest = [ordered]@{
        schema_version = 'hermes-agents-discord-cody-aru-direct-bridge-runtime-manifest/v1'
        transport = 'discord'
        runtime_alias = 'discord_cody_aru_direct_bridge_manual_canary'
        destination_alias = 'cody_aru_private_canary'
        cody_identity_alias = 'cody'
        aru_identity_alias = 'aru'
        destination_binding_digest = Get-CodyManualCanaryLauncherBindingDigest 'destination' $Manifest.discord_channel_id
        cody_identity_binding_digest = Get-CodyManualCanaryLauncherBindingDigest 'cody_identity' $Manifest.cody_bot_user_id
        aru_identity_binding_digest = Get-CodyManualCanaryLauncherBindingDigest 'aru_identity' $Manifest.aru_bot_user_id
        model_call_permitted = $false
        automatic_reply_permitted = $false
        background_listener_permitted = $false
        cron_permitted = $false
        retry_permitted = $false
    }
    $runtimeDigest = Get-CodyManualCanaryLauncherSha256Utf8 (ConvertTo-CodyManualCanaryLauncherCanonicalJson $runtimeManifest)
    $seedDigest = Get-CodyManualCanaryLauncherSha256Utf8 (ConvertTo-CodyManualCanaryLauncherCanonicalJson ([ordered]@{
        canary_seed_namespace = 'discord_cody_aru_direct_bridge_manual_canary_v1'
        user_approval_reference = $WireApprovalReference
    }))
    $correlationDigest = Get-CodyManualCanaryLauncherSha256Utf8 (ConvertTo-CodyManualCanaryLauncherCanonicalJson ([ordered]@{
        schema_version = 'hermes-agents-discord-cody-aru-direct-bridge-request/v1'
        runtime_manifest_digest = $runtimeDigest
        canary_seed_digest = $seedDigest
        correlation_namespace = 'discord_cody_aru_ack_only_v1'
    }))
    $correlationId = "discord_cody_aru_correlation_$correlationDigest"
    $nonceDigest = Get-CodyManualCanaryLauncherSha256Utf8 (ConvertTo-CodyManualCanaryLauncherCanonicalJson ([ordered]@{
        schema_version = 'hermes-agents-discord-cody-aru-direct-bridge-request/v1'
        nonce_namespace = 'discord_create_message_enforce_nonce_v1'
        correlation_id = $correlationId
    }))
    return [pscustomobject]@{
        runtime_manifest_digest = $runtimeDigest
        correlation_id = $correlationId
        nonce = "dcab_$($nonceDigest.Substring(0, 20))"
        request_content = "CODY_CANARY_REQUEST $correlationId"
        expected_ack_content = "ARU_CANARY_ACK $correlationId"
    }
}

function Get-CodyManualCanaryLauncherStateKey {
    param([Parameter(Mandatory)][string]$ServiceRoot, [Parameter(Mandatory)][string]$WireApprovalReference)
    return Get-CodyManualCanaryLauncherSha256Utf8 "$script:LauncherSchemaVersion|$ServiceRoot|$WireApprovalReference"
}

function Get-CodyManualCanaryLauncherActionDigest {
    param([Parameter(Mandatory)][string]$ServiceRoot, [Parameter(Mandatory)][string]$Mode, [Parameter(Mandatory)][string]$ActionApprovalReference)
    return Get-CodyManualCanaryLauncherSha256Utf8 "$script:LauncherSchemaVersion|$ServiceRoot|$Mode|$ActionApprovalReference"
}

function Ensure-CodyManualCanaryLauncherProtectedDirectory {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$ServiceRoot)
    if (-not (Test-CodyManualCanaryLauncherPathWithin $Directory $ServiceRoot)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
    }
    try {
        if (-not (Test-Path -LiteralPath $Directory)) {
            [System.IO.Directory]::CreateDirectory($Directory) | Out-Null
            Set-CodyManualCanaryLauncherCurrentUserOnlyDacl $Directory $true
        }
        $item = Get-Item -LiteralPath $Directory -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
        }
        Assert-CodyManualCanaryLauncherNoReparsePointAncestors $Directory
        Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $Directory $true
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LOCAL_ROOT_REJECTED'
    }
}

function Assert-CodyManualCanaryLauncherExistingLatch {
    param([Parameter(Mandatory)][string]$LatchPath)
    Assert-CodyManualCanaryLauncherNoReparsePointAncestors $LatchPath
    Assert-CodyManualCanaryLauncherRegularFile $LatchPath 2KB 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LATCH_REJECTED'
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $LatchPath $false
}

function Claim-CodyManualCanaryLauncherActionLatch {
    param([Parameter(Mandatory)][pscustomobject]$Layout, [Parameter(Mandatory)][string]$Mode, [Parameter(Mandatory)][string]$ActionApprovalReference)
    $script:LastActionLatchState = 'not_acquired'
    $digest = Get-CodyManualCanaryLauncherActionDigest $Layout.service_root $Mode $ActionApprovalReference
    $path = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $Layout.latch_root "$digest.consumed")
    if (-not (Test-CodyManualCanaryLauncherPathWithin $path $Layout.latch_root)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LATCH_REJECTED'
    }
    Ensure-CodyManualCanaryLauncherProtectedDirectory $Layout.latch_root $Layout.service_root
    Assert-CodyManualCanaryLauncherNoReparsePointAncestors $path
    if (Test-Path -LiteralPath $path) {
        Assert-CodyManualCanaryLauncherExistingLatch $path
        $script:LastActionLatchState = 'already_consumed_or_ambiguous'
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_ALREADY_CONSUMED_OR_AMBIGUOUS'
    }
    $payload = $null
    $stream = $null
    $created = $false
    try {
        $payload = [System.Text.UTF8Encoding]::new($false).GetBytes((([ordered]@{
            schema_version = $script:LatchSchemaVersion
            action_digest = $digest
        }) | ConvertTo-Json -Compress))
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Write($payload, 0, $payload.Length)
        $stream.Flush($true)
        $created = $true
        $stream.Dispose()
        $stream = $null
        Set-CodyManualCanaryLauncherCurrentUserOnlyDacl $path $false
        Assert-CodyManualCanaryLauncherExistingLatch $path
        $script:LastActionLatchState = 'acquired'
    } catch {
        if ($null -ne $stream) { try { $stream.Dispose() } catch { } }
        if ($created -or (Test-Path -LiteralPath $path)) {
            Assert-CodyManualCanaryLauncherExistingLatch $path
            $script:LastActionLatchState = 'already_consumed_or_ambiguous'
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_ALREADY_CONSUMED_OR_AMBIGUOUS'
        }
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_LATCH_REJECTED'
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $payload) { [System.Array]::Clear($payload, 0, $payload.Length) }
    }
}

function Get-CodyManualCanaryLauncherDataProperty {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Name)
    try {
        if ($null -eq $Value -or $Value -is [System.Array]) { return $null }
        $matches = @($Value.PSObject.Properties | Where-Object { $_.Name -ceq $Name -and $_.MemberType -eq 'NoteProperty' })
        if ($matches.Count -ne 1 -or $matches[0].Value -is [System.Array]) { return $null }
        return $matches[0].Value
    } catch { return $null }
}

function Test-CodyManualCanaryLauncherEmptyArrayOrAbsent {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Name)
    try {
        if ($null -eq $Value -or $Value -is [System.Array]) { return $false }
        $matches = @($Value.PSObject.Properties | Where-Object { $_.Name -ceq $Name -and $_.MemberType -eq 'NoteProperty' })
        if ($matches.Count -eq 0) { return $true }
        return $matches.Count -eq 1 -and $matches[0].Value -is [System.Array] -and $matches[0].Value.Count -eq 0
    } catch { return $false }
}

function ConvertTo-CodyManualCanaryLauncherMessage {
    param([AllowNull()][object]$Value)
    $id = Get-CodyManualCanaryLauncherDataProperty $Value 'id'
    $channel = Get-CodyManualCanaryLauncherDataProperty $Value 'channel_id'
    $author = Get-CodyManualCanaryLauncherDataProperty $Value 'author'
    $type = Get-CodyManualCanaryLauncherDataProperty $Value 'type'
    $content = Get-CodyManualCanaryLauncherDataProperty $Value 'content'
    $nonce = Get-CodyManualCanaryLauncherDataProperty $Value 'nonce'
    $reference = Get-CodyManualCanaryLauncherDataProperty $Value 'message_reference'
    $webhook = Get-CodyManualCanaryLauncherDataProperty $Value 'webhook_id'
    if (-not (Test-CodyManualCanaryLauncherSnowflake $id) -or -not (Test-CodyManualCanaryLauncherSnowflake $channel) -or
        $null -eq $author -or $author -is [System.Array] -or
        -not ($type -is [int] -or $type -is [long]) -or
        $content -isnot [string] -or $content.Length -gt 512 -or
        -not (Test-CodyManualCanaryLauncherEmptyArrayOrAbsent $Value 'attachments') -or
        -not (Test-CodyManualCanaryLauncherEmptyArrayOrAbsent $Value 'embeds') -or
        -not (Test-CodyManualCanaryLauncherEmptyArrayOrAbsent $Value 'components')) { return $null }
    $authorId = Get-CodyManualCanaryLauncherDataProperty $author 'id'
    $authorBot = Get-CodyManualCanaryLauncherDataProperty $author 'bot'
    if (-not (Test-CodyManualCanaryLauncherSnowflake $authorId) -or $authorBot -isnot [bool] -or -not $authorBot) { return $null }
    return [pscustomobject]@{
        id = $id; channel_id = $channel; author_id = $authorId; type = [int64]$type
        content = $content; nonce = $nonce; message_reference = $reference; webhook_id = $webhook
    }
}

function Test-CodyManualCanaryLauncherCodyPost {
    param([AllowNull()][object]$Message, [Parameter(Mandatory)][pscustomobject]$Manifest, [Parameter(Mandatory)][pscustomobject]$Material)
    if ($null -eq $Message) { return 'ambiguous' }
    if ($Message.channel_id -cne $Manifest.discord_channel_id) { return 'binding_rejected' }
    if ($Message.author_id -cne $Manifest.cody_bot_user_id -or $null -ne $Message.webhook_id) { return 'sender_rejected' }
    if ($Message.type -ne 0 -or $Message.content -cne $Material.request_content -or $Message.nonce -cne $Material.nonce -or $null -ne $Message.message_reference) {
        return 'ambiguous'
    }
    return 'valid'
}

function Test-CodyManualCanaryLauncherAruReply {
    param(
        [AllowNull()][object]$Message,
        [Parameter(Mandatory)][string]$ReplyMessageId,
        [Parameter(Mandatory)][pscustomobject]$State,
        [Parameter(Mandatory)][pscustomobject]$Manifest,
        [Parameter(Mandatory)][pscustomobject]$Material
    )
    if ($null -eq $Message -or $Message.id -cne $ReplyMessageId) { return 'ambiguous' }
    if ($Message.channel_id -cne $Manifest.discord_channel_id) { return 'binding_rejected' }
    if ($Message.author_id -cne $Manifest.aru_bot_user_id -or $null -ne $Message.webhook_id) { return 'sender_rejected' }
    $reference = $Message.message_reference
    $referenceMessageId = Get-CodyManualCanaryLauncherDataProperty $reference 'message_id'
    $referenceChannelId = Get-CodyManualCanaryLauncherDataProperty $reference 'channel_id'
    if ($Message.type -ne 19 -or -not (Test-CodyManualCanaryLauncherSnowflake $referenceMessageId) -or -not (Test-CodyManualCanaryLauncherSnowflake $referenceChannelId)) {
        return 'ambiguous'
    }
    if ($referenceChannelId -cne $Manifest.discord_channel_id -or $referenceMessageId -cne $State.request_message_id) { return 'reply_lineage_rejected' }
    if ($Message.content -cne $Material.expected_ack_content -or $Message.nonce -cne $Material.nonce) { return 'ambiguous' }
    return 'valid'
}

function Write-CodyManualCanaryLauncherStartState {
    param(
        [Parameter(Mandatory)][pscustomobject]$Layout,
        [Parameter(Mandatory)][string]$WireApprovalReference,
        [Parameter(Mandatory)][pscustomobject]$Manifest,
        [Parameter(Mandatory)][pscustomobject]$Material,
        [Parameter(Mandatory)][string]$RequestMessageId
    )
    Ensure-CodyManualCanaryLauncherProtectedDirectory $Layout.state_root $Layout.service_root
    $stateKey = Get-CodyManualCanaryLauncherStateKey $Layout.service_root $WireApprovalReference
    $path = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $Layout.state_root "start-$stateKey.private.json")
    if (-not (Test-CodyManualCanaryLauncherPathWithin $path $Layout.state_root)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STATE_REJECTED'
    }
    $record = [ordered]@{
        schema_version = $script:StateSchemaVersion
        state_key = $stateKey
        runtime_manifest_digest = $Material.runtime_manifest_digest
        correlation_id = $Material.correlation_id
        nonce = $Material.nonce
        request_message_id = $RequestMessageId
        request_message_ref_digest = Get-CodyManualCanaryLauncherMessageReferenceDigest $Manifest.discord_channel_id $RequestMessageId
    }
    $bytes = $null
    $stream = $null
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Compress))
        if ($bytes.Length -le 0 -or $bytes.Length -gt $script:MaximumStateBytes) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STATE_REJECTED'
        }
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null
        Set-CodyManualCanaryLauncherCurrentUserOnlyDacl $path $false
        return (Read-CodyManualCanaryLauncherStartState $Layout $WireApprovalReference $Manifest $Material)
    } catch {
        if ((Get-CodyManualCanaryLauncherErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_OPERATION_REJECTED') { throw }
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STATE_REJECTED'
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $bytes) { [System.Array]::Clear($bytes, 0, $bytes.Length) }
    }
}

function Read-CodyManualCanaryLauncherStartState {
    param(
        [Parameter(Mandatory)][pscustomobject]$Layout,
        [Parameter(Mandatory)][string]$WireApprovalReference,
        [Parameter(Mandatory)][pscustomobject]$Manifest,
        [Parameter(Mandatory)][pscustomobject]$Material
    )
    Ensure-CodyManualCanaryLauncherProtectedDirectory $Layout.state_root $Layout.service_root
    $stateKey = Get-CodyManualCanaryLauncherStateKey $Layout.service_root $WireApprovalReference
    $path = Get-CodyManualCanaryLauncherNormalizedPath (Join-Path $Layout.state_root "start-$stateKey.private.json")
    Assert-CodyManualCanaryLauncherNoReparsePointAncestors $path
    Assert-CodyManualCanaryLauncherCurrentUserOnlyDacl $path $false
    $record = ConvertFrom-CodyManualCanaryLauncherUtf8JsonObject -Path $path -MaximumBytes $script:MaximumStateBytes -RequiredKeys @('schema_version', 'state_key', 'runtime_manifest_digest', 'correlation_id', 'nonce', 'request_message_id', 'request_message_ref_digest') -ErrorCode 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STATE_REJECTED'
    if ($record.schema_version -cne $script:StateSchemaVersion -or
        $record.state_key -cne $stateKey -or
        $record.runtime_manifest_digest -cne $Material.runtime_manifest_digest -or
        $record.correlation_id -cne $Material.correlation_id -or
        $record.nonce -cne $Material.nonce -or
        -not (Test-CodyManualCanaryLauncherSnowflake $record.request_message_id) -or
        $record.request_message_ref_digest -cne (Get-CodyManualCanaryLauncherMessageReferenceDigest $Manifest.discord_channel_id $record.request_message_id)) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STATE_REJECTED'
    }
    return [pscustomobject]@{ request_message_id = $record.request_message_id; request_message_ref_digest = $record.request_message_ref_digest }
}

function Invoke-CodyManualCanaryLauncherHttpJsonRequest {
    param(
        [Parameter(Mandatory)][string]$RequestMode,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [AllowNull()][object]$Body
    )
    if ($RequestMode -cnotin @('POST', 'GET')) {
        Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_HTTP_REJECTED'
    }
    $request = $null
    $response = $null
    $requestStream = $null
    $responseStream = $null
    $memory = $null
    $buffer = $null
    $bodyBytes = $null
    $responseBytes = $null
    $previousSecurityProtocol = $null
    try {
        $previousSecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
        [System.Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $request = [System.Net.WebRequest]::CreateHttp($Uri)
        if ($request -isnot [System.Net.HttpWebRequest]) { return $null }
        $request.Method = $RequestMode
        $request.AllowAutoRedirect = $false
        $request.Proxy = $null
        $request.CookieContainer = $null
        $request.UseDefaultCredentials = $false
        $request.Credentials = $null
        $request.PreAuthenticate = $false
        $request.UnsafeAuthenticatedConnectionSharing = $false
        $request.AutomaticDecompression = [System.Net.DecompressionMethods]::None
        $request.KeepAlive = $false
        $request.Timeout = 10000
        $request.ReadWriteTimeout = 10000
        $request.Headers[[System.Net.HttpRequestHeader]::Authorization] = "Bot $Token"
        $request.Accept = 'application/json'
        if ($RequestMode -eq 'POST') {
            $serialized = $Body | ConvertTo-Json -Compress -Depth 4
            $bodyBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($serialized)
            if ($bodyBytes.Length -le 0 -or $bodyBytes.Length -gt 4KB) { return $null }
            $request.ContentType = 'application/json'
            $request.ContentLength = $bodyBytes.Length
            $requestStream = $request.GetRequestStream()
            $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
            $requestStream.Flush()
            $requestStream.Dispose()
            $requestStream = $null
        }
        try {
            $response = [System.Net.HttpWebResponse]$request.GetResponse()
        } catch [System.Net.WebException] {
            $errorResponse = $_.Exception.Response
            if ($_.Exception.Status -ne [System.Net.WebExceptionStatus]::ProtocolError -or $errorResponse -isnot [System.Net.HttpWebResponse]) { return $null }
            $response = [System.Net.HttpWebResponse]$errorResponse
        }
        $allowed = if ($RequestMode -eq 'POST') { @(200, 201) } else { @(200) }
        if ($allowed -notcontains [int]$response.StatusCode -or $response.ContentLength -gt $script:MaximumResponseBytes) { return $null }
        $responseStream = $response.GetResponseStream()
        $memory = [System.IO.MemoryStream]::new()
        $buffer = [byte[]]::new(4096)
        while ($true) {
            $remaining = $script:MaximumResponseBytes - [int]$memory.Length
            $read = $responseStream.Read($buffer, 0, [Math]::Min($buffer.Length, $remaining + 1))
            if ($read -le 0) { break }
            if (($memory.Length + $read) -gt $script:MaximumResponseBytes) { return $null }
            $memory.Write($buffer, 0, $read)
        }
        $responseBytes = $memory.ToArray()
        return ([System.Text.UTF8Encoding]::new($false, $true).GetString($responseBytes) | ConvertFrom-Json -ErrorAction Stop)
    } catch { return $null } finally {
        if ($null -ne $responseBytes) { [System.Array]::Clear($responseBytes, 0, $responseBytes.Length) }
        if ($null -ne $bodyBytes) { [System.Array]::Clear($bodyBytes, 0, $bodyBytes.Length) }
        if ($null -ne $buffer) { [System.Array]::Clear($buffer, 0, $buffer.Length) }
        if ($null -ne $memory) { $memory.Dispose() }
        if ($null -ne $responseStream) { $responseStream.Dispose() }
        if ($null -ne $requestStream) { $requestStream.Dispose() }
        if ($null -ne $response) { $response.Close() }
        if ($null -ne $request) { $request.Abort() }
        if ($null -ne $previousSecurityProtocol) { [System.Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol }
    }
}

function Invoke-CodyManualCanaryLauncherSafeJsonRequest {
    param(
        [Parameter(Mandatory)][scriptblock]$JsonRequest,
        [Parameter(Mandatory)][string]$RequestMode,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [AllowNull()][object]$Body
    )
    try { return (& $JsonRequest $RequestMode $Uri $Token $Body) } catch { return $null }
}

function New-CodyManualCanaryLauncherResult {
    param(
        [Parameter(Mandatory)][bool]$Ok,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string]$TerminalState,
        [Parameter(Mandatory)][string]$TerminalReason,
        [Parameter(Mandatory)][int]$CodyRequestAttemptCount,
        [Parameter(Mandatory)][int]$CodyRequestConfirmedCount,
        [Parameter(Mandatory)][int]$AruRequestReceiveCount,
        [Parameter(Mandatory)][int]$AruReplySendAttemptCount,
        [Parameter(Mandatory)][int]$AruReplySendConfirmedCount,
        [Parameter(Mandatory)][int]$CodyReplyReceiveCount,
        [Parameter(Mandatory)][int]$MessageHistoryReadCount,
        [Parameter(Mandatory)][string]$ReplyLineageState
    )
    return [ordered]@{
        schema_version = $script:OutputSchemaVersion
        ok = $Ok
        operation = 'cody_discord_manual_canary'
        mode = $Mode
        receipt_emitted = $true
        action_semantics = 'durable_single_use_per_canary_reference_and_mode'
        action_latch_state = $script:LastActionLatchState
        action_consumption_recorded = ($script:LastActionLatchState -eq 'acquired')
        terminal_state = $TerminalState
        terminal_reason = $TerminalReason
        error_code = $null
        cody_request_send_attempt_count = $CodyRequestAttemptCount
        cody_request_send_confirmed_count = $CodyRequestConfirmedCount
        aru_request_receive_count = $AruRequestReceiveCount
        aru_reply_send_attempt_count = $AruReplySendAttemptCount
        aru_reply_send_confirmed_count = $AruReplySendConfirmedCount
        cody_reply_receive_count = $CodyReplyReceiveCount
        message_history_read_count = $MessageHistoryReadCount
        reply_lineage_state = $ReplyLineageState
        retry_permitted = $false
        retry_count = 0
        model_call_count = 0
        sensitive_output_count = 0
    }
}

function New-CodyManualCanaryLauncherErrorResult {
    param([Parameter(Mandatory)][string]$ErrorCode, [AllowNull()][string]$RequestedMode)
    $safeMode = if ($RequestedMode -cin @('start', 'collect')) { $RequestedMode } else { 'invalid' }
    return [ordered]@{
        schema_version = $script:OutputSchemaVersion
        ok = $false
        operation = 'cody_discord_manual_canary'
        mode = $safeMode
        receipt_emitted = $false
        action_semantics = 'durable_single_use_per_canary_reference_and_mode'
        action_latch_state = $script:LastActionLatchState
        action_consumption_recorded = ($script:LastActionLatchState -eq 'acquired')
        terminal_state = 'not_started'
        terminal_reason = 'manual_canary_not_started'
        error_code = $ErrorCode
        cody_request_send_attempt_count = 0
        cody_request_send_confirmed_count = 0
        aru_request_receive_count = 0
        aru_reply_send_attempt_count = 0
        aru_reply_send_confirmed_count = 0
        cody_reply_receive_count = 0
        message_history_read_count = 0
        reply_lineage_state = 'not_observed'
        retry_permitted = $false
        retry_count = 0
        model_call_count = 0
        sensitive_output_count = 0
    }
}

function Invoke-CodyManualCanaryLauncherCore {
    param(
        [Parameter(Mandatory)][string]$RequestedMode,
        [Parameter(Mandatory)][pscustomobject]$Layout,
        [Parameter(Mandatory)][pscustomobject]$Manifest,
        [Parameter(Mandatory)][string]$ActionApprovalReference,
        [AllowNull()][string]$ReplyMessageId,
        [Parameter(Mandatory)][scriptblock]$ProtectedTokenReader,
        [Parameter(Mandatory)][scriptblock]$JsonRequest
    )
    $entropy = $null
    $tokenBytes = $null
    try {
        $script:LastActionLatchState = 'not_acquired'
        if ($RequestedMode -cnotin @('start', 'collect') -or
            -not (Test-CodyManualCanaryLauncherOpaqueReference $ActionApprovalReference) -or
            $ActionApprovalReference -ceq $Manifest.user_approval_reference -or
            ($RequestedMode -eq 'collect' -and -not (Test-CodyManualCanaryLauncherSnowflake $ReplyMessageId)) -or
            ($RequestedMode -eq 'start' -and -not [string]::IsNullOrEmpty($ReplyMessageId))) {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_APPROVAL_REFERENCE_REJECTED'
        }
        # The manifest reference is the immutable cross-side wire binding.  The
        # separately entered action reference is deliberately confined to this
        # launcher's local latch namespace and never changes Discord content.
        $material = Get-CodyManualCanaryLauncherCanaryMaterial $Manifest $Manifest.user_approval_reference
        Claim-CodyManualCanaryLauncherActionLatch $Layout $RequestedMode $ActionApprovalReference
        $state = $null
        if ($RequestedMode -eq 'collect') {
            $state = Read-CodyManualCanaryLauncherStartState $Layout $Manifest.user_approval_reference $Manifest $material
        }
        $artifact = Read-CodyManualCanaryLauncherArtifactMetadata $Layout
        Assert-CodyManualCanaryLauncherBootstrapStage $Layout $artifact.bootstrap_sha256
        $entropy = Get-CodyManualCanaryLauncherEntropy $Layout.service_root $artifact.bootstrap_sha256
        try { $tokenBytes = [byte[]]@(& $ProtectedTokenReader $artifact.ciphertext_base64 $entropy) } catch {
            Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_TOKEN_REJECTED'
        }
        Assert-CodyManualCanaryLauncherTokenBytes $tokenBytes
        $token = [System.Text.Encoding]::ASCII.GetString($tokenBytes)
        if ($RequestedMode -eq 'start') {
            $body = [ordered]@{
                content = $material.request_content
                allowed_mentions = [ordered]@{ parse = @() }
                nonce = $material.nonce
                enforce_nonce = $true
            }
            $response = Invoke-CodyManualCanaryLauncherSafeJsonRequest $JsonRequest 'POST' "$script:DiscordApiRoot/channels/$($Manifest.discord_channel_id)/messages" $token $body
            $message = ConvertTo-CodyManualCanaryLauncherMessage $response
            if ((Test-CodyManualCanaryLauncherCodyPost $message $Manifest $material) -ne 'valid') {
                return (New-CodyManualCanaryLauncherResult $false 'start' 'ambiguous' 'cody_request_post_ambiguous' 1 0 0 0 0 0 0 'ambiguous')
            }
            try {
                [void](Write-CodyManualCanaryLauncherStartState $Layout $Manifest.user_approval_reference $Manifest $material $message.id)
            } catch {
                return (New-CodyManualCanaryLauncherResult $false 'start' 'ambiguous' 'cody_request_state_ambiguous' 1 1 0 0 0 0 0 'not_observed')
            }
            return (New-CodyManualCanaryLauncherResult $true 'start' 'sent' 'cody_request_sent' 1 1 0 0 0 0 0 'not_observed')
        }
        $response = Invoke-CodyManualCanaryLauncherSafeJsonRequest $JsonRequest 'GET' "$script:DiscordApiRoot/channels/$($Manifest.discord_channel_id)/messages/$ReplyMessageId" $token $null
        $reply = ConvertTo-CodyManualCanaryLauncherMessage $response
        $replyState = Test-CodyManualCanaryLauncherAruReply $reply $ReplyMessageId $state $Manifest $material
        if ($replyState -eq 'valid') {
            return (New-CodyManualCanaryLauncherResult $true 'collect' 'replied' 'aru_ack_replied' 1 1 1 1 1 1 1 'verified')
        }
        if ($replyState -in @('binding_rejected', 'sender_rejected', 'reply_lineage_rejected')) {
            return (New-CodyManualCanaryLauncherResult $false 'collect' 'rejected' $replyState 1 1 0 0 0 0 1 'rejected')
        }
        return (New-CodyManualCanaryLauncherResult $false 'collect' 'ambiguous' 'reply_observation_ambiguous' 1 1 0 0 0 0 1 'ambiguous')
    } finally {
        if ($null -ne $tokenBytes) { [System.Array]::Clear($tokenBytes, 0, $tokenBytes.Length) }
        if ($null -ne $entropy) { [System.Array]::Clear($entropy, 0, $entropy.Length) }
    }
}

function Invoke-CodyManualCanaryLauncher {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RequestedMode)
    if ($args.Count -ne 0) { Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_ARGUMENT_REJECTED' }
    $layout = Get-CodyManualCanaryLauncherTrustedLayout
    if ($RequestedMode -cnotin @('start', 'collect')) { Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_MODE_REJECTED' }
    $manifest = Read-CodyManualCanaryLauncherPrivateManifest $layout
    $reference = Read-Host -Prompt 'Action approval reference (non-secret)'
    $replyMessageId = $null
    if ($RequestedMode -eq 'collect') {
        $replyMessageId = Read-Host -Prompt 'Aru reply message ID (private)'
    }
    $reader = { param([string]$CiphertextBase64, [byte[]]$Entropy) ConvertFrom-CodyManualCanaryLauncherProtectedToken $CiphertextBase64 $Entropy }
    $request = { param([string]$RequestMode, [string]$Uri, [string]$Token, [AllowNull()][object]$Body) Invoke-CodyManualCanaryLauncherHttpJsonRequest $RequestMode $Uri $Token $Body }
    return (Invoke-CodyManualCanaryLauncherCore $RequestedMode $layout $manifest $reference $replyMessageId $reader $request)
}

function Invoke-CodyManualCanaryLauncherForTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RequestedMode,
        [Parameter(Mandatory)][string]$UserApprovalReference,
        [AllowNull()][string]$ReplyMessageId,
        [Parameter(Mandatory)][scriptblock]$ProtectedTokenReader,
        [Parameter(Mandatory)][scriptblock]$JsonRequest
    )
    if ($args.Count -ne 0) { Throw-CodyManualCanaryLauncherError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_ARGUMENT_REJECTED' }
    $layout = Get-CodyManualCanaryLauncherTrustedLayout
    $manifest = Read-CodyManualCanaryLauncherPrivateManifest $layout
    return (Invoke-CodyManualCanaryLauncherCore $RequestedMode $layout $manifest $UserApprovalReference $ReplyMessageId $ProtectedTokenReader $JsonRequest)
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        [Console]::Out.WriteLine((Invoke-CodyManualCanaryLauncher $Mode | ConvertTo-Json -Compress))
    } catch {
        [Console]::Out.WriteLine((New-CodyManualCanaryLauncherErrorResult (Get-CodyManualCanaryLauncherErrorCode $_) $Mode | ConvertTo-Json -Compress))
        exit 2
    }
}
