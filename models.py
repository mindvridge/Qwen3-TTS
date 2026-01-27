# coding=utf-8
# Qwen3-TTS Model Loader

import torch
from typing import Optional, Dict
from qwen_tts import Qwen3TTSModel

import config


class TTSModelManager:
    """Manages TTS model loading and inference."""

    def __init__(self):
        self.models: Dict[str, Qwen3TTSModel] = {}
        self.device = config.DEVICE
        self.dtype = self._get_dtype()
        self.attn_impl = "flash_attention_2" if config.USE_FLASH_ATTENTION else "sdpa"

    def _get_dtype(self):
        dtype_map = {
            "bfloat16": torch.bfloat16,
            "float16": torch.float16,
            "float32": torch.float32,
        }
        return dtype_map.get(config.DTYPE, torch.bfloat16)

    def load_model(self, model_type: str) -> Qwen3TTSModel:
        """Load a specific model type."""
        if model_type in self.models:
            return self.models[model_type]

        if model_type not in config.MODELS:
            raise ValueError(f"Unknown model type: {model_type}. Available: {list(config.MODELS.keys())}")

        model_path = config.MODELS[model_type]
        print(f"Loading model: {model_type} from {model_path}...")

        model = Qwen3TTSModel.from_pretrained(
            model_path,
            device_map=self.device,
            dtype=self.dtype,
            attn_implementation=self.attn_impl,
        )

        self.models[model_type] = model
        print(f"Model {model_type} loaded successfully!")
        return model

    def get_model(self, model_type: str) -> Qwen3TTSModel:
        """Get a loaded model or load it if not already loaded."""
        if model_type not in self.models:
            return self.load_model(model_type)
        return self.models[model_type]

    def load_default_models(self):
        """Load default models based on configuration."""
        if config.DEFAULT_MODEL == "all":
            for model_type in ["custom_voice", "voice_design", "base"]:
                self.load_model(model_type)
        else:
            self.load_model(config.DEFAULT_MODEL)

    def is_loaded(self, model_type: str) -> bool:
        """Check if a model is loaded."""
        return model_type in self.models

    def get_loaded_models(self) -> list:
        """Get list of loaded model types."""
        return list(self.models.keys())


# Global model manager instance
model_manager = TTSModelManager()
