# coding=utf-8
# Qwen3-TTS Server Configuration

import os
from typing import Optional

# Server settings
HOST = os.getenv("TTS_HOST", "0.0.0.0")
PORT = int(os.getenv("TTS_PORT", "8000"))

# Model settings
DEVICE = os.getenv("TTS_DEVICE", "cuda:0")
DTYPE = os.getenv("TTS_DTYPE", "float16")  # bfloat16, float16, float32
USE_FLASH_ATTENTION = os.getenv("TTS_USE_FLASH_ATTENTION", "false").lower() == "true"
USE_TORCH_COMPILE = os.getenv("TTS_USE_TORCH_COMPILE", "false").lower() == "true"  # Disabled - causes CUDA errors with some configurations
USE_WARMUP = os.getenv("TTS_USE_WARMUP", "false").lower() == "true"  # Disabled by default due to torch.compile compatibility

# Model paths - 1.7B models (higher quality, slower)
MODEL_1_7B_CUSTOM_VOICE = "c:/Qwen3-TTS/models/Qwen3-TTS-12Hz-1.7B-CustomVoice"
MODEL_1_7B_VOICE_DESIGN = "c:/Qwen3-TTS/models/Qwen3-TTS-12Hz-1.7B-VoiceDesign"
MODEL_1_7B_BASE = "c:/Qwen3-TTS/models/Qwen3-TTS-12Hz-1.7B-Base"

# Model paths - 0.6B models (faster, slightly lower quality)
MODEL_0_6B_CUSTOM_VOICE = "c:/Qwen3-TTS/models/Qwen3-TTS-12Hz-0.6B-CustomVoice"
MODEL_0_6B_BASE = "c:/Qwen3-TTS/models/Qwen3-TTS-12Hz-0.6B-Base"

# All available models
MODELS = {
    # 1.7B models
    "custom_voice_1.7b": MODEL_1_7B_CUSTOM_VOICE,
    "voice_design_1.7b": MODEL_1_7B_VOICE_DESIGN,
    "base_1.7b": MODEL_1_7B_BASE,
    # 0.6B models (faster)
    "custom_voice_0.6b": MODEL_0_6B_CUSTOM_VOICE,
    "base_0.6b": MODEL_0_6B_BASE,
    # Aliases for backward compatibility
    "custom_voice": MODEL_1_7B_CUSTOM_VOICE,
    "voice_design": MODEL_1_7B_VOICE_DESIGN,
    "base": MODEL_1_7B_BASE,
}

# Default model to load on startup
DEFAULT_MODEL = os.getenv("TTS_DEFAULT_MODEL", "custom_voice_0.6b")

# Generation defaults
DEFAULT_MAX_NEW_TOKENS = 2048
DEFAULT_TEMPERATURE = 0.9
DEFAULT_TOP_K = 50
DEFAULT_TOP_P = 1.0
DEFAULT_REPETITION_PENALTY = 1.05

# Available speakers for CustomVoice model
AVAILABLE_SPEAKERS = [
    "Vivian",      # Chinese female
    "Serena",      # Chinese female
    "Uncle_Fu",    # Chinese male
    "Dylan",       # Beijing dialect
    "Eric",        # Sichuan dialect
    "Ryan",        # English male
    "Aiden",       # English male
    "Ono_Anna",    # Japanese female
    "Sohee",       # Korean female
]

# Supported languages
SUPPORTED_LANGUAGES = [
    "Auto",
    "Chinese",
    "English",
    "Japanese",
    "Korean",
    "German",
    "French",
    "Russian",
    "Portuguese",
    "Spanish",
    "Italian",
]
