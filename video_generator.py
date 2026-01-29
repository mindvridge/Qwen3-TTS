# coding=utf-8
# Video Generator - NewAvata Lip-sync Integration
# Uses NewAvata's video-based precomputed avatar system
# https://github.com/mindvridge/NewAvata

import os
import time
import uuid
import requests
from pathlib import Path
from typing import Optional, Dict, List, Any

import config


class VideoGenerator:
    """
    NewAvata 립싱크 비디오 생성 래퍼 클래스.

    NewAvata는 영상 기반 사전계산된 아바타를 사용합니다:
    - 아바타 영상 → precompute → .pkl 파일
    - 텍스트 → TTS → 오디오 → 립싱크 → 비디오

    API 모드에서는 NewAvata 서버의 /api/generate 또는 /api/record 엔드포인트를 호출합니다.
    """

    def __init__(self):
        """Initialize VideoGenerator based on configuration."""
        self.use_api = config.USE_NEWAVATA_API
        self.api_url = config.NEWAVATA_API_URL
        self.output_dir = Path(config.VIDEO_OUTPUT_DIR)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        if self.use_api:
            self._init_api_mode()
        else:
            raise RuntimeError(
                "Embedded mode is not supported for video-based NewAvata.\n"
                "Please use API mode by setting USE_NEWAVATA_API=true and running NewAvata server."
            )

    def _init_api_mode(self):
        """Initialize API mode - verify NewAvata service."""
        print(f"[VideoGenerator] Using NewAvata API mode: {self.api_url}")

        try:
            # Check if NewAvata API is available
            response = requests.get(f"{self.api_url}/api/availability", timeout=5)
            if response.status_code == 200:
                data = response.json()
                print(f"[VideoGenerator] NewAvata API is available")
                print(f"  Status: {data}")
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

    def list_avatars(self) -> List[Dict[str, Any]]:
        """
        사용 가능한 아바타 목록 조회.

        Returns:
            아바타 정보 리스트 (name, path, preview 등)
        """
        if not self.use_api:
            return []

        try:
            response = requests.get(f"{self.api_url}/api/avatars", timeout=10)
            if response.status_code == 200:
                return response.json()
            else:
                print(f"[VideoGenerator] Failed to get avatars: {response.status_code}")
                return []
        except Exception as e:
            print(f"[VideoGenerator] Error getting avatars: {e}")
            return []

    def list_tts_engines(self) -> List[Dict[str, Any]]:
        """
        사용 가능한 TTS 엔진 목록 조회.

        Returns:
            TTS 엔진 정보 리스트
        """
        if not self.use_api:
            return []

        try:
            response = requests.get(f"{self.api_url}/api/tts_engines", timeout=10)
            if response.status_code == 200:
                return response.json()
            else:
                return []
        except Exception as e:
            print(f"[VideoGenerator] Error getting TTS engines: {e}")
            return []

    def generate(
        self,
        text: str,
        avatar_path: str = "auto",
        tts_engine: str = "qwen3tts",
        tts_voice: str = "default",
        quality: str = "medium",
        timeout: int = 300
    ) -> Dict[str, Any]:
        """
        립싱크 비디오 생성 (녹화 모드).

        NewAvata의 /api/record 엔드포인트를 사용하여 동기적으로 비디오를 생성합니다.

        Args:
            text: 생성할 텍스트
            avatar_path: 아바타 경로 (precomputed/*.pkl) 또는 "auto"
            tts_engine: TTS 엔진 (qwen3tts, cosyvoice, elevenlabs)
            tts_voice: TTS 음성
            quality: 품질 설정 (low, medium, high)
            timeout: 타임아웃 (초)

        Returns:
            생성 결과 딕셔너리 (success, video_url, audio_url, duration 등)
        """
        if not self.newavata_available:
            raise RuntimeError("NewAvata is not available")

        t0 = time.time()
        session_id = str(uuid.uuid4())[:8]

        print(f"[VideoGenerator] Generating lip-sync video:")
        print(f"  Text: {text[:50]}...")
        print(f"  Avatar: {avatar_path}")
        print(f"  TTS Engine: {tts_engine}")
        print(f"  Quality: {quality}")

        try:
            # Use /api/record for synchronous video generation
            payload = {
                "text": text,
                "avatar_path": avatar_path,
                "tts_engine": tts_engine,
                "tts_voice": tts_voice,
                "quality": quality,
                "sid": session_id,
                "output_format": "mp4"
            }

            response = requests.post(
                f"{self.api_url}/api/record",
                json=payload,
                timeout=timeout
            )

            if response.status_code != 200:
                error_msg = response.text[:500] if response.text else "Unknown error"
                return {
                    "success": False,
                    "error": f"NewAvata API error ({response.status_code}): {error_msg}"
                }

            result = response.json()
            gen_time = time.time() - t0

            print(f"[VideoGenerator] Video generated in {gen_time:.2f}s")
            print(f"  Result: {result}")

            return result

        except requests.exceptions.ConnectionError:
            return {
                "success": False,
                "error": f"Cannot connect to NewAvata API at {self.api_url}"
            }
        except requests.exceptions.Timeout:
            return {
                "success": False,
                "error": f"NewAvata API request timed out (>{timeout}s)"
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e)
            }

    def generate_async(
        self,
        text: str,
        avatar_path: str = "auto",
        tts_engine: str = "qwen3tts",
        tts_voice: str = "default",
        quality: str = "medium"
    ) -> Dict[str, Any]:
        """
        립싱크 비디오 비동기 생성 (큐 시스템).

        NewAvata의 /api/generate 엔드포인트를 사용하여 큐에 요청을 추가합니다.
        결과는 WebSocket을 통해 전달됩니다.

        Args:
            text: 생성할 텍스트
            avatar_path: 아바타 경로 또는 "auto"
            tts_engine: TTS 엔진
            tts_voice: TTS 음성
            quality: 품질 설정

        Returns:
            큐 상태 딕셔너리 (status, position, request_id)
        """
        if not self.newavata_available:
            raise RuntimeError("NewAvata is not available")

        session_id = str(uuid.uuid4())[:8]

        try:
            payload = {
                "text": text,
                "avatar_path": avatar_path,
                "tts_engine": tts_engine,
                "tts_voice": tts_voice,
                "quality": quality,
                "sid": session_id
            }

            response = requests.post(
                f"{self.api_url}/api/generate",
                json=payload,
                timeout=30
            )

            if response.status_code != 200:
                error_msg = response.text[:500] if response.text else "Unknown error"
                return {
                    "success": False,
                    "error": f"NewAvata API error ({response.status_code}): {error_msg}"
                }

            result = response.json()
            result["session_id"] = session_id
            return result

        except Exception as e:
            return {
                "success": False,
                "error": str(e)
            }

    def get_system_status(self) -> Dict[str, Any]:
        """NewAvata 서버 시스템 상태 조회."""
        try:
            response = requests.get(f"{self.api_url}/api/system_status", timeout=10)
            if response.status_code == 200:
                return response.json()
            return {"error": f"Status code: {response.status_code}"}
        except Exception as e:
            return {"error": str(e)}


def check_video_support() -> bool:
    """Check if video generation is available."""
    if not config.ENABLE_VIDEO:
        return False

    if not config.USE_NEWAVATA_API:
        print("[VideoGenerator] Video requires USE_NEWAVATA_API=true")
        return False

    try:
        gen = VideoGenerator()
        return gen.newavata_available
    except Exception as e:
        print(f"[VideoGenerator] Not available: {e}")
        return False
