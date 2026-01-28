# coding=utf-8
# Video Generator - TTS + Lip-sync Integration
# Wrapper for NewAvata (https://github.com/mindvridge/NewAvata)

import os
import sys
import io
import tempfile
from pathlib import Path
from typing import Union, Optional
import numpy as np
import soundfile as sf

import config


class VideoGenerator:
    """
    Wrapper class for NewAvata lip-sync video generation.

    This class integrates TTS-generated audio with avatar images to create
    lip-synced videos using the NewAvata framework.
    """

    def __init__(self):
        """Initialize VideoGenerator and check NewAvata availability."""
        self.newavata_path = Path(config.NEWAVATA_PATH)
        self.avatar_dir = Path(config.VIDEO_AVATAR_DIR)
        self.output_dir = Path(config.VIDEO_OUTPUT_DIR)

        # Create directories if they don't exist
        self.avatar_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Check if MuseTalk is available
        musetalk_path = self.newavata_path / "MuseTalk"
        if not musetalk_path.exists():
            raise FileNotFoundError(
                f"MuseTalk not found at {musetalk_path}. "
                f"Please clone it first:\n"
                f"  git clone https://github.com/TMElyralab/MuseTalk.git {musetalk_path}\n"
                f"  cd {musetalk_path}\n"
                f"  python scripts/download_models.py"
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
            avatar_image_path: Path to avatar image file (JPG/PNG)
            sample_rate: Audio sample rate (default: 12000 for Qwen3-TTS)
            output_path: Optional path to save output video (if None, returns bytes)

        Returns:
            Video file as bytes (MP4 format)
        """
        if not self.newavata_available:
            raise RuntimeError("NewAvata is not properly initialized")

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
            print(f"[VideoGenerator] Generating lip-sync video:")
            print(f"  Audio: {audio_temp_path}")
            print(f"  Avatar: {avatar_image_path}")
            print(f"  Output: {video_output}")

            # Load MuseTalk models (lazy loading)
            if not self.models_loaded:
                print(f"[VideoGenerator] Loading MuseTalk models (first time)...")
                musetalk_path = self.newavata_path / "MuseTalk"
                sys.path.insert(0, str(musetalk_path))

                from musetalk.utils.utils import load_all_model
                from musetalk.utils.preprocessing import get_landmark_and_bbox, coord_placeholder
                from musetalk.utils.blending import get_image
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
            from musetalk.utils.utils import datagen

            # Prepare input
            # MuseTalk expects a video path or image folder
            # Since we have a single image, create a temp folder with the image
            import shutil
            temp_img_dir = tempfile.mkdtemp()
            try:
                # Copy avatar image to temp folder
                temp_img_path = os.path.join(temp_img_dir, "avatar.jpg")
                shutil.copy(str(avatar_image_path), temp_img_path)

                # Run inference using MuseTalk's main function
                # Note: This is a simplified version - you may need to adjust parameters
                from musetalk.inference import inference

                video_output, _ = inference(
                    audio_path=audio_temp_path,
                    video_path=temp_img_dir,  # Use image folder
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
