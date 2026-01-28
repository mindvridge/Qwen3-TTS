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

        # Check if NewAvata is available
        if not self.newavata_path.exists():
            raise FileNotFoundError(
                f"NewAvata not found at {self.newavata_path}. "
                f"Please clone it first:\n"
                f"  git clone https://github.com/mindvridge/NewAvata {self.newavata_path}"
            )

        # Add NewAvata to Python path
        sys.path.insert(0, str(self.newavata_path))

        try:
            # Import NewAvata modules (adjust based on actual NewAvata structure)
            # This is a placeholder - you'll need to adjust based on NewAvata's actual API
            self.newavata_available = True
            print(f"[VideoGenerator] NewAvata loaded from {self.newavata_path}")
        except ImportError as e:
            self.newavata_available = False
            raise ImportError(
                f"Failed to import NewAvata modules: {e}\n"
                f"Make sure NewAvata dependencies are installed:\n"
                f"  pip install -r requirements-video.txt"
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

        try:
            # Generate video using NewAvata
            # PLACEHOLDER: Replace with actual NewAvata API call
            # Example (adjust based on actual NewAvata API):
            # from newavata import generate_video
            # video_path = generate_video(
            #     audio_path=audio_temp_path,
            #     image_path=str(avatar_image_path),
            #     output_path=output_path or tempfile.mktemp(suffix='.mp4')
            # )

            print(f"[VideoGenerator] Generating video:")
            print(f"  Audio: {audio_temp_path}")
            print(f"  Avatar: {avatar_image_path}")
            print(f"  Output: {output_path or 'memory'}")

            # For now, raise an error to indicate integration is needed
            raise NotImplementedError(
                "NewAvata integration not yet implemented. "
                "Please implement the actual API call in video_generator.py"
            )

            # Read generated video
            # with open(video_path, 'rb') as f:
            #     video_bytes = f.read()

            # Clean up temporary video if not saving
            # if output_path is None:
            #     os.unlink(video_path)

            # return video_bytes

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
