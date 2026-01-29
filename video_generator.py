# coding=utf-8
# Video Generator - TTS + Lip-sync Integration
# Supports two modes:
# 1. Direct MuseTalk integration (embedded)
# 2. NewAvata API integration (external service, recommended for A100)

import os
import sys
import io
import tempfile
import time
import requests
from pathlib import Path
from typing import Union, Optional
import numpy as np
import soundfile as sf

import config


class VideoGenerator:
    """
    Wrapper class for lip-sync video generation.

    Supports two modes:
    1. USE_NEWAVATA_API=true: Calls external NewAvata REST API (recommended)
    2. USE_NEWAVATA_API=false: Runs MuseTalk directly (embedded mode)
    """

    def __init__(self):
        """Initialize VideoGenerator based on configuration."""
        self.avatar_dir = Path(config.VIDEO_AVATAR_DIR)
        self.output_dir = Path(config.VIDEO_OUTPUT_DIR)

        # Create directories if they don't exist
        self.avatar_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Check which mode to use
        self.use_api = config.USE_NEWAVATA_API
        self.api_url = config.NEWAVATA_API_URL

        if self.use_api:
            # API mode - verify NewAvata service is reachable
            self._init_api_mode()
        else:
            # Embedded mode - initialize MuseTalk directly
            self._init_embedded_mode()

    def _init_api_mode(self):
        """Initialize API mode - verify NewAvata service."""
        print(f"[VideoGenerator] Using NewAvata API mode: {self.api_url}")

        try:
            # Check if NewAvata API is available
            response = requests.get(f"{self.api_url}/health", timeout=5)
            if response.status_code == 200:
                print(f"[VideoGenerator] NewAvata API is available")
                self.newavata_available = True
            else:
                print(f"[VideoGenerator] Warning: NewAvata API returned {response.status_code}")
                self.newavata_available = True  # Still allow initialization
        except requests.exceptions.ConnectionError:
            print(f"[VideoGenerator] Warning: NewAvata API not reachable at {self.api_url}")
            print(f"[VideoGenerator] Make sure NewAvata server is running:")
            print(f"  cd NewAvata/realtime-interview-avatar && bash run_server.sh")
            self.newavata_available = True  # Allow initialization, will fail on generate
        except Exception as e:
            print(f"[VideoGenerator] Warning: API check failed: {e}")
            self.newavata_available = True

        self.models_loaded = True  # API mode doesn't need local model loading

    def _init_embedded_mode(self):
        """Initialize embedded mode - load MuseTalk directly."""
        self.newavata_path = Path(config.NEWAVATA_PATH)

        # Check if MuseTalk is available
        musetalk_path = self.newavata_path / "MuseTalk"
        if not musetalk_path.exists():
            raise FileNotFoundError(
                f"MuseTalk not found at {musetalk_path}. "
                f"Please clone it first:\n"
                f"  git clone https://github.com/TMElyralab/MuseTalk.git {musetalk_path}\n"
                f"  cd {musetalk_path}\n"
                f"  python scripts/download_models.py\n\n"
                f"Or use NewAvata API mode by setting USE_NEWAVATA_API=true"
            )

        # Add MuseTalk to Python path
        sys.path.insert(0, str(musetalk_path))

        try:
            # Import MuseTalk modules
            from musetalk.utils.utils import load_all_model
            from musetalk.utils.preprocessing import get_landmark_and_bbox
            from musetalk.utils.blending import get_image

            self.musetalk = {
                'load_all_model': load_all_model,
                'get_landmark_and_bbox': get_landmark_and_bbox,
                'get_image': get_image
            }

            # Load models (lazy loading - only when first inference)
            self.models_loaded = False
            self.newavata_available = True
            print(f"[VideoGenerator] MuseTalk modules loaded from {musetalk_path}")
        except ImportError as e:
            self.newavata_available = False
            raise ImportError(
                f"Failed to import MuseTalk modules: {e}\n"
                f"Make sure dependencies are installed:\n"
                f"  pip install -r requirements-video.txt\n"
                f"  cd {musetalk_path}\n"
                f"  pip install -r requirements.txt"
            )

    def generate(
        self,
        audio_data: Union[bytes, np.ndarray],
        avatar_image_path: Union[str, Path],
        sample_rate: int = 12000,
        output_path: Optional[Union[str, Path]] = None
    ) -> bytes:
        """
        Generate lip-synced video from audio and avatar image.

        Args:
            audio_data: Audio data as bytes (WAV format) or numpy array
            avatar_image_path: Path to avatar image file (JPG/PNG) or avatar name
            sample_rate: Audio sample rate (default: 12000 for Qwen3-TTS)
            output_path: Optional path to save output video (if None, returns bytes)

        Returns:
            Video file as bytes (MP4 format)
        """
        if not self.newavata_available:
            raise RuntimeError("Video generation is not properly initialized")

        if self.use_api:
            return self._generate_via_api(audio_data, avatar_image_path, sample_rate, output_path)
        else:
            return self._generate_embedded(audio_data, avatar_image_path, sample_rate, output_path)

    def _generate_via_api(
        self,
        audio_data: Union[bytes, np.ndarray],
        avatar_image_path: Union[str, Path],
        sample_rate: int,
        output_path: Optional[Union[str, Path]]
    ) -> bytes:
        """Generate video using NewAvata REST API."""
        t0 = time.time()

        # Convert audio to bytes if needed
        if isinstance(audio_data, np.ndarray):
            audio_io = io.BytesIO()
            sf.write(audio_io, audio_data, sample_rate, format='WAV')
            audio_bytes = audio_io.getvalue()
        else:
            audio_bytes = audio_data

        # Resolve avatar path
        avatar_path = Path(avatar_image_path)
        if not avatar_path.is_absolute():
            avatar_path = self.avatar_dir / avatar_path

        if not avatar_path.exists():
            raise FileNotFoundError(f"Avatar not found: {avatar_path}")

        print(f"[VideoGenerator] Calling NewAvata API:")
        print(f"  URL: {self.api_url}/generate")
        print(f"  Avatar: {avatar_path}")
        print(f"  Audio size: {len(audio_bytes)} bytes")

        try:
            # Prepare multipart form data
            files = {
                'audio': ('audio.wav', audio_bytes, 'audio/wav'),
                'avatar': ('avatar.jpg', open(avatar_path, 'rb'), 'image/jpeg')
            }

            # Call NewAvata API
            response = requests.post(
                f"{self.api_url}/generate",
                files=files,
                timeout=300  # 5 minutes timeout for long videos
            )

            if response.status_code != 200:
                error_msg = response.text[:500] if response.text else "Unknown error"
                raise RuntimeError(f"NewAvata API error ({response.status_code}): {error_msg}")

            video_bytes = response.content
            gen_time = time.time() - t0
            print(f"[VideoGenerator] Video generated via API in {gen_time:.2f}s ({len(video_bytes)} bytes)")

            # Save to file if output_path specified
            if output_path:
                with open(output_path, 'wb') as f:
                    f.write(video_bytes)
                print(f"[VideoGenerator] Saved to {output_path}")

            return video_bytes

        except requests.exceptions.ConnectionError:
            raise RuntimeError(
                f"Cannot connect to NewAvata API at {self.api_url}\n"
                f"Make sure the NewAvata server is running:\n"
                f"  cd NewAvata/realtime-interview-avatar && bash run_server.sh"
            )
        except requests.exceptions.Timeout:
            raise RuntimeError("NewAvata API request timed out (>5 minutes)")

    def _generate_embedded(
        self,
        audio_data: Union[bytes, np.ndarray],
        avatar_image_path: Union[str, Path],
        sample_rate: int,
        output_path: Optional[Union[str, Path]]
    ) -> bytes:
        """Generate video using embedded MuseTalk (original implementation)."""
        # Convert audio to temporary file if needed
        if isinstance(audio_data, bytes):
            audio_io = io.BytesIO(audio_data)
            audio_array, sr = sf.read(audio_io)
        elif isinstance(audio_data, np.ndarray):
            audio_array = audio_data
            sr = sample_rate
        else:
            raise ValueError("audio_data must be bytes or numpy array")

        # Create temporary files
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as audio_temp:
            audio_temp_path = audio_temp.name
            sf.write(audio_temp_path, audio_array, sr)

        # Prepare output path
        if output_path is None:
            video_output = tempfile.mktemp(suffix='.mp4')
        else:
            video_output = str(output_path)

        try:
            print(f"[VideoGenerator] Generating lip-sync video (embedded mode):")
            print(f"  Audio: {audio_temp_path}")
            print(f"  Avatar: {avatar_image_path}")
            print(f"  Output: {video_output}")

            # Load MuseTalk models (lazy loading)
            if not self.models_loaded:
                print(f"[VideoGenerator] Loading MuseTalk models (first time)...")
                musetalk_path = self.newavata_path / "MuseTalk"
                sys.path.insert(0, str(musetalk_path))

                from musetalk.utils.utils import load_all_model
                import torch

                # Load models
                audio_processor, vae, unet, pe = load_all_model()
                device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
                timesteps = torch.tensor([0], device=device)

                self.models = {
                    'audio_processor': audio_processor,
                    'vae': vae,
                    'unet': unet,
                    'pe': pe,
                    'device': device,
                    'timesteps': timesteps
                }
                self.models_loaded = True
                print(f"[VideoGenerator] Models loaded successfully")

            # Run MuseTalk inference
            import shutil
            temp_img_dir = tempfile.mkdtemp()
            try:
                # Copy avatar image to temp folder
                temp_img_path = os.path.join(temp_img_dir, "avatar.jpg")
                shutil.copy(str(avatar_image_path), temp_img_path)

                # Run inference using MuseTalk's main function
                from musetalk.inference import inference

                video_output, _ = inference(
                    audio_path=audio_temp_path,
                    video_path=temp_img_dir,
                    bbox_shift=0,
                    extra_margin=10,
                    parsing_mode="jaw"
                )

                print(f"[VideoGenerator] Video generated: {video_output}")

                # Read generated video
                with open(video_output, 'rb') as f:
                    video_bytes = f.read()

                # Clean up temporary video if not saving to output_path
                if output_path is None:
                    os.unlink(video_output)

                return video_bytes

            finally:
                # Clean up temp image directory
                shutil.rmtree(temp_img_dir, ignore_errors=True)

        finally:
            # Clean up temporary audio file
            os.unlink(audio_temp_path)

    def list_avatars(self) -> list:
        """List available avatar images."""
        avatar_files = []
        for ext in ['*.jpg', '*.jpeg', '*.png']:
            avatar_files.extend(self.avatar_dir.glob(ext))
        return sorted([f.name for f in avatar_files])

    def get_avatar_path(self, avatar_name: str) -> Path:
        """Get full path to avatar image."""
        avatar_path = self.avatar_dir / avatar_name
        if not avatar_path.exists():
            raise FileNotFoundError(f"Avatar not found: {avatar_name}")
        return avatar_path


def check_video_support() -> bool:
    """Check if video generation is available."""
    if not config.ENABLE_VIDEO:
        return False

    try:
        VideoGenerator()
        return True
    except (FileNotFoundError, ImportError) as e:
        print(f"[VideoGenerator] Not available: {e}")
        return False
