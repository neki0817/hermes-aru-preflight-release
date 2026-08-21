# Review-only outer staging reference. It must never be used as an operator
# command from this checkout. A separately reviewed, hash-pinned static host
# may use equivalent bytes only after it has established its own trust anchor.
# This reference stages verified launcher bytes; it never executes them, reads
# DPAPI, prompts for an approval reference, or contacts Discord.

if ($MyInvocation.InvocationName -ne '.') {
    [Console]::Out.WriteLine('{"ok":false,"error_code":"DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_REFERENCE_ONLY","sensitive_output_count":0}')
    exit 2
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:OuterStageSchemaVersion = 'hermes-agents-discord-cody-aru-cody-manual-canary-outer-stage-reference/v1'
$script:LauncherFileName = 'CodyManualCanaryLauncher.ps1'
$script:NamespaceDirectoryName = 'HermesAgents'
$script:ServiceDirectoryName = 'discord-cody-aru-direct-bridge'
$script:LauncherDirectoryName = 'manual-canary-launcher'
$script:MaximumSourceBytes = 256KB

function Throw-CodyManualCanaryOuterStageError {
    param([Parameter(Mandatory)][string]$Code)
    throw [System.InvalidOperationException]::new($Code)
}

function Get-CodyManualCanaryOuterStageErrorCode {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match '^DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_[A-Z_]+$') {
        return $message
    }
    return 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_OPERATION_REJECTED'
}

function Get-CodyManualCanaryOuterStageLocalAppDataRoot {
    $value = [System.Environment]::GetFolderPath(
        [System.Environment+SpecialFolder]::LocalApplicationData
    )
    if ([string]::IsNullOrWhiteSpace($value)) {
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
    }
    return $value
}

function Get-CodyManualCanaryOuterStageNormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        if ($fullPath -notmatch '^[A-Za-z]:\\' -or $fullPath.StartsWith('\\')) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
        }
        $volumeRoot = [System.IO.Path]::GetPathRoot($fullPath)
        if ([string]::IsNullOrWhiteSpace($volumeRoot)) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
        }
        if ($fullPath.Length -gt $volumeRoot.Length) {
            $fullPath = $fullPath.TrimEnd([char[]]@(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ))
        }
        return $fullPath
    } catch {
        if ((Get-CodyManualCanaryOuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_OPERATION_REJECTED') {
            throw
        }
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
    }
}

function Test-CodyManualCanaryOuterStagePathWithin {
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Root
    )
    $candidatePath = Get-CodyManualCanaryOuterStageNormalizedPath $Candidate
    $rootPath = Get-CodyManualCanaryOuterStageNormalizedPath $Root
    if ($candidatePath.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $candidatePath.StartsWith(
        "$rootPath$([System.IO.Path]::DirectorySeparatorChar)",
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Assert-CodyManualCanaryOuterStageFixedLocalPath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $normalized = Get-CodyManualCanaryOuterStageNormalizedPath $Path
        $drive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($normalized))
        if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
        }
    } catch {
        if ((Get-CodyManualCanaryOuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_OPERATION_REJECTED') {
            throw
        }
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
    }
}

function Assert-CodyManualCanaryOuterStageNoReparsePointAncestors {
    param([Parameter(Mandatory)][string]$Path)
    $probe = Get-CodyManualCanaryOuterStageNormalizedPath $Path
    try {
        while (-not (Test-Path -LiteralPath $probe)) {
            $parent = Split-Path -Path $probe -Parent
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($probe, [System.StringComparison]::OrdinalIgnoreCase)) {
                Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
            }
            $probe = $parent
        }
        while ($true) {
            $item = Get-Item -LiteralPath $probe -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
            }
            $parent = Split-Path -Path $probe -Parent
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($probe, [System.StringComparison]::OrdinalIgnoreCase)) {
                break
            }
            $probe = $parent
        }
    } catch {
        if ((Get-CodyManualCanaryOuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_OPERATION_REJECTED') {
            throw
        }
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
    }
}

function Get-CodyManualCanaryOuterStageCurrentUserSid {
    try {
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ([string]::IsNullOrWhiteSpace($sid)) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_DACL_REJECTED'
        }
        return $sid
    } catch {
        if ((Get-CodyManualCanaryOuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_OPERATION_REJECTED') {
            throw
        }
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_DACL_REJECTED'
    }
}

function Assert-CodyManualCanaryOuterStageCurrentUserOnlyDacl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][bool]$IsDirectory
    )
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $sid = [System.Security.Principal.SecurityIdentifier]::new((Get-CodyManualCanaryOuterStageCurrentUserSid))
        $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if (
            -not $owner.Equals($sid.Value, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not $acl.AreAccessRulesProtected
        ) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_DACL_REJECTED'
        }
        $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        $inheritance = if ($IsDirectory) {
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        } else {
            [System.Security.AccessControl.InheritanceFlags]::None
        }
        if (
            $rules.Count -ne 1 -or
            $rules[0].IsInherited -or
            -not $rules[0].IdentityReference.Value.Equals($sid.Value, [System.StringComparison]::OrdinalIgnoreCase) -or
            $rules[0].AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or
            $rules[0].FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl -or
            $rules[0].InheritanceFlags -ne $inheritance -or
            $rules[0].PropagationFlags -ne [System.Security.AccessControl.PropagationFlags]::None
        ) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_DACL_REJECTED'
        }
    } catch {
        if ((Get-CodyManualCanaryOuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_OPERATION_REJECTED') {
            throw
        }
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_DACL_REJECTED'
    }
}

function Set-CodyManualCanaryOuterStageCurrentUserOnlyDacl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][bool]$IsDirectory
    )
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $sid = [System.Security.Principal.SecurityIdentifier]::new((Get-CodyManualCanaryOuterStageCurrentUserSid))
        $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if (-not $owner.Equals($sid.Value, [System.StringComparison]::OrdinalIgnoreCase)) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_DACL_REJECTED'
        }
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) {
            [void]$acl.RemoveAccessRuleAll($rule)
        }
        $inheritance = if ($IsDirectory) {
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        } else {
            [System.Security.AccessControl.InheritanceFlags]::None
        }
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
            $sid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        ))
        Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
        Assert-CodyManualCanaryOuterStageCurrentUserOnlyDacl $Path $IsDirectory
    } catch {
        if ((Get-CodyManualCanaryOuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_OPERATION_REJECTED') {
            throw
        }
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_DACL_REJECTED'
    }
}

function Assert-CodyManualCanaryOuterStageRegularFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ErrorCode
    )
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (
            $item.PSIsContainer -or
            (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) -or
            $item.Length -le 0 -or
            $item.Length -gt $script:MaximumSourceBytes
        ) {
            Throw-CodyManualCanaryOuterStageError $ErrorCode
        }
    } catch {
        if ((Get-CodyManualCanaryOuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_OPERATION_REJECTED') {
            throw
        }
        Throw-CodyManualCanaryOuterStageError $ErrorCode
    }
}

function Get-CodyManualCanaryOuterStageSha256FromBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha256 = $null
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        return ([System.BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        if ($null -ne $sha256) {
            $sha256.Dispose()
        }
    }
}

function Get-CodyManualCanaryOuterStageSha256FromFile {
    param([Parameter(Mandatory)][string]$Path)
    $stream = $null
    $sha256 = $null
    try {
        Assert-CodyManualCanaryOuterStageRegularFile $Path 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_STAGED_FILE_REJECTED'
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    } catch {
        if ((Get-CodyManualCanaryOuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_OPERATION_REJECTED') {
            throw
        }
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_STAGED_HASH_REJECTED'
    } finally {
        if ($null -ne $sha256) {
            $sha256.Dispose()
        }
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Get-CodyManualCanaryOuterStageLayout {
    param([Parameter(Mandatory)][string]$PinnedLauncherSha256)
    $localAppDataRoot = Get-CodyManualCanaryOuterStageNormalizedPath (Get-CodyManualCanaryOuterStageLocalAppDataRoot)
    $namespaceRoot = Get-CodyManualCanaryOuterStageNormalizedPath (Join-Path $localAppDataRoot $script:NamespaceDirectoryName)
    $serviceRoot = Get-CodyManualCanaryOuterStageNormalizedPath (Join-Path $namespaceRoot $script:ServiceDirectoryName)
    $launcherRoot = Get-CodyManualCanaryOuterStageNormalizedPath (Join-Path $serviceRoot $script:LauncherDirectoryName)
    $stageRoot = Get-CodyManualCanaryOuterStageNormalizedPath (Join-Path $launcherRoot $PinnedLauncherSha256)
    $stageFile = Get-CodyManualCanaryOuterStageNormalizedPath (Join-Path $stageRoot $script:LauncherFileName)

    Assert-CodyManualCanaryOuterStageFixedLocalPath $localAppDataRoot
    Assert-CodyManualCanaryOuterStageNoReparsePointAncestors $localAppDataRoot
    if (
        -not (Test-CodyManualCanaryOuterStagePathWithin $namespaceRoot $localAppDataRoot) -or
        -not (Test-CodyManualCanaryOuterStagePathWithin $serviceRoot $namespaceRoot) -or
        -not (Test-CodyManualCanaryOuterStagePathWithin $launcherRoot $serviceRoot) -or
        -not (Test-CodyManualCanaryOuterStagePathWithin $stageRoot $launcherRoot) -or
        -not (Test-CodyManualCanaryOuterStagePathWithin $stageFile $stageRoot)
    ) {
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
    }
    return [pscustomobject]@{
        namespace_root = $namespaceRoot
        service_root = $serviceRoot
        launcher_root = $launcherRoot
        stage_root = $stageRoot
        stage_file = $stageFile
    }
}

function Assert-CodyManualCanaryOuterStageMissing {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_EXISTING_STAGE_REJECTED'
    }
}

function New-CodyManualCanaryOuterStageProtectedDirectory {
    param([Parameter(Mandatory)][string]$Path)
    try {
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
        }
        Set-CodyManualCanaryOuterStageCurrentUserOnlyDacl $Path $true
        Assert-CodyManualCanaryOuterStageNoReparsePointAncestors $Path
    } catch {
        if ((Get-CodyManualCanaryOuterStageErrorCode $_) -ne 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_OPERATION_REJECTED') {
            throw
        }
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_LOCAL_ROOT_REJECTED'
    }
}

function Invoke-CodyManualCanaryOuterStageReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$PinnedLauncherSha256
    )
    if ($args.Count -ne 0) {
        Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_ARGUMENT_REJECTED'
    }

    $sourceBytes = $null
    try {
        if ($PinnedLauncherSha256 -notmatch '^[a-fA-F0-9]{64}$') {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_SOURCE_HASH_REJECTED'
        }
        $pinnedHash = $PinnedLauncherSha256.ToLowerInvariant()
        $layout = Get-CodyManualCanaryOuterStageLayout $pinnedHash
        $normalizedSourcePath = Get-CodyManualCanaryOuterStageNormalizedPath $SourcePath
        if (-not (Split-Path -Path $normalizedSourcePath -Leaf).Equals($script:LauncherFileName, [System.StringComparison]::Ordinal)) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_SOURCE_PATH_REJECTED'
        }
        Assert-CodyManualCanaryOuterStageFixedLocalPath $normalizedSourcePath
        Assert-CodyManualCanaryOuterStageNoReparsePointAncestors $normalizedSourcePath
        Assert-CodyManualCanaryOuterStageRegularFile $normalizedSourcePath 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_SOURCE_PATH_REJECTED'

        # The source is read exactly once. Hashing and writing use the same
        # bytes; this reference never imports, parses, dot-sources, or executes
        # the launcher source.
        $sourceBytes = [System.IO.File]::ReadAllBytes($normalizedSourcePath)
        if ($sourceBytes.Length -le 0 -or $sourceBytes.Length -gt $script:MaximumSourceBytes) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_SOURCE_PATH_REJECTED'
        }
        if ((Get-CodyManualCanaryOuterStageSha256FromBytes $sourceBytes) -ne $pinnedHash) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_SOURCE_HASH_REJECTED'
        }

        foreach ($path in @($layout.namespace_root, $layout.service_root)) {
            Assert-CodyManualCanaryOuterStageNoReparsePointAncestors $path
            Assert-CodyManualCanaryOuterStageCurrentUserOnlyDacl $path $true
        }
        if (Test-Path -LiteralPath $layout.launcher_root) {
            Assert-CodyManualCanaryOuterStageNoReparsePointAncestors $layout.launcher_root
            Assert-CodyManualCanaryOuterStageCurrentUserOnlyDacl $layout.launcher_root $true
        } else {
            New-CodyManualCanaryOuterStageProtectedDirectory $layout.launcher_root
        }
        Assert-CodyManualCanaryOuterStageMissing $layout.stage_root
        New-CodyManualCanaryOuterStageProtectedDirectory $layout.stage_root

        $stream = $null
        try {
            $stream = [System.IO.File]::Open(
                $layout.stage_file,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None
            )
            $stream.Write($sourceBytes, 0, $sourceBytes.Length)
            $stream.Flush($true)
        } finally {
            if ($null -ne $stream) {
                $stream.Dispose()
            }
        }
        Assert-CodyManualCanaryOuterStageNoReparsePointAncestors $layout.stage_file
        Assert-CodyManualCanaryOuterStageRegularFile $layout.stage_file 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_STAGED_FILE_REJECTED'
        Set-CodyManualCanaryOuterStageCurrentUserOnlyDacl $layout.stage_file $false
        if ((Get-CodyManualCanaryOuterStageSha256FromFile $layout.stage_file) -ne $pinnedHash) {
            Throw-CodyManualCanaryOuterStageError 'DISCORD_CODY_ARU_WINDOWS_MANUAL_CANARY_STAGE_STAGED_HASH_REJECTED'
        }
        return [pscustomobject]@{
            ok = $true
            status = 'staged'
            sensitive_output_count = 0
        }
    } finally {
        if ($null -ne $sourceBytes) {
            [System.Array]::Clear($sourceBytes, 0, $sourceBytes.Length)
        }
    }
}
