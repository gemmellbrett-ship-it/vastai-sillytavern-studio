#!/bin/bash
# Vast.ai One-Click: SillyTavern + Ollama + ComfyUI + Wan2GP
# Fixed: robust Node.js install (NodeSource fallback), better error handling
#
# PROVISIONING_SCRIPT=https://raw.githubusercontent.com/gemmellbrett-ship-it/vastai-sillytavern-studio/main/onstart.sh

set -euo pipefail
exec > >(tee -a /workspace/setup.log) 2>&1

echo "=========================================="
echo "Vast.ai SillyTavern Studio"
echo "Started: $(date)"
echo "=========================================="

WORKSPACE="/workspace"
cd "$WORKSPACE"
export DEBIAN_FRONTEND=noninteractive

# ---------- Robust Node.js + base packages ----------
echo "[0] Installing base packages + Node.js..."
apt-get update -qq || true
apt-get install -y --fix-broken || true

# Try distro nodejs/npm first
if ! command -v npm &>/dev/null; then
  apt-get install -y nodejs npm || true
fi

# Fallback to NodeSource 20 if still missing
if ! command -v npm &>/dev/null; then
  echo "npm missing — installing Node.js 20 from NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || true
  apt-get install -y nodejs || true
fi

# Other packages
apt-get install -y -qq \
  git curl wget \
  python3-pip python3-venv \
  ffmpeg libgl1 \
  supervisor jq \
  chromium-browser || apt-get install -y -qq firefox || true

if command -v npm &>/dev/null; then
  echo "Node $(node -v) / npm $(npm -v) ready"
else
  echo "ERROR: npm still not available"
fi

# ---------- Supervisor ----------
mkdir -p /etc/supervisor/conf.d
if ! pgrep -x supervisord >/dev/null 2>&1; then
  supervisord -c /etc/supervisor/supervisord.conf || true
  sleep 3
fi

# ---------- 1. Ollama ----------
echo "[1] Ollama + dolphin-mistral..."
if ! command -v ollama &>/dev/null; then
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
sleep 15
ollama pull dolphin-mistral || echo "WARNING: dolphin-mistral pull failed"
echo "Ollama started"

# ---------- 2. SillyTavern ----------
echo "[2] SillyTavern..."
if [ ! -d "$WORKSPACE/SillyTavern" ]; then
  git clone https://github.com/SillyTavern/SillyTavern.git
fi
cd "$WORKSPACE/SillyTavern"
git pull || true

if command -v npm &>/dev/null; then
  npm install --omit=dev || npm install || echo "WARNING: npm install failed"
else
  echo "ERROR: npm not available — skipping npm install"
fi

mkdir -p data/default-user

cat > data/default-user/settings.json << 'EOF'
{
  "main_api": "openai",
  "api_server": "http://127.0.0.1:11434/v1",
  "openai_model": "dolphin-mistral",
  "openai_endpoint": "http://127.0.0.1:11434/v1",
  "openai_api_key": "ollama",
  "image_generation_source": "comfy",
  "comfy_url": "http://127.0.0.1:8188",
  "enable_extensions": true,
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
echo "SillyTavern started"
cd "$WORKSPACE"

# ---------- 3. ComfyUI ----------
echo "[3] ComfyUI..."
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
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 || \
  pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 || true
pip install -r requirements.txt || echo "WARNING: some ComfyUI dependencies failed"
if [ ! -d "custom_nodes/ComfyUI-Manager" ]; then
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager
fi
deactivate

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
echo "ComfyUI started"
sleep 8
cd "$WORKSPACE"

# ---------- 4. Wan2GP ----------
echo "[4] Wan2GP..."
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
pip install -r requirements.txt || echo "WARNING: some Wan2GP dependencies failed"
deactivate

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
echo "Wan2GP started"
cd "$WORKSPACE"

# ---------- Shared models ----------
mkdir -p "$WORKSPACE/models/checkpoints" "$WORKSPACE/models/loras" "$WORKSPACE/models/vae"
ln -sfn "$WORKSPACE/models/checkpoints" "$WORKSPACE/ComfyUI/models/checkpoints" 2>/dev/null || true

# ---------- Desktop shortcut ----------
echo "[5] Creating desktop shortcut..."
mkdir -p /root/Desktop /home/*/Desktop 2>/dev/null || true

cat > /root/Desktop/SillyTavern.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=SillyTavern
Comment=Open SillyTavern (NSFW ready)
Exec=sh -c "chromium-browser --new-window http://127.0.0.1:8000 || google-chrome --new-window http://127.0.0.1:8000 || firefox --new-window http://127.0.0.1:8000"
Icon=web-browser
Terminal=false
StartupNotify=true
Categories=Network;
EOF

chmod +x /root/Desktop/SillyTavern.desktop
cp /root/Desktop/SillyTavern.desktop /home/*/Desktop/ 2>/dev/null || true
touch /root/.config/panel-reload 2>/dev/null || true

# ---------- Health check summary ----------
echo ""
echo "[6] Waiting for services..."
sleep 30

echo ""
echo "=========================================="
echo "HEALTH CHECK SUMMARY"
echo "=========================================="

check_port() {
  local name="$1"
  local port="$2"
  if curl -sf --max-time 6 "http://127.0.0.1:${port}" >/dev/null 2>&1; then
    echo "  [OK]   $name  (port $port)"
  else
    echo "  [FAIL] $name  (port $port)"
  fi
}

check_port "SillyTavern" 8000
check_port "Ollama"      11434
check_port "ComfyUI"     8188
check_port "Wan2GP"      7861

echo ""
echo "Models directory : /workspace/models/checkpoints/"
echo "Logs             : /workspace/*.log and /workspace/setup.log"
echo "Control          : supervisorctl status"
echo "=========================================="
echo "Setup finished: $(date)"
echo "=========================================="

sleep infinity
