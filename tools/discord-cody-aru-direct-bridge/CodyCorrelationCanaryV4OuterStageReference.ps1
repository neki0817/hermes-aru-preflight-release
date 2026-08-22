# Hash-pinned source-only staging reference for Cody correlation-canary v4.
# It creates no runtime manifest, token, network request, or launcher process.
# The caller supplies independently pinned launcher bytes; this file verifies
# the bytes before copying them into a protected, isolated stage.

if ($MyInvocation.InvocationName -ne '.') {
    [Console]::Out.WriteLine('{"ok":false,"error_code":"DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REFERENCE_ONLY","sensitive_output_count":0}')
    exit 2
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:V4LauncherFileName = 'CodyCorrelationCanaryV4Launcher.ps1'
$script:V4NamespaceDirectoryName = 'HermesAgentsCodyAruCorrelationCanaryV4'
$script:V4ServiceDirectoryName = 'discord-cody-aru-correlation-canary-v4'
$script:V4LauncherDirectoryName = 'launcher'
$script:V4ProofFileName = 'CodyCorrelationCanaryV4StageProof.json'
$script:V4ProofSchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-v4-cody-stage-proof/v1'
$script:V4MaximumSourceBytes = 256KB

function Throw-CodyCorrelationCanaryV4OuterStageError {
    param([Parameter(Mandatory)][string]$Code)
    throw [System.InvalidOperationException]::new($Code)
}
function Get-CodyCorrelationCanaryV4OuterStageErrorCode {
    param([AllowNull()][object]$ErrorRecord)
    if($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception -and [string]$ErrorRecord.Exception.Message -match '^DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_[A-Z_]+$'){
        return [string]$ErrorRecord.Exception.Message
    }
    return 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'
}
function Get-CodyCorrelationCanaryV4OuterStageLocalAppDataRoot {
    $value=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if([string]::IsNullOrWhiteSpace($value)){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
    return $value
}
function Get-CodyCorrelationCanaryV4OuterStageNormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $full=[IO.Path]::GetFullPath($Path)
        if($full -notmatch '^[A-Za-z]:\\' -or $full.StartsWith('\\')){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
        $volume=[IO.Path]::GetPathRoot($full)
        if([string]::IsNullOrWhiteSpace($volume) -or [IO.DriveInfo]::new($volume).DriveType -ne [IO.DriveType]::Fixed){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
        if($full.Length -gt $volume.Length){$full=$full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))}
        return $full
    } catch {
        if((Get-CodyCorrelationCanaryV4OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'
    }
}
function Test-CodyCorrelationCanaryV4OuterStagePathWithin {
    param([Parameter(Mandatory)][string]$Candidate,[Parameter(Mandatory)][string]$Root)
    $candidatePath=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath $Candidate
    $rootPath=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath $Root
    return $candidatePath.Equals($rootPath,[StringComparison]::OrdinalIgnoreCase) -or $candidatePath.StartsWith("$rootPath$([IO.Path]::DirectorySeparatorChar)",[StringComparison]::OrdinalIgnoreCase)
}
function Assert-CodyCorrelationCanaryV4OuterStageNoReparseAncestors {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $probe=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath $Path
        while(-not (Test-Path -LiteralPath $probe)){
            $parent=Split-Path -Path $probe -Parent
            if([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($probe,[StringComparison]::OrdinalIgnoreCase)){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
            $probe=$parent
        }
        while($true){
            $item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
            $parent=Split-Path -Path $probe -Parent
            if([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($probe,[StringComparison]::OrdinalIgnoreCase)){break}
            $probe=$parent
        }
    } catch {
        if((Get-CodyCorrelationCanaryV4OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'
    }
}
function Get-CodyCorrelationCanaryV4OuterStageCurrentUserSid {
    $sidValue=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if([string]::IsNullOrWhiteSpace($sidValue)){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
    return [Security.Principal.SecurityIdentifier]::new($sidValue)
}
function Get-CodyCorrelationCanaryV4OuterStageAccessControlObject {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][Security.AccessControl.AccessControlSections]$Sections)
    $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if($null -ne $extensions){
        if($Item -is [IO.DirectoryInfo]){return $extensions::GetAccessControl([IO.DirectoryInfo]$Item,$Sections)}
        if($Item -is [IO.FileInfo]){return $extensions::GetAccessControl([IO.FileInfo]$Item,$Sections)}
    }
    return $Item.GetAccessControl($Sections)
}
function Set-CodyCorrelationCanaryV4OuterStageAccessControlObject {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][Security.AccessControl.FileSystemSecurity]$Security)
    $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if($null -ne $extensions){
        if($Item -is [IO.DirectoryInfo]){[void]$extensions::SetAccessControl([IO.DirectoryInfo]$Item,[Security.AccessControl.DirectorySecurity]$Security);return}
        if($Item -is [IO.FileInfo]){[void]$extensions::SetAccessControl([IO.FileInfo]$Item,[Security.AccessControl.FileSecurity]$Security);return}
    }
    $Item.SetAccessControl($Security)
}
function Get-CodyCorrelationCanaryV4OuterStageAccessControl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if([bool]$item.PSIsContainer -ne $Directory -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
    return [pscustomobject]@{
        item=$item
        owner=(Get-CodyCorrelationCanaryV4OuterStageAccessControlObject $item ([Security.AccessControl.AccessControlSections]::Owner)).GetOwner([Security.Principal.SecurityIdentifier])
        dacl=Get-CodyCorrelationCanaryV4OuterStageAccessControlObject $item ([Security.AccessControl.AccessControlSections]::Access)
    }
}
function Assert-CodyCorrelationCanaryV4OuterStageCurrentUserOnlyDacl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    try {
        $sid=Get-CodyCorrelationCanaryV4OuterStageCurrentUserSid
        $security=Get-CodyCorrelationCanaryV4OuterStageAccessControl $Path $Directory
        $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
        $rules=@($security.dacl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
        if(-not $security.owner.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase) -or -not $security.dacl.AreAccessRulesProtected -or $rules.Count -ne 1 -or $rules[0].IsInherited -or -not $rules[0].IdentityReference.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase) -or $rules[0].AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or $rules[0].FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or $rules[0].InheritanceFlags -ne $inheritance -or $rules[0].PropagationFlags -ne [Security.AccessControl.PropagationFlags]::None){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
    } catch {
        if((Get-CodyCorrelationCanaryV4OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'
    }
}
function Set-CodyCorrelationCanaryV4OuterStageCurrentUserOnlyDacl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    try {
        $sid=Get-CodyCorrelationCanaryV4OuterStageCurrentUserSid
        $security=Get-CodyCorrelationCanaryV4OuterStageAccessControl $Path $Directory
        if(-not $security.owner.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase)){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
        $security.dacl.SetAccessRuleProtection($true,$false)
        foreach($rule in @($security.dacl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))){if($null -ne $rule){[void]$security.dacl.RemoveAccessRuleAll($rule)}}
        $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
        $security.dacl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,$inheritance,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
        Set-CodyCorrelationCanaryV4OuterStageAccessControlObject $security.item $security.dacl
        Assert-CodyCorrelationCanaryV4OuterStageCurrentUserOnlyDacl $Path $Directory
    } catch {
        if((Get-CodyCorrelationCanaryV4OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'
    }
}
function Assert-CodyCorrelationCanaryV4OuterStageRegularFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ErrorCode)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 0 -or $item.Length -gt $script:V4MaximumSourceBytes){Throw-CodyCorrelationCanaryV4OuterStageError $ErrorCode}
}
function Get-CodyCorrelationCanaryV4OuterStageSha256FromBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Get-CodyCorrelationCanaryV4OuterStageSha256FromFile {
    param([Parameter(Mandatory)][string]$Path)
    $bytes=$null
    try {
        Assert-CodyCorrelationCanaryV4OuterStageRegularFile $Path 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_HASH_REJECTED'
        $bytes=[IO.File]::ReadAllBytes($Path)
        return Get-CodyCorrelationCanaryV4OuterStageSha256FromBytes $bytes
    } finally {if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
}
function Get-CodyCorrelationCanaryV4OuterStageLayout {
    param([Parameter(Mandatory)][string]$PinnedLauncherSha256)
    $local=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath (Get-CodyCorrelationCanaryV4OuterStageLocalAppDataRoot)
    $namespace=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath (Join-Path $local $script:V4NamespaceDirectoryName)
    $service=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath (Join-Path $namespace $script:V4ServiceDirectoryName)
    $launcher=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath (Join-Path $service $script:V4LauncherDirectoryName)
    $stage=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath (Join-Path $launcher $PinnedLauncherSha256)
    $stageFile=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath (Join-Path $stage $script:V4LauncherFileName)
    $proof=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath (Join-Path $stage $script:V4ProofFileName)
    Assert-CodyCorrelationCanaryV4OuterStageNoReparseAncestors $local
    if(-not(Test-CodyCorrelationCanaryV4OuterStagePathWithin $namespace $local) -or -not(Test-CodyCorrelationCanaryV4OuterStagePathWithin $service $namespace) -or -not(Test-CodyCorrelationCanaryV4OuterStagePathWithin $launcher $service) -or -not(Test-CodyCorrelationCanaryV4OuterStagePathWithin $stage $launcher) -or -not(Test-CodyCorrelationCanaryV4OuterStagePathWithin $stageFile $stage) -or -not(Test-CodyCorrelationCanaryV4OuterStagePathWithin $proof $stage)){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
    return [pscustomobject]@{namespace_root=$namespace;service_root=$service;launcher_root=$launcher;stage_root=$stage;stage_file=$stageFile;proof_file=$proof}
}
function Assert-CodyCorrelationCanaryV4OuterStageMissing {
    param([Parameter(Mandatory)][string]$Path)
    if(Test-Path -LiteralPath $Path){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_EXISTING_STAGE_REJECTED'}
}
function Ensure-CodyCorrelationCanaryV4OuterStageProtectedDirectory {
    param([Parameter(Mandatory)][string]$Path)
    Assert-CodyCorrelationCanaryV4OuterStageNoReparseAncestors $Path
    [IO.Directory]::CreateDirectory($Path) | Out-Null
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
    Set-CodyCorrelationCanaryV4OuterStageCurrentUserOnlyDacl $Path $true
    Assert-CodyCorrelationCanaryV4OuterStageNoReparseAncestors $Path
}
function Invoke-CodyCorrelationCanaryV4OuterStageReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$PinnedLauncherSha256)
    if($args.Count -ne 0 -or $PinnedLauncherSha256 -notmatch '^[a-fA-F0-9]{64}$'){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'}
    $sourceBytes=$null;$proofBytes=$null
    try {
        $pinned=$PinnedLauncherSha256.ToLowerInvariant()
        $source=Get-CodyCorrelationCanaryV4OuterStageNormalizedPath $SourcePath
        if(-not (Split-Path -Path $source -Leaf).Equals($script:V4LauncherFileName,[StringComparison]::Ordinal)){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_SOURCE_PATH_REJECTED'}
        Assert-CodyCorrelationCanaryV4OuterStageNoReparseAncestors $source
        Assert-CodyCorrelationCanaryV4OuterStageRegularFile $source 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_SOURCE_PATH_REJECTED'
        $sourceBytes=[IO.File]::ReadAllBytes($source)
        if((Get-CodyCorrelationCanaryV4OuterStageSha256FromBytes $sourceBytes) -cne $pinned){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_SOURCE_HASH_REJECTED'}
        $layout=Get-CodyCorrelationCanaryV4OuterStageLayout $pinned
        # A fresh v4 lane must not require an operator to prepare mutable
        # directories.  Create only the two isolated roots when absent; an
        # already-present root is never repaired and must already satisfy the
        # strict current-user DACL/readback checks.
        foreach($path in @($layout.namespace_root,$layout.service_root)){
            if(Test-Path -LiteralPath $path){
                Assert-CodyCorrelationCanaryV4OuterStageNoReparseAncestors $path
                Assert-CodyCorrelationCanaryV4OuterStageCurrentUserOnlyDacl $path $true
            } else {
                Ensure-CodyCorrelationCanaryV4OuterStageProtectedDirectory $path
            }
        }
        if(Test-Path -LiteralPath $layout.launcher_root){Assert-CodyCorrelationCanaryV4OuterStageNoReparseAncestors $layout.launcher_root;Assert-CodyCorrelationCanaryV4OuterStageCurrentUserOnlyDacl $layout.launcher_root $true}else{Ensure-CodyCorrelationCanaryV4OuterStageProtectedDirectory $layout.launcher_root}
        Assert-CodyCorrelationCanaryV4OuterStageMissing $layout.stage_root
        Ensure-CodyCorrelationCanaryV4OuterStageProtectedDirectory $layout.stage_root
        $stream=$null
        try {$stream=[IO.File]::Open($layout.stage_file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($sourceBytes,0,$sourceBytes.Length);$stream.Flush($true)}finally{if($null -ne $stream){$stream.Dispose()}}
        Assert-CodyCorrelationCanaryV4OuterStageNoReparseAncestors $layout.stage_file
        Assert-CodyCorrelationCanaryV4OuterStageRegularFile $layout.stage_file 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_STAGED_FILE_REJECTED'
        Set-CodyCorrelationCanaryV4OuterStageCurrentUserOnlyDacl $layout.stage_file $false
        if((Get-CodyCorrelationCanaryV4OuterStageSha256FromFile $layout.stage_file) -cne $pinned){Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_STAGED_HASH_REJECTED'}
        $proof=[ordered]@{schema_version=$script:V4ProofSchemaVersion;pinned_launcher_sha256=$pinned}
        $proofBytes=[Text.UTF8Encoding]::new($false).GetBytes(($proof | ConvertTo-Json -Compress))
        $stream=$null
        try {$stream=[IO.File]::Open($layout.proof_file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($proofBytes,0,$proofBytes.Length);$stream.Flush($true)}finally{if($null -ne $stream){$stream.Dispose()}}
        Assert-CodyCorrelationCanaryV4OuterStageNoReparseAncestors $layout.proof_file
        Assert-CodyCorrelationCanaryV4OuterStageRegularFile $layout.proof_file 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_STAGED_FILE_REJECTED'
        Set-CodyCorrelationCanaryV4OuterStageCurrentUserOnlyDacl $layout.proof_file $false
        return [ordered]@{ok=$true;operation='cody_correlation_canary_v4_stage';terminal_state='staged';sensitive_output_count=0}
    } catch {
        if((Get-CodyCorrelationCanaryV4OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV4OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'
    } finally {
        if($null -ne $sourceBytes){[Array]::Clear($sourceBytes,0,$sourceBytes.Length)}
        if($null -ne $proofBytes){[Array]::Clear($proofBytes,0,$proofBytes.Length)}
    }
}
