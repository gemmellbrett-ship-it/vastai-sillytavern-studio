# Vast.ai One-Click Linux Desktop: SillyTavern Studio

Minimal auto-setup for **SillyTavern** on Vast.ai Linux Desktop (Selkies).  
Services: SillyTavern + Ollama (dolphin-mistral) + ComfyUI + Wan2GP.  
Desktop shortcut is created automatically.

## Services

| Service       | Port  | Purpose                    |
|---------------|-------|----------------------------|
| SillyTavern   | 8000  | Main chat UI               |
| Ollama        | 11434 | Uncensored LLM (dolphin-mistral) |
| ComfyUI       | 8188  | Image generation           |
| Wan2GP        | 7861  | Video generation           |
| Desktop       | 6100 / 6200 | Selkies / VNC         |

## Vast.ai Setup Instructions

1. Go to Templates → find or create a **Linux Desktop** template.
2. Edit the template.
3. Set **Environment Variable**:
