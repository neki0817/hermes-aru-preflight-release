[CmdletBinding()]
# Do not use a mandatory/ValidateSet binder here: a missing or unrecognised
# mode must reach the fail-closed JSON result below without touching layout,
# token, latch, or transport.
param([AllowNull()][string]$Mode)

# A new Cody v5 lane. It does not read or reuse v1 manual-canary state, nor
# adopt, persist, or output the v1 approval reference. Bootstrap validates the
# legacy private manifest only to recover its independently verified public
# bindings, then writes a new private manifest; start consumes an isolated
# CreateNew latch before one POST; handoff is read-only with no token or HTTP.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-v5-cody-launcher/v1'
$script:ManifestSchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-v5-cody-private-runtime/v1'
$script:HandoffStateSchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-v5-cody-operator-handoff-state/v1'
$script:HandoffSchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-v5-cody-operator-handoff/v1'
$script:RuntimeNamespaceDirectoryName = 'HermesAgentsCodyAruCorrelationCanaryV5'
$script:NamespaceName = 'discord-cody-aru-correlation-canary-v5'
$script:LegacyNamespaceName = 'discord-cody-aru-direct-bridge'
$script:LegacyBootstrapSchemaVersion = 'hermes-agents-discord-cody-aru-cody-token-dpapi-bootstrap/v1'
$script:ManifestName = 'cody-correlation-canary-v5-private-runtime.local.json'
$script:StateDirectoryName = 'cody-correlation-canary-v5-start-state'
$script:LauncherName = 'CodyCorrelationCanaryV5Launcher.ps1'
$script:LastLatchState = 'not_acquired'
$script:CodyRequestSendAttemptCount = 0
$script:CodyRequestSendConfirmedCount = 0
$script:TokenReadCount = 0
$script:LauncherScriptPath = $MyInvocation.MyCommand.Path
$script:MaximumManifestBytes = 8KB
$script:MaximumArtifactBytes = 16KB
$script:MaximumStateBytes = 8KB
$script:MaximumResponseBytes = 8KB

function Throw-CodyCorrelationCanaryV5Error { param([string]$Code) $error = [System.Exception]::new($Code); $error.Data['code'] = $Code; throw $error }
function Get-CodyCorrelationCanaryV5ErrorCode { param([AllowNull()][object]$ErrorRecord) if ($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception -and $null -ne $ErrorRecord.Exception.Data['code']) { return [string]$ErrorRecord.Exception.Data['code'] }; return 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_REJECTED' }
function Get-CodyCorrelationCanaryV5LocalAppDataRoot {
    $value = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($value)) {
        Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'
    }
    return $value
}
function Get-CodyCorrelationCanaryV5Sha256 { param([Parameter(Mandatory)][string]$Text) $bytes = [Text.Encoding]::UTF8.GetBytes($Text); $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose(); [Array]::Clear($bytes, 0, $bytes.Length) } }
function Get-CodyCorrelationCanaryV5FileSha256 { param([Parameter(Mandatory)][string]$Path) $bytes=[IO.File]::ReadAllBytes($Path);$sha=[Security.Cryptography.SHA256]::Create();try{return([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();[Array]::Clear($bytes,0,$bytes.Length)} }
function ConvertTo-CodyCorrelationCanaryV5CanonicalJson { param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) { return ($Value | ConvertTo-Json -Compress) }
    if ($Value -is [int] -or $Value -is [long]) { return [string]$Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys=@($Value.Keys | ForEach-Object {[string]$_} | Sort-Object)
        if($keys.Count -eq 0){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_CANONICAL_REJECTED'}
        return '{' + (($keys | ForEach-Object {(ConvertTo-CodyCorrelationCanaryV5CanonicalJson $_) + ':' + (ConvertTo-CodyCorrelationCanaryV5CanonicalJson $Value[$_])}) -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [pscustomobject]) { return '[' + ((@($Value) | ForEach-Object { ConvertTo-CodyCorrelationCanaryV5CanonicalJson $_ }) -join ',') + ']' }
    $properties = @($Value.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } | Sort-Object -Property Name)
    if ($properties.Count -eq 0) { Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_CANONICAL_REJECTED' }
    return '{' + (($properties | ForEach-Object { (ConvertTo-CodyCorrelationCanaryV5CanonicalJson $_.Name) + ':' + (ConvertTo-CodyCorrelationCanaryV5CanonicalJson $_.Value) }) -join ',') + '}'
}
function Test-CodyCorrelationCanaryV5Snowflake { param([AllowNull()][object]$Value) return $Value -is [string] -and $Value -match '^[1-9][0-9]{15,19}$' }
function Test-CodyCorrelationCanaryV5Reference { param([AllowNull()][object]$Value) return $Value -is [string] -and $Value -match '^[A-Za-z0-9._-]{8,160}$' }
function Test-CodyCorrelationCanaryV5Correlation { param([AllowNull()][object]$Value) return $Value -is [string] -and $Value -match '^discord_cody_aru_correlation_v5_[a-f0-9]{64}$' }
function Test-CodyCorrelationCanaryV5FixedTimeEqual {
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
function Test-CodyCorrelationCanaryV5AbsentOrNullNoteProperty {
    param([AllowNull()][object]$Value,[Parameter(Mandatory)][string]$Name)
    try {
        if($null -eq $Value -or $Value -is [System.Array]){return $false}
        $matches=@($Value.PSObject.Properties | Where-Object { $_.Name -ceq $Name -and $_.MemberType -eq 'NoteProperty' })
        return $matches.Count -eq 0 -or ($matches.Count -eq 1 -and $null -eq $matches[0].Value)
    } catch { return $false }
}
function Test-CodyCorrelationCanaryV5OptionalNonce {
    param([AllowNull()][object]$Value,[Parameter(Mandatory)][string]$Expected)
    try {
        if($null -eq $Value -or $Value -is [System.Array]){return $false}
        $matches=@($Value.PSObject.Properties | Where-Object { $_.Name -ceq 'nonce' -and $_.MemberType -eq 'NoteProperty' })
        return $matches.Count -eq 0 -or ($matches.Count -eq 1 -and ($null -eq $matches[0].Value -or (Test-CodyCorrelationCanaryV5FixedTimeEqual $matches[0].Value $Expected)))
    } catch { return $false }
}
function Test-CodyCorrelationCanaryV5DistinctSnowflakes {
    param([Parameter(Mandatory)][string]$First,[Parameter(Mandatory)][string]$Second,[Parameter(Mandatory)][string]$Third)
    $firstSecond=Test-CodyCorrelationCanaryV5FixedTimeEqual $First $Second
    $firstThird=Test-CodyCorrelationCanaryV5FixedTimeEqual $First $Third
    $secondThird=Test-CodyCorrelationCanaryV5FixedTimeEqual $Second $Third
    return (-not $firstSecond) -and (-not $firstThird) -and (-not $secondThird)
}
function Reset-CodyCorrelationCanaryV5OperationCounters {
    $script:LastLatchState='not_acquired'
    $script:CodyRequestSendAttemptCount=0
    $script:CodyRequestSendConfirmedCount=0
    $script:TokenReadCount=0
}
function Get-CodyCorrelationCanaryV5NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^[A-Za-z]:\\' -or $full.StartsWith('\\')) {
        Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'
    }
    $volumeRoot = [IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($volumeRoot)) {
        Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'
    }
    if ([IO.DriveInfo]::new($volumeRoot).DriveType -ne [IO.DriveType]::Fixed) {
        Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'
    }
    if ($full.Length -gt $volumeRoot.Length) {
        $full = $full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
    }
    return $full
}
function Test-CodyCorrelationCanaryV5PathWithin {
    param([Parameter(Mandatory)][string]$Candidate,[Parameter(Mandatory)][string]$Root)
    $candidatePath = Get-CodyCorrelationCanaryV5NormalizedPath $Candidate
    $rootPath = Get-CodyCorrelationCanaryV5NormalizedPath $Root
    return $candidatePath.Equals($rootPath,[StringComparison]::OrdinalIgnoreCase) -or $candidatePath.StartsWith("$rootPath$([IO.Path]::DirectorySeparatorChar)",[StringComparison]::OrdinalIgnoreCase)
}
function Assert-CodyCorrelationCanaryV5NoReparseAncestors {
    param([Parameter(Mandatory)][string]$Path)
    $probe=Get-CodyCorrelationCanaryV5NormalizedPath $Path
    while(-not (Test-Path -LiteralPath $probe)){
        $parent=Split-Path -Path $probe -Parent
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $probe){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'}
        $probe=$parent
    }
    while($true){
        $item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'}
        $parent=Split-Path -Path $probe -Parent
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $probe){break}
        $probe=$parent
    }
}
function Assert-CodyCorrelationCanaryV5RegularFile {
    param([Parameter(Mandatory)][string]$Path,[int]$MaximumBytes = 256KB,[string]$ErrorCode = 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED')
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 0 -or $item.Length -gt $MaximumBytes){Throw-CodyCorrelationCanaryV5Error $ErrorCode}
}
function Assert-CodyCorrelationCanaryV5TrustedStage {
    if([string]::IsNullOrWhiteSpace($script:LauncherScriptPath)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED'}
    $scriptPath = Get-CodyCorrelationCanaryV5NormalizedPath $script:LauncherScriptPath
    $local = Get-CodyCorrelationCanaryV5NormalizedPath (Get-CodyCorrelationCanaryV5LocalAppDataRoot)
    $namespaceRoot=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $local $script:RuntimeNamespaceDirectoryName)
    $service = Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $namespaceRoot $script:NamespaceName)
    $launcherRoot=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $service 'launcher')
    $stageRoot=Get-CodyCorrelationCanaryV5NormalizedPath (Split-Path -Path $scriptPath -Parent)
    $proof=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $stageRoot 'CodyCorrelationCanaryV5StageProof.json')
    if (-not (Test-CodyCorrelationCanaryV5PathWithin $namespaceRoot $local) -or
        -not (Test-CodyCorrelationCanaryV5PathWithin $service $namespaceRoot) -or
        -not (Test-CodyCorrelationCanaryV5PathWithin $launcherRoot $service) -or
        -not (Test-CodyCorrelationCanaryV5PathWithin $stageRoot $launcherRoot) -or
        -not (Test-CodyCorrelationCanaryV5PathWithin $scriptPath $stageRoot) -or
        -not (Test-CodyCorrelationCanaryV5PathWithin $proof $stageRoot) -or
        -not ((Split-Path -Path $stageRoot -Parent).Equals($launcherRoot,[StringComparison]::OrdinalIgnoreCase)) -or
        -not $scriptPath.Equals((Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $stageRoot $script:LauncherName)),[StringComparison]::OrdinalIgnoreCase)) {
        Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED'
    }
    foreach($path in @($namespaceRoot,$service,$launcherRoot,$stageRoot,$scriptPath,$proof)){Assert-CodyCorrelationCanaryV5NoReparseAncestors $path}
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $namespaceRoot $true
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $service $true
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $launcherRoot $true
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $stageRoot $true
    Assert-CodyCorrelationCanaryV5RegularFile $scriptPath 256KB 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED'
    Assert-CodyCorrelationCanaryV5RegularFile $proof 4KB 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED'
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $scriptPath $false
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $proof $false
    $record=([IO.File]::ReadAllText($proof,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json -ErrorAction Stop);$keys=@($record.PSObject.Properties.Name)
    $unexpectedProofKeys=@(@('schema_version','pinned_launcher_sha256') | Where-Object {$_ -notin $keys})
    if($keys.Count -ne 2 -or $unexpectedProofKeys.Count -ne 0 -or $record.schema_version -cne 'hermes-agents-discord-cody-aru-correlation-canary-v5-cody-stage-proof/v1' -or $record.pinned_launcher_sha256 -notmatch '^[a-f0-9]{64}$'){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED'}
    if ((Split-Path -Path $stageRoot -Leaf) -cne $record.pinned_launcher_sha256 -or (Get-CodyCorrelationCanaryV5FileSha256 $scriptPath) -cne $record.pinned_launcher_sha256) { Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TRUSTED_STAGE_REQUIRED' }
    return [pscustomobject]@{ service_root = $service; manifest_path = (Join-Path $service $script:ManifestName); state_root = (Join-Path $service $script:StateDirectoryName) }
}
function Get-CodyCorrelationCanaryV5CurrentUserSid {
    $sidValue=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if([string]::IsNullOrWhiteSpace($sidValue)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'}
    return [Security.Principal.SecurityIdentifier]::new($sidValue)
}
function Get-CodyCorrelationCanaryV5AccessControlObject {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][Security.AccessControl.AccessControlSections]$Sections)
    $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if($null -ne $extensions){
        if($Item -is [IO.DirectoryInfo]){return $extensions::GetAccessControl([IO.DirectoryInfo]$Item,$Sections)}
        if($Item -is [IO.FileInfo]){return $extensions::GetAccessControl([IO.FileInfo]$Item,$Sections)}
    }
    return $Item.GetAccessControl($Sections)
}
function Set-CodyCorrelationCanaryV5AccessControlObject {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][Security.AccessControl.FileSystemSecurity]$Security)
    $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if($null -ne $extensions){
        if($Item -is [IO.DirectoryInfo]){[void]$extensions::SetAccessControl([IO.DirectoryInfo]$Item,[Security.AccessControl.DirectorySecurity]$Security);return}
        if($Item -is [IO.FileInfo]){[void]$extensions::SetAccessControl([IO.FileInfo]$Item,[Security.AccessControl.FileSecurity]$Security);return}
    }
    $Item.SetAccessControl($Security)
}
function Get-CodyCorrelationCanaryV5AccessControl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if([bool]$item.PSIsContainer -ne $Directory -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'}
    return [pscustomobject]@{
        item=$item
        owner=(Get-CodyCorrelationCanaryV5AccessControlObject $item ([Security.AccessControl.AccessControlSections]::Owner)).GetOwner([Security.Principal.SecurityIdentifier])
        dacl=Get-CodyCorrelationCanaryV5AccessControlObject $item ([Security.AccessControl.AccessControlSections]::Access)
    }
}
function Set-CodyCorrelationCanaryV5CurrentUserOnlyDacl { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    try {
        $sid=Get-CodyCorrelationCanaryV5CurrentUserSid
        $security=Get-CodyCorrelationCanaryV5AccessControl $Path $Directory
        if(-not $security.owner.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'}
        $security.dacl.SetAccessRuleProtection($true,$false)
        foreach($existing in @($security.dacl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))){if($null -ne $existing){[void]$security.dacl.RemoveAccessRuleAll($existing)}}
        $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
        $security.dacl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,$inheritance,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
        Set-CodyCorrelationCanaryV5AccessControlObject $security.item $security.dacl
        Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $Path $Directory
    } catch {
        if((Get-CodyCorrelationCanaryV5ErrorCode $_) -eq 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'
    }
}
function Ensure-CodyCorrelationCanaryV5Directory { param([Parameter(Mandatory)][string]$Path)
    Assert-CodyCorrelationCanaryV5NoReparseAncestors $Path
    [IO.Directory]::CreateDirectory($Path) | Out-Null
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'}
    Set-CodyCorrelationCanaryV5CurrentUserOnlyDacl $Path $true
    Assert-CodyCorrelationCanaryV5NoReparseAncestors $Path
}
function Get-CodyCorrelationCanaryV5Layout { $layout = Assert-CodyCorrelationCanaryV5TrustedStage; Ensure-CodyCorrelationCanaryV5Directory $layout.service_root; Ensure-CodyCorrelationCanaryV5Directory $layout.state_root; return $layout }
function Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    $sid=Get-CodyCorrelationCanaryV5CurrentUserSid;$security=Get-CodyCorrelationCanaryV5AccessControl $Path $Directory;$acl=$security.dacl;$owner=$security.owner.Value
    $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
    if($null -eq $sid -or -not $acl.AreAccessRulesProtected -or -not $owner.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'}
    $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if($rules.Count -ne 1 -or $rules[0].IsInherited -or -not $rules[0].IdentityReference.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase) -or $rules[0].AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or $rules[0].FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or $rules[0].InheritanceFlags -ne $inheritance -or $rules[0].PropagationFlags -ne [Security.AccessControl.PropagationFlags]::None){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ACL_REJECTED'}
}
function Read-CodyCorrelationCanaryV5Utf8JsonObject {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][int]$MaximumBytes,[Parameter(Mandatory)][string[]]$RequiredKeys,[Parameter(Mandatory)][string]$ErrorCode)
    $bytes = $null
    try {
        Assert-CodyCorrelationCanaryV5NoReparseAncestors $Path
        Assert-CodyCorrelationCanaryV5RegularFile $Path $MaximumBytes $ErrorCode
        $bytes = [IO.File]::ReadAllBytes($Path)
        if($bytes.Length -le 0 -or $bytes.Length -gt $MaximumBytes){Throw-CodyCorrelationCanaryV5Error $ErrorCode}
        $record = ([Text.UTF8Encoding]::new($false,$true).GetString($bytes) | ConvertFrom-Json -ErrorAction Stop)
        if($null -eq $record -or $record.GetType().FullName -ne 'System.Management.Automation.PSCustomObject'){Throw-CodyCorrelationCanaryV5Error $ErrorCode}
        $properties = @($record.PSObject.Properties)
        if($properties.Count -ne $RequiredKeys.Count){Throw-CodyCorrelationCanaryV5Error $ErrorCode}
        foreach($key in $RequiredKeys){if(@($properties | Where-Object { $_.Name -ceq $key -and $_.MemberType -eq 'NoteProperty' }).Count -ne 1){Throw-CodyCorrelationCanaryV5Error $ErrorCode}}
        return $record
    } catch { Throw-CodyCorrelationCanaryV5Error $ErrorCode
    } finally { if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)} }
}
function Get-CodyCorrelationCanaryV5LegacyLayout {
    $local=Get-CodyCorrelationCanaryV5NormalizedPath (Get-CodyCorrelationCanaryV5LocalAppDataRoot)
    $namespace=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $local 'HermesAgents')
    $root=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $namespace $script:LegacyNamespaceName)
    $secrets=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $root 'secrets')
    $provisioner=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $root 'provisioner')
    $manifest=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $root 'cody-runtime-manifest.local.json')
    $artifact=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $secrets 'cody-bot-token.currentuser.dpapi.json')
    if(-not(Test-CodyCorrelationCanaryV5PathWithin $namespace $local) -or -not(Test-CodyCorrelationCanaryV5PathWithin $root $namespace) -or -not(Test-CodyCorrelationCanaryV5PathWithin $secrets $root) -or -not(Test-CodyCorrelationCanaryV5PathWithin $provisioner $root) -or -not(Test-CodyCorrelationCanaryV5PathWithin $manifest $root) -or -not(Test-CodyCorrelationCanaryV5PathWithin $artifact $secrets)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LEGACY_STORE_REJECTED'}
    return [pscustomobject]@{namespace=$namespace;root=$root;secrets=$secrets;manifest=$manifest;artifact=$artifact;provisioner=$provisioner}
}
function Assert-CodyCorrelationCanaryV5LegacyRoot {
    param([Parameter(Mandatory)][pscustomobject]$Legacy)
    foreach($path in @($Legacy.namespace,$Legacy.root)){Assert-CodyCorrelationCanaryV5NoReparseAncestors $path}
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $Legacy.namespace $true
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $Legacy.root $true
}
function Get-CodyCorrelationCanaryV5LegacyBindings {
    $legacy=Get-CodyCorrelationCanaryV5LegacyLayout;Assert-CodyCorrelationCanaryV5LegacyRoot $legacy
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $legacy.manifest $false
    $record=Read-CodyCorrelationCanaryV5Utf8JsonObject $legacy.manifest $script:MaximumManifestBytes @('schema_version','discord_channel_id','cody_bot_user_id','aru_bot_user_id','user_approval_reference') 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LEGACY_STORE_REJECTED'
if($record.schema_version -cnotin @('hermes-agents-discord-cody-aru-direct-bridge-cody-private-runtime/v1','hermes-agents-discord-cody-aru-cody-private-runtime/v1') -or -not(Test-CodyCorrelationCanaryV5Snowflake $record.discord_channel_id) -or -not(Test-CodyCorrelationCanaryV5Snowflake $record.cody_bot_user_id) -or -not(Test-CodyCorrelationCanaryV5Snowflake $record.aru_bot_user_id) -or -not(Test-CodyCorrelationCanaryV5DistinctSnowflakes $record.discord_channel_id $record.cody_bot_user_id $record.aru_bot_user_id) -or -not(Test-CodyCorrelationCanaryV5Reference $record.user_approval_reference)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LEGACY_STORE_REJECTED'}
    return [pscustomobject]@{channel=$record.discord_channel_id;cody=$record.cody_bot_user_id;aru=$record.aru_bot_user_id}
}
function Get-CodyCorrelationCanaryV5Entropy {
    param([Parameter(Mandatory)][pscustomobject]$Legacy,[Parameter(Mandatory)][string]$BootstrapSha256)
    $material=[Text.Encoding]::UTF8.GetBytes("$script:LegacyBootstrapSchemaVersion|$($Legacy.root)|$BootstrapSha256");$sha=[Security.Cryptography.SHA256]::Create()
    try{return $sha.ComputeHash($material)}finally{$sha.Dispose();[Array]::Clear($material,0,$material.Length)}
}
function Assert-CodyCorrelationCanaryV5BootstrapStage {
    param([Parameter(Mandatory)][pscustomobject]$Legacy,[Parameter(Mandatory)][string]$BootstrapSha256)
    $stage=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $Legacy.provisioner $BootstrapSha256)
    $bootstrap=Get-CodyCorrelationCanaryV5NormalizedPath (Join-Path $stage 'CodyTokenDpapiBootstrap.ps1')
    if(-not(Test-CodyCorrelationCanaryV5PathWithin $stage $Legacy.provisioner) -or -not(Test-CodyCorrelationCanaryV5PathWithin $bootstrap $stage)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
    foreach($path in @($Legacy.provisioner,$stage,$bootstrap)){Assert-CodyCorrelationCanaryV5NoReparseAncestors $path}
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $Legacy.provisioner $true
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $stage $true
    Assert-CodyCorrelationCanaryV5RegularFile $bootstrap 128KB 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $bootstrap $false
    if((Get-CodyCorrelationCanaryV5FileSha256 $bootstrap) -cne $BootstrapSha256){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
}
function Get-CodyCorrelationCanaryV5ProtectedCodyToken {
    $legacy=Get-CodyCorrelationCanaryV5LegacyLayout;Assert-CodyCorrelationCanaryV5LegacyRoot $legacy
    Assert-CodyCorrelationCanaryV5NoReparseAncestors $legacy.secrets;Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $legacy.secrets $true
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $legacy.artifact $false
    $artifact=Read-CodyCorrelationCanaryV5Utf8JsonObject $legacy.artifact $script:MaximumArtifactBytes @('schema_version','protection_scope','bootstrap_sha256','ciphertext_base64') 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'
    if($artifact.schema_version -cne $script:LegacyBootstrapSchemaVersion -or $artifact.protection_scope -cne 'CurrentUser' -or $artifact.bootstrap_sha256 -isnot [string] -or $artifact.bootstrap_sha256 -notmatch '^[a-f0-9]{64}$' -or $artifact.ciphertext_base64 -isnot [string] -or $artifact.ciphertext_base64.Length -lt 4 -or $artifact.ciphertext_base64.Length -gt $script:MaximumArtifactBytes -or $artifact.ciphertext_base64 -notmatch '^[A-Za-z0-9+/]+={0,2}$'){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
    Assert-CodyCorrelationCanaryV5BootstrapStage $legacy $artifact.bootstrap_sha256
    $entropy=$null;$cipher=$null;$plain=$null
    try {
        if($null -eq ('System.Security.Cryptography.ProtectedData' -as [type])){Add-Type -AssemblyName System.Security -ErrorAction Stop}
        if($null -eq ('System.Security.Cryptography.ProtectedData' -as [type])){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
        $entropy=Get-CodyCorrelationCanaryV5Entropy $legacy $artifact.bootstrap_sha256
        $cipher=[Convert]::FromBase64String($artifact.ciphertext_base64)
        if($cipher.Length -le 0 -or $cipher.Length -gt $script:MaximumArtifactBytes){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
        $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        if($plain.Length -lt 20 -or $plain.Length -gt 4096){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
        foreach($value in $plain){if(($value -lt 0x21)-or($value -gt 0x7e)-or-not([char]$value -match '[A-Za-z0-9._-]')){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}}
        return [Text.Encoding]::ASCII.GetString($plain)
    } catch { Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'
    } finally { if($null-ne$cipher){[Array]::Clear($cipher,0,$cipher.Length)};if($null-ne$plain){[Array]::Clear($plain,0,$plain.Length)};if($null-ne$entropy){[Array]::Clear($entropy,0,$entropy.Length)} }
}
function ConvertFrom-CodyCorrelationCanaryV5Manifest { param([Parameter(Mandatory)][string]$Path)
    Assert-CodyCorrelationCanaryV5NoReparseAncestors $Path
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $Path $false
    $manifest = Read-CodyCorrelationCanaryV5Utf8JsonObject $Path $script:MaximumManifestBytes @('schema_version','discord_channel_id','cody_bot_user_id','aru_bot_user_id','user_approval_reference') 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MANIFEST_REJECTED'
if ($manifest.schema_version -cne $script:ManifestSchemaVersion -or -not (Test-CodyCorrelationCanaryV5Snowflake $manifest.discord_channel_id) -or -not (Test-CodyCorrelationCanaryV5Snowflake $manifest.cody_bot_user_id) -or -not (Test-CodyCorrelationCanaryV5Snowflake $manifest.aru_bot_user_id) -or -not(Test-CodyCorrelationCanaryV5DistinctSnowflakes $manifest.discord_channel_id $manifest.cody_bot_user_id $manifest.aru_bot_user_id) -or -not (Test-CodyCorrelationCanaryV5Reference $manifest.user_approval_reference)) { Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MANIFEST_REJECTED' }
    return $manifest
}
function New-CodyCorrelationCanaryV5Reference { $bytes = [byte[]]::new(32); $rng=[Security.Cryptography.RandomNumberGenerator]::Create(); try { $rng.GetBytes($bytes); return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant() } finally { $rng.Dispose(); [Array]::Clear($bytes,0,$bytes.Length) } }
function Write-CodyCorrelationCanaryV5Manifest { param([Parameter(Mandatory)][pscustomobject]$Layout,[Parameter(Mandatory)][string]$Channel,[Parameter(Mandatory)][string]$Cody,[Parameter(Mandatory)][string]$Aru)
if (-not (Test-CodyCorrelationCanaryV5Snowflake $Channel) -or -not (Test-CodyCorrelationCanaryV5Snowflake $Cody) -or -not (Test-CodyCorrelationCanaryV5Snowflake $Aru) -or -not(Test-CodyCorrelationCanaryV5DistinctSnowflakes $Channel $Cody $Aru)) { Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MANIFEST_REJECTED' }
    $record = [ordered]@{ schema_version=$script:ManifestSchemaVersion; discord_channel_id=$Channel; cody_bot_user_id=$Cody; aru_bot_user_id=$Aru; user_approval_reference=(New-CodyCorrelationCanaryV5Reference) }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Compress)); $stream = $null
    try {
        Assert-CodyCorrelationCanaryV5NoReparseAncestors $Layout.manifest_path
        $stream = [IO.File]::Open($Layout.manifest_path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        [Array]::Clear($bytes,0,$bytes.Length)
    }
    Set-CodyCorrelationCanaryV5CurrentUserOnlyDacl $Layout.manifest_path $false
}
function Get-CodyCorrelationCanaryV5Material { param([Parameter(Mandatory)][pscustomobject]$Manifest)
    $manifestDigest = Get-CodyCorrelationCanaryV5Sha256 (ConvertTo-CodyCorrelationCanaryV5CanonicalJson ([ordered]@{ schema_version=$Manifest.schema_version; discord_channel_id=$Manifest.discord_channel_id; cody_bot_user_id=$Manifest.cody_bot_user_id; aru_bot_user_id=$Manifest.aru_bot_user_id }))
    $correlation = 'discord_cody_aru_correlation_v5_' + (Get-CodyCorrelationCanaryV5Sha256 (ConvertTo-CodyCorrelationCanaryV5CanonicalJson ([ordered]@{ schema_version='hermes-agents-discord-cody-aru-correlation-canary-v5-cody-start/v1'; manifest_digest=$manifestDigest; approval_reference=$Manifest.user_approval_reference; correlation_namespace='discord_cody_aru_correlation_bound_canary_v5' })))
    # Discord Create Message permits nonce values up to 25 characters.  The
    # six-character v5 prefix therefore leaves nineteen hexadecimal digits.
    $nonce = 'dcab5_' + ((Get-CodyCorrelationCanaryV5Sha256 (ConvertTo-CodyCorrelationCanaryV5CanonicalJson ([ordered]@{ schema_version='hermes-agents-discord-cody-aru-correlation-canary-v5-request/v1'; nonce_namespace='discord_create_message_enforce_nonce_v5'; correlation_id=$correlation }))).Substring(0,19))
    return [pscustomobject]@{ manifest_digest=$manifestDigest; correlation_id=$correlation; nonce=$nonce; request_content="CODY_CANARY_V5_REQUEST $correlation" }
}
function Get-CodyCorrelationCanaryV5StatePath { param([Parameter(Mandatory)][pscustomobject]$Layout,[Parameter(Mandatory)][pscustomobject]$Manifest) $key = Get-CodyCorrelationCanaryV5Sha256 "$script:SchemaVersion|$($Manifest.user_approval_reference)"; return [pscustomobject]@{ latch=(Join-Path $Layout.state_root "$key.claimed"); handoff=(Join-Path $Layout.state_root "$key.handoff.json") } }
function Get-CodyCorrelationCanaryV5ValidatedStatePath {
    param([Parameter(Mandatory)][pscustomobject]$Layout,[Parameter(Mandatory)][pscustomobject]$Manifest)
    $paths=Get-CodyCorrelationCanaryV5StatePath $Layout $Manifest
    $state=Get-CodyCorrelationCanaryV5NormalizedPath $Layout.state_root
    $latch=Get-CodyCorrelationCanaryV5NormalizedPath $paths.latch
    $handoff=Get-CodyCorrelationCanaryV5NormalizedPath $paths.handoff
    if(-not(Test-CodyCorrelationCanaryV5PathWithin $latch $state) -or -not(Test-CodyCorrelationCanaryV5PathWithin $handoff $state)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_LAYOUT_REJECTED'}
    Assert-CodyCorrelationCanaryV5NoReparseAncestors $state
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $state $true
    return [pscustomobject]@{latch=$latch;handoff=$handoff}
}
function Claim-CodyCorrelationCanaryV5Latch { param([Parameter(Mandatory)][string]$Path)
    $script:LastLatchState='not_acquired';$stream=$null;$bytes=$null
    try {
        Assert-CodyCorrelationCanaryV5NoReparseAncestors $Path
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $bytes=[Text.Encoding]::ASCII.GetBytes('claimed')
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
        $stream.Dispose();$stream=$null
        Set-CodyCorrelationCanaryV5CurrentUserOnlyDacl $Path $false
        $script:LastLatchState='acquired'
    } catch { Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_ALREADY_CONSUMED_OR_AMBIGUOUS'
    } finally {if($null-ne$stream){$stream.Dispose()};if($null-ne$bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
}
function Test-CodyCorrelationCanaryV5PostedMessage { param([AllowNull()][object]$Message,[Parameter(Mandatory)][pscustomobject]$Manifest,[Parameter(Mandatory)][pscustomobject]$Material)
    if ($null -eq $Message -or -not (Test-CodyCorrelationCanaryV5Snowflake $Message.id) -or -not(Test-CodyCorrelationCanaryV5Snowflake $Message.channel_id) -or -not(Test-CodyCorrelationCanaryV5Snowflake $Message.author.id) -or -not(Test-CodyCorrelationCanaryV5FixedTimeEqual $Message.channel_id $Manifest.discord_channel_id) -or -not(Test-CodyCorrelationCanaryV5FixedTimeEqual $Message.author.id $Manifest.cody_bot_user_id) -or $Message.author.bot -ne $true -or $Message.type -ne 0 -or -not(Test-CodyCorrelationCanaryV5FixedTimeEqual $Message.content $Material.request_content) -or -not(Test-CodyCorrelationCanaryV5OptionalNonce $Message $Material.nonce) -or @($Message.attachments).Count -ne 0 -or @($Message.embeds).Count -ne 0 -or @($Message.components).Count -ne 0 -or -not(Test-CodyCorrelationCanaryV5AbsentOrNullNoteProperty $Message 'webhook_id') -or -not(Test-CodyCorrelationCanaryV5AbsentOrNullNoteProperty $Message 'message_reference')) { return $false }; return $true
}
function Get-CodyCorrelationCanaryV5HandoffBundle { param([Parameter(Mandatory)][string]$MessageId,[Parameter(Mandatory)][string]$Correlation)
    if(-not(Test-CodyCorrelationCanaryV5Snowflake $MessageId) -or -not(Test-CodyCorrelationCanaryV5Correlation $Correlation)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_HANDOFF_REJECTED'}
    $digest=Get-CodyCorrelationCanaryV5Sha256 "hermes-agents-discord-cody-aru-correlation-canary-v5-operator-handoff-bundle/v1|$MessageId|$Correlation"
    return "dcab5h.$MessageId.$Correlation.$digest"
}
function Write-CodyCorrelationCanaryV5Handoff { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][pscustomobject]$Manifest,[Parameter(Mandatory)][pscustomobject]$Material,[Parameter(Mandatory)][string]$MessageId)
    if(-not(Test-CodyCorrelationCanaryV5Snowflake $MessageId)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_HANDOFF_REJECTED'}
    $record=[ordered]@{ schema_version=$script:HandoffStateSchemaVersion; correlation_id=$Material.correlation_id; cody_request_message_id=$MessageId; manifest_digest=$Material.manifest_digest; channel_binding_verified=$true; cody_binding_verified=$true; aru_binding_available=$true }
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Compress));$stream=$null
    try {
        Assert-CodyCorrelationCanaryV5NoReparseAncestors $Path
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } finally {
        if($null -ne $stream){$stream.Dispose()}
        [Array]::Clear($bytes,0,$bytes.Length)
    }
    Set-CodyCorrelationCanaryV5CurrentUserOnlyDacl $Path $false
}
function Read-CodyCorrelationCanaryV5Handoff { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][pscustomobject]$Material)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_HANDOFF_ABSENT'}
    Assert-CodyCorrelationCanaryV5NoReparseAncestors $Path
    Assert-CodyCorrelationCanaryV5CurrentUserOnlyDacl $Path $false
    $record=Read-CodyCorrelationCanaryV5Utf8JsonObject $Path $script:MaximumStateBytes @('schema_version','correlation_id','cody_request_message_id','manifest_digest','channel_binding_verified','cody_binding_verified','aru_binding_available') 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_HANDOFF_REJECTED'
    if($record.schema_version -cne $script:HandoffStateSchemaVersion -or -not(Test-CodyCorrelationCanaryV5Correlation $record.correlation_id) -or -not(Test-CodyCorrelationCanaryV5FixedTimeEqual $record.correlation_id $Material.correlation_id) -or -not(Test-CodyCorrelationCanaryV5Snowflake $record.cody_request_message_id) -or $record.manifest_digest -notmatch '^[a-f0-9]{64}$' -or -not(Test-CodyCorrelationCanaryV5FixedTimeEqual $record.manifest_digest $Material.manifest_digest) -or $record.channel_binding_verified -ne $true -or $record.cody_binding_verified -ne $true -or $record.aru_binding_available -ne $true){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_HANDOFF_REJECTED'}
    return [ordered]@{schema_version=$script:HandoffSchemaVersion;ok=$true;operation='cody_correlation_canary_v5_operator_handoff';handoff_bundle=(Get-CodyCorrelationCanaryV5HandoffBundle $record.cody_request_message_id $record.correlation_id);channel_binding_verified=$true;cody_binding_verified=$true;aru_binding_available=$true;token_read_count=0;network_request_count=0;sensitive_output_count=0}
}
function New-CodyCorrelationCanaryV5Result { param([bool]$Ok,[string]$Mode,[string]$State,[string]$Reason,[AllowNull()][object]$Handoff,[AllowNull()][string]$Correlation,[bool]$HandoffAvailable=$false,[int]$CodyRequestSendAttemptCount=$script:CodyRequestSendAttemptCount,[int]$CodyRequestSendConfirmedCount=$script:CodyRequestSendConfirmedCount,[int]$TokenReadCount=$script:TokenReadCount)
    return [ordered]@{schema_version=$script:SchemaVersion;ok=$Ok;operation='cody_correlation_canary_v5';mode=$Mode;action_latch_state=$script:LastLatchState;terminal_state=$State;terminal_reason=$Reason;correlation_id=$null;correlation_available=(Test-CodyCorrelationCanaryV5Correlation $Correlation);post_start_handoff_available=$HandoffAvailable;handoff=$Handoff;cody_request_send_attempt_count=$CodyRequestSendAttemptCount;cody_request_send_confirmed_count=$CodyRequestSendConfirmedCount;token_read_count=$TokenReadCount;network_request_count=$CodyRequestSendAttemptCount;retry_permitted=$false;retry_count=0;model_call_count=0;sensitive_output_count=0}
}
function Invoke-CodyCorrelationCanaryV5ForTest { param([AllowNull()][string]$RequestedMode,[AllowNull()][string]$Channel,[AllowNull()][string]$Cody,[AllowNull()][string]$Aru,[Parameter(Mandatory)][scriptblock]$TokenReader,[Parameter(Mandatory)][scriptblock]$JsonPost)
Reset-CodyCorrelationCanaryV5OperationCounters
    if($RequestedMode -cnotin @('bootstrap','start','handoff')){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MODE_REJECTED'}
    $layout=Get-CodyCorrelationCanaryV5Layout
    if($RequestedMode -eq 'bootstrap'){Write-CodyCorrelationCanaryV5Manifest $layout $Channel $Cody $Aru;return(New-CodyCorrelationCanaryV5Result $true 'bootstrap' 'imported' 'private_manifest_created' $null $null)}
    $manifest=ConvertFrom-CodyCorrelationCanaryV5Manifest $layout.manifest_path;$material=Get-CodyCorrelationCanaryV5Material $manifest;$paths=Get-CodyCorrelationCanaryV5ValidatedStatePath $layout $manifest
    if($RequestedMode -eq 'handoff'){return(New-CodyCorrelationCanaryV5Result $true 'handoff' 'ready' 'post_start_handoff_ready' (Read-CodyCorrelationCanaryV5Handoff $paths.handoff $material) $material.correlation_id $true)}
    if($RequestedMode -ne 'start'){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MODE_REJECTED'}
Claim-CodyCorrelationCanaryV5Latch $paths.latch;$script:TokenReadCount+=1;$token=& $TokenReader;if($token -isnot [string] -or $token -notmatch '^[A-Za-z0-9._-]{20,256}$'){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_TOKEN_REJECTED'}
$script:CodyRequestSendAttemptCount+=1;$message=& $JsonPost $manifest.discord_channel_id $token $material.request_content $material.nonce
if(-not(Test-CodyCorrelationCanaryV5PostedMessage $message $manifest $material)){return(New-CodyCorrelationCanaryV5Result $false 'start' 'ambiguous' 'cody_request_post_ambiguous' $null $material.correlation_id $false)}
$script:CodyRequestSendConfirmedCount+=1
try { Write-CodyCorrelationCanaryV5Handoff $paths.handoff $manifest $material $message.id } catch { return(New-CodyCorrelationCanaryV5Result $false 'start' 'ambiguous' 'cody_request_confirmed_state_ambiguous' $null $material.correlation_id $false) }
return(New-CodyCorrelationCanaryV5Result $true 'start' 'sent' 'cody_request_sent' $null $material.correlation_id $true)
}
function Invoke-CodyCorrelationCanaryV5BoundedPost {
    param([Parameter(Mandatory)][string]$Channel,[Parameter(Mandatory)][string]$Token,[Parameter(Mandatory)][string]$Content,[Parameter(Mandatory)][string]$Nonce)
    $request=$null;$response=$null;$requestStream=$null;$responseStream=$null;$memory=$null;$reader=$null;$bodyBytes=$null;$buffer=$null;$previous=$null;$responseBytes=$null
    try {
        if(-not(Test-CodyCorrelationCanaryV5Snowflake $Channel) -or -not(Test-CodyCorrelationCanaryV5Correlation ($Content.Substring('CODY_CANARY_V5_REQUEST '.Length))) -or $Nonce -notmatch '^dcab5_[a-f0-9]{19}$'){return $null}
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
function Invoke-CodyCorrelationCanaryV5 { param([AllowNull()][string]$RequestedMode)
Reset-CodyCorrelationCanaryV5OperationCounters
    if($RequestedMode -cnotin @('bootstrap','start','handoff')){Throw-CodyCorrelationCanaryV5Error 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_MODE_REJECTED'}
    if($RequestedMode -eq 'bootstrap'){$bindings=Get-CodyCorrelationCanaryV5LegacyBindings;return(Invoke-CodyCorrelationCanaryV5ForTest 'bootstrap' $bindings.channel $bindings.cody $bindings.aru {throw 'unused'} {throw 'unused'})}
    if($RequestedMode -eq 'handoff'){return(Invoke-CodyCorrelationCanaryV5ForTest 'handoff' $null $null $null {throw 'unused'} {throw 'unused'})}
    $post={param($channel,$credential,$content,$nonce)Invoke-CodyCorrelationCanaryV5BoundedPost $channel $credential $content $nonce};return(Invoke-CodyCorrelationCanaryV5ForTest 'start' $null $null $null {Get-CodyCorrelationCanaryV5ProtectedCodyToken} $post)
}
if($MyInvocation.InvocationName -ne '.') { try { [Console]::Out.WriteLine((Invoke-CodyCorrelationCanaryV5 $Mode|ConvertTo-Json -Compress)) } catch { [Console]::Out.WriteLine((New-CodyCorrelationCanaryV5Result $false $Mode 'rejected' (Get-CodyCorrelationCanaryV5ErrorCode $_) $null|ConvertTo-Json -Compress)); exit 2 } }
