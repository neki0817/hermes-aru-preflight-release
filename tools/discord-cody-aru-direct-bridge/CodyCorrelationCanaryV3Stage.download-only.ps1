# Hash-pinned download-only source stage for Cody correlation-canary v3.
# It downloads only the already-pinned outer stage reference and launcher,
# verifies their bytes, and invokes the outer stage.  It never reads a token,
# creates a canary manifest, sends to Discord, or starts the launcher.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StageGuardName = 'HERMES_CODY_CORRELATION_CANARY_V3_STAGE'
$script:ReleaseCommit = '56071b3fd1ca48769dcf6a8628e0256681516667'
$script:OuterFileName = 'CodyCorrelationCanaryV3OuterStageReference.ps1'
$script:LauncherFileName = 'CodyCorrelationCanaryV3Launcher.ps1'
$script:ExpectedOuterSha256 = '134ee6d6eeeab42d93a5b1212cac1293b5805523e28a774b56afc6c344527c2b'
$script:ExpectedLauncherSha256 = '2af24cb365391956903a6fdafb5f4640c2dcf7ce8870c539dca7622382e61fab'
$script:MaximumSourceBytes = 256KB

function Throw-CodyCorrelationCanaryV3DownloadStageError {
    param([Parameter(Mandatory)][string]$Code)
    throw [System.InvalidOperationException]::new($Code)
}

function Get-CodyCorrelationCanaryV3DownloadStageErrorCode {
    param([AllowNull()][object]$ErrorRecord)
    if ($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception -and [string]$ErrorRecord.Exception.Message -match '^DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_[A-Z_]+$') {
        return [string]$ErrorRecord.Exception.Message
    }
    return 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_REJECTED'
}

function Write-CodyCorrelationCanaryV3DownloadStageResult {
    param(
        [Parameter(Mandatory)][bool]$Ok,
        [Parameter(Mandatory)][string]$TerminalState,
        [Parameter(Mandatory)][string]$TerminalReason,
        [Parameter(Mandatory)][int]$NetworkRequestCount
    )
    $result = [ordered]@{
        schema_version = 'hermes-agents-discord-cody-aru-correlation-canary-v3-cody-download-stage/v1'
        ok = $Ok
        operation = 'cody_correlation_canary_v3_download_stage'
        terminal_state = $TerminalState
        terminal_reason = $TerminalReason
        network_request_count = $NetworkRequestCount
        message_send_attempt_count = 0
        token_read_count = 0
        sensitive_output_count = 0
    }
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
}

function Get-CodyCorrelationCanaryV3DownloadStageSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) -or $item.Length -le 0 -or $item.Length -gt $script:MaximumSourceBytes) {
        Throw-CodyCorrelationCanaryV3DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_SOURCE_REJECTED'
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Invoke-CodyCorrelationCanaryV3DownloadStage {
    [CmdletBinding()]
    param()

    $networkRequestCount = 0
    try {
        if ($args.Count -ne 0 -or [Environment]::GetEnvironmentVariable($script:StageGuardName) -cne '1') {
            Throw-CodyCorrelationCanaryV3DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_GUARD_REJECTED'
        }
        if ($script:ReleaseCommit -notmatch '^[a-f0-9]{40}$' -or $script:ExpectedOuterSha256 -notmatch '^[a-f0-9]{64}$' -or $script:ExpectedLauncherSha256 -notmatch '^[a-f0-9]{64}$') {
            Throw-CodyCorrelationCanaryV3DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_RELEASE_REJECTED'
        }
        $temporaryRoot = [System.IO.Path]::GetTempPath()
        if ([string]::IsNullOrWhiteSpace($temporaryRoot)) {
            Throw-CodyCorrelationCanaryV3DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_LOCAL_ROOT_REJECTED'
        }
        $temporaryDirectory = Join-Path ([System.IO.Path]::GetFullPath($temporaryRoot)) ('.hermes-cody-correlation-stage-' + [Guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
        $outerPath = Join-Path $temporaryDirectory $script:OuterFileName
        $launcherPath = Join-Path $temporaryDirectory $script:LauncherFileName
        $base = "https://raw.githubusercontent.com/neki0817/hermes-aru-preflight-release/$($script:ReleaseCommit)/tools/discord-cody-aru-direct-bridge"

        $networkRequestCount += 1
        Invoke-WebRequest -Uri "$base/$($script:OuterFileName)" -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30 -OutFile $outerPath -ErrorAction Stop | Out-Null
        if ((Get-CodyCorrelationCanaryV3DownloadStageSha256 $outerPath) -cne $script:ExpectedOuterSha256) {
            Throw-CodyCorrelationCanaryV3DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_OUTER_HASH_REJECTED'
        }

        $networkRequestCount += 1
        Invoke-WebRequest -Uri "$base/$($script:LauncherFileName)" -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30 -OutFile $launcherPath -ErrorAction Stop | Out-Null
        if ((Get-CodyCorrelationCanaryV3DownloadStageSha256 $launcherPath) -cne $script:ExpectedLauncherSha256) {
            Throw-CodyCorrelationCanaryV3DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_LAUNCHER_HASH_REJECTED'
        }

        . $outerPath
        $stage = Invoke-CodyCorrelationCanaryV3OuterStageReference -SourcePath $launcherPath -PinnedLauncherSha256 $script:ExpectedLauncherSha256
        if ($null -eq $stage -or $stage.terminal_state -cne 'staged') {
            Throw-CodyCorrelationCanaryV3DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_OUTER_REJECTED'
        }
        Write-CodyCorrelationCanaryV3DownloadStageResult $true 'staged' 'source_staged' $networkRequestCount
    } catch {
        Write-CodyCorrelationCanaryV3DownloadStageResult $false 'rejected' (Get-CodyCorrelationCanaryV3DownloadStageErrorCode $_) $networkRequestCount
        exit 2
    }
}

Invoke-CodyCorrelationCanaryV3DownloadStage
