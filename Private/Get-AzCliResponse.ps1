#Requires -Version 5.1
<#
.SYNOPSIS
    Azure CLI wrapper with retry, timeout, caching, and structured logging.
.DESCRIPTION
    Central point for all `az` calls. Provides:
    - Exponential backoff retry with transient-error detection
    - Response cache with configurable TTL
    - Per-call timeout (default 30s)
    - Graceful degradation for rate-limits (429 Retry-After)
#>

$script:AzCliRetryCount = 3
$script:AzCliRetryBase  = 1
$script:AzCliTimeoutSec = 30
$script:AzCliCacheTTL   = 60

if (-not (Get-Variable -Name 'script:AzCliCache' -Scope 'Script' -ErrorAction SilentlyContinue)) {
    $script:AzCliCache = @{}
}

function Clear-BsiAzCliCache {
    $script:AzCliCache = @{}
}

function Get-AzCliResponse {
    <#
    .SYNOPSIS
        Executes an Azure CLI command with retry, timeout, and caching.
    .PARAMETER Arguments
        Arguments to pass to `az`.
    .PARAMETER SubscriptionId
        Optional Azure subscription ID.
    .PARAMETER UseCache
        Whether to use response cache.
    .PARAMETER TtlSeconds
        Cache TTL override.
    .PARAMETER TimeoutSeconds
        Per-call timeout override.
    .OUTPUTS
        PSCustomObject with Output, ExitCode, Stderr properties.
    #>
    param(
        [Parameter(Mandatory)][array]$Arguments,
        [string]$SubscriptionId = '',
        [bool]$UseCache = $true,
        [int]$TtlSeconds = 0,
        [int]$TimeoutSeconds = 0
    )

    if ($TimeoutSeconds -le 0) { $TimeoutSeconds = $script:AzCliTimeoutSec }
    if ($TtlSeconds -le 0)     { $TtlSeconds = $script:AzCliCacheTTL }

    $allArgs = @()
    if ($SubscriptionId) {
        $allArgs += @('--subscription', $SubscriptionId)
    }
    $allArgs += $Arguments
    if ($allArgs -notcontains '--only-show-errors') {
        $allArgs += @('--only-show-errors')
    }
    $allArgs += @('-o', 'json')

    $cacheKey = ($allArgs -join ' ')

    # Cache lookup
    if ($UseCache -and $script:AzCliCache.ContainsKey($cacheKey)) {
        $cached = $script:AzCliCache[$cacheKey]
        if (([datetime]::UtcNow - $cached.Timestamp).TotalSeconds -lt $TtlSeconds) {
            Write-Verbose "[AzCli] Cache hit: $cacheKey"
            return $cached
        }
        $script:AzCliCache.Remove($cacheKey)
    }

    $lastOutput = ''
    $lastRc     = 1
    $lastErr    = ''

    for ($attempt = 1; $attempt -le $script:AzCliRetryCount; $attempt++) {
        try {
            $azExe = (Get-Command 'az' -ErrorAction SilentlyContinue).Source
            if (-not $azExe) {
                return [PSCustomObject]@{ Output = ''; ExitCode = 1; Stderr = 'az CLI not found in PATH' }
            }

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo.FileName = $azExe
            $process.StartInfo.Arguments = ($allArgs | ForEach-Object {
                if ($_ -match '\s') { "`"$_`"" } else { $_ }
            }) -join ' '
            $process.StartInfo.UseShellExecute = $false
            $process.StartInfo.RedirectStandardOutput = $true
            $process.StartInfo.RedirectStandardError = $true
            $process.StartInfo.CreateNoWindow = $true

            # WSL2 interop: ensure Windows az binary uses WSL HOME for auth tokens
            # WSLENV HOME/p translates /home/user → \\wsl$\... for Windows process
            if ($IsLinux -and $azExe -match '^/mnt/') {
                $process.StartInfo.EnvironmentVariables["HOME"] = $env:HOME
                $existingWslEnv = if ($env:WSLENV) { "$env:WSLENV:" } else { '' }
                $process.StartInfo.EnvironmentVariables["WSLENV"] = "${existingWslEnv}HOME/p"
            }

            $null = $process.Start()
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()

            if (-not $process.WaitForMilliseconds($TimeoutSeconds * 1000)) {
                try { $process.Kill() } catch {}
                $lastOutput = ''
                $lastRc     = 2
                $lastErr    = "Command timed out after $TimeoutSeconds seconds"
                Write-Warning "[AzCli] Timeout ($TimeoutSeconds s) for: $($Arguments -join ' ')"
            } else {
                $lastOutput = if ($null -eq $stdout) { '' } else { $stdout.Trim() }
                $lastRc     = $process.ExitCode
                $lastErr    = if ($null -eq $stderr) { '' } else { $stderr.Trim() }
            }
        } catch {
            $lastOutput = ''
            $lastRc     = 1
            $lastErr    = $_.Exception.Message
        }

        # Success or timeout — no retry
        if ($lastRc -eq 0 -or $lastRc -eq 2) { break }

        # Rate-limit detection: check for 429 and Retry-After
        $isRateLimit = $lastErr -match '429'
        if ($isRateLimit -and $attempt -lt $script:AzCliRetryCount) {
            $delay = [Math]::Pow($script:AzCliRetryBase, $attempt) * 2
            Write-Warning "[AzCli] Rate limit (attempt $attempt/$($script:AzCliRetryCount)): retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
            continue
        }

        # Transient error detection
        $isTransient = ($lastErr -match 'EAGAIN|ETIMEDOUT|timeout|502|503|throttl') -and
                       ($lastErr -notmatch 'RequestDisallowedByPolicy')

        if ($isTransient -and $attempt -lt $script:AzCliRetryCount) {
            $delay = [Math]::Pow($script:AzCliRetryBase, $attempt)
            Write-Warning "[AzCli] Transient error (attempt $attempt/$($script:AzCliRetryCount)): retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
            continue
        }

        break
    }

    $result = [PSCustomObject]@{
        Output   = $lastOutput
        ExitCode = $lastRc
        Stderr   = $lastErr
    }

    # Cache successful results
    if ($UseCache -and $lastRc -eq 0 -and $lastOutput) {
        $script:AzCliCache[$cacheKey] = [PSCustomObject]@{
            Output    = $lastOutput
            ExitCode  = $lastRc
            Stderr    = $lastErr
            Timestamp = [datetime]::UtcNow
        }
    }

    return $result
}

function Test-AzCliReady {
    <#
    .SYNOPSIS
        Validates Azure CLI is installed and logged in.
    .OUTPUTS
        $true if ready, throws otherwise.
    #>
    $azExe = Get-Command 'az' -ErrorAction SilentlyContinue
    if (-not $azExe) {
        throw "Azure CLI (az) not found in PATH."
    }

    $result = Get-AzCliResponse -Arguments @("account", "show", "--query", "name", "-o", "tsv") -UseCache $false
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        throw "Azure CLI is not logged in. Run 'az login' first."
    }

    return $true
}

function Get-AzCliSubscriptionId {
    $result = Get-AzCliResponse -Arguments @("account", "show", "--query", "id", "-o", "tsv") -UseCache $false
    if ($result.ExitCode -eq 0) {
        return $result.Output.Trim()
    }
    return ''
}
