# coding=utf-8
# Qwen3-TTS Model Loader

import time
import torch
from typing import Optional, Dict
from qwen_tts import Qwen3TTSModel

import config

# Warmup settings
WARMUP_TEXT = "안녕하세요."


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

        # Apply torch.compile() for faster inference
        if config.USE_TORCH_COMPILE:
            print(f"Applying torch.compile() to {model_type}...")
            try:
                model.model = torch.compile(model.model, mode="reduce-overhead")
                print(f"torch.compile() applied successfully!")
            except Exception as e:
                print(f"torch.compile() failed: {e}")

        self.models[model_type] = model
        print(f"Model {model_type} loaded successfully!")

        # Warmup to trigger JIT compilation
        if config.USE_WARMUP and config.USE_TORCH_COMPILE:
            self._warmup_model(model, model_type)

        return model

    def _warmup_model(self, model: Qwen3TTSModel, model_type: str):
        """Run warmup inference to trigger JIT compilation."""
        print(f"Warming up {model_type}...")
        try:
            import os
            t0 = time.time()
            # Determine which method to use based on model type
            if "base" in model_type:
                # For base models, use a simple reference audio warmup
                # Look for sample audio in the project directory (cross-platform)
                base_dir = os.path.dirname(os.path.abspath(__file__))
                sample_audio = os.path.join(base_dir, "sample(1).mp3")

                # Skip warmup if sample audio doesn't exist
                if not os.path.exists(sample_audio):
                    print(f"Skipping warmup: sample audio not found at {sample_audio}")
                    return

                model.generate_voice_clone(
                    text=WARMUP_TEXT,
                    language="Korean",
                    ref_audio=sample_audio,
                    ref_text="안녕하세요.",
                    x_vector_only_mode=True,
                    max_new_tokens=256,
                )
            else:
                # For custom_voice models
                model.generate_custom_voice(
                    text=WARMUP_TEXT,
                    language="Korean",
                    speaker="Sohee",
                    max_new_tokens=256,
                )
            torch.cuda.synchronize()
            t1 = time.time()
            print(f"Warmup completed in {t1 - t0:.2f}s (subsequent inferences will be faster)")
        except Exception as e:
            print(f"Warmup failed (this is okay): {e}")

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
