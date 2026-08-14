#!/usr/bin/env bash
set -euo pipefail

# Installs the local voice-output helper: a Python venv with mlx-audio serving
# Chatterbox Turbo over an OpenAI-compatible endpoint. Apple Silicon only.
#
# The app looks for the helper at:
#   ~/Library/Application Support/Suniye/voice-helper/venv/bin/python3
# or the SUNIYE_VOICE_HELPER_PYTHON override.
#
# A frozen (PyInstaller) bundle replaces this for release packaging; this
# script is the development and early-adopter path, mirroring
# setup_llama_cpp.sh for the Gemma helper.

MODEL_ID="mlx-community/chatterbox-turbo-8bit"
HELPER_DIR="${HOME}/Library/Application Support/Suniye/voice-helper"
VENV_DIR="${HELPER_DIR}/venv"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Voice output requires Apple Silicon (MLX)." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required (brew install python)." >&2
  exit 1
fi

echo "[1/3] Creating venv at ${VENV_DIR}"
mkdir -p "${HELPER_DIR}"
python3 -m venv "${VENV_DIR}"

echo "[2/3] Installing mlx-audio"
"${VENV_DIR}/bin/pip" install --quiet --upgrade pip
# mlx-audio's base package omits its server dependencies; webrtcvad needs
# pkg_resources, gone from setuptools 81+.
"${VENV_DIR}/bin/pip" install --quiet mlx-audio fastapi uvicorn python-multipart webrtcvad soundfile "setuptools<81"

echo "[3/3] Prefetching ${MODEL_ID} (~700 MB)"
"${VENV_DIR}/bin/python3" - << EOF
from huggingface_hub import snapshot_download
snapshot_download("${MODEL_ID}")
print("model cached")
EOF

echo "Voice helper installed. Enable Voice Output in Computer Use settings."
