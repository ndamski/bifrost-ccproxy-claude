# Bifrost + CCProxy — Claude Code Multi-Provider Proxy

Route Claude Code through multiple LLM providers (Gemini, Cerebras, OpenRouter, Mistral, Ollama) using Bifrost and CCProxy.

## Architecture
```
Claude Code  →  CCProxy (:8082)  →  Bifrost (:8080)  →  Provider APIs
```

- **CCProxy** translates Anthropic-protocol requests into OpenAI-compatible ones.
- **Bifrost** handles provider routing, key management, and load balancing.
- **PowerShell functions** manage startup and model switching.

## Installation

```bash
git clone https://github.com/ndamski/bifrost-ccproxy-claude.git
cd bifrost-ccproxy-claude
```

## Prerequisites

| Tool | Notes |
|------|-------|
| Bifrost | Must be on your PATH |
| CCProxy | Must be on your PATH |
| PowerShell 7+ | `winget install Microsoft.PowerShell` |
| Git | `winget install Git.Git` |

## Setup

### 1. Configure API Keys

Copy the template to your home directory and fill in your real keys:
```powershell
Copy-Item config.template.json "$env:USERPROFILE\config.json"
# Edit C:\Users\<you>\config.json and replace all YOUR_*_KEY_HERE placeholders
```

> WARNING: config.json is listed in .gitignore and must never be committed.

### 2. Load the PowerShell Functions

Append the contents of Microsoft.PowerShell_profile.ps1 to your own profile:
```powershell
Get-Content "Microsoft.PowerShell_profile.ps1" | Add-Content $PROFILE
```

Restart your terminal, or dot-source for the current session:
```powershell
. "Microsoft.PowerShell_profile.ps1"
```

### 3. Start the Proxy Stack
```powershell
Start-Proxy
```

This will:
- Kill any existing Bifrost/CCProxy processes
- Copy ~/config.json to Bifrost's AppData working directory
- Start Bifrost and wait for it to open port 8080
- Start CCProxy with an auto-restart loop

## Switching Models
```powershell
Show-Models        # List all available providers and costs

# Free options
Use-AIStudio       # Gemini 2.5 Flash (AI Studio key)
Use-Cerebras       # GPT OSS 120B

# OpenRouter — cheapest first
Use-GLM            # GLM 4.7 Flash      $0.06/$0.40 per M tokens
Use-MiMo           # MiMo V2 Flash      $0.09/$0.29 per M tokens
Use-FlashLite      # Gemini 2.5 FL      $0.10/$0.40 per M tokens
Use-DeepSeek       # DeepSeek V3.2      $0.26/$0.38 per M tokens

# Other
Use-Mistral        # Mistral Small (direct)
Use-Ollama         # Local Ollama instance (bypasses proxy stack entirely)
```

## Testing Connectivity
```powershell
Test-Models        # Pings all configured models via Bifrost
```

## File Reference

| File | Purpose |
|------|---------|
| config.template.json | Sanitized Bifrost config — copy to ~/config.json and add real keys |
| Microsoft.PowerShell_profile.ps1 | All proxy management functions |
| .gitignore | Excludes config.json, *.db, logs, and machine-specific files |

## Security Notes

- Real API keys live only in ~/config.json (excluded from version control).
- CCProxy settings at ~/.ccproxy/settings.json are auto-generated and machine-specific.
- Bifrost SQLite state (config.db) is ephemeral and excluded.

## License

MIT

