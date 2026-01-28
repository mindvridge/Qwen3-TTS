# coding=utf-8
# Copyright 2026 The Alibaba Qwen team.
# SPDX-License-Identifier: Apache-2.0
#
# Qwen3-TTS API Server
# Based on Qwen3-TTS examples from https://github.com/QwenLM/Qwen3-TTS

import io
import json
import base64
import time
import re
import os
from typing import List
from contextlib import asynccontextmanager

import torch
import soundfile as sf
import numpy as np
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse, FileResponse

import config
from models import model_manager
from schemas import (
    VoiceCloneRequest,
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

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============== Helpers ==============

def split_into_sentences(text: str) -> List[str]:
    """Split text into sentences for Korean/English."""
    # Korean sentence endings: . ? ! and their combinations
    # Also handle cases like "... " or "?? "
    pattern = r'[.!?]+[\s]+'
    sentences = re.split(pattern, text)
    # Filter out empty strings and strip whitespace
    sentences = [s.strip() for s in sentences if s.strip()]

    # If no split occurred (no sentence endings), return original text
    if len(sentences) == 0:
        sentences = [text.strip()]

    print(f"[DEBUG] Split text into {len(sentences)} sentence(s)")
    for i, sent in enumerate(sentences):
        print(f"[DEBUG] Sentence {i}: '{sent[:50]}...'")

    return sentences


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


def create_wav_response(wavs: List[np.ndarray], sample_rate: int, single: bool = False, generation_time: float = 0.0):
    """Create response with audio data."""
    if single and len(wavs) == 1:
        buffer = io.BytesIO()
        sf.write(buffer, wavs[0], sample_rate, format="WAV")
        buffer.seek(0)
        return StreamingResponse(
            buffer,
            media_type="audio/wav",
            headers={
                "Content-Disposition": "attachment; filename=output.wav",
                "X-Generation-Time": f"{generation_time:.3f}",
                "Access-Control-Expose-Headers": "X-Generation-Time",
            }
        )
    else:
        audio_data = [audio_to_base64(wav, sample_rate) for wav in wavs]
        return JSONResponse({
            "success": True,
            "message": f"Generated {len(wavs)} audio(s)",
            "sample_rate": sample_rate,
            "audio_count": len(wavs),
            "audio_data": audio_data,
            "generation_time": generation_time,
        })


# ============== Health & Info ==============

@app.get("/", response_model=HealthResponse)
async def root():
    return HealthResponse(status="ok", models_loaded=model_manager.get_loaded_models())


@app.get("/health", response_model=HealthResponse)
async def health_check():
    return HealthResponse(status="ok", models_loaded=model_manager.get_loaded_models())


@app.get("/info")
async def get_info():
    return {
        "loaded_models": model_manager.get_loaded_models(),
        "available_models": list(config.MODELS.keys()),
        "available_speakers": config.AVAILABLE_SPEAKERS,
        "supported_languages": config.SUPPORTED_LANGUAGES,
    }


@app.post("/load/{model_type}")
async def load_model(model_type: str):
    try:
        model_manager.load_model(model_type)
        return {"success": True, "message": f"Model {model_type} loaded successfully"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# ============== TTS Endpoints ==============

@app.post("/tts/voice_clone")
async def generate_voice_clone(request: VoiceCloneRequest, model_size: str = "0.6b"):
    """
    Generate speech by cloning a reference voice.

    - model_size: "0.6b" (faster) or "1.7b" (higher quality)

    Splits text into sentences and generates each sentence separately to prevent truncation,
    then concatenates all audio chunks into a single file.
    """
    try:
        model_key = f"base_{model_size}" if model_size in ["0.6b", "1.7b"] else "base"
        model = model_manager.get_model(model_key)
        gen_kwargs = get_generation_kwargs(request.generation_params)

        torch.cuda.synchronize()
        t0 = time.time()

        # Handle single string input
        if isinstance(request.text, str):
            input_text = request.text
            print(f"[DEBUG] Input text: '{input_text[:100]}...'")

            # Split into sentences
            sentences = split_into_sentences(input_text)

            # Generate each sentence separately
            all_wavs = []
            for i, sentence in enumerate(sentences):
                print(f"[DEBUG] Generating sentence {i+1}/{len(sentences)}: '{sentence[:50]}...'")

                wavs, sr = model.generate_voice_clone(
                    text=sentence,
                    language=request.language,
                    ref_audio=request.ref_audio,
                    ref_text=request.ref_text,
                    x_vector_only_mode=request.x_vector_only_mode,
                    non_streaming_mode=True,  # Use non-streaming for single sentences
                    **gen_kwargs,
                )

                # Each sentence returns a list of wavs, take the first one
                if len(wavs) > 0:
                    all_wavs.append(wavs[0])
                    print(f"[DEBUG]   Sentence {i+1} audio: shape={wavs[0].shape}, duration={len(wavs[0])/sr:.2f}s")

            torch.cuda.synchronize()
            gen_time = time.time() - t0

            print(f"[DEBUG] Generated {len(all_wavs)} sentence audio(s)")

            # Concatenate all sentence audios
            if len(all_wavs) > 1:
                print(f"[DEBUG] Concatenating {len(all_wavs)} sentence audios")
                combined = np.concatenate(all_wavs)
                wavs = [combined]
                print(f"[DEBUG] Combined audio duration: {len(combined)/sr:.2f}s")
            elif len(all_wavs) == 1:
                wavs = all_wavs
            else:
                raise ValueError("No audio generated")

            print(f"[VoiceClone] Generated in {gen_time:.3f}s ({len(sentences)} sentence(s))")
            return create_wav_response(wavs, sr, single=True, generation_time=gen_time)

        # Handle list input (original behavior)
        else:
            print(f"[DEBUG] Input text list: {len(request.text)} items")

            wavs, sr = model.generate_voice_clone(
                text=request.text,
                language=request.language,
                ref_audio=request.ref_audio,
                ref_text=request.ref_text,
                x_vector_only_mode=request.x_vector_only_mode,
                non_streaming_mode=True,
                **gen_kwargs,
            )

            torch.cuda.synchronize()
            gen_time = time.time() - t0
            print(f"[VoiceClone] Generated in {gen_time:.3f}s ({len(wavs)} item(s))")
            return create_wav_response(wavs, sr, single=False, generation_time=gen_time)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============== SSE Streaming ==============

@app.post("/tts/voice_clone/sse")
async def voice_clone_sse(request: VoiceCloneRequest, model_size: str = "0.6b", streaming: bool = True):
    """
    Generate TTS via Server-Sent Events.

    Sends progress events (meta, audio, done) for real-time UI updates.
    - streaming: use streaming text processing mode (default: True)
    """
    try:
        model_key = f"base_{model_size}" if model_size in ["0.6b", "1.7b"] else "base"
        model = model_manager.get_model(model_key)
        gen_kwargs = get_generation_kwargs(request.generation_params)

        text = request.text if isinstance(request.text, str) else request.text[0]
        print(f"[SSE VoiceClone] Generating: '{text[:50]}...'")

        async def event_generator():
            t0 = time.time()

            meta = {"status": "generating", "text": text}
            yield f"event: meta\ndata: {json.dumps(meta, ensure_ascii=False)}\n\n"

            torch.cuda.synchronize()

            wavs, sr = model.generate_voice_clone(
                text=text,
                language=request.language if isinstance(request.language, str) else request.language[0],
                ref_audio=request.ref_audio if isinstance(request.ref_audio, str) else request.ref_audio[0],
                ref_text=request.ref_text if isinstance(request.ref_text, str) else request.ref_text[0],
                x_vector_only_mode=request.x_vector_only_mode,
                non_streaming_mode=not streaming,
                **gen_kwargs,
            )

            torch.cuda.synchronize()
            gen_time = time.time() - t0
            print(f"[SSE VoiceClone] Generated in {gen_time:.3f}s")

            audio_b64 = audio_to_base64(wavs[0], sr)
            chunk_data = {
                "chunk_index": 0,
                "audio": audio_b64,
                "sample_rate": sr,
                "generation_time": round(gen_time, 3),
            }
            yield f"event: audio\ndata: {json.dumps(chunk_data, ensure_ascii=False)}\n\n"

            done_data = {"total_time": round(gen_time, 3), "total_chunks": 1}
            yield f"event: done\ndata: {json.dumps(done_data)}\n\n"

        return StreamingResponse(
            event_generator(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "Access-Control-Expose-Headers": "X-Generation-Time",
            }
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============== Video Generation (Optional) ==============

if config.ENABLE_VIDEO:
    try:
        from fastapi import File, UploadFile, Form
        from video_generator import VideoGenerator, check_video_support

        if check_video_support():
            video_gen = VideoGenerator()

            @app.post("/video/generate")
            async def generate_video(
                text: str = Form(...),
                language: str = Form("Korean"),
                ref_audio: str = Form(...),
                ref_text: str = Form(...),
                avatar_image: UploadFile = File(...),
                model_size: str = Form("0.6b"),
                x_vector_only_mode: bool = Form(True)
            ):
                """
                Generate lip-synced video with TTS audio.

                This endpoint combines TTS voice cloning with lip-sync video generation.
                It first generates audio using the TTS model, then creates a video
                with synchronized lip movements using the NewAvata framework.

                Args:
                    text: Text to synthesize
                    language: Language code (e.g., "Korean", "English")
                    ref_audio: Path to reference audio file for voice cloning
                    ref_text: Text spoken in reference audio
                    avatar_image: Avatar image file (JPG/PNG)
                    model_size: TTS model size ("0.6b" or "1.7b")
                    x_vector_only_mode: Use x-vector mode for voice cloning

                Returns:
                    MP4 video file with lip-synced avatar
                """
                try:
                    # Step 1: Generate audio using TTS
                    print(f"[VideoGenerate] Step 1/2: Generating TTS audio")
                    model_key = f"base_{model_size}" if model_size in ["0.6b", "1.7b"] else "base"
                    model = model_manager.get_model(model_key)

                    torch.cuda.synchronize()
                    t0 = time.time()

                    # Split into sentences and generate audio
                    sentences = split_into_sentences(text)
                    all_wavs = []
                    for i, sentence in enumerate(sentences):
                        print(f"[VideoGenerate] Generating sentence {i+1}/{len(sentences)}")
                        wavs, sr = model.generate_voice_clone(
                            text=sentence,
                            language=language,
                            ref_audio=ref_audio,
                            ref_text=ref_text,
                            x_vector_only_mode=x_vector_only_mode,
                            non_streaming_mode=True,
                        )
                        if len(wavs) > 0:
                            all_wavs.append(wavs[0])

                    # Concatenate audio
                    if len(all_wavs) > 1:
                        audio_array = np.concatenate(all_wavs)
                    else:
                        audio_array = all_wavs[0]

                    torch.cuda.synchronize()
                    tts_time = time.time() - t0
                    print(f"[VideoGenerate] TTS completed in {tts_time:.3f}s")

                    # Step 2: Generate video with lip-sync
                    print(f"[VideoGenerate] Step 2/2: Generating lip-sync video")

                    # Save avatar image temporarily
                    import tempfile
                    with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as avatar_temp:
                        avatar_temp_path = avatar_temp.name
                        avatar_temp.write(await avatar_image.read())

                    try:
                        video_bytes = video_gen.generate(
                            audio_data=audio_array,
                            avatar_image_path=avatar_temp_path,
                            sample_rate=sr
                        )

                        torch.cuda.synchronize()
                        total_time = time.time() - t0
                        print(f"[VideoGenerate] Total time: {total_time:.3f}s (TTS: {tts_time:.3f}s)")

                        return StreamingResponse(
                            io.BytesIO(video_bytes),
                            media_type="video/mp4",
                            headers={
                                "Content-Disposition": "attachment; filename=output.mp4",
                                "X-Generation-Time": str(round(total_time, 3)),
                                "X-TTS-Time": str(round(tts_time, 3))
                            }
                        )
                    finally:
                        # Clean up avatar temp file
                        os.unlink(avatar_temp_path)

                except Exception as e:
                    raise HTTPException(status_code=500, detail=str(e))

            @app.get("/video/avatars")
            async def list_avatars():
                """List available avatar images."""
                try:
                    avatars = video_gen.list_avatars()
                    return {"avatars": avatars}
                except Exception as e:
                    raise HTTPException(status_code=500, detail=str(e))

            print("[Server] Video generation endpoints enabled")
        else:
            print("[Server] Video generation not available (check NewAvata installation)")
    except ImportError as e:
        print(f"[Server] Video generation disabled: {e}")


# ============== Web UI ==============

@app.get("/ui")
async def web_ui():
    return FileResponse("web/index.html")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=config.HOST, port=config.PORT)
