[CmdletBinding()]
# Do not use a mandatory/ValidateSet binder here: a missing or unrecognised
# mode must reach the fail-closed JSON result below without touching layout,
# token, latch, or transport.
param([AllowNull()][string]$Mode)

# A new Cody v2 lane. It does not read or reuse v1 manual-canary state, nor
# adopt, persist, or output the v1 approval reference. Bootstrap validates the
# legacy private manifest only to recover its independently verified public
# bindings, then writes a new private manifest; start consumes an isolated
# CreateNew latch before one POST; handoff is read-only with no token or HTTP.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-cody-launcher/v1'
$script:ManifestSchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-cody-private-runtime/v1'
$script:HandoffStateSchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-cody-operator-handoff-state/v1'
$script:HandoffSchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-cody-operator-handoff/v1'
$script:RuntimeNamespaceDirectoryName = 'HermesAgentsCodyAruCorrelationCanaryV2'
$script:NamespaceName = 'discord-cody-aru-correlation-canary-v2'
$script:LegacyNamespaceName = 'discord-cody-aru-direct-bridge'
$script:LegacyBootstrapSchemaVersion = 'hermes-agents-discord-cody-aru-cody-token-dpapi-bootstrap/v1'
$script:ManifestName = 'cody-correlation-canary-private-runtime.local.json'
$script:StateDirectoryName = 'cody-correlation-canary-v2-start-state'
$script:LauncherName = 'CodyCorrelationCanaryV2Launcher.ps1'
$script:LastLatchState = 'not_acquired'
$script:CodyRequestSendAttemptCount = 0
$script:CodyRequestSendConfirmedCount = 0
$script:TokenReadCount = 0
$script:LauncherScriptPath = $MyInvocation.MyCommand.Path
$script:MaximumManifestBytes = 8KB
$script:MaximumArtifactBytes = 16KB
$script:MaximumStateBytes = 8KB
$script:MaximumResponseBytes = 8KB

function Throw-CodyCorrelationCanaryV2Error { param([string]$Code) $error = [System.Exception]::new($Code); $error.Data['code'] = $Code; throw $error }
function Get-CodyCorrelationCanaryV2ErrorCode { param([AllowNull()][object]$ErrorRecord) if ($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception -and $null -ne $ErrorRecord.Exception.Data['code']) { return [string]$ErrorRecord.Exception.Data['code'] }; return 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_REJECTED' }
function Get-CodyCorrelationCanaryV2LocalAppDataRoot {
    $value = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($value)) {
        Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'
    }
    return $value
}
function Get-CodyCorrelationCanaryV2Sha256 { param([Parameter(Mandatory)][string]$Text) $bytes = [Text.Encoding]::UTF8.GetBytes($Text); $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose(); [Array]::Clear($bytes, 0, $bytes.Length) } }
function Get-CodyCorrelationCanaryV2FileSha256 { param([Parameter(Mandatory)][string]$Path) $bytes=[IO.File]::ReadAllBytes($Path);$sha=[Security.Cryptography.SHA256]::Create();try{return([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();[Array]::Clear($bytes,0,$bytes.Length)} }
function ConvertTo-CodyCorrelationCanaryV2CanonicalJson { param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) { return ($Value | ConvertTo-Json -Compress) }
    if ($Value -is [int] -or $Value -is [long]) { return [string]$Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys=@($Value.Keys | ForEach-Object {[string]$_} | Sort-Object)
        if($keys.Count -eq 0){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_CANONICAL_REJECTED'}
        return '{' + (($keys | ForEach-Object {(ConvertTo-CodyCorrelationCanaryV2CanonicalJson $_) + ':' + (ConvertTo-CodyCorrelationCanaryV2CanonicalJson $Value[$_])}) -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [pscustomobject]) { return '[' + ((@($Value) | ForEach-Object { ConvertTo-CodyCorrelationCanaryV2CanonicalJson $_ }) -join ',') + ']' }
    $properties = @($Value.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } | Sort-Object -Property Name)
    if ($properties.Count -eq 0) { Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_CANONICAL_REJECTED' }
    return '{' + (($properties | ForEach-Object { (ConvertTo-CodyCorrelationCanaryV2CanonicalJson $_.Name) + ':' + (ConvertTo-CodyCorrelationCanaryV2CanonicalJson $_.Value) }) -join ',') + '}'
}
function Test-CodyCorrelationCanaryV2Snowflake { param([AllowNull()][object]$Value) return $Value -is [string] -and $Value -match '^[1-9][0-9]{15,19}$' }
function Test-CodyCorrelationCanaryV2Reference { param([AllowNull()][object]$Value) return $Value -is [string] -and $Value -match '^[A-Za-z0-9._-]{8,160}$' }
function Test-CodyCorrelationCanaryV2Correlation { param([AllowNull()][object]$Value) return $Value -is [string] -and $Value -match '^discord_cody_aru_correlation_[a-f0-9]{64}$' }
function Test-CodyCorrelationCanaryV2FixedTimeEqual {
    param([AllowNull()][object]$Left,[AllowNull()][object]$Right)
    if($Left -isnot [string] -or $Right -isnot [string]){return $false}
    $leftBytes=[Text.Encoding]::UTF8.GetBytes($Left);$rightBytes=[Text.Encoding]::UTF8.GetBytes($Right)
    try {
        if($leftBytes.Length -ne $rightBytes.Length){return $false}
        $difference=0
        for($i=0;$i -lt $leftBytes.Length;$i++){$difference=$difference -bor ($leftBytes[$i] -bxor $rightBytes[$i])}
        return $difference -eq 0
    } finally {[Array]::Clear($leftBytes,0,$leftBytes.Length);[Array]::Clear($rightBytes,0,$rightBytes.Length)}
}
function Test-CodyCorrelationCanaryV2DistinctSnowflakes {
    param([Parameter(Mandatory)][string]$First,[Parameter(Mandatory)][string]$Second,[Parameter(Mandatory)][string]$Third)
    $firstSecond=Test-CodyCorrelationCanaryV2FixedTimeEqual $First $Second
    $firstThird=Test-CodyCorrelationCanaryV2FixedTimeEqual $First $Third
    $secondThird=Test-CodyCorrelationCanaryV2FixedTimeEqual $Second $Third
    return (-not $firstSecond) -and (-not $firstThird) -and (-not $secondThird)
}
function Reset-CodyCorrelationCanaryV2OperationCounters {
    $script:LastLatchState='not_acquired'
    $script:CodyRequestSendAttemptCount=0
    $script:CodyRequestSendConfirmedCount=0
    $script:TokenReadCount=0
}
function Get-CodyCorrelationCanaryV2NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^[A-Za-z]:\\' -or $full.StartsWith('\\')) {
        Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'
    }
    $volumeRoot = [IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($volumeRoot)) {
        Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'
    }
    if ([IO.DriveInfo]::new($volumeRoot).DriveType -ne [IO.DriveType]::Fixed) {
        Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'
    }
    if ($full.Length -gt $volumeRoot.Length) {
        $full = $full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
    }
    return $full
}
function Test-CodyCorrelationCanaryV2PathWithin {
    param([Parameter(Mandatory)][string]$Candidate,[Parameter(Mandatory)][string]$Root)
    $candidatePath = Get-CodyCorrelationCanaryV2NormalizedPath $Candidate
    $rootPath = Get-CodyCorrelationCanaryV2NormalizedPath $Root
    return $candidatePath.Equals($rootPath,[StringComparison]::OrdinalIgnoreCase) -or $candidatePath.StartsWith("$rootPath$([IO.Path]::DirectorySeparatorChar)",[StringComparison]::OrdinalIgnoreCase)
}
function Assert-CodyCorrelationCanaryV2NoReparseAncestors {
    param([Parameter(Mandatory)][string]$Path)
    $probe=Get-CodyCorrelationCanaryV2NormalizedPath $Path
    while(-not (Test-Path -LiteralPath $probe)){
        $parent=Split-Path -Path $probe -Parent
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $probe){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'}
        $probe=$parent
    }
    while($true){
        $item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'}
        $parent=Split-Path -Path $probe -Parent
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $probe){break}
        $probe=$parent
    }
}
function Assert-CodyCorrelationCanaryV2RegularFile {
    param([Parameter(Mandatory)][string]$Path,[int]$MaximumBytes = 256KB,[string]$ErrorCode = 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED')
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 0 -or $item.Length -gt $MaximumBytes){Throw-CodyCorrelationCanaryV2Error $ErrorCode}
}
function Assert-CodyCorrelationCanaryV2TrustedStage {
    if([string]::IsNullOrWhiteSpace($script:LauncherScriptPath)){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED'}
    $scriptPath = Get-CodyCorrelationCanaryV2NormalizedPath $script:LauncherScriptPath
    $local = Get-CodyCorrelationCanaryV2NormalizedPath (Get-CodyCorrelationCanaryV2LocalAppDataRoot)
    $namespaceRoot=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $local $script:RuntimeNamespaceDirectoryName)
    $service = Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $namespaceRoot $script:NamespaceName)
    $launcherRoot=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $service 'launcher')
    $stageRoot=Get-CodyCorrelationCanaryV2NormalizedPath (Split-Path -Path $scriptPath -Parent)
    $proof=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $stageRoot 'CodyCorrelationCanaryV2StageProof.json')
    if (-not (Test-CodyCorrelationCanaryV2PathWithin $namespaceRoot $local) -or
        -not (Test-CodyCorrelationCanaryV2PathWithin $service $namespaceRoot) -or
        -not (Test-CodyCorrelationCanaryV2PathWithin $launcherRoot $service) -or
        -not (Test-CodyCorrelationCanaryV2PathWithin $stageRoot $launcherRoot) -or
        -not (Test-CodyCorrelationCanaryV2PathWithin $scriptPath $stageRoot) -or
        -not (Test-CodyCorrelationCanaryV2PathWithin $proof $stageRoot) -or
        -not ((Split-Path -Path $stageRoot -Parent).Equals($launcherRoot,[StringComparison]::OrdinalIgnoreCase)) -or
        -not $scriptPath.Equals((Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $stageRoot $script:LauncherName)),[StringComparison]::OrdinalIgnoreCase)) {
        Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED'
    }
    foreach($path in @($namespaceRoot,$service,$launcherRoot,$stageRoot,$scriptPath,$proof)){Assert-CodyCorrelationCanaryV2NoReparseAncestors $path}
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $namespaceRoot $true
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $service $true
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $launcherRoot $true
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $stageRoot $true
    Assert-CodyCorrelationCanaryV2RegularFile $scriptPath 256KB 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED'
    Assert-CodyCorrelationCanaryV2RegularFile $proof 4KB 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED'
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $scriptPath $false
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $proof $false
    $record=([IO.File]::ReadAllText($proof,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json -ErrorAction Stop);$keys=@($record.PSObject.Properties.Name)
    $unexpectedProofKeys=@(@('schema_version','pinned_launcher_sha256') | Where-Object {$_ -notin $keys})
    if($keys.Count -ne 2 -or $unexpectedProofKeys.Count -ne 0 -or $record.schema_version -cne 'hermes-agents-discord-cody-aru-correlation-canary-cody-stage-proof/v1' -or $record.pinned_launcher_sha256 -notmatch '^[a-f0-9]{64}$'){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED'}
    if ((Split-Path -Path $stageRoot -Leaf) -cne $record.pinned_launcher_sha256 -or (Get-CodyCorrelationCanaryV2FileSha256 $scriptPath) -cne $record.pinned_launcher_sha256) { Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED' }
    return [pscustomobject]@{ service_root = $service; manifest_path = (Join-Path $service $script:ManifestName); state_root = (Join-Path $service $script:StateDirectoryName) }
}
function Get-CodyCorrelationCanaryV2CurrentUserSid {
    $sidValue=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if([string]::IsNullOrWhiteSpace($sidValue)){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'}
    return [Security.Principal.SecurityIdentifier]::new($sidValue)
}
function Get-CodyCorrelationCanaryV2AccessControlObject {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][Security.AccessControl.AccessControlSections]$Sections)
    $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if($null -ne $extensions){
        if($Item -is [IO.DirectoryInfo]){return $extensions::GetAccessControl([IO.DirectoryInfo]$Item,$Sections)}
        if($Item -is [IO.FileInfo]){return $extensions::GetAccessControl([IO.FileInfo]$Item,$Sections)}
    }
    return $Item.GetAccessControl($Sections)
}
function Set-CodyCorrelationCanaryV2AccessControlObject {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][Security.AccessControl.FileSystemSecurity]$Security)
    $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if($null -ne $extensions){
        if($Item -is [IO.DirectoryInfo]){[void]$extensions::SetAccessControl([IO.DirectoryInfo]$Item,[Security.AccessControl.DirectorySecurity]$Security);return}
        if($Item -is [IO.FileInfo]){[void]$extensions::SetAccessControl([IO.FileInfo]$Item,[Security.AccessControl.FileSecurity]$Security);return}
    }
    $Item.SetAccessControl($Security)
}
function Get-CodyCorrelationCanaryV2AccessControl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if([bool]$item.PSIsContainer -ne $Directory -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'}
    return [pscustomobject]@{
        item=$item
        owner=(Get-CodyCorrelationCanaryV2AccessControlObject $item ([Security.AccessControl.AccessControlSections]::Owner)).GetOwner([Security.Principal.SecurityIdentifier])
        dacl=Get-CodyCorrelationCanaryV2AccessControlObject $item ([Security.AccessControl.AccessControlSections]::Access)
    }
}
function Set-CodyCorrelationCanaryV2CurrentUserOnlyDacl { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    try {
        $sid=Get-CodyCorrelationCanaryV2CurrentUserSid
        $security=Get-CodyCorrelationCanaryV2AccessControl $Path $Directory
        if(-not $security.owner.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase)){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'}
        $security.dacl.SetAccessRuleProtection($true,$false)
        foreach($existing in @($security.dacl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))){if($null -ne $existing){[void]$security.dacl.RemoveAccessRuleAll($existing)}}
        $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
        $security.dacl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,$inheritance,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
        Set-CodyCorrelationCanaryV2AccessControlObject $security.item $security.dacl
        Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $Path $Directory
    } catch {
        if((Get-CodyCorrelationCanaryV2ErrorCode $_) -eq 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'
    }
}
function Ensure-CodyCorrelationCanaryV2Directory { param([Parameter(Mandatory)][string]$Path)
    Assert-CodyCorrelationCanaryV2NoReparseAncestors $Path
    [IO.Directory]::CreateDirectory($Path) | Out-Null
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'}
    Set-CodyCorrelationCanaryV2CurrentUserOnlyDacl $Path $true
    Assert-CodyCorrelationCanaryV2NoReparseAncestors $Path
}
function Get-CodyCorrelationCanaryV2Layout { $layout = Assert-CodyCorrelationCanaryV2TrustedStage; Ensure-CodyCorrelationCanaryV2Directory $layout.service_root; Ensure-CodyCorrelationCanaryV2Directory $layout.state_root; return $layout }
function Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    $sid=Get-CodyCorrelationCanaryV2CurrentUserSid;$security=Get-CodyCorrelationCanaryV2AccessControl $Path $Directory;$acl=$security.dacl;$owner=$security.owner.Value
    $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
    if($null -eq $sid -or -not $acl.AreAccessRulesProtected -or -not $owner.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase)){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'}
    $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if($rules.Count -ne 1 -or $rules[0].IsInherited -or -not $rules[0].IdentityReference.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase) -or $rules[0].AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or $rules[0].FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or $rules[0].InheritanceFlags -ne $inheritance -or $rules[0].PropagationFlags -ne [Security.AccessControl.PropagationFlags]::None){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'}
}
function Read-CodyCorrelationCanaryV2Utf8JsonObject {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][int]$MaximumBytes,[Parameter(Mandatory)][string[]]$RequiredKeys,[Parameter(Mandatory)][string]$ErrorCode)
    $bytes = $null
    try {
        Assert-CodyCorrelationCanaryV2NoReparseAncestors $Path
        Assert-CodyCorrelationCanaryV2RegularFile $Path $MaximumBytes $ErrorCode
        $bytes = [IO.File]::ReadAllBytes($Path)
        if($bytes.Length -le 0 -or $bytes.Length -gt $MaximumBytes){Throw-CodyCorrelationCanaryV2Error $ErrorCode}
        $record = ([Text.UTF8Encoding]::new($false,$true).GetString($bytes) | ConvertFrom-Json -ErrorAction Stop)
        if($null -eq $record -or $record.GetType().FullName -ne 'System.Management.Automation.PSCustomObject'){Throw-CodyCorrelationCanaryV2Error $ErrorCode}
        $properties = @($record.PSObject.Properties)
        if($properties.Count -ne $RequiredKeys.Count){Throw-CodyCorrelationCanaryV2Error $ErrorCode}
        foreach($key in $RequiredKeys){if(@($properties | Where-Object { $_.Name -ceq $key -and $_.MemberType -eq 'NoteProperty' }).Count -ne 1){Throw-CodyCorrelationCanaryV2Error $ErrorCode}}
        return $record
    } catch { Throw-CodyCorrelationCanaryV2Error $ErrorCode
    } finally { if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)} }
}
function Get-CodyCorrelationCanaryV2LegacyLayout {
    $local=Get-CodyCorrelationCanaryV2NormalizedPath (Get-CodyCorrelationCanaryV2LocalAppDataRoot)
    $namespace=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $local 'HermesAgents')
    $root=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $namespace $script:LegacyNamespaceName)
    $secrets=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $root 'secrets')
    $provisioner=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $root 'provisioner')
    $manifest=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $root 'cody-runtime-manifest.local.json')
    $artifact=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $secrets 'cody-bot-token.currentuser.dpapi.json')
    if(-not(Test-CodyCorrelationCanaryV2PathWithin $namespace $local) -or -not(Test-CodyCorrelationCanaryV2PathWithin $root $namespace) -or -not(Test-CodyCorrelationCanaryV2PathWithin $secrets $root) -or -not(Test-CodyCorrelationCanaryV2PathWithin $provisioner $root) -or -not(Test-CodyCorrelationCanaryV2PathWithin $manifest $root) -or -not(Test-CodyCorrelationCanaryV2PathWithin $artifact $secrets)){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LEGACY_STORE_REJECTED'}
    return [pscustomobject]@{namespace=$namespace;root=$root;secrets=$secrets;manifest=$manifest;artifact=$artifact;provisioner=$provisioner}
}
function Assert-CodyCorrelationCanaryV2LegacyRoot {
    param([Parameter(Mandatory)][pscustomobject]$Legacy)
    foreach($path in @($Legacy.namespace,$Legacy.root)){Assert-CodyCorrelationCanaryV2NoReparseAncestors $path}
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $Legacy.namespace $true
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $Legacy.root $true
}
function Get-CodyCorrelationCanaryV2LegacyBindings {
    $legacy=Get-CodyCorrelationCanaryV2LegacyLayout;Assert-CodyCorrelationCanaryV2LegacyRoot $legacy
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $legacy.manifest $false
    $record=Read-CodyCorrelationCanaryV2Utf8JsonObject $legacy.manifest $script:MaximumManifestBytes @('schema_version','discord_channel_id','cody_bot_user_id','aru_bot_user_id','user_approval_reference') 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LEGACY_STORE_REJECTED'
if($record.schema_version -cnotin @('hermes-agents-discord-cody-aru-direct-bridge-cody-private-runtime/v1','hermes-agents-discord-cody-aru-cody-private-runtime/v1') -or -not(Test-CodyCorrelationCanaryV2Snowflake $record.discord_channel_id) -or -not(Test-CodyCorrelationCanaryV2Snowflake $record.cody_bot_user_id) -or -not(Test-CodyCorrelationCanaryV2Snowflake $record.aru_bot_user_id) -or -not(Test-CodyCorrelationCanaryV2DistinctSnowflakes $record.discord_channel_id $record.cody_bot_user_id $record.aru_bot_user_id) -or -not(Test-CodyCorrelationCanaryV2Reference $record.user_approval_reference)){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LEGACY_STORE_REJECTED'}
    return [pscustomobject]@{channel=$record.discord_channel_id;cody=$record.cody_bot_user_id;aru=$record.aru_bot_user_id}
}
function Get-CodyCorrelationCanaryV2Entropy {
    param([Parameter(Mandatory)][pscustomobject]$Legacy,[Parameter(Mandatory)][string]$BootstrapSha256)
    $material=[Text.Encoding]::UTF8.GetBytes("$script:LegacyBootstrapSchemaVersion|$($Legacy.root)|$BootstrapSha256");$sha=[Security.Cryptography.SHA256]::Create()
    try{return $sha.ComputeHash($material)}finally{$sha.Dispose();[Array]::Clear($material,0,$material.Length)}
}
function Assert-CodyCorrelationCanaryV2BootstrapStage {
    param([Parameter(Mandatory)][pscustomobject]$Legacy,[Parameter(Mandatory)][string]$BootstrapSha256)
    $stage=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $Legacy.provisioner $BootstrapSha256)
    $bootstrap=Get-CodyCorrelationCanaryV2NormalizedPath (Join-Path $stage 'CodyTokenDpapiBootstrap.ps1')
    if(-not(Test-CodyCorrelationCanaryV2PathWithin $stage $Legacy.provisioner) -or -not(Test-CodyCorrelationCanaryV2PathWithin $bootstrap $stage)){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
    foreach($path in @($Legacy.provisioner,$stage,$bootstrap)){Assert-CodyCorrelationCanaryV2NoReparseAncestors $path}
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $Legacy.provisioner $true
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $stage $true
    Assert-CodyCorrelationCanaryV2RegularFile $bootstrap 128KB 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $bootstrap $false
    if((Get-CodyCorrelationCanaryV2FileSha256 $bootstrap) -cne $BootstrapSha256){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
}
function Get-CodyCorrelationCanaryV2ProtectedCodyToken {
    $legacy=Get-CodyCorrelationCanaryV2LegacyLayout;Assert-CodyCorrelationCanaryV2LegacyRoot $legacy
    Assert-CodyCorrelationCanaryV2NoReparseAncestors $legacy.secrets;Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $legacy.secrets $true
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $legacy.artifact $false
    $artifact=Read-CodyCorrelationCanaryV2Utf8JsonObject $legacy.artifact $script:MaximumArtifactBytes @('schema_version','protection_scope','bootstrap_sha256','ciphertext_base64') 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'
    if($artifact.schema_version -cne $script:LegacyBootstrapSchemaVersion -or $artifact.protection_scope -cne 'CurrentUser' -or $artifact.bootstrap_sha256 -isnot [string] -or $artifact.bootstrap_sha256 -notmatch '^[a-f0-9]{64}$' -or $artifact.ciphertext_base64 -isnot [string] -or $artifact.ciphertext_base64.Length -lt 4 -or $artifact.ciphertext_base64.Length -gt $script:MaximumArtifactBytes -or $artifact.ciphertext_base64 -notmatch '^[A-Za-z0-9+/]+={0,2}$'){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
    Assert-CodyCorrelationCanaryV2BootstrapStage $legacy $artifact.bootstrap_sha256
    $entropy=$null;$cipher=$null;$plain=$null
    try {
        if($null -eq ('System.Security.Cryptography.ProtectedData' -as [type])){Add-Type -AssemblyName System.Security -ErrorAction Stop}
        if($null -eq ('System.Security.Cryptography.ProtectedData' -as [type])){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
        $entropy=Get-CodyCorrelationCanaryV2Entropy $legacy $artifact.bootstrap_sha256
        $cipher=[Convert]::FromBase64String($artifact.ciphertext_base64)
        if($cipher.Length -le 0 -or $cipher.Length -gt $script:MaximumArtifactBytes){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
        $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        if($plain.Length -lt 20 -or $plain.Length -gt 4096){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
        foreach($value in $plain){if(($value -lt 0x21)-or($value -gt 0x7e)-or-not([char]$value -match '[A-Za-z0-9._-]')){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}}
        return [Text.Encoding]::ASCII.GetString($plain)
    } catch { Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'
    } finally { if($null-ne$cipher){[Array]::Clear($cipher,0,$cipher.Length)};if($null-ne$plain){[Array]::Clear($plain,0,$plain.Length)};if($null-ne$entropy){[Array]::Clear($entropy,0,$entropy.Length)} }
}
function ConvertFrom-CodyCorrelationCanaryV2Manifest { param([Parameter(Mandatory)][string]$Path)
    Assert-CodyCorrelationCanaryV2NoReparseAncestors $Path
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $Path $false
    $manifest = Read-CodyCorrelationCanaryV2Utf8JsonObject $Path $script:MaximumManifestBytes @('schema_version','discord_channel_id','cody_bot_user_id','aru_bot_user_id','user_approval_reference') 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MANIFEST_REJECTED'
if ($manifest.schema_version -cne $script:ManifestSchemaVersion -or -not (Test-CodyCorrelationCanaryV2Snowflake $manifest.discord_channel_id) -or -not (Test-CodyCorrelationCanaryV2Snowflake $manifest.cody_bot_user_id) -or -not (Test-CodyCorrelationCanaryV2Snowflake $manifest.aru_bot_user_id) -or -not(Test-CodyCorrelationCanaryV2DistinctSnowflakes $manifest.discord_channel_id $manifest.cody_bot_user_id $manifest.aru_bot_user_id) -or -not (Test-CodyCorrelationCanaryV2Reference $manifest.user_approval_reference)) { Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MANIFEST_REJECTED' }
    return $manifest
}
function New-CodyCorrelationCanaryV2Reference { $bytes = [byte[]]::new(32); $rng=[Security.Cryptography.RandomNumberGenerator]::Create(); try { $rng.GetBytes($bytes); return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant() } finally { $rng.Dispose(); [Array]::Clear($bytes,0,$bytes.Length) } }
function Write-CodyCorrelationCanaryV2Manifest { param([Parameter(Mandatory)][pscustomobject]$Layout,[Parameter(Mandatory)][string]$Channel,[Parameter(Mandatory)][string]$Cody,[Parameter(Mandatory)][string]$Aru)
if (-not (Test-CodyCorrelationCanaryV2Snowflake $Channel) -or -not (Test-CodyCorrelationCanaryV2Snowflake $Cody) -or -not (Test-CodyCorrelationCanaryV2Snowflake $Aru) -or -not(Test-CodyCorrelationCanaryV2DistinctSnowflakes $Channel $Cody $Aru)) { Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MANIFEST_REJECTED' }
    $record = [ordered]@{ schema_version=$script:ManifestSchemaVersion; discord_channel_id=$Channel; cody_bot_user_id=$Cody; aru_bot_user_id=$Aru; user_approval_reference=(New-CodyCorrelationCanaryV2Reference) }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Compress)); $stream = $null
    try {
        Assert-CodyCorrelationCanaryV2NoReparseAncestors $Layout.manifest_path
        $stream = [IO.File]::Open($Layout.manifest_path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        [Array]::Clear($bytes,0,$bytes.Length)
    }
    Set-CodyCorrelationCanaryV2CurrentUserOnlyDacl $Layout.manifest_path $false
}
function Get-CodyCorrelationCanaryV2Material { param([Parameter(Mandatory)][pscustomobject]$Manifest)
    $manifestDigest = Get-CodyCorrelationCanaryV2Sha256 (ConvertTo-CodyCorrelationCanaryV2CanonicalJson ([ordered]@{ schema_version=$Manifest.schema_version; discord_channel_id=$Manifest.discord_channel_id; cody_bot_user_id=$Manifest.cody_bot_user_id; aru_bot_user_id=$Manifest.aru_bot_user_id }))
    $correlation = 'discord_cody_aru_correlation_' + (Get-CodyCorrelationCanaryV2Sha256 (ConvertTo-CodyCorrelationCanaryV2CanonicalJson ([ordered]@{ schema_version='hermes-agents-discord-cody-aru-correlation-canary-cody-start/v1'; manifest_digest=$manifestDigest; approval_reference=$Manifest.user_approval_reference; correlation_namespace='discord_cody_aru_correlation_bound_canary_v2' })))
    $nonce = 'dcab_' + ((Get-CodyCorrelationCanaryV2Sha256 (ConvertTo-CodyCorrelationCanaryV2CanonicalJson ([ordered]@{ schema_version='hermes-agents-discord-cody-aru-direct-bridge-request/v1'; nonce_namespace='discord_create_message_enforce_nonce_v1'; correlation_id=$correlation }))).Substring(0,20))
    return [pscustomobject]@{ manifest_digest=$manifestDigest; correlation_id=$correlation; nonce=$nonce; request_content="CODY_CANARY_REQUEST $correlation" }
}
function Get-CodyCorrelationCanaryV2StatePath { param([Parameter(Mandatory)][pscustomobject]$Layout,[Parameter(Mandatory)][pscustomobject]$Manifest) $key = Get-CodyCorrelationCanaryV2Sha256 "$script:SchemaVersion|$($Manifest.user_approval_reference)"; return [pscustomobject]@{ latch=(Join-Path $Layout.state_root "$key.claimed"); handoff=(Join-Path $Layout.state_root "$key.handoff.json") } }
function Get-CodyCorrelationCanaryV2ValidatedStatePath {
    param([Parameter(Mandatory)][pscustomobject]$Layout,[Parameter(Mandatory)][pscustomobject]$Manifest)
    $paths=Get-CodyCorrelationCanaryV2StatePath $Layout $Manifest
    $state=Get-CodyCorrelationCanaryV2NormalizedPath $Layout.state_root
    $latch=Get-CodyCorrelationCanaryV2NormalizedPath $paths.latch
    $handoff=Get-CodyCorrelationCanaryV2NormalizedPath $paths.handoff
    if(-not(Test-CodyCorrelationCanaryV2PathWithin $latch $state) -or -not(Test-CodyCorrelationCanaryV2PathWithin $handoff $state)){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'}
    Assert-CodyCorrelationCanaryV2NoReparseAncestors $state
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $state $true
    return [pscustomobject]@{latch=$latch;handoff=$handoff}
}
function Claim-CodyCorrelationCanaryV2Latch { param([Parameter(Mandatory)][string]$Path)
    $script:LastLatchState='not_acquired';$stream=$null;$bytes=$null
    try {
        Assert-CodyCorrelationCanaryV2NoReparseAncestors $Path
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $bytes=[Text.Encoding]::ASCII.GetBytes('claimed')
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
        $stream.Dispose();$stream=$null
        Set-CodyCorrelationCanaryV2CurrentUserOnlyDacl $Path $false
        $script:LastLatchState='acquired'
    } catch { Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ALREADY_CONSUMED_OR_AMBIGUOUS'
    } finally {if($null-ne$stream){$stream.Dispose()};if($null-ne$bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
}
function Test-CodyCorrelationCanaryV2PostedMessage { param([AllowNull()][object]$Message,[Parameter(Mandatory)][pscustomobject]$Manifest,[Parameter(Mandatory)][pscustomobject]$Material)
    if ($null -eq $Message -or -not (Test-CodyCorrelationCanaryV2Snowflake $Message.id) -or -not(Test-CodyCorrelationCanaryV2Snowflake $Message.channel_id) -or -not(Test-CodyCorrelationCanaryV2Snowflake $Message.author.id) -or -not(Test-CodyCorrelationCanaryV2FixedTimeEqual $Message.channel_id $Manifest.discord_channel_id) -or -not(Test-CodyCorrelationCanaryV2FixedTimeEqual $Message.author.id $Manifest.cody_bot_user_id) -or $Message.author.bot -ne $true -or $Message.type -ne 0 -or -not(Test-CodyCorrelationCanaryV2FixedTimeEqual $Message.content $Material.request_content) -or -not(Test-CodyCorrelationCanaryV2FixedTimeEqual $Message.nonce $Material.nonce) -or @($Message.attachments).Count -ne 0 -or @($Message.embeds).Count -ne 0 -or @($Message.components).Count -ne 0 -or $null -ne $Message.webhook_id -or $null -ne $Message.message_reference) { return $false }; return $true
}
function Write-CodyCorrelationCanaryV2Handoff { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][pscustomobject]$Manifest,[Parameter(Mandatory)][pscustomobject]$Material,[Parameter(Mandatory)][string]$MessageId)
    if(-not(Test-CodyCorrelationCanaryV2Snowflake $MessageId)){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_HANDOFF_REJECTED'}
    $record=[ordered]@{ schema_version=$script:HandoffStateSchemaVersion; correlation_id=$Material.correlation_id; cody_request_message_id=$MessageId; manifest_digest=$Material.manifest_digest; channel_binding_verified=$true; cody_binding_verified=$true; aru_binding_available=$true }
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Compress));$stream=$null
    try {
        Assert-CodyCorrelationCanaryV2NoReparseAncestors $Path
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } finally {
        if($null -ne $stream){$stream.Dispose()}
        [Array]::Clear($bytes,0,$bytes.Length)
    }
    Set-CodyCorrelationCanaryV2CurrentUserOnlyDacl $Path $false
}
function Read-CodyCorrelationCanaryV2Handoff { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][pscustomobject]$Material)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_HANDOFF_ABSENT'}
    Assert-CodyCorrelationCanaryV2NoReparseAncestors $Path
    Assert-CodyCorrelationCanaryV2CurrentUserOnlyDacl $Path $false
    $record=Read-CodyCorrelationCanaryV2Utf8JsonObject $Path $script:MaximumStateBytes @('schema_version','correlation_id','cody_request_message_id','manifest_digest','channel_binding_verified','cody_binding_verified','aru_binding_available') 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_HANDOFF_REJECTED'
    if($record.schema_version -cne $script:HandoffStateSchemaVersion -or -not(Test-CodyCorrelationCanaryV2Correlation $record.correlation_id) -or -not(Test-CodyCorrelationCanaryV2FixedTimeEqual $record.correlation_id $Material.correlation_id) -or -not(Test-CodyCorrelationCanaryV2Snowflake $record.cody_request_message_id) -or $record.manifest_digest -notmatch '^[a-f0-9]{64}$' -or -not(Test-CodyCorrelationCanaryV2FixedTimeEqual $record.manifest_digest $Material.manifest_digest) -or $record.channel_binding_verified -ne $true -or $record.cody_binding_verified -ne $true -or $record.aru_binding_available -ne $true){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_HANDOFF_REJECTED'}
    return [ordered]@{schema_version=$script:HandoffSchemaVersion;ok=$true;operation='cody_correlation_canary_operator_handoff';correlation_id=$record.correlation_id;cody_request_message_id=$record.cody_request_message_id;channel_binding_verified=$true;cody_binding_verified=$true;aru_binding_available=$true;token_read_count=0;network_request_count=0;sensitive_output_count=0}
}
function New-CodyCorrelationCanaryV2Result { param([bool]$Ok,[string]$Mode,[string]$State,[string]$Reason,[AllowNull()][object]$Handoff,[AllowNull()][string]$Correlation,[bool]$HandoffAvailable=$false,[int]$CodyRequestSendAttemptCount=$script:CodyRequestSendAttemptCount,[int]$CodyRequestSendConfirmedCount=$script:CodyRequestSendConfirmedCount,[int]$TokenReadCount=$script:TokenReadCount)
    return [ordered]@{schema_version=$script:SchemaVersion;ok=$Ok;operation='cody_correlation_canary_v2';mode=$Mode;action_latch_state=$script:LastLatchState;terminal_state=$State;terminal_reason=$Reason;correlation_id=$Correlation;post_start_handoff_available=$HandoffAvailable;handoff=$Handoff;cody_request_send_attempt_count=$CodyRequestSendAttemptCount;cody_request_send_confirmed_count=$CodyRequestSendConfirmedCount;token_read_count=$TokenReadCount;network_request_count=$CodyRequestSendAttemptCount;retry_permitted=$false;retry_count=0;model_call_count=0;sensitive_output_count=0}
}
function Invoke-CodyCorrelationCanaryV2ForTest { param([AllowNull()][string]$RequestedMode,[AllowNull()][string]$Channel,[AllowNull()][string]$Cody,[AllowNull()][string]$Aru,[Parameter(Mandatory)][scriptblock]$TokenReader,[Parameter(Mandatory)][scriptblock]$JsonPost)
Reset-CodyCorrelationCanaryV2OperationCounters
    if($RequestedMode -cnotin @('bootstrap','start','handoff')){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MODE_REJECTED'}
    $layout=Get-CodyCorrelationCanaryV2Layout
    if($RequestedMode -eq 'bootstrap'){Write-CodyCorrelationCanaryV2Manifest $layout $Channel $Cody $Aru;return(New-CodyCorrelationCanaryV2Result $true 'bootstrap' 'imported' 'private_manifest_created' $null $null)}
    $manifest=ConvertFrom-CodyCorrelationCanaryV2Manifest $layout.manifest_path;$material=Get-CodyCorrelationCanaryV2Material $manifest;$paths=Get-CodyCorrelationCanaryV2ValidatedStatePath $layout $manifest
    if($RequestedMode -eq 'handoff'){return(New-CodyCorrelationCanaryV2Result $true 'handoff' 'ready' 'post_start_handoff_ready' (Read-CodyCorrelationCanaryV2Handoff $paths.handoff $material) $material.correlation_id $true)}
    if($RequestedMode -ne 'start'){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MODE_REJECTED'}
Claim-CodyCorrelationCanaryV2Latch $paths.latch;$script:TokenReadCount+=1;$token=& $TokenReader;if($token -isnot [string] -or $token -notmatch '^[A-Za-z0-9._-]{20,256}$'){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
$script:CodyRequestSendAttemptCount+=1;$message=& $JsonPost $manifest.discord_channel_id $token $material.request_content $material.nonce
if(-not(Test-CodyCorrelationCanaryV2PostedMessage $message $manifest $material)){return(New-CodyCorrelationCanaryV2Result $false 'start' 'ambiguous' 'cody_request_post_ambiguous' $null $material.correlation_id $false)}
$script:CodyRequestSendConfirmedCount+=1
try { Write-CodyCorrelationCanaryV2Handoff $paths.handoff $manifest $material $message.id } catch { return(New-CodyCorrelationCanaryV2Result $false 'start' 'ambiguous' 'cody_request_confirmed_state_ambiguous' $null $material.correlation_id $false) }
return(New-CodyCorrelationCanaryV2Result $true 'start' 'sent' 'cody_request_sent' $null $material.correlation_id $true)
}
function Invoke-CodyCorrelationCanaryV2BoundedPost {
    param([Parameter(Mandatory)][string]$Channel,[Parameter(Mandatory)][string]$Token,[Parameter(Mandatory)][string]$Content,[Parameter(Mandatory)][string]$Nonce)
    $request=$null;$response=$null;$requestStream=$null;$responseStream=$null;$memory=$null;$reader=$null;$bodyBytes=$null;$buffer=$null;$previous=$null;$responseBytes=$null
    try {
        if(-not(Test-CodyCorrelationCanaryV2Snowflake $Channel) -or -not(Test-CodyCorrelationCanaryV2Correlation ($Content.Substring('CODY_CANARY_REQUEST '.Length))) -or $Nonce -notmatch '^dcab_[a-f0-9]{20}$'){return $null}
        $body=[ordered]@{content=$Content;allowed_mentions=[ordered]@{parse=@()};nonce=$Nonce;enforce_nonce=$true}
        $bodyBytes=[Text.UTF8Encoding]::new($false).GetBytes(($body|ConvertTo-Json -Compress))
        if($bodyBytes.Length -le 0 -or $bodyBytes.Length -gt 4KB){return $null}
        $previous=[Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol=$previous -bor [Net.SecurityProtocolType]::Tls12
        $request=[Net.WebRequest]::CreateHttp("https://discord.com/api/v10/channels/$Channel/messages")
        if($request -isnot [Net.HttpWebRequest]){return $null}
        $request.Method='POST'
        $request.AllowAutoRedirect=$false
        $request.Proxy=$null
        $request.CookieContainer=$null
        $request.UseDefaultCredentials=$false
        $request.Credentials=$null
        $request.PreAuthenticate=$false
        $request.UnsafeAuthenticatedConnectionSharing=$false
        $request.AutomaticDecompression=[Net.DecompressionMethods]::None
        $request.KeepAlive=$false
        $request.Timeout=10000
        $request.ReadWriteTimeout=10000
        $request.Headers[[Net.HttpRequestHeader]::Authorization]="Bot $Token"
        $request.Accept='application/json'
        $request.ContentType='application/json'
        $request.ContentLength=$bodyBytes.Length
        $requestStream=$request.GetRequestStream()
        $requestStream.Write($bodyBytes,0,$bodyBytes.Length)
        $requestStream.Flush()
        $requestStream.Dispose();$requestStream=$null
        try {
            $response=[Net.HttpWebResponse]$request.GetResponse()
        } catch [Net.WebException] {
            if($_.Exception.Status -ne [Net.WebExceptionStatus]::ProtocolError -or $_.Exception.Response -isnot [Net.HttpWebResponse]){return $null}
            $response=[Net.HttpWebResponse]$_.Exception.Response
        }
        if(@(200,201) -notcontains [int]$response.StatusCode -or $response.ContentLength -gt $script:MaximumResponseBytes){return $null}
        $responseStream=$response.GetResponseStream()
        $memory=[IO.MemoryStream]::new()
        $buffer=[byte[]]::new(4096)
        while($true){
            $remaining=$script:MaximumResponseBytes-[int]$memory.Length
            $read=$responseStream.Read($buffer,0,[Math]::Min($buffer.Length,$remaining+1))
            if($read -le 0){break}
            if(($memory.Length+$read) -gt $script:MaximumResponseBytes){return $null}
            $memory.Write($buffer,0,$read)
        }
        $responseBytes=$memory.ToArray()
        $reader=[IO.StreamReader]::new([IO.MemoryStream]::new($responseBytes),[Text.UTF8Encoding]::new($false,$true))
        return ($reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return $null
    } finally {
        if($null-ne$reader){$reader.Dispose()}
        if($null-ne$memory){$memory.Dispose()}
        if($null-ne$responseStream){$responseStream.Dispose()}
        if($null-ne$requestStream){$requestStream.Dispose()}
        if($null-ne$response){$response.Close()}
        if($null-ne$request){$request.Abort()}
        if($null-ne$bodyBytes){[Array]::Clear($bodyBytes,0,$bodyBytes.Length)}
        if($null-ne$buffer){[Array]::Clear($buffer,0,$buffer.Length)}
        if($null-ne$responseBytes){[Array]::Clear($responseBytes,0,$responseBytes.Length)}
        if($null-ne$previous){[Net.ServicePointManager]::SecurityProtocol=$previous}
    }
}
function Invoke-CodyCorrelationCanaryV2 { param([AllowNull()][string]$RequestedMode)
Reset-CodyCorrelationCanaryV2OperationCounters
    if($RequestedMode -cnotin @('bootstrap','start','handoff')){Throw-CodyCorrelationCanaryV2Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MODE_REJECTED'}
    if($RequestedMode -eq 'bootstrap'){$bindings=Get-CodyCorrelationCanaryV2LegacyBindings;return(Invoke-CodyCorrelationCanaryV2ForTest 'bootstrap' $bindings.channel $bindings.cody $bindings.aru {throw 'unused'} {throw 'unused'})}
    if($RequestedMode -eq 'handoff'){return(Invoke-CodyCorrelationCanaryV2ForTest 'handoff' $null $null $null {throw 'unused'} {throw 'unused'})}
    $post={param($channel,$credential,$content,$nonce)Invoke-CodyCorrelationCanaryV2BoundedPost $channel $credential $content $nonce};return(Invoke-CodyCorrelationCanaryV2ForTest 'start' $null $null $null {Get-CodyCorrelationCanaryV2ProtectedCodyToken} $post)
}
if($MyInvocation.InvocationName -ne '.') { try { [Console]::Out.WriteLine((Invoke-CodyCorrelationCanaryV2 $Mode|ConvertTo-Json -Compress)) } catch { [Console]::Out.WriteLine((New-CodyCorrelationCanaryV2Result $false $Mode 'rejected' (Get-CodyCorrelationCanaryV2ErrorCode $_) $null|ConvertTo-Json -Compress)); exit 2 } }
