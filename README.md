# Bifrost + Claude Code Multi-Provider Proxy

PowerShell profile helpers for running [Bifrost](https://www.getbifrost.ai/) + a local Python proxy as an AI gateway, letting Claude Code switch freely between providers without restarting.

## Architecture

```
Claude Code  →  Python Proxy (:8082)  →  Bifrost (:8080)  →  Provider APIs
```

- **Python proxy** (`fuergaosi233/claude-code-proxy`) translates Claude Code's Anthropic-protocol requests into OpenAI-compatible ones, with full tool-call support.
- **Bifrost** handles provider routing, API key management, and load balancing across providers.
- **PowerShell functions** in `Microsoft.PowerShell_profile.ps1` manage startup and model switching.

## Prerequisites

| Tool | Install |
|------|---------|
| PowerShell 7+ | `winget install Microsoft.PowerShell` |
| Git | `winget install Git.Git` |
| Node.js + npm | `winget install OpenJS.NodeJS` |
| Bifrost | `npm install -g bifrost` |
| uv (Python runner) | `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"` |

## Installation

### 1. Clone this repo

```powershell
git clone https://github.com/ndamski/bifrost-ccproxy-claude.git
cd bifrost-ccproxy-claude
```

### 2. Clone the Python proxy

```powershell
cd ~
git clone https://github.com/fuergaosi233/claude-code-proxy
cd claude-code-proxy
uv sync
```

### 3. Configure API Keys

Copy the template to your home directory and fill in your real keys:

```powershell
Copy-Item "$env:USERPROFILE\bifrost-ccproxy-claude\config.template.json" "$env:USERPROFILE\config.json"
# Edit C:\Users\<you>\config.json and replace all YOUR_*_KEY placeholders
```

> **Warning:** `config.json` is listed in `.gitignore` and must never be committed.

### 4. Load the PowerShell Functions

Append the profile functions to your own PowerShell profile:

```powershell
Get-Content "$env:USERPROFILE\bifrost-ccproxy-claude\Microsoft.PowerShell_profile.ps1" | Add-Content $PROFILE
```

Restart your terminal, or dot-source for the current session:

```powershell
. "$env:USERPROFILE\bifrost-ccproxy-claude\Microsoft.PowerShell_profile.ps1"
```

### 5. Start the Proxy Stack

```powershell
Start-Proxy
```

This will:
- Copy `~/config.json` to Bifrost's AppData working directory
- Start Bifrost in a new window and wait up to 15s for port 8080
- Start the Python proxy in a new window on port 8082

### 6. Select a Model

```powershell
Use-AIStudio    # or any other Use-* function — see Switching Models below
```

Then launch Claude Code normally:

```powershell
claude
```

## Switching Models

```powershell
Show-Models          # List all available providers and costs

# Free (AI Studio key)
Use-AIStudio         # Gemini 2.5 Flash
Use-AIStudioLite     # Gemini 2.5 Flash Lite
Use-Cerebras         # GPT OSS 120B

# OpenRouter — cheapest first
Use-GLM              # GLM 4.7 Flash       $0.06/$0.40 per M tokens
Use-MiMo             # MiMo V2 Flash       $0.09/$0.29 per M tokens
Use-FlashLite        # Gemini 2.5 FL       $0.10/$0.40 per M tokens
Use-DeepSeek         # DeepSeek V3.2       $0.26/$0.38 per M tokens

# Other
Use-Mistral          # Mistral Small (direct)
Use-Ollama           # Local Ollama (bypasses proxy stack entirely)
```

Each `Use-*` call rewrites `~/claude-code-proxy/.env` and updates the `ANTHROPIC_*` environment variables in the current session. The proxy window must be restarted for the model change to take effect.

## Testing Connectivity

```powershell
# Ping all models directly via Bifrost
Test-Models

# Test the full proxy stack with a simple prompt
claude -p "say hello"

# Verify tool calls work (the real test)
cd some-directory
claude
# then type: list the files in this directory
# you should see actual file output, not silence
```

## Troubleshooting

**Claude says "I'll list the files..." but produces no output**
Tool calls are silently failing. Check:
1. Only one process is on port 8082: `netstat -ano | findstr :8082`
2. The Python proxy window shows `200 OK` responses, not `500`
3. Bifrost is running: `netstat -ano | findstr :8080`

**500 Internal Server Error in proxy window**
Usually a streaming conversion error. Restart the Python proxy window.

**429 Too Many Requests**
You've hit the free tier rate limit (20 req/min for Gemini). Switch models with `Use-DeepSeek` or wait 60 seconds.

**`Start-Proxy` launches old CCProxy instead of Python proxy**
Make sure your profile is sourced from the updated `Microsoft.PowerShell_profile.ps1` in this repo, not an older version.

## File Reference

| File | Purpose |
|------|---------|
| `Microsoft.PowerShell_profile.ps1` | All proxy management functions (`Start-Proxy`, `Use-*`, etc.) |
| `config.template.json` | Sanitized Bifrost config — copy to `~/config.json` and add real keys |
| `.gitignore` | Excludes `config.json`, `*.db`, logs, and machine-specific files |

The Python proxy lives separately at `~/claude-code-proxy/` and is not part of this repo.

## Security Notes

- Real API keys live only in `~/config.json` (excluded from version control).
- The Python proxy `.env` at `~/claude-code-proxy/.env` is auto-generated by `Use-*` functions and is machine-specific.
- Bifrost SQLite state (`config.db`) is ephemeral and excluded from git.

## License

MIT
