# Local AI Stack for Mac Mini

Run your own AI services locally. Stop paying per-API-call rates for routine work.

## What's Included

| Service | Port | What It Does |
|---------|------|--------------|
| Ollama | 11434 | Local LLM inference (Llama 3, Qwen, etc.) |
| Whisper | 5115 | Speech-to-text transcription |
| Piper TTS | 5114 | Text-to-speech synthesis |
| EasyOCR | 5117 | Document text extraction |

## Requirements

- Mac Mini M1/M2/M3/M4 (or any Apple Silicon Mac)
- macOS 13+
- 16GB RAM minimum (more is better for larger models)

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/local-ai-stack/main/install.sh | bash
```

## Manual Install

```bash
git clone https://github.com/yourusername/local-ai-stack.git
cd local-ai-stack
chmod +x install.sh
./install.sh
```

## Usage

Start all services:
```bash
ai-stack-start
```

### LLM Inference
```bash
curl http://localhost:11434/api/generate -d '{
  "model": "llama3:8b",
  "prompt": "Summarize this document..."
}'
```

### Speech-to-Text
```bash
curl -X POST http://localhost:5115/transcribe -F "file=@audio.mp3"
```

### Text-to-Speech
```bash
curl -X POST http://localhost:5114/tts \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello world"}' -o speech.wav
```

### OCR
```bash
curl -X POST http://localhost:5117/ocr -F "file=@document.png"
```

## Cloud Cost Comparison

| Service | Cloud Cost | Local Cost |
|---------|------------|------------|
| Transcription (30 hrs/mo) | $11/mo | $0 |
| TTS (500 min/mo) | $150/mo | $0 |
| LLM calls (routine tasks) | $50-150/mo | $0 |
| OCR (500 pages/mo) | $25/mo | $0 |
| **Total** | **$236-336/mo** | **$0** |

Hardware cost: $400 (base Mac Mini M4)  
Break-even: 5-7 weeks

## Adding More Models

```bash
# Larger LLM for more complex tasks
ollama pull llama3:70b

# Vision model for image analysis
ollama pull llava:13b

# Code-focused model
ollama pull codellama:34b
```

## Troubleshooting

**Port already in use:**
```bash
lsof -i :5115  # Find what's using the port
kill -9 <PID>  # Kill it
```

**Models running slow:**
- Close other applications to free RAM
- Use smaller model variants (8b instead of 70b)
- Check Activity Monitor for memory pressure

## License

MIT
