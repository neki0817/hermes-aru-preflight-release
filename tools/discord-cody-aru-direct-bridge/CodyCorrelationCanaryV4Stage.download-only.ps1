# Hash-pinned download-only source stage for Cody correlation-canary v4.
# It downloads only the already-pinned outer stage reference and launcher,
# verifies their bytes, and invokes the outer stage.  It never reads a token,
# creates a canary manifest, sends to Discord, or starts the launcher.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StageGuardName = 'HERMES_CODY_CORRELATION_CANARY_V4_STAGE'
$script:ReleaseCommit = '39f42db5394d357f9958f403b0bf78b410f68c28'
$script:OuterFileName = 'CodyCorrelationCanaryV4OuterStageReference.ps1'
$script:LauncherFileName = 'CodyCorrelationCanaryV4Launcher.ps1'
$script:ExpectedOuterSha256 = '6183bfa7c0f1ff8360f63ab0bf94abe02820ce2bcb9dc84973c540840c7d7702'
$script:ExpectedLauncherSha256 = '77c92e349568bfeb303d4a7df9e4811d1888fc9f7c64389835245a61d2b8c8f1'
$script:MaximumSourceBytes = 256KB

function Throw-CodyCorrelationCanaryV4DownloadStageError {
    param([Parameter(Mandatory)][string]$Code)
    throw [System.InvalidOperationException]::new($Code)
}

function Get-CodyCorrelationCanaryV4DownloadStageErrorCode {
    param([AllowNull()][object]$ErrorRecord)
    if ($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception -and [string]$ErrorRecord.Exception.Message -match '^DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_[A-Z_]+$') {
        return [string]$ErrorRecord.Exception.Message
    }
    return 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_REJECTED'
}

function Write-CodyCorrelationCanaryV4DownloadStageResult {
    param(
        [Parameter(Mandatory)][bool]$Ok,
        [Parameter(Mandatory)][string]$TerminalState,
        [Parameter(Mandatory)][string]$TerminalReason,
        [Parameter(Mandatory)][int]$NetworkRequestCount
    )
    $result = [ordered]@{
        schema_version = 'hermes-agents-discord-cody-aru-correlation-canary-v4-cody-download-stage/v1'
        ok = $Ok
        operation = 'cody_correlation_canary_v4_download_stage'
        terminal_state = $TerminalState
        terminal_reason = $TerminalReason
        network_request_count = $NetworkRequestCount
        message_send_attempt_count = 0
        token_read_count = 0
        sensitive_output_count = 0
    }
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
}

function Get-CodyCorrelationCanaryV4DownloadStageSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) -or $item.Length -le 0 -or $item.Length -gt $script:MaximumSourceBytes) {
        Throw-CodyCorrelationCanaryV4DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_SOURCE_REJECTED'
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Invoke-CodyCorrelationCanaryV4DownloadStage {
    [CmdletBinding()]
    param()

    $networkRequestCount = 0
    try {
        if ($args.Count -ne 0 -or [Environment]::GetEnvironmentVariable($script:StageGuardName) -cne '1') {
            Throw-CodyCorrelationCanaryV4DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_GUARD_REJECTED'
        }
        if ($script:ReleaseCommit -notmatch '^[a-f0-9]{40}$' -or $script:ExpectedOuterSha256 -notmatch '^[a-f0-9]{64}$' -or $script:ExpectedLauncherSha256 -notmatch '^[a-f0-9]{64}$') {
            Throw-CodyCorrelationCanaryV4DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_RELEASE_REJECTED'
        }
        $temporaryRoot = [System.IO.Path]::GetTempPath()
        if ([string]::IsNullOrWhiteSpace($temporaryRoot)) {
            Throw-CodyCorrelationCanaryV4DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_LOCAL_ROOT_REJECTED'
        }
        $temporaryDirectory = Join-Path ([System.IO.Path]::GetFullPath($temporaryRoot)) ('.hermes-cody-correlation-stage-' + [Guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
        $outerPath = Join-Path $temporaryDirectory $script:OuterFileName
        $launcherPath = Join-Path $temporaryDirectory $script:LauncherFileName
        $base = "https://raw.githubusercontent.com/neki0817/hermes-aru-preflight-release/$($script:ReleaseCommit)/tools/discord-cody-aru-direct-bridge"

        $networkRequestCount += 1
        Invoke-WebRequest -Uri "$base/$($script:OuterFileName)" -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30 -OutFile $outerPath -ErrorAction Stop | Out-Null
        if ((Get-CodyCorrelationCanaryV4DownloadStageSha256 $outerPath) -cne $script:ExpectedOuterSha256) {
            Throw-CodyCorrelationCanaryV4DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_OUTER_HASH_REJECTED'
        }

        $networkRequestCount += 1
        Invoke-WebRequest -Uri "$base/$($script:LauncherFileName)" -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30 -OutFile $launcherPath -ErrorAction Stop | Out-Null
        if ((Get-CodyCorrelationCanaryV4DownloadStageSha256 $launcherPath) -cne $script:ExpectedLauncherSha256) {
            Throw-CodyCorrelationCanaryV4DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_LAUNCHER_HASH_REJECTED'
        }

        . $outerPath
        $stage = Invoke-CodyCorrelationCanaryV4OuterStageReference -SourcePath $launcherPath -PinnedLauncherSha256 $script:ExpectedLauncherSha256
        if ($null -eq $stage -or $stage.terminal_state -cne 'staged') {
            Throw-CodyCorrelationCanaryV4DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_OUTER_REJECTED'
        }
        Write-CodyCorrelationCanaryV4DownloadStageResult $true 'staged' 'source_staged' $networkRequestCount
    } catch {
        Write-CodyCorrelationCanaryV4DownloadStageResult $false 'rejected' (Get-CodyCorrelationCanaryV4DownloadStageErrorCode $_) $networkRequestCount
        exit 2
    }
}

Invoke-CodyCorrelationCanaryV4DownloadStage
