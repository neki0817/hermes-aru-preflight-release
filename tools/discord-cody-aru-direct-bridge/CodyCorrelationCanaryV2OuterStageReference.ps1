# Hash-pinned source-only staging reference for Cody correlation-canary v2.
# It creates no runtime manifest, token, network request, or launcher process.
# The caller supplies independently pinned launcher bytes; this file verifies
# the bytes before copying them into a protected, isolated stage.

if ($MyInvocation.InvocationName -ne '.') {
    [Console]::Out.WriteLine('{"ok":false,"error_code":"DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REFERENCE_ONLY","sensitive_output_count":0}')
    exit 2
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:V2LauncherFileName = 'CodyCorrelationCanaryV2Launcher.ps1'
$script:V2NamespaceDirectoryName = 'HermesAgentsCodyAruCorrelationCanaryV2'
$script:V2ServiceDirectoryName = 'discord-cody-aru-correlation-canary-v2'
$script:V2LauncherDirectoryName = 'launcher'
$script:V2ProofFileName = 'CodyCorrelationCanaryV2StageProof.json'
$script:V2ProofSchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-cody-stage-proof/v1'
$script:V2MaximumSourceBytes = 256KB

function Throw-CodyCorrelationCanaryV2OuterStageError {
    param([Parameter(Mandatory)][string]$Code)
    throw [System.InvalidOperationException]::new($Code)
}
function Get-CodyCorrelationCanaryV2OuterStageErrorCode {
    param([AllowNull()][object]$ErrorRecord)
    if($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception -and [string]$ErrorRecord.Exception.Message -match '^DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_[A-Z_]+$'){
        return [string]$ErrorRecord.Exception.Message
    }
    return 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'
}
function Get-CodyCorrelationCanaryV2OuterStageLocalAppDataRoot {
    $value=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if([string]::IsNullOrWhiteSpace($value)){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
    return $value
}
function Get-CodyCorrelationCanaryV2OuterStageNormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $full=[IO.Path]::GetFullPath($Path)
        if($full -notmatch '^[A-Za-z]:\\' -or $full.StartsWith('\\')){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
        $volume=[IO.Path]::GetPathRoot($full)
        if([string]::IsNullOrWhiteSpace($volume) -or [IO.DriveInfo]::new($volume).DriveType -ne [IO.DriveType]::Fixed){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
        if($full.Length -gt $volume.Length){$full=$full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))}
        return $full
    } catch {
        if((Get-CodyCorrelationCanaryV2OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'
    }
}
function Test-CodyCorrelationCanaryV2OuterStagePathWithin {
    param([Parameter(Mandatory)][string]$Candidate,[Parameter(Mandatory)][string]$Root)
    $candidatePath=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath $Candidate
    $rootPath=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath $Root
    return $candidatePath.Equals($rootPath,[StringComparison]::OrdinalIgnoreCase) -or $candidatePath.StartsWith("$rootPath$([IO.Path]::DirectorySeparatorChar)",[StringComparison]::OrdinalIgnoreCase)
}
function Assert-CodyCorrelationCanaryV2OuterStageNoReparseAncestors {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $probe=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath $Path
        while(-not (Test-Path -LiteralPath $probe)){
            $parent=Split-Path -Path $probe -Parent
            if([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($probe,[StringComparison]::OrdinalIgnoreCase)){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
            $probe=$parent
        }
        while($true){
            $item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
            $parent=Split-Path -Path $probe -Parent
            if([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($probe,[StringComparison]::OrdinalIgnoreCase)){break}
            $probe=$parent
        }
    } catch {
        if((Get-CodyCorrelationCanaryV2OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'
    }
}
function Get-CodyCorrelationCanaryV2OuterStageCurrentUserSid {
    $sidValue=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if([string]::IsNullOrWhiteSpace($sidValue)){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
    return [Security.Principal.SecurityIdentifier]::new($sidValue)
}
function Get-CodyCorrelationCanaryV2OuterStageAccessControlObject {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][Security.AccessControl.AccessControlSections]$Sections)
    $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if($null -ne $extensions){
        if($Item -is [IO.DirectoryInfo]){return $extensions::GetAccessControl([IO.DirectoryInfo]$Item,$Sections)}
        if($Item -is [IO.FileInfo]){return $extensions::GetAccessControl([IO.FileInfo]$Item,$Sections)}
    }
    return $Item.GetAccessControl($Sections)
}
function Set-CodyCorrelationCanaryV2OuterStageAccessControlObject {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][Security.AccessControl.FileSystemSecurity]$Security)
    $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if($null -ne $extensions){
        if($Item -is [IO.DirectoryInfo]){[void]$extensions::SetAccessControl([IO.DirectoryInfo]$Item,[Security.AccessControl.DirectorySecurity]$Security);return}
        if($Item -is [IO.FileInfo]){[void]$extensions::SetAccessControl([IO.FileInfo]$Item,[Security.AccessControl.FileSecurity]$Security);return}
    }
    $Item.SetAccessControl($Security)
}
function Get-CodyCorrelationCanaryV2OuterStageAccessControl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if([bool]$item.PSIsContainer -ne $Directory -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
    return [pscustomobject]@{
        item=$item
        owner=(Get-CodyCorrelationCanaryV2OuterStageAccessControlObject $item ([Security.AccessControl.AccessControlSections]::Owner)).GetOwner([Security.Principal.SecurityIdentifier])
        dacl=Get-CodyCorrelationCanaryV2OuterStageAccessControlObject $item ([Security.AccessControl.AccessControlSections]::Access)
    }
}
function Assert-CodyCorrelationCanaryV2OuterStageCurrentUserOnlyDacl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    try {
        $sid=Get-CodyCorrelationCanaryV2OuterStageCurrentUserSid
        $security=Get-CodyCorrelationCanaryV2OuterStageAccessControl $Path $Directory
        $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
        $rules=@($security.dacl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
        if(-not $security.owner.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase) -or -not $security.dacl.AreAccessRulesProtected -or $rules.Count -ne 1 -or $rules[0].IsInherited -or -not $rules[0].IdentityReference.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase) -or $rules[0].AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or $rules[0].FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or $rules[0].InheritanceFlags -ne $inheritance -or $rules[0].PropagationFlags -ne [Security.AccessControl.PropagationFlags]::None){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
    } catch {
        if((Get-CodyCorrelationCanaryV2OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'
    }
}
function Set-CodyCorrelationCanaryV2OuterStageCurrentUserOnlyDacl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    try {
        $sid=Get-CodyCorrelationCanaryV2OuterStageCurrentUserSid
        $security=Get-CodyCorrelationCanaryV2OuterStageAccessControl $Path $Directory
        if(-not $security.owner.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase)){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
        $security.dacl.SetAccessRuleProtection($true,$false)
        foreach($rule in @($security.dacl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))){if($null -ne $rule){[void]$security.dacl.RemoveAccessRuleAll($rule)}}
        $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
        $security.dacl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,$inheritance,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
        Set-CodyCorrelationCanaryV2OuterStageAccessControlObject $security.item $security.dacl
        Assert-CodyCorrelationCanaryV2OuterStageCurrentUserOnlyDacl $Path $Directory
    } catch {
        if((Get-CodyCorrelationCanaryV2OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'
    }
}
function Assert-CodyCorrelationCanaryV2OuterStageRegularFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ErrorCode)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 0 -or $item.Length -gt $script:V2MaximumSourceBytes){Throw-CodyCorrelationCanaryV2OuterStageError $ErrorCode}
}
function Get-CodyCorrelationCanaryV2OuterStageSha256FromBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Get-CodyCorrelationCanaryV2OuterStageSha256FromFile {
    param([Parameter(Mandatory)][string]$Path)
    $bytes=$null
    try {
        Assert-CodyCorrelationCanaryV2OuterStageRegularFile $Path 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_HASH_REJECTED'
        $bytes=[IO.File]::ReadAllBytes($Path)
        return Get-CodyCorrelationCanaryV2OuterStageSha256FromBytes $bytes
    } finally {if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
}
function Get-CodyCorrelationCanaryV2OuterStageLayout {
    param([Parameter(Mandatory)][string]$PinnedLauncherSha256)
    $local=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath (Get-CodyCorrelationCanaryV2OuterStageLocalAppDataRoot)
    $namespace=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath (Join-Path $local $script:V2NamespaceDirectoryName)
    $service=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath (Join-Path $namespace $script:V2ServiceDirectoryName)
    $launcher=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath (Join-Path $service $script:V2LauncherDirectoryName)
    $stage=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath (Join-Path $launcher $PinnedLauncherSha256)
    $stageFile=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath (Join-Path $stage $script:V2LauncherFileName)
    $proof=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath (Join-Path $stage $script:V2ProofFileName)
    Assert-CodyCorrelationCanaryV2OuterStageNoReparseAncestors $local
    if(-not(Test-CodyCorrelationCanaryV2OuterStagePathWithin $namespace $local) -or -not(Test-CodyCorrelationCanaryV2OuterStagePathWithin $service $namespace) -or -not(Test-CodyCorrelationCanaryV2OuterStagePathWithin $launcher $service) -or -not(Test-CodyCorrelationCanaryV2OuterStagePathWithin $stage $launcher) -or -not(Test-CodyCorrelationCanaryV2OuterStagePathWithin $stageFile $stage) -or -not(Test-CodyCorrelationCanaryV2OuterStagePathWithin $proof $stage)){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
    return [pscustomobject]@{namespace_root=$namespace;service_root=$service;launcher_root=$launcher;stage_root=$stage;stage_file=$stageFile;proof_file=$proof}
}
function Assert-CodyCorrelationCanaryV2OuterStageMissing {
    param([Parameter(Mandatory)][string]$Path)
    if(Test-Path -LiteralPath $Path){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_EXISTING_STAGE_REJECTED'}
}
function Ensure-CodyCorrelationCanaryV2OuterStageProtectedDirectory {
    param([Parameter(Mandatory)][string]$Path)
    Assert-CodyCorrelationCanaryV2OuterStageNoReparseAncestors $Path
    [IO.Directory]::CreateDirectory($Path) | Out-Null
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
    Set-CodyCorrelationCanaryV2OuterStageCurrentUserOnlyDacl $Path $true
    Assert-CodyCorrelationCanaryV2OuterStageNoReparseAncestors $Path
}
function Invoke-CodyCorrelationCanaryV2OuterStageReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$PinnedLauncherSha256)
    if($args.Count -ne 0 -or $PinnedLauncherSha256 -notmatch '^[a-fA-F0-9]{64}$'){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'}
    $sourceBytes=$null;$proofBytes=$null
    try {
        $pinned=$PinnedLauncherSha256.ToLowerInvariant()
        $source=Get-CodyCorrelationCanaryV2OuterStageNormalizedPath $SourcePath
        if(-not (Split-Path -Path $source -Leaf).Equals($script:V2LauncherFileName,[StringComparison]::Ordinal)){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_SOURCE_PATH_REJECTED'}
        Assert-CodyCorrelationCanaryV2OuterStageNoReparseAncestors $source
        Assert-CodyCorrelationCanaryV2OuterStageRegularFile $source 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_SOURCE_PATH_REJECTED'
        $sourceBytes=[IO.File]::ReadAllBytes($source)
        if((Get-CodyCorrelationCanaryV2OuterStageSha256FromBytes $sourceBytes) -cne $pinned){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_SOURCE_HASH_REJECTED'}
        $layout=Get-CodyCorrelationCanaryV2OuterStageLayout $pinned
        # A fresh v2 lane must not require an operator to prepare mutable
        # directories.  Create only the two isolated roots when absent; an
        # already-present root is never repaired and must already satisfy the
        # strict current-user DACL/readback checks.
        foreach($path in @($layout.namespace_root,$layout.service_root)){
            if(Test-Path -LiteralPath $path){
                Assert-CodyCorrelationCanaryV2OuterStageNoReparseAncestors $path
                Assert-CodyCorrelationCanaryV2OuterStageCurrentUserOnlyDacl $path $true
            } else {
                Ensure-CodyCorrelationCanaryV2OuterStageProtectedDirectory $path
            }
        }
        if(Test-Path -LiteralPath $layout.launcher_root){Assert-CodyCorrelationCanaryV2OuterStageNoReparseAncestors $layout.launcher_root;Assert-CodyCorrelationCanaryV2OuterStageCurrentUserOnlyDacl $layout.launcher_root $true}else{Ensure-CodyCorrelationCanaryV2OuterStageProtectedDirectory $layout.launcher_root}
        Assert-CodyCorrelationCanaryV2OuterStageMissing $layout.stage_root
        Ensure-CodyCorrelationCanaryV2OuterStageProtectedDirectory $layout.stage_root
        $stream=$null
        try {$stream=[IO.File]::Open($layout.stage_file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($sourceBytes,0,$sourceBytes.Length);$stream.Flush($true)}finally{if($null -ne $stream){$stream.Dispose()}}
        Assert-CodyCorrelationCanaryV2OuterStageNoReparseAncestors $layout.stage_file
        Assert-CodyCorrelationCanaryV2OuterStageRegularFile $layout.stage_file 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_STAGED_FILE_REJECTED'
        Set-CodyCorrelationCanaryV2OuterStageCurrentUserOnlyDacl $layout.stage_file $false
        if((Get-CodyCorrelationCanaryV2OuterStageSha256FromFile $layout.stage_file) -cne $pinned){Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_STAGED_HASH_REJECTED'}
        $proof=[ordered]@{schema_version=$script:V2ProofSchemaVersion;pinned_launcher_sha256=$pinned}
        $proofBytes=[Text.UTF8Encoding]::new($false).GetBytes(($proof | ConvertTo-Json -Compress))
        $stream=$null
        try {$stream=[IO.File]::Open($layout.proof_file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($proofBytes,0,$proofBytes.Length);$stream.Flush($true)}finally{if($null -ne $stream){$stream.Dispose()}}
        Assert-CodyCorrelationCanaryV2OuterStageNoReparseAncestors $layout.proof_file
        Assert-CodyCorrelationCanaryV2OuterStageRegularFile $layout.proof_file 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_STAGED_FILE_REJECTED'
        Set-CodyCorrelationCanaryV2OuterStageCurrentUserOnlyDacl $layout.proof_file $false
        return [ordered]@{ok=$true;operation='cody_correlation_canary_v2_stage';terminal_state='staged';sensitive_output_count=0}
    } catch {
        if((Get-CodyCorrelationCanaryV2OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV2OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'
    } finally {
        if($null -ne $sourceBytes){[Array]::Clear($sourceBytes,0,$sourceBytes.Length)}
        if($null -ne $proofBytes){[Array]::Clear($proofBytes,0,$proofBytes.Length)}
    }
}
