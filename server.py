# coding=utf-8
# Copyright 2026 The Alibaba Qwen team.
# SPDX-License-Identifier: Apache-2.0
#
# Qwen3-TTS API Server
# Based on Qwen3-TTS examples from https://github.com/QwenLM/Qwen3-TTS

import io
import os
import base64
import time
import tempfile
from typing import List, Union
from contextlib import asynccontextmanager

import torch
import soundfile as sf
import numpy as np
from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles

import config
from models import model_manager
from schemas import (
    CustomVoiceRequest,
    VoiceDesignRequest,
    VoiceCloneRequest,
    TTSResponse,
    ModelInfo,
    HealthResponse,
    GenerationParams,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load models on startup."""
    print("=" * 50)
    print("Qwen3-TTS Server Starting...")
    print(f"Device: {config.DEVICE}")
    print(f"Dtype: {config.DTYPE}")
    print(f"Flash Attention: {config.USE_FLASH_ATTENTION}")
    print("=" * 50)

    # Load default models
    model_manager.load_default_models()

    print("=" * 50)
    print("Server ready!")
    print("=" * 50)
    yield
    print("Server shutting down...")


app = FastAPI(
    title="Qwen3-TTS API Server",
    description="Text-to-Speech API using Qwen3-TTS models",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_generation_kwargs(params: GenerationParams = None) -> dict:
    """Convert generation params to kwargs."""
    if params is None:
        params = GenerationParams()
    return {
        "max_new_tokens": params.max_new_tokens,
        "temperature": params.temperature,
        "top_k": params.top_k,
        "top_p": params.top_p,
        "repetition_penalty": params.repetition_penalty,
        "do_sample": params.do_sample,
    }


def audio_to_base64(wav: np.ndarray, sample_rate: int) -> str:
    """Convert audio array to base64 encoded WAV."""
    buffer = io.BytesIO()
    sf.write(buffer, wav, sample_rate, format="WAV")
    buffer.seek(0)
    return base64.b64encode(buffer.read()).decode("utf-8")


def create_wav_response(wavs: List[np.ndarray], sample_rate: int, single: bool = False):
    """Create response with audio data."""
    if single and len(wavs) == 1:
        # Return single WAV file directly
        buffer = io.BytesIO()
        sf.write(buffer, wavs[0], sample_rate, format="WAV")
        buffer.seek(0)
        return StreamingResponse(
            buffer,
            media_type="audio/wav",
            headers={"Content-Disposition": "attachment; filename=output.wav"}
        )
    else:
        # Return JSON with base64 encoded audio
        audio_data = [audio_to_base64(wav, sample_rate) for wav in wavs]
        return JSONResponse({
            "success": True,
            "message": f"Generated {len(wavs)} audio(s)",
            "sample_rate": sample_rate,
            "audio_count": len(wavs),
            "audio_data": audio_data,
        })


# ============== Health & Info Endpoints ==============

@app.get("/", response_model=HealthResponse)
async def root():
    """Health check endpoint."""
    return HealthResponse(
        status="ok",
        models_loaded=model_manager.get_loaded_models()
    )


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    return HealthResponse(
        status="ok",
        models_loaded=model_manager.get_loaded_models()
    )


@app.get("/info")
async def get_info():
    """Get server and model information."""
    return {
        "loaded_models": model_manager.get_loaded_models(),
        "available_models": list(config.MODELS.keys()),
        "available_speakers": config.AVAILABLE_SPEAKERS,
        "supported_languages": config.SUPPORTED_LANGUAGES,
    }


@app.post("/load/{model_type}")
async def load_model(model_type: str):
    """Load a specific model."""
    try:
        model_manager.load_model(model_type)
        return {"success": True, "message": f"Model {model_type} loaded successfully"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# ============== TTS Endpoints ==============

@app.post("/tts/custom_voice")
async def generate_custom_voice(request: CustomVoiceRequest, model_size: str = "0.6b"):
    """
    Generate speech using custom voice.

    Available speakers: Vivian, Serena, Uncle_Fu, Dylan, Eric, Ryan, Aiden, Ono_Anna, Sohee
    model_size: "0.6b" (faster) or "1.7b" (higher quality)
    """
    try:
        model_key = f"custom_voice_{model_size}" if model_size in ["0.6b", "1.7b"] else "custom_voice"
        model = model_manager.get_model(model_key)
        gen_kwargs = get_generation_kwargs(request.generation_params)

        torch.cuda.synchronize()
        t0 = time.time()

        wavs, sr = model.generate_custom_voice(
            text=request.text,
            language=request.language,
            speaker=request.speaker,
            instruct=request.instruct,
            **gen_kwargs,
        )

        torch.cuda.synchronize()
        t1 = time.time()
        print(f"[CustomVoice] Generated in {t1 - t0:.3f}s")

        single = isinstance(request.text, str)
        return create_wav_response(wavs, sr, single=single)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/tts/voice_design")
async def generate_voice_design(request: VoiceDesignRequest):
    """
    Generate speech using voice design.

    Provide a detailed description of the desired voice characteristics.
    """
    try:
        model = model_manager.get_model("voice_design")
        gen_kwargs = get_generation_kwargs(request.generation_params)

        torch.cuda.synchronize()
        t0 = time.time()

        wavs, sr = model.generate_voice_design(
            text=request.text,
            language=request.language,
            instruct=request.instruct,
            **gen_kwargs,
        )

        torch.cuda.synchronize()
        t1 = time.time()
        print(f"[VoiceDesign] Generated in {t1 - t0:.3f}s")

        single = isinstance(request.text, str)
        return create_wav_response(wavs, sr, single=single)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/tts/voice_clone")
async def generate_voice_clone(request: VoiceCloneRequest, model_size: str = "0.6b"):
    """
    Generate speech by cloning a reference voice.

    Provide reference audio (path or URL) and its transcript.
    model_size: "0.6b" (faster) or "1.7b" (higher quality)
    """
    try:
        model_key = f"base_{model_size}" if model_size in ["0.6b", "1.7b"] else "base"
        model = model_manager.get_model(model_key)
        gen_kwargs = get_generation_kwargs(request.generation_params)

        torch.cuda.synchronize()
        t0 = time.time()

        wavs, sr = model.generate_voice_clone(
            text=request.text,
            language=request.language,
            ref_audio=request.ref_audio,
            ref_text=request.ref_text,
            x_vector_only_mode=request.x_vector_only_mode,
            **gen_kwargs,
        )

        torch.cuda.synchronize()
        t1 = time.time()
        print(f"[VoiceClone] Generated in {t1 - t0:.3f}s")

        single = isinstance(request.text, str)
        return create_wav_response(wavs, sr, single=single)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============== Simple GET endpoints for quick testing ==============

@app.get("/tts/speak")
async def speak(
    text: str,
    speaker: str = "Vivian",
    language: str = "Auto",
    instruct: str = "",
    model_size: str = "0.6b",
):
    """
    Simple GET endpoint for quick TTS testing.

    Example: /tts/speak?text=Hello&speaker=Ryan&language=English&model_size=0.6b
    model_size: "0.6b" (faster) or "1.7b" (higher quality)
    """
    try:
        model_key = f"custom_voice_{model_size}" if model_size in ["0.6b", "1.7b"] else "custom_voice"
        model = model_manager.get_model(model_key)

        wavs, sr = model.generate_custom_voice(
            text=text,
            language=language,
            speaker=speaker,
            instruct=instruct,
            max_new_tokens=config.DEFAULT_MAX_NEW_TOKENS,
        )

        buffer = io.BytesIO()
        sf.write(buffer, wavs[0], sr, format="WAV")
        buffer.seek(0)

        return StreamingResponse(
            buffer,
            media_type="audio/wav",
            headers={"Content-Disposition": f"attachment; filename=speech.wav"}
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============== Web UI ==============

@app.get("/ui")
async def web_ui():
    """Serve the web UI."""
    return FileResponse("web/index.html")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=config.HOST, port=config.PORT)
