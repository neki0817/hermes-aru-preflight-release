# Hash-pinned source-only staging reference for Cody correlation-canary v5.
# It creates no runtime manifest, token, network request, or launcher process.
# The caller supplies independently pinned launcher bytes; this file verifies
# the bytes before copying them into a protected, isolated stage.

if ($MyInvocation.InvocationName -ne '.') {
    [Console]::Out.WriteLine('{"ok":false,"error_code":"DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REFERENCE_ONLY","sensitive_output_count":0}')
    exit 2
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:V5LauncherFileName = 'CodyCorrelationCanaryV5Launcher.ps1'
$script:V5NamespaceDirectoryName = 'HermesAgentsCodyAruCorrelationCanaryV5'
$script:V5ServiceDirectoryName = 'discord-cody-aru-correlation-canary-v5'
$script:V5LauncherDirectoryName = 'launcher'
$script:V5ProofFileName = 'CodyCorrelationCanaryV5StageProof.json'
$script:V5ProofSchemaVersion = 'hermes-agents-discord-cody-aru-correlation-canary-v5-cody-stage-proof/v1'
$script:V5MaximumSourceBytes = 256KB

function Throw-CodyCorrelationCanaryV5OuterStageError {
    param([Parameter(Mandatory)][string]$Code)
    throw [System.InvalidOperationException]::new($Code)
}
function Get-CodyCorrelationCanaryV5OuterStageErrorCode {
    param([AllowNull()][object]$ErrorRecord)
    if($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception -and [string]$ErrorRecord.Exception.Message -match '^DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_[A-Z_]+$'){
        return [string]$ErrorRecord.Exception.Message
    }
    return 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'
}
function Get-CodyCorrelationCanaryV5OuterStageLocalAppDataRoot {
    $value=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if([string]::IsNullOrWhiteSpace($value)){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
    return $value
}
function Get-CodyCorrelationCanaryV5OuterStageNormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $full=[IO.Path]::GetFullPath($Path)
        if($full -notmatch '^[A-Za-z]:\\' -or $full.StartsWith('\\')){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
        $volume=[IO.Path]::GetPathRoot($full)
        if([string]::IsNullOrWhiteSpace($volume) -or [IO.DriveInfo]::new($volume).DriveType -ne [IO.DriveType]::Fixed){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
        if($full.Length -gt $volume.Length){$full=$full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))}
        return $full
    } catch {
        if((Get-CodyCorrelationCanaryV5OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'
    }
}
function Test-CodyCorrelationCanaryV5OuterStagePathWithin {
    param([Parameter(Mandatory)][string]$Candidate,[Parameter(Mandatory)][string]$Root)
    $candidatePath=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath $Candidate
    $rootPath=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath $Root
    return $candidatePath.Equals($rootPath,[StringComparison]::OrdinalIgnoreCase) -or $candidatePath.StartsWith("$rootPath$([IO.Path]::DirectorySeparatorChar)",[StringComparison]::OrdinalIgnoreCase)
}
function Assert-CodyCorrelationCanaryV5OuterStageNoReparseAncestors {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $probe=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath $Path
        while(-not (Test-Path -LiteralPath $probe)){
            $parent=Split-Path -Path $probe -Parent
            if([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($probe,[StringComparison]::OrdinalIgnoreCase)){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
            $probe=$parent
        }
        while($true){
            $item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
            $parent=Split-Path -Path $probe -Parent
            if([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($probe,[StringComparison]::OrdinalIgnoreCase)){break}
            $probe=$parent
        }
    } catch {
        if((Get-CodyCorrelationCanaryV5OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'
    }
}
function Get-CodyCorrelationCanaryV5OuterStageCurrentUserSid {
    $sidValue=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if([string]::IsNullOrWhiteSpace($sidValue)){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
    return [Security.Principal.SecurityIdentifier]::new($sidValue)
}
function Get-CodyCorrelationCanaryV5OuterStageAccessControlObject {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][Security.AccessControl.AccessControlSections]$Sections)
    $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if($null -ne $extensions){
        if($Item -is [IO.DirectoryInfo]){return $extensions::GetAccessControl([IO.DirectoryInfo]$Item,$Sections)}
        if($Item -is [IO.FileInfo]){return $extensions::GetAccessControl([IO.FileInfo]$Item,$Sections)}
    }
    return $Item.GetAccessControl($Sections)
}
function Set-CodyCorrelationCanaryV5OuterStageAccessControlObject {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][Security.AccessControl.FileSystemSecurity]$Security)
    $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if($null -ne $extensions){
        if($Item -is [IO.DirectoryInfo]){[void]$extensions::SetAccessControl([IO.DirectoryInfo]$Item,[Security.AccessControl.DirectorySecurity]$Security);return}
        if($Item -is [IO.FileInfo]){[void]$extensions::SetAccessControl([IO.FileInfo]$Item,[Security.AccessControl.FileSecurity]$Security);return}
    }
    $Item.SetAccessControl($Security)
}
function Get-CodyCorrelationCanaryV5OuterStageAccessControl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if([bool]$item.PSIsContainer -ne $Directory -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
    return [pscustomobject]@{
        item=$item
        owner=(Get-CodyCorrelationCanaryV5OuterStageAccessControlObject $item ([Security.AccessControl.AccessControlSections]::Owner)).GetOwner([Security.Principal.SecurityIdentifier])
        dacl=Get-CodyCorrelationCanaryV5OuterStageAccessControlObject $item ([Security.AccessControl.AccessControlSections]::Access)
    }
}
function Assert-CodyCorrelationCanaryV5OuterStageCurrentUserOnlyDacl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    try {
        $sid=Get-CodyCorrelationCanaryV5OuterStageCurrentUserSid
        $security=Get-CodyCorrelationCanaryV5OuterStageAccessControl $Path $Directory
        $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
        $rules=@($security.dacl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
        if(-not $security.owner.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase) -or -not $security.dacl.AreAccessRulesProtected -or $rules.Count -ne 1 -or $rules[0].IsInherited -or -not $rules[0].IdentityReference.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase) -or $rules[0].AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or $rules[0].FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or $rules[0].InheritanceFlags -ne $inheritance -or $rules[0].PropagationFlags -ne [Security.AccessControl.PropagationFlags]::None){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
    } catch {
        if((Get-CodyCorrelationCanaryV5OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'
    }
}
function Set-CodyCorrelationCanaryV5OuterStageCurrentUserOnlyDacl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Directory)
    try {
        $sid=Get-CodyCorrelationCanaryV5OuterStageCurrentUserSid
        $security=Get-CodyCorrelationCanaryV5OuterStageAccessControl $Path $Directory
        if(-not $security.owner.Value.Equals($sid.Value,[StringComparison]::OrdinalIgnoreCase)){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'}
        $security.dacl.SetAccessRuleProtection($true,$false)
        foreach($rule in @($security.dacl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))){if($null -ne $rule){[void]$security.dacl.RemoveAccessRuleAll($rule)}}
        $inheritance=if($Directory){[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}else{[Security.AccessControl.InheritanceFlags]::None}
        $security.dacl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,$inheritance,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
        Set-CodyCorrelationCanaryV5OuterStageAccessControlObject $security.item $security.dacl
        Assert-CodyCorrelationCanaryV5OuterStageCurrentUserOnlyDacl $Path $Directory
    } catch {
        if((Get-CodyCorrelationCanaryV5OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_DACL_REJECTED'
    }
}
function Assert-CodyCorrelationCanaryV5OuterStageRegularFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ErrorCode)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 0 -or $item.Length -gt $script:V5MaximumSourceBytes){Throw-CodyCorrelationCanaryV5OuterStageError $ErrorCode}
}
function Get-CodyCorrelationCanaryV5OuterStageSha256FromBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Get-CodyCorrelationCanaryV5OuterStageSha256FromFile {
    param([Parameter(Mandatory)][string]$Path)
    $bytes=$null
    try {
        Assert-CodyCorrelationCanaryV5OuterStageRegularFile $Path 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_HASH_REJECTED'
        $bytes=[IO.File]::ReadAllBytes($Path)
        return Get-CodyCorrelationCanaryV5OuterStageSha256FromBytes $bytes
    } finally {if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
}
function Get-CodyCorrelationCanaryV5OuterStageLayout {
    param([Parameter(Mandatory)][string]$PinnedLauncherSha256)
    $local=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath (Get-CodyCorrelationCanaryV5OuterStageLocalAppDataRoot)
    $namespace=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath (Join-Path $local $script:V5NamespaceDirectoryName)
    $service=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath (Join-Path $namespace $script:V5ServiceDirectoryName)
    $launcher=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath (Join-Path $service $script:V5LauncherDirectoryName)
    $stage=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath (Join-Path $launcher $PinnedLauncherSha256)
    $stageFile=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath (Join-Path $stage $script:V5LauncherFileName)
    $proof=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath (Join-Path $stage $script:V5ProofFileName)
    Assert-CodyCorrelationCanaryV5OuterStageNoReparseAncestors $local
    if(-not(Test-CodyCorrelationCanaryV5OuterStagePathWithin $namespace $local) -or -not(Test-CodyCorrelationCanaryV5OuterStagePathWithin $service $namespace) -or -not(Test-CodyCorrelationCanaryV5OuterStagePathWithin $launcher $service) -or -not(Test-CodyCorrelationCanaryV5OuterStagePathWithin $stage $launcher) -or -not(Test-CodyCorrelationCanaryV5OuterStagePathWithin $stageFile $stage) -or -not(Test-CodyCorrelationCanaryV5OuterStagePathWithin $proof $stage)){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
    return [pscustomobject]@{namespace_root=$namespace;service_root=$service;launcher_root=$launcher;stage_root=$stage;stage_file=$stageFile;proof_file=$proof}
}
function Assert-CodyCorrelationCanaryV5OuterStageMissing {
    param([Parameter(Mandatory)][string]$Path)
    if(Test-Path -LiteralPath $Path){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_EXISTING_STAGE_REJECTED'}
}
function Ensure-CodyCorrelationCanaryV5OuterStageProtectedDirectory {
    param([Parameter(Mandatory)][string]$Path)
    Assert-CodyCorrelationCanaryV5OuterStageNoReparseAncestors $Path
    [IO.Directory]::CreateDirectory($Path) | Out-Null
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_LOCAL_ROOT_REJECTED'}
    Set-CodyCorrelationCanaryV5OuterStageCurrentUserOnlyDacl $Path $true
    Assert-CodyCorrelationCanaryV5OuterStageNoReparseAncestors $Path
}
function Invoke-CodyCorrelationCanaryV5OuterStageReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$PinnedLauncherSha256)
    if($args.Count -ne 0 -or $PinnedLauncherSha256 -notmatch '^[a-fA-F0-9]{64}$'){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'}
    $sourceBytes=$null;$proofBytes=$null
    try {
        $pinned=$PinnedLauncherSha256.ToLowerInvariant()
        $source=Get-CodyCorrelationCanaryV5OuterStageNormalizedPath $SourcePath
        if(-not (Split-Path -Path $source -Leaf).Equals($script:V5LauncherFileName,[StringComparison]::Ordinal)){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_SOURCE_PATH_REJECTED'}
        Assert-CodyCorrelationCanaryV5OuterStageNoReparseAncestors $source
        Assert-CodyCorrelationCanaryV5OuterStageRegularFile $source 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_SOURCE_PATH_REJECTED'
        $sourceBytes=[IO.File]::ReadAllBytes($source)
        if((Get-CodyCorrelationCanaryV5OuterStageSha256FromBytes $sourceBytes) -cne $pinned){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_SOURCE_HASH_REJECTED'}
        $layout=Get-CodyCorrelationCanaryV5OuterStageLayout $pinned
        # A fresh v5 lane must not require an operator to prepare mutable
        # directories.  Create only the two isolated roots when absent; an
        # already-present root is never repaired and must already satisfy the
        # strict current-user DACL/readback checks.
        foreach($path in @($layout.namespace_root,$layout.service_root)){
            if(Test-Path -LiteralPath $path){
                Assert-CodyCorrelationCanaryV5OuterStageNoReparseAncestors $path
                Assert-CodyCorrelationCanaryV5OuterStageCurrentUserOnlyDacl $path $true
            } else {
                Ensure-CodyCorrelationCanaryV5OuterStageProtectedDirectory $path
            }
        }
        if(Test-Path -LiteralPath $layout.launcher_root){Assert-CodyCorrelationCanaryV5OuterStageNoReparseAncestors $layout.launcher_root;Assert-CodyCorrelationCanaryV5OuterStageCurrentUserOnlyDacl $layout.launcher_root $true}else{Ensure-CodyCorrelationCanaryV5OuterStageProtectedDirectory $layout.launcher_root}
        Assert-CodyCorrelationCanaryV5OuterStageMissing $layout.stage_root
        Ensure-CodyCorrelationCanaryV5OuterStageProtectedDirectory $layout.stage_root
        $stream=$null
        try {$stream=[IO.File]::Open($layout.stage_file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($sourceBytes,0,$sourceBytes.Length);$stream.Flush($true)}finally{if($null -ne $stream){$stream.Dispose()}}
        Assert-CodyCorrelationCanaryV5OuterStageNoReparseAncestors $layout.stage_file
        Assert-CodyCorrelationCanaryV5OuterStageRegularFile $layout.stage_file 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_STAGED_FILE_REJECTED'
        Set-CodyCorrelationCanaryV5OuterStageCurrentUserOnlyDacl $layout.stage_file $false
        if((Get-CodyCorrelationCanaryV5OuterStageSha256FromFile $layout.stage_file) -cne $pinned){Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_STAGED_HASH_REJECTED'}
        $proof=[ordered]@{schema_version=$script:V5ProofSchemaVersion;pinned_launcher_sha256=$pinned}
        $proofBytes=[Text.UTF8Encoding]::new($false).GetBytes(($proof | ConvertTo-Json -Compress))
        $stream=$null
        try {$stream=[IO.File]::Open($layout.proof_file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($proofBytes,0,$proofBytes.Length);$stream.Flush($true)}finally{if($null -ne $stream){$stream.Dispose()}}
        Assert-CodyCorrelationCanaryV5OuterStageNoReparseAncestors $layout.proof_file
        Assert-CodyCorrelationCanaryV5OuterStageRegularFile $layout.proof_file 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_STAGED_FILE_REJECTED'
        Set-CodyCorrelationCanaryV5OuterStageCurrentUserOnlyDacl $layout.proof_file $false
        return [ordered]@{ok=$true;operation='cody_correlation_canary_v5_stage';terminal_state='staged';sensitive_output_count=0}
    } catch {
        if((Get-CodyCorrelationCanaryV5OuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'){throw}
        Throw-CodyCorrelationCanaryV5OuterStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_STAGE_REJECTED'
    } finally {
        if($null -ne $sourceBytes){[Array]::Clear($sourceBytes,0,$sourceBytes.Length)}
        if($null -ne $proofBytes){[Array]::Clear($proofBytes,0,$proofBytes.Length)}
    }
}
