$script:BifrostPort  = 8080
$script:CCProxyPort  = 8082
$script:BifrostDir   = "$env:APPDATA\bifrost"
$script:PyProxyDir   = "$env:USERPROFILE\claude-code-proxy"

function Start-Proxy {
    New-Item -ItemType Directory -Force -Path $script:BifrostDir | Out-Null
    Copy-Item "$env:USERPROFILE\config.json" "$script:BifrostDir\config.json" -Force
    Remove-Item "$script:BifrostDir\config.db" -Force -ErrorAction SilentlyContinue

    # Start Bifrost
    Start-Process pwsh `
        -ArgumentList "-NoExit -Command bifrost" `
        -WindowStyle Normal `
        -WorkingDirectory $script:BifrostDir

    Write-Host "Waiting for Bifrost on port $script:BifrostPort..." -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $healthy = $false
    while ($sw.Elapsed.TotalSeconds -lt 15) {
        if (Test-NetConnection -ComputerName localhost -Port $script:BifrostPort `
                -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) {
            $healthy = $true; break
        }
        Start-Sleep -Seconds 1
    }
    $sw.Stop()

    if ($healthy) {
        Write-Host "Bifrost ready ($([int]$sw.Elapsed.TotalSeconds)s)." -ForegroundColor Gray
    } else {
        Write-Warning "Bifrost did not open port $script:BifrostPort within 15s — check the Bifrost window."
        return
    }

    # Start Python proxy (replaces CCProxy)
    Start-Process pwsh `
        -ArgumentList "-NoExit -Command Set-Location '$script:PyProxyDir'; uv run claude-code-proxy" `
        -WindowStyle Normal `
        -WorkingDirectory $script:PyProxyDir

    Write-Host "Proxy stack ready." -ForegroundColor Green
}

function Set-ProxyProvider {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ModelName   # plain model name, no @openai suffix
    )

    # Write the Python proxy .env
    $envPath = "$script:PyProxyDir\.env"
    $envContent = @"
OPENAI_BASE_URL=http://localhost:$script:BifrostPort/v1
OPENAI_API_KEY=any-string
BIG_MODEL=$ModelName
MIDDLE_MODEL=$ModelName
SMALL_MODEL=$ModelName
PORT=$script:CCProxyPort
"@
    Set-Content $envPath -Value $envContent -Encoding UTF8

    $env:ANTHROPIC_BASE_URL         = "http://localhost:$script:CCProxyPort"
    $env:ANTHROPIC_API_KEY          = "any-string"
    $env:ANTHROPIC_MODEL            = $ModelName
    $env:ANTHROPIC_SMALL_FAST_MODEL = $ModelName
    Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue

    Write-Host "Switched to $Name" -ForegroundColor Cyan
    Write-Host "  Restart the proxy window for model change to take effect." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Provider shortcuts  (no @openai suffix — Python proxy passes directly to Bifrost)
# ---------------------------------------------------------------------------

function Use-AIStudio     { Set-ProxyProvider "AI Studio - Gemini 2.5 Flash"       "gemini/gemini-2.5-flash"               }
function Use-AIStudioLite { Set-ProxyProvider "AI Studio - Gemini 2.5 Flash Lite"  "gemini/gemini-2.5-flash-lite"          }
function Use-Cerebras     { Set-ProxyProvider "Cerebras - GPT OSS 120B"            "cerebras/gpt-oss-120b"                 }
function Use-GLM          { Set-ProxyProvider "OpenRouter - GLM 4.7 Flash"         "openrouter/z-ai/glm-4.7-flash"        }
function Use-MiMo         { Set-ProxyProvider "OpenRouter - MiMo V2 Flash"         "openrouter/xiaomi/mimo-v2-flash"      }
function Use-FlashLite    { Set-ProxyProvider "OpenRouter - Gemini 2.5 Flash Lite" "openrouter/google/gemini-2.5-flash-lite" }
function Use-DeepSeek     { Set-ProxyProvider "OpenRouter - DeepSeek V3.2"         "openrouter/deepseek/deepseek-v3.2"    }
function Use-Mistral      { Set-ProxyProvider "Mistral Small"                      "mistral/mistral-small-latest"         }

function Use-Ollama {
    # Bypasses Bifrost/Python proxy entirely — call Start-Proxy or another Use-* to return to the proxy stack.
    $env:ANTHROPIC_BASE_URL         = "http://localhost:11434"
    $env:ANTHROPIC_API_KEY          = ""
    $env:ANTHROPIC_MODEL            = "minimax-m2.5:cloud"
    $env:ANTHROPIC_SMALL_FAST_MODEL = ""
    Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
    Write-Host "Switched to Ollama (bypasses proxy — call Start-Proxy to return)" -ForegroundColor Yellow
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
    Write-Host "  Use-GLM            - GLM 4.7 Flash        `$0.06/`$0.40 per M"
    Write-Host "  Use-MiMo           - MiMo V2 Flash        `$0.09/`$0.29 per M"
    Write-Host "  Use-FlashLite      - Gemini 2.5 FL        `$0.10/`$0.40 per M"
    Write-Host "  Use-DeepSeek       - DeepSeek V3.2        `$0.26/`$0.38 per M"
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
        "openrouter/z-ai/glm-4.7-flash",
        "openrouter/xiaomi/mimo-v2-flash",
        "openrouter/google/gemini-2.5-flash-lite",
        "openrouter/deepseek/deepseek-v3.2",
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