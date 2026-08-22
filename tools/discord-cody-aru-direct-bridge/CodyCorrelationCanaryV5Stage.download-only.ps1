# Hash-pinned download-only source stage for Cody correlation-canary v5.
# It downloads only the already-pinned outer stage reference and launcher,
# verifies their bytes, and invokes the outer stage.  It never reads a token,
# creates a canary manifest, sends to Discord, or starts the launcher.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StageGuardName = 'HERMES_CODY_CORRELATION_CANARY_V5_STAGE'
$script:ReleaseCommit = 'deb09fc378c025c4382147f1fe0cf984b196da29'
$script:OuterFileName = 'CodyCorrelationCanaryV5OuterStageReference.ps1'
$script:LauncherFileName = 'CodyCorrelationCanaryV5Launcher.ps1'
$script:ExpectedOuterSha256 = 'af9c9b4dc79d8012645663fc36713288c3caf224caae7a6742a541810075a347'
$script:ExpectedLauncherSha256 = '692b01fdaf523eb353188d9599890db045662e5efc3bebe521c67d8301356093'
$script:MaximumSourceBytes = 256KB

function Throw-CodyCorrelationCanaryV5DownloadStageError {
    param([Parameter(Mandatory)][string]$Code)
    throw [System.InvalidOperationException]::new($Code)
}

function Get-CodyCorrelationCanaryV5DownloadStageErrorCode {
    param([AllowNull()][object]$ErrorRecord)
    if ($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception -and [string]$ErrorRecord.Exception.Message -match '^DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_[A-Z_]+$') {
        return [string]$ErrorRecord.Exception.Message
    }
    return 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_REJECTED'
}

function Write-CodyCorrelationCanaryV5DownloadStageResult {
    param(
        [Parameter(Mandatory)][bool]$Ok,
        [Parameter(Mandatory)][string]$TerminalState,
        [Parameter(Mandatory)][string]$TerminalReason,
        [Parameter(Mandatory)][int]$NetworkRequestCount
    )
    $result = [ordered]@{
        schema_version = 'hermes-agents-discord-cody-aru-correlation-canary-v5-cody-download-stage/v1'
        ok = $Ok
        operation = 'cody_correlation_canary_v5_download_stage'
        terminal_state = $TerminalState
        terminal_reason = $TerminalReason
        network_request_count = $NetworkRequestCount
        message_send_attempt_count = 0
        token_read_count = 0
        sensitive_output_count = 0
    }
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
}

function Get-CodyCorrelationCanaryV5DownloadStageSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) -or $item.Length -le 0 -or $item.Length -gt $script:MaximumSourceBytes) {
        Throw-CodyCorrelationCanaryV5DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_SOURCE_REJECTED'
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Invoke-CodyCorrelationCanaryV5DownloadStage {
    [CmdletBinding()]
    param()

    $networkRequestCount = 0
    try {
        if ($args.Count -ne 0 -or [Environment]::GetEnvironmentVariable($script:StageGuardName) -cne '1') {
            Throw-CodyCorrelationCanaryV5DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_GUARD_REJECTED'
        }
        if ($script:ReleaseCommit -notmatch '^[a-f0-9]{40}$' -or $script:ExpectedOuterSha256 -notmatch '^[a-f0-9]{64}$' -or $script:ExpectedLauncherSha256 -notmatch '^[a-f0-9]{64}$') {
            Throw-CodyCorrelationCanaryV5DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_RELEASE_REJECTED'
        }
        $temporaryRoot = [System.IO.Path]::GetTempPath()
        if ([string]::IsNullOrWhiteSpace($temporaryRoot)) {
            Throw-CodyCorrelationCanaryV5DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_LOCAL_ROOT_REJECTED'
        }
        $temporaryDirectory = Join-Path ([System.IO.Path]::GetFullPath($temporaryRoot)) ('.hermes-cody-correlation-stage-' + [Guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
        $outerPath = Join-Path $temporaryDirectory $script:OuterFileName
        $launcherPath = Join-Path $temporaryDirectory $script:LauncherFileName
        $base = "https://raw.githubusercontent.com/neki0817/hermes-aru-preflight-release/$($script:ReleaseCommit)/tools/discord-cody-aru-direct-bridge"

        $networkRequestCount += 1
        Invoke-WebRequest -Uri "$base/$($script:OuterFileName)" -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30 -OutFile $outerPath -ErrorAction Stop | Out-Null
        if ((Get-CodyCorrelationCanaryV5DownloadStageSha256 $outerPath) -cne $script:ExpectedOuterSha256) {
            Throw-CodyCorrelationCanaryV5DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_OUTER_HASH_REJECTED'
        }

        $networkRequestCount += 1
        Invoke-WebRequest -Uri "$base/$($script:LauncherFileName)" -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30 -OutFile $launcherPath -ErrorAction Stop | Out-Null
        if ((Get-CodyCorrelationCanaryV5DownloadStageSha256 $launcherPath) -cne $script:ExpectedLauncherSha256) {
            Throw-CodyCorrelationCanaryV5DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_LAUNCHER_HASH_REJECTED'
        }

        . $outerPath
        $stage = Invoke-CodyCorrelationCanaryV5OuterStageReference -SourcePath $launcherPath -PinnedLauncherSha256 $script:ExpectedLauncherSha256
        if ($null -eq $stage -or $stage.terminal_state -cne 'staged') {
            Throw-CodyCorrelationCanaryV5DownloadStageError 'DISCORD_CODY_ARU_CORRELATION_CANARY_CODY_DOWNLOAD_STAGE_OUTER_REJECTED'
        }
        Write-CodyCorrelationCanaryV5DownloadStageResult $true 'staged' 'source_staged' $networkRequestCount
    } catch {
        Write-CodyCorrelationCanaryV5DownloadStageResult $false 'rejected' (Get-CodyCorrelationCanaryV5DownloadStageErrorCode $_) $networkRequestCount
        exit 2
    }
}

Invoke-CodyCorrelationCanaryV5DownloadStage
