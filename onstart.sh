#!/bin/bash
# Vast.ai One-Click Template: SillyTavern (main) + Wan2GP + Ollama + ComfyUI + A1111 + Forge
# Fully automated: installs, configures, starts all services, pre-connects SillyTavern for NSFW,
# creates desktop shortcut. Idempotent. Logs to /workspace/setup.log
#
# Usage in Vast.ai Linux Desktop template:
# PROVISIONING_SCRIPT=https://raw.githubusercontent.com/gemmellbrett-ship-it/vastai-sillytavern-studio/main/onstart.sh

set -euo pipefail
exec > >(tee -a /workspace/setup.log) 2>&1

echo "=========================================="
echo "Vast.ai SillyTavern NSFW Studio Setup"
echo "Started: $(date)"
echo "=========================================="

WORKSPACE="/workspace"
cd "$WORKSPACE"

export DEBIAN_FRONTEND=noninteractive

# Basic tools + supervisor + browser
echo "[0/8] Installing base packages..."
apt-get update -qq || true
apt-get install -y -qq git curl wget nodejs npm python3-pip python3-venv ffmpeg libgl1 supervisor jq chromium-browser || apt-get install -y -qq firefox || true

# Start supervisord
if ! pgrep -x supervisord > /dev/null; then
  mkdir -p /etc/supervisor/conf.d
  supervisord -c /etc/supervisor/supervisord.conf || true
  sleep 2
fi

# ========== 1. Ollama (uncensored LLMs) ==========
echo "[1/8] Installing Ollama + uncensored models..."
if ! command -v ollama &> /dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

cat > /etc/supervisor/conf.d/ollama.conf << 'EOF'
[program:ollama]
command=ollama serve
directory=/workspace
autostart=true
autorestart=true
stdout_logfile=/workspace/ollama.log
stderr_logfile=/workspace/ollama.log
user=root
EOF

supervisorctl reread || true
supervisorctl update || true
supervisorctl start ollama || true
sleep 10

ollama pull dolphin-mistral || echo "dolphin-mistral pull failed, continuing..."
echo "Ollama ready on port 11434"

# ========== 2. SillyTavern (main frontend) + auto-config ==========
echo "[2/8] Installing SillyTavern and pre-configuring connections..."
if [ ! -d "$WORKSPACE/SillyTavern" ]; then
  git clone https://github.com/SillyTavern/SillyTavern.git
fi
cd "$WORKSPACE/SillyTavern"
git pull || true
npm install --omit=dev || npm install

mkdir -p data/default-user settings

# Pre-configure settings.json for Ollama + image backends (NSFW ready)
cat > data/default-user/settings.json << 'EOF'
{
  "main_api": "openai",
  "api_server": "http://127.0.0.1:11434/v1",
  "openai_model": "dolphin-mistral",
  "openai_endpoint": "http://127.0.0.1:11434/v1",
  "openai_api_key": "ollama",
  "image_generation_source": "comfy",
  "comfy_url": "http://127.0.0.1:8188",
  "sd_url": "http://127.0.0.1:7860",
  "forge_url": "http://127.0.0.1:7862",
  "enable_extensions": true,
  "extension_settings": {
    "image_generation": {
      "source": "comfy",
      "comfy_url": "http://127.0.0.1:8188",
      "sd_url": "http://127.0.0.1:7860"
    }
  },
  "nsfw_mode": true,
  "allow_nsfw": true
}
EOF

cat > config.yaml << 'EOF'
listen: true
port: 8000
whitelistMode: false
basicAuthMode: false
enableUserAccounts: false
securityOverride: true
EOF

cat > /etc/supervisor/conf.d/sillytavern.conf << 'EOF'
[program:sillytavern]
command=node server.js --listen --port 8000
directory=/workspace/SillyTavern
autostart=true
autorestart=true
stdout_logfile=/workspace/sillytavern.log
stderr_logfile=/workspace/sillytavern.log
user=root
environment=NODE_ENV="production"
EOF

supervisorctl reread || true
supervisorctl update || true
supervisorctl start sillytavern || true
echo "SillyTavern starting on port 8000 (pre-configured for Ollama + ComfyUI/A1111/Forge)"

cd "$WORKSPACE"

# ========== 3. Wan2GP (video generation) ==========
echo "[3/8] Installing Wan2GP..."
if [ ! -d "$WORKSPACE/Wan2GP" ]; then
  git clone https://github.com/deepbeepmeep/Wan2GP.git
fi
cd "$WORKSPACE/Wan2GP"
git pull || true

if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 || \
  pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 || true
pip install -r requirements.txt || echo "Some Wan2GP deps failed; check logs"
deactivate || true

cat > /etc/supervisor/conf.d/wan2gp.conf << 'EOF'
[program:wan2gp]
command=/workspace/Wan2GP/venv/bin/python wgp.py --listen --server-port 7861 --server-name 0.0.0.0
directory=/workspace/Wan2GP
autostart=true
autorestart=true
stdout_logfile=/workspace/wan2gp.log
stderr_logfile=/workspace/wan2gp.log
user=root
EOF

supervisorctl reread || true
supervisorctl update || true
supervisorctl start wan2gp || true
echo "Wan2GP starting on port 7861"

cd "$WORKSPACE"

# ========== 4. ComfyUI ==========
echo "[4/8] Installing ComfyUI..."
if [ ! -d "$WORKSPACE/ComfyUI" ]; then
  git clone https://github.com/comfyanonymous/ComfyUI.git
fi
cd "$WORKSPACE/ComfyUI"
git pull || true
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 || true
pip install -r requirements.txt || true
if [ ! -d "custom_nodes/ComfyUI-Manager" ]; then
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager
fi
deactivate || true

cat > /etc/supervisor/conf.d/comfyui.conf << 'EOF'
[program:comfyui]
command=/workspace/ComfyUI/venv/bin/python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header "*"
directory=/workspace/ComfyUI
autostart=true
autorestart=true
stdout_logfile=/workspace/comfyui.log
stderr_logfile=/workspace/comfyui.log
user=root
EOF

supervisorctl reread || true
supervisorctl update || true
supervisorctl start comfyui || true
echo "ComfyUI starting on port 8188 (CORS enabled)"

cd "$WORKSPACE"

# ========== 5. A1111 (Automatic1111) ==========
echo "[5/8] Installing Automatic1111..."
if [ ! -d "$WORKSPACE/stable-diffusion-webui" ]; then
  git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
fi
cd "$WORKSPACE/stable-diffusion-webui"
git pull || true

echo 'export COMMANDLINE_ARGS="--api --listen --port 7860 --enable-insecure-extension-access --skip-version-check --cors-allow-origins=*"' > webui-user.sh
chmod +x webui.sh webui-user.sh || true

cat > /etc/supervisor/conf.d/a1111.conf << 'EOF'
[program:a1111]
command=bash webui.sh
directory=/workspace/stable-diffusion-webui
autostart=true
autorestart=true
stdout_logfile=/workspace/a1111.log
stderr_logfile=/workspace/a1111.log
user=root
environment=COMMANDLINE_ARGS="--api --listen --port 7860 --enable-insecure-extension-access --skip-version-check --cors-allow-origins=*"
EOF

supervisorctl reread || true
supervisorctl update || true
supervisorctl start a1111 || true
echo "A1111 starting on port 7860"

cd "$WORKSPACE"

# ========== 6. Forge ==========
echo "[6/8] Installing SD Forge..."
if [ ! -d "$WORKSPACE/stable-diffusion-webui-forge" ]; then
  git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git
fi
cd "$WORKSPACE/stable-diffusion-webui-forge"
git pull || true

echo 'export COMMANDLINE_ARGS="--api --listen --port 7862 --enable-insecure-extension-access --skip-version-check --cors-allow-origins=*"' > webui-user.sh
chmod +x webui.sh webui-user.sh || true

cat > /etc/supervisor/conf.d/forge.conf << 'EOF'
[program:forge]
command=bash webui.sh
directory=/workspace/stable-diffusion-webui-forge
autostart=true
autorestart=true
stdout_logfile=/workspace/forge.log
stderr_logfile=/workspace/forge.log
user=root
environment=COMMANDLINE_ARGS="--api --listen --port 7862 --enable-insecure-extension-access --skip-version-check --cors-allow-origins=*"
EOF

supervisorctl reread || true
supervisorctl update || true
supervisorctl start forge || true
echo "Forge starting on port 7862"

cd "$WORKSPACE"

# ========== Shared models directory + symlinks ==========
echo "[Models] Setting up shared models directory..."
mkdir -p "$WORKSPACE/models/checkpoints" "$WORKSPACE/models/loras" "$WORKSPACE/models/vae" || true

# Symlink shared models into each backend (idempotent)
ln -sfn "$WORKSPACE/models/checkpoints" "$WORKSPACE/ComfyUI/models/checkpoints" 2>/dev/null || true
ln -sfn "$WORKSPACE/models/checkpoints" "$WORKSPACE/stable-diffusion-webui/models/Stable-diffusion" 2>/dev/null || true
ln -sfn "$WORKSPACE/models/checkpoints" "$WORKSPACE/stable-diffusion-webui-forge/models/Stable-diffusion" 2>/dev/null || true

echo "Shared models dir ready at /workspace/models/ (drop your NSFW checkpoints here)"

# ========== 7. Readiness wait ==========
echo "[7/8] Waiting for core services to become ready..."
sleep 30

for i in {1..18}; do
  if curl -s --max-time 5 http://127.0.0.1:8000 > /dev/null 2>&1; then
    echo "SillyTavern is responding on 8000"
    break
  fi
  echo "Waiting for SillyTavern... ($i/18)"
  sleep 10
done

if curl -s --max-time 5 http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
  echo "Ollama API responding"
fi

# Jupyter fallback
pip install jupyterlab notebook --quiet || true

# ========== 8. Linux Desktop Shortcut for SillyTavern ==========
echo "[8/8] Creating SillyTavern desktop shortcut..."

mkdir -p /root/Desktop /home/*/Desktop 2>/dev/null || true

DESKTOP_FILE="/root/Desktop/SillyTavern.desktop"
cat > "$DESKTOP_FILE" << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=SillyTavern
Comment=Open SillyTavern AI Chat (NSFW ready)
Exec=sh -c "google-chrome --new-window http://127.0.0.1:8000 || chromium-browser --new-window http://127.0.0.1:8000 || firefox --new-window http://127.0.0.1:8000"
Icon=web-browser
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
DESKTOP_EOF

chmod +x "$DESKTOP_FILE"
cp "$DESKTOP_FILE" /home/*/Desktop/ 2>/dev/null || true

# Trigger desktop refresh for Selkies / XFCE / etc.
mkdir -p /root/.config && touch /root/.config/panel-reload 2>/dev/null || true
( pkill -HUP xfce4-panel 2>/dev/null || true )
( pkill -HUP lxpanel 2>/dev/null || true )

echo "SillyTavern shortcut created on desktop."

echo "=========================================="
echo "Setup complete: $(date)"
echo ""
echo "ALL SERVICES AUTO-STARTED VIA SUPERVISOR:"
echo "  - SillyTavern:  http://127.0.0.1:8000  (pre-connected to Ollama + image backends)"
echo "  - Ollama:       http://127.0.0.1:11434 (dolphin-mistral ready)"
echo "  - Wan2GP:       http://127.0.0.1:7861  (video)"
echo "  - ComfyUI:      http://127.0.0.1:8188  (image, CORS on)"
echo "  - A1111:        http://127.0.0.1:7860  (image, --api)"
echo "  - Forge:        http://127.0.0.1:7862  (image, --api)"
echo ""
echo "SillyTavern is pre-configured for:"
echo "  - LLM: Ollama dolphin-mistral"
echo "  - Image gen: ComfyUI (primary), A1111, Forge"
echo ""
echo "Desktop shortcut is on the desktop."
echo "Control: supervisorctl status | start | stop | restart <name>"
echo "Logs: /workspace/*.log and /workspace/setup.log"
echo "Drop models into /workspace/models/checkpoints/ (symlinked into all backends)"
echo "=========================================="

# Keep container alive
sleep infinity
