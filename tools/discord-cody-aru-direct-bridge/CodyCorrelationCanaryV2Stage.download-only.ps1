# Hash-pinned download-only source stage for Cody correlation-canary v2.
# It downloads only the already-pinned outer stage reference and launcher,
# verifies their bytes, and invokes the outer stage.  It never reads a token,
# creates a canary manifest, sends to Discord, or starts the launcher.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StageGuardName = 'HERMES_CODY_CORRELATION_CANARY_STAGE'
$script:ReleaseCommit = 'c247d190cfdfbd5fc17aedf1e36b13873ab1d754'
$script:OuterFileName = 'CodyCorrelationCanaryV2OuterStageReference.ps1'
$script:LauncherFileName = 'CodyCorrelationCanaryV2Launcher.ps1'
$script:ExpectedOuterSha256 = '0c233987e0c635c5427c6f237b542d5876a1b6e829bc4fffa52b3e7a430662f9'
$script:ExpectedLauncherSha256 = '56c1dcadd3234de0fcd97d909af7ccf572d07fe12c467d3a8af7f0d2bbb0c666'
$script:MaximumSourceBytes = 256KB

function Throw-CodyCorrelationCanaryV2DownloadStageError {
    param([Parameter(Mandatory)][string]$Code)
    throw [System.InvalidOperationException]::new($Code)
}

function Get-CodyCorrelationCanaryV2DownloadStageErrorCode {
    param([AllowNull()][object]$ErrorRecord)
    if ($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception -and [string]$ErrorRecord.Exception.Message -match '^DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_[A-Z_]+$') {
        return [string]$ErrorRecord.Exception.Message
    }
    return 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_REJECTED'
}

function Write-CodyCorrelationCanaryV2DownloadStageResult {
    param(
        [Parameter(Mandatory)][bool]$Ok,
        [Parameter(Mandatory)][string]$TerminalState,
        [Parameter(Mandatory)][string]$TerminalReason,
        [Parameter(Mandatory)][int]$NetworkRequestCount
    )
    $result = [ordered]@{
        schema_version = 'hermes-agents-discord-cody-aru-correlation-canary-cody-download-stage/v1'
        ok = $Ok
        operation = 'cody_correlation_canary_v2_download_stage'
        terminal_state = $TerminalState
        terminal_reason = $TerminalReason
        network_request_count = $NetworkRequestCount
        message_send_attempt_count = 0
        token_read_count = 0
        sensitive_output_count = 0
    }
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
}

function Get-CodyCorrelationCanaryV2DownloadStageSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) -or $item.Length -le 0 -or $item.Length -gt $script:MaximumSourceBytes) {
        Throw-CodyCorrelationCanaryV2DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_SOURCE_REJECTED'
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Invoke-CodyCorrelationCanaryV2DownloadStage {
    [CmdletBinding()]
    param()

    $networkRequestCount = 0
    try {
        if ($args.Count -ne 0 -or [Environment]::GetEnvironmentVariable($script:StageGuardName) -cne '1') {
            Throw-CodyCorrelationCanaryV2DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_GUARD_REJECTED'
        }
        if ($script:ReleaseCommit -notmatch '^[a-f0-9]{40}$' -or $script:ExpectedOuterSha256 -notmatch '^[a-f0-9]{64}$' -or $script:ExpectedLauncherSha256 -notmatch '^[a-f0-9]{64}$') {
            Throw-CodyCorrelationCanaryV2DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_RELEASE_REJECTED'
        }
        $temporaryRoot = [System.IO.Path]::GetTempPath()
        if ([string]::IsNullOrWhiteSpace($temporaryRoot)) {
            Throw-CodyCorrelationCanaryV2DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_LOCAL_ROOT_REJECTED'
        }
        $temporaryDirectory = Join-Path ([System.IO.Path]::GetFullPath($temporaryRoot)) ('.hermes-cody-correlation-stage-' + [Guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
        $outerPath = Join-Path $temporaryDirectory $script:OuterFileName
        $launcherPath = Join-Path $temporaryDirectory $script:LauncherFileName
        $base = "https://raw.githubusercontent.com/neki0817/hermes-aru-preflight-release/$($script:ReleaseCommit)/tools/discord-cody-aru-direct-bridge"

        $networkRequestCount += 1
        Invoke-WebRequest -Uri "$base/$($script:OuterFileName)" -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30 -OutFile $outerPath -ErrorAction Stop | Out-Null
        if ((Get-CodyCorrelationCanaryV2DownloadStageSha256 $outerPath) -cne $script:ExpectedOuterSha256) {
            Throw-CodyCorrelationCanaryV2DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_OUTER_HASH_REJECTED'
        }

        $networkRequestCount += 1
        Invoke-WebRequest -Uri "$base/$($script:LauncherFileName)" -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30 -OutFile $launcherPath -ErrorAction Stop | Out-Null
        if ((Get-CodyCorrelationCanaryV2DownloadStageSha256 $launcherPath) -cne $script:ExpectedLauncherSha256) {
            Throw-CodyCorrelationCanaryV2DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_LAUNCHER_HASH_REJECTED'
        }

        . $outerPath
        $stage = Invoke-CodyCorrelationCanaryV2OuterStageReference -SourcePath $launcherPath -PinnedLauncherSha256 $script:ExpectedLauncherSha256
        if ($null -eq $stage -or $stage.terminal_state -cne 'staged') {
            Throw-CodyCorrelationCanaryV2DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_OUTER_REJECTED'
        }
        Write-CodyCorrelationCanaryV2DownloadStageResult $true 'staged' 'source_staged' $networkRequestCount
    } catch {
        Write-CodyCorrelationCanaryV2DownloadStageResult $false 'rejected' (Get-CodyCorrelationCanaryV2DownloadStageErrorCode $_) $networkRequestCount
        exit 2
    }
}

Invoke-CodyCorrelationCanaryV2DownloadStage
