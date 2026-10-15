# Vast.ai One-Click Linux Desktop Template: SillyTavern NSFW Studio

**Fully auto-setup** Linux Desktop (Selkies / VNC) focused on **SillyTavern**. Everything installs, configures, and starts before the instance is usable. SillyTavern is pre-connected to Ollama (uncensored dolphin-mistral) and image backends (ComfyUI, A1111, Forge) for NSFW image generation. Wan2GP handles video. A desktop shortcut for SillyTavern is waiting on the desktop.

## Included Services (all managed by Supervisor)

| Service       | Port  | Purpose                              | Notes |
|---------------|-------|--------------------------------------|-------|
| **SillyTavern** | 8000  | Main chat UI + image gen             | Pre-connected to Ollama + ComfyUI/A1111/Forge; desktop shortcut ready |
| **Ollama**    | 11434 | Uncensored LLM API                   | dolphin-mistral pre-pulled |
| **Wan2GP**    | 7861  | Video generation                     | Models download on first use |
| **ComfyUI**   | 8188  | Image gen backend                    | Manager + CORS enabled |
| **A1111**     | 7860  | Classic SD WebUI                     | `--api` + CORS |
| **Forge**     | 7862  | Faster Forge WebUI                   | `--api` + CORS |
| Desktop       | 6100 / 6200 | Linux Desktop (Selkies WebRTC / Guacamole VNC) | Full graphical environment |
| Jupyter       | (Vast portal) | Terminal / notebooks            | |

## How to Apply to the Linux Desktop Template

Template: https://cloud.vast.ai/template/readme/8caa42e6d98f2414eae26def4c7a67be

1. Open the template editor on Vast.ai (Templates → your template → Edit).
2. Keep the base Docker image (Linux Desktop / Selkies based).
3. Set **Launch Mode** to Jupyter or SSH (desktop access is via Open button).
4. **Ports / Environment** (add the AI ports; desktop ports are already handled):
   ```
   -p 8000:8000 -p 11434:11434 -p 7860:7860 -p 7861:7861 -p 7862:7862 -p 8188:8188
   ```
5. **Onstart / Provisioning Script**: Paste the full contents of `onstart.sh` from this folder.
6. Recommended disk: 150–250 GB. Recommended VRAM: 24 GB+ (you can stop unused UIs later).
7. Save template. Rent a new instance (or restart existing) and wait for setup.log to finish.

## What Auto-Setup Does

- Installs and starts all AI services via Supervisor.
- Pulls `dolphin-mistral` into Ollama.
- Writes SillyTavern `settings.json` so it defaults to:
  - LLM: Ollama at `http://127.0.0.1:11434` (model `dolphin-mistral`)
  - Image generation: ComfyUI at `http://127.0.0.1:8188` (A1111/Forge also available)
- Enables CORS and `--api` on image backends so SillyTavern can talk to them.
- Creates a **SillyTavern.desktop** shortcut on `/root/Desktop` (and other possible Desktop folders) that opens the browser to `http://127.0.0.1:8000`.
- Reloads Selkies panel if applicable so the icon appears.
- Waits briefly and checks that SillyTavern is responding before finishing.
- Creates shared models directory at `/workspace/models/`.

## After Instance Opens

1. Click **Open** on the instance card → choose **Selkies Desktop** (best) or Guacamole VNC.
2. On the Linux desktop you will see the **SillyTavern** shortcut. Double-click it — Chrome (or available browser) opens to the pre-configured SillyTavern.
3. Image generation: use the wand / `/sd` menu. Source is pre-set to ComfyUI; switch to A1111 (7860) or Forge (7862) in the extension if desired.
4. Video: open Wan2GP on port **7861** (or from a browser tab).
5. Supervisor control (from desktop terminal or Jupyter):
   ```bash
   supervisorctl status
   supervisorctl stop a1111 forge wan2gp   # free VRAM if needed
   supervisorctl start comfyui
   ```

## NSFW / Uncensored Models

- LLM: dolphin-mistral is already pulled. Add more with `ollama pull <model>`.
- Images: Download Pony, Illustrious, or other NSFW checkpoints into `/workspace/models/checkpoints/` then symlink or copy into each WebUI’s models folder, or use ComfyUI-Manager / A1111 extensions. First generation may pull additional files.
- Shared models tip: Place checkpoints in `/workspace/models/checkpoints` and symlink into each WebUI’s models folder.

## Files

- `onstart.sh` — Full provisioning + auto-config + desktop shortcut script (paste this into the template).
- This README.

## Tips

- First boot is slow (git clones + pip installs). Watch `/workspace/setup.log`.
- Everything under `/workspace` persists across restarts.
- Update any component with `git pull` inside its folder then `supervisorctl restart <name>`.
- Stop unused UIs to free VRAM.
- Desktop access is via the Instance Portal Open button (Selkies recommended for performance).

Edit `onstart.sh` if you want different default models, ports, extra checkpoints, or shortcut tweaks.
