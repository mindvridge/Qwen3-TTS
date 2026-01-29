# coding=utf-8
# Qwen3-TTS API Schemas

from typing import Optional, List, Union
from pydantic import BaseModel, Field

import config


class GenerationParams(BaseModel):
    """Common generation parameters."""
    max_new_tokens: int = Field(default=config.DEFAULT_MAX_NEW_TOKENS, ge=1, le=4096)
    temperature: float = Field(default=config.DEFAULT_TEMPERATURE, ge=0.0, le=2.0)
    top_k: int = Field(default=config.DEFAULT_TOP_K, ge=1, le=100)
    top_p: float = Field(default=config.DEFAULT_TOP_P, ge=0.0, le=1.0)
    repetition_penalty: float = Field(default=config.DEFAULT_REPETITION_PENALTY, ge=1.0, le=2.0)
    do_sample: bool = True


class VoiceCloneRequest(BaseModel):
    """Request for voice clone generation."""
    text: Union[str, List[str]] = Field(..., description="Text to synthesize")
    language: Union[str, List[str]] = Field(default="Auto", description="Language")
    ref_audio: Union[str, List[str]] = Field(..., description="Reference audio path or URL")
    ref_text: Union[str, List[str]] = Field(..., description="Reference audio transcript")
    x_vector_only_mode: bool = Field(default=False, description="Use x-vector only mode")
    split_sentences: Optional[bool] = Field(default=None, description="Split text into sentences (None = auto-detect, True = always split, False = never split)")
    seed: Optional[int] = Field(default=None, description="Random seed for reproducible output (None = auto-generate)")
    generation_params: Optional[GenerationParams] = None


class HealthResponse(BaseModel):
    """Health check response."""
    status: str
    models_loaded: List[str]
