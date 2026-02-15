#!/bin/bash
#
# Local AI Stack Installer for Mac Mini
# Sets up: Ollama, Whisper, TTS, OCR, and supporting tools
#
# Usage: curl -fsSL https://raw.githubusercontent.com/yourusername/local-ai-stack/main/install.sh | bash
#

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════╗"
echo "║     Local AI Stack Installer          ║"
echo "║     For Mac Mini M-series             ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "This script is for macOS. For Linux, see install-linux.sh"
    exit 1
fi

# Check for Apple Silicon
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "This script requires Apple Silicon (M1/M2/M3/M4)"
    exit 1
fi

echo -e "${YELLOW}This will install:${NC}"
echo "  • Homebrew (if not installed)"
echo "  • Ollama (local LLM inference)"
echo "  • Python 3.11+ and pip"
echo "  • faster-whisper (speech-to-text)"
echo "  • Piper TTS (text-to-speech)"
echo "  • EasyOCR (document processing)"
echo ""

# Skip prompt if piped (curl | bash) - detect by checking if stdin is a terminal
if [ -t 0 ]; then
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo "Running in non-interactive mode (piped install)..."
fi

# Install Homebrew if needed
if ! command -v brew &> /dev/null; then
    echo -e "${BLUE}Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Install dependencies
echo -e "${BLUE}Installing dependencies...${NC}"
brew install python@3.11 ffmpeg portaudio

# Install Ollama
echo -e "${BLUE}Installing Ollama...${NC}"
if ! command -v ollama &> /dev/null; then
    # Use </dev/null to prevent ollama installer from consuming our stdin
    curl -fsSL https://ollama.com/install.sh | sh </dev/null
fi

# Start Ollama and pull a model
echo -e "${BLUE}Starting Ollama and downloading Llama 3...${NC}"
ollama serve &>/dev/null &
sleep 3
ollama pull llama3:8b

# Create Python virtual environment
echo -e "${BLUE}Setting up Python environment...${NC}"
VENV_DIR="$HOME/.local-ai-stack"
python3.11 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Install Python packages
pip install --upgrade pip
pip install faster-whisper flask easyocr

# Install Piper TTS
echo -e "${BLUE}Installing Piper TTS...${NC}"
pip install piper-tts

# Download a default Piper voice
PIPER_VOICES="$HOME/.local/share/piper-voices"
mkdir -p "$PIPER_VOICES"
if [ ! -f "$PIPER_VOICES/en_US-lessac-medium.onnx" ]; then
    curl -L -o "$PIPER_VOICES/en_US-lessac-medium.onnx" \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx"
    curl -L -o "$PIPER_VOICES/en_US-lessac-medium.onnx.json" \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json"
fi

# Create wrapper scripts
echo -e "${BLUE}Creating helper scripts...${NC}"

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

# Whisper server script
cat > "$BIN_DIR/whisper-server" << 'EOF'
#!/bin/bash
source "$HOME/.local-ai-stack/bin/activate"
python -c "
from flask import Flask, request, jsonify
from faster_whisper import WhisperModel
import tempfile
import os

app = Flask(__name__)
model = WhisperModel('base', device='cpu', compute_type='int8')

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

@app.route('/transcribe', methods=['POST'])
def transcribe():
    if 'file' not in request.files:
        return jsonify({'error': 'No file'}), 400
    f = request.files['file']
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        f.save(tmp.name)
        segments, info = model.transcribe(tmp.name)
        text = ' '.join([s.text for s in segments])
        os.unlink(tmp.name)
        return jsonify({'text': text.strip(), 'language': info.language})

if __name__ == '__main__':
    print('Whisper server running on http://localhost:5115')
    app.run(host='0.0.0.0', port=5115)
"
EOF
chmod +x "$BIN_DIR/whisper-server"

# TTS server script
cat > "$BIN_DIR/tts-server" << 'EOF'
#!/bin/bash
source "$HOME/.local-ai-stack/bin/activate"
python -c "
from flask import Flask, request, jsonify, send_file
import subprocess
import tempfile
import os

app = Flask(__name__)
VOICE = os.path.expanduser('~/.local/share/piper-voices/en_US-lessac-medium.onnx')

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

@app.route('/tts', methods=['POST'])
def tts():
    data = request.get_json()
    text = data.get('text', '')
    if not text:
        return jsonify({'error': 'No text'}), 400
    
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        proc = subprocess.run(
            ['piper', '--model', VOICE, '--output_file', tmp.name],
            input=text.encode(),
            capture_output=True
        )
        if proc.returncode != 0:
            return jsonify({'error': proc.stderr.decode()}), 500
        return send_file(tmp.name, mimetype='audio/wav')

if __name__ == '__main__':
    print('TTS server running on http://localhost:5114')
    app.run(host='0.0.0.0', port=5114)
"
EOF
chmod +x "$BIN_DIR/tts-server"

# OCR server script  
cat > "$BIN_DIR/ocr-server" << 'EOF'
#!/bin/bash
source "$HOME/.local-ai-stack/bin/activate"
python -c "
from flask import Flask, request, jsonify
import easyocr
import tempfile
import os

app = Flask(__name__)
reader = None

def get_reader():
    global reader
    if reader is None:
        reader = easyocr.Reader(['en'])
    return reader

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

@app.route('/ocr', methods=['POST'])
def ocr():
    if 'file' not in request.files:
        return jsonify({'error': 'No file'}), 400
    f = request.files['file']
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp:
        f.save(tmp.name)
        result = get_reader().readtext(tmp.name)
        text = ' '.join([r[1] for r in result])
        os.unlink(tmp.name)
        return jsonify({'text': text})

if __name__ == '__main__':
    print('OCR server running on http://localhost:5117')
    app.run(host='0.0.0.0', port=5117)
"
EOF
chmod +x "$BIN_DIR/ocr-server"

# Start all services script
cat > "$BIN_DIR/ai-stack-start" << 'EOF'
#!/bin/bash
echo "Starting Local AI Stack..."

# Start Ollama
if ! pgrep -x "ollama" > /dev/null; then
    ollama serve &>/dev/null &
    echo "✓ Ollama started (port 11434)"
fi

# Start Whisper
if ! lsof -i:5115 &>/dev/null; then
    nohup ~/.local/bin/whisper-server &>/dev/null &
    echo "✓ Whisper STT started (port 5115)"
fi

# Start TTS
if ! lsof -i:5114 &>/dev/null; then
    nohup ~/.local/bin/tts-server &>/dev/null &
    echo "✓ TTS started (port 5114)"
fi

# Start OCR
if ! lsof -i:5117 &>/dev/null; then
    nohup ~/.local/bin/ocr-server &>/dev/null &
    echo "✓ OCR started (port 5117)"
fi

echo ""
echo "All services running. Test with:"
echo "  curl http://localhost:11434/api/generate -d '{\"model\":\"llama3:8b\",\"prompt\":\"Hello\"}'"
EOF
chmod +x "$BIN_DIR/ai-stack-start"

# Add to PATH if needed
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗"
echo "║     Installation Complete!            ║"
echo "╚═══════════════════════════════════════╝${NC}"
echo ""
echo "To start all services:"
echo "  ai-stack-start"
echo ""
echo "Or start individually:"
echo "  ollama serve          # LLM (port 11434)"
echo "  whisper-server        # STT (port 5115)"
echo "  tts-server            # TTS (port 5114)"
echo "  ocr-server            # OCR (port 5117)"
echo ""
echo "Restart your terminal or run: source ~/.zshrc"
