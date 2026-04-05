# =============================================================================
# Bifrost / CCProxy Helper Functions
# Bifrost listens on :8080, CCProxy translates to Anthropic API on :8082.
# ~/config.json contains your real API keys and is copied as-is by Start-Proxy.
# Note: config.json uses a relative ./config.db path, which works because
# Start-Proxy sets the working directory to $env:APPDATA\bifrost explicitly.
# =============================================================================

$script:BifrostPort = 8080
$script:CCProxyPort = 8082
$script:BifrostDir  = "$env:APPDATA\bifrost"

function Start-Proxy {
    Write-Host "Stopping existing Bifrost and CCProxy instances..." -ForegroundColor Gray
    Get-Process | Where-Object { $_.Name -like "*bifrost*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process | Where-Object { $_.Name -like "*ccproxy*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # Prepare Bifrost config directory (config.db is ephemeral, always removed on restart)
    New-Item -ItemType Directory -Force -Path $script:BifrostDir | Out-Null
    Copy-Item "$env:USERPROFILE\config.json" "$script:BifrostDir\config.json" -Force
    Remove-Item "$script:BifrostDir\config.db" -Force -ErrorAction SilentlyContinue

    Start-Process pwsh -ArgumentList "-NoExit -Command bifrost" `
        -WindowStyle Normal `
        -WorkingDirectory $script:BifrostDir

    # Wait for Bifrost to open its port before starting CCProxy.
    # Using Test-NetConnection rather than a /health endpoint, as Bifrost's
    # HTTP health route has not been confirmed to exist.
    # -WarningAction SilentlyContinue suppresses the "TCP connect failed" noise
    # on each failed attempt. Stopwatch used for accurate elapsed reporting since
    # Test-NetConnection's internal TCP timeout adds 1-2s per iteration on top
    # of Start-Sleep, making a simple counter unreliable.
    Write-Host "Waiting for Bifrost to open port $script:BifrostPort..." -ForegroundColor Yellow
    $timeout = 30
    $healthy = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeout) {
        if (Test-NetConnection -ComputerName localhost -Port $script:BifrostPort `
                -InformationLevel Quiet `
                -WarningAction SilentlyContinue `
                -ErrorAction SilentlyContinue) {
            $healthy = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    $sw.Stop()

    if (-not $healthy) {
        Write-Warning "Bifrost did not open port $script:BifrostPort within ${timeout}s. CCProxy may fail — check the Bifrost window."
    } else {
        Write-Host "Bifrost ready after $([int]$sw.Elapsed.TotalSeconds)s." -ForegroundColor Gray
    }

    # CCProxy is restarted in a loop in case it exits unexpectedly.
    # Close this window manually when you no longer need the proxy.
    Start-Process pwsh `
        -ArgumentList "-NoExit -Command while (`$true) { ccproxy server; Start-Sleep -Seconds 2 }" `
        -WindowStyle Normal

    Write-Host "Proxy stack ready!" -ForegroundColor Green

    # Default to cheapest model on fresh start
    Use-GLM
}

function Set-ProxyProvider {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ModelName
    )

    $settingsPath = "$env:USERPROFILE\.ccproxy\settings.json"
    $settingsDir  = Split-Path $settingsPath -Parent

    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
    }

    # Build the settings object and serialize safely with ConvertTo-Json
    $settings = [ordered]@{
        server    = [ordered]@{ port = $script:CCProxyPort; host = "0.0.0.0" }
        providers = [ordered]@{
            openai = [ordered]@{
                apiKey        = "any-string"
                baseURL       = "http://localhost:$script:BifrostPort/v1"
                responseStyle = "openai"
            }
        }
        models    = [ordered]@{
            bigModel          = $ModelName
            smallModel        = $ModelName
            preferredProvider = "openai"
        }
    }

    $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding UTF8

    $env:ANTHROPIC_BASE_URL         = "http://localhost:$script:CCProxyPort"
    $env:ANTHROPIC_API_KEY          = "any-string"
    $env:ANTHROPIC_MODEL            = $ModelName
    $env:ANTHROPIC_SMALL_FAST_MODEL = $ModelName
    Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue

    Write-Host "Switched to $Name" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Provider shortcuts
# ---------------------------------------------------------------------------

# Free via AI Studio key
function Use-AIStudio     { Set-ProxyProvider "AI Studio - Gemini 2.5 Flash"      "gemini/gemini-2.5-flash@openai"      }
function Use-AIStudioLite { Set-ProxyProvider "AI Studio - Gemini 2.5 Flash Lite" "gemini/gemini-2.5-flash-lite@openai" }

# Free via Cerebras
function Use-Cerebras     { Set-ProxyProvider "Cerebras - GPT OSS 120B"           "cerebras/gpt-oss-120b@openai"        }

# OpenRouter — sorted cheapest first
function Use-GLM          { Set-ProxyProvider "OpenRouter - GLM 4.7 Flash"         "openrouter/z-ai/glm-4.7-flash@openai"          }
function Use-MiMo         { Set-ProxyProvider "OpenRouter - MiMo V2 Flash"         "openrouter/xiaomi/mimo-v2-flash@openai"         }
function Use-FlashLite    { Set-ProxyProvider "OpenRouter - Gemini 2.5 Flash Lite" "openrouter/google/gemini-2.5-flash-lite@openai" }
function Use-DeepSeek     { Set-ProxyProvider "OpenRouter - DeepSeek V3.2"         "openrouter/deepseek/deepseek-v3.2@openai"       }

# Direct providers
function Use-Mistral      { Set-ProxyProvider "Mistral Small" "mistral/mistral-small-latest@openai" }

function Use-Ollama {
    # NOTE: Ollama bypasses Bifrost/CCProxy entirely and talks directly to a local
    # Ollama instance. Environment will not revert automatically — call Start-Proxy
    # or another Use-* function to return to the proxy stack.
    $env:ANTHROPIC_BASE_URL         = "http://localhost:11434"
    $env:ANTHROPIC_API_KEY          = ""
    $env:ANTHROPIC_MODEL            = "minimax-m2.5:cloud"
    $env:ANTHROPIC_SMALL_FAST_MODEL = ""
    Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
    Write-Host "Switched to Ollama (bypasses Bifrost — call Start-Proxy to return to proxy stack)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

function Show-Models {
    Write-Host ""
    Write-Host "=== FREE (AI Studio key) ===" -ForegroundColor Green
    Write-Host "  Use-AIStudio       - Gemini 2.5 Flash"
    Write-Host "  Use-AIStudioLite   - Gemini 2.5 Flash Lite"
    Write-Host "  Use-Cerebras       - GPT OSS 120B"
    Write-Host ""
    Write-Host "=== OPENROUTER — cheapest first ===" -ForegroundColor Yellow
    Write-Host "  Use-GLM            - GLM 4.7 Flash       `$0.06/`$0.40 per M"
    Write-Host "  Use-MiMo           - MiMo V2 Flash       `$0.09/`$0.29 per M"
    Write-Host "  Use-FlashLite      - Gemini 2.5 FL       `$0.10/`$0.40 per M"
    Write-Host "  Use-DeepSeek       - DeepSeek V3.2       `$0.26/`$0.38 per M"
    Write-Host ""
    Write-Host "=== OTHER ===" -ForegroundColor Gray
    Write-Host "  Use-Mistral        - Mistral Small (direct)"
    Write-Host "  Use-Ollama         - Ollama local (bypasses proxy!)"
    Write-Host ""
}

function Test-Models {
    $models = @(
        "gemini/gemini-2.5-flash",
        "gemini/gemini-2.5-flash-lite",
        "cerebras/gpt-oss-120b",
        "z-ai/glm-4.7-flash",
        "xiaomi/mimo-v2-flash",
        "google/gemini-2.5-flash-lite",
        "deepseek/deepseek-v3.2",
        "mistral/mistral-small-latest"
    )

    Write-Host "`nTesting model connectivity via Bifrost (port $script:BifrostPort)..." -ForegroundColor Yellow

    foreach ($model in $models) {
        try {
            $payload = @{
                model      = $model
                messages   = @(@{ role = 'user'; content = 'ping' })
                max_tokens = 5
            } | ConvertTo-Json -Depth 4

            Invoke-RestMethod `
                -Uri "http://localhost:$script:BifrostPort/v1/chat/completions" `
                -Method POST `
                -ContentType "application/json" `
                -Body $payload `
                -ErrorAction Stop | Out-Null

            Write-Host "  OK  $model" -ForegroundColor Green
        } catch {
            Write-Host "  ERR $model  ($($_.Exception.Message))" -ForegroundColor Red
        }
    }
    Write-Host ""
}