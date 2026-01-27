# coding=utf-8
# Qwen3-TTS API Client Library

import requests
import base64
from typing import Optional, Union, List

DEFAULT_BASE_URL = "http://localhost:8000"


class TTSClient:
    """Qwen3-TTS API Client"""

    def __init__(self, base_url: str = DEFAULT_BASE_URL):
        self.base_url = base_url.rstrip("/")

    def speak(
        self,
        text: str,
        speaker: str = "Sohee",
        language: str = "Korean",
        instruct: str = "",
        model_size: str = "0.6b",
        output_file: Optional[str] = None,
    ) -> bytes:
        """
        Simple TTS - convert text to speech.

        Args:
            text: Text to synthesize
            speaker: Speaker name (Vivian, Serena, Ryan, Aiden, Sohee, etc.)
            language: Language (Auto, Korean, English, Chinese, Japanese, etc.)
            instruct: Voice instruction (emotion, tone)
            model_size: "0.6b" (faster) or "1.7b" (higher quality)
            output_file: Save to file path (optional)

        Returns:
            Audio data as bytes
        """
        response = requests.get(
            f"{self.base_url}/tts/speak",
            params={
                "text": text,
                "speaker": speaker,
                "language": language,
                "instruct": instruct,
                "model_size": model_size,
            },
        )
        response.raise_for_status()

        if output_file:
            with open(output_file, "wb") as f:
                f.write(response.content)

        return response.content

    def custom_voice(
        self,
        text: Union[str, List[str]],
        speaker: Union[str, List[str]] = "Sohee",
        language: Union[str, List[str]] = "Korean",
        instruct: Union[str, List[str]] = "",
        model_size: str = "0.6b",
        output_file: Optional[str] = None,
    ) -> bytes:
        """
        Custom voice TTS with more options.

        Args:
            text: Text(s) to synthesize
            speaker: Speaker name(s)
            language: Language(s)
            instruct: Voice instruction(s)
            model_size: "0.6b" or "1.7b"
            output_file: Save to file (for single text only)

        Returns:
            Audio data or JSON response for batch
        """
        response = requests.post(
            f"{self.base_url}/tts/custom_voice",
            params={"model_size": model_size},
            json={
                "text": text,
                "speaker": speaker,
                "language": language,
                "instruct": instruct,
            },
        )
        response.raise_for_status()

        if output_file and isinstance(text, str):
            with open(output_file, "wb") as f:
                f.write(response.content)

        return response.content

    def voice_clone(
        self,
        text: str,
        ref_audio: str,
        ref_text: str = "",
        language: str = "Korean",
        x_vector_only_mode: bool = False,
        model_size: str = "0.6b",
        output_file: Optional[str] = None,
    ) -> bytes:
        """
        Clone a voice from reference audio.

        Args:
            text: Text to synthesize
            ref_audio: Reference audio file path or URL
            ref_text: Transcript of reference audio (optional but recommended)
            language: Language
            x_vector_only_mode: Use x-vector only (faster, no ref_text needed)
            model_size: "0.6b" or "1.7b"
            output_file: Save to file path (optional)

        Returns:
            Audio data as bytes
        """
        response = requests.post(
            f"{self.base_url}/tts/voice_clone",
            params={"model_size": model_size},
            json={
                "text": text,
                "language": language,
                "ref_audio": ref_audio,
                "ref_text": ref_text,
                "x_vector_only_mode": x_vector_only_mode,
            },
        )
        response.raise_for_status()

        if output_file:
            with open(output_file, "wb") as f:
                f.write(response.content)

        return response.content

    def voice_design(
        self,
        text: str,
        instruct: str,
        language: str = "Korean",
        output_file: Optional[str] = None,
    ) -> bytes:
        """
        Generate speech with custom voice design.

        Args:
            text: Text to synthesize
            instruct: Voice design description
            language: Language
            output_file: Save to file path (optional)

        Returns:
            Audio data as bytes
        """
        response = requests.post(
            f"{self.base_url}/tts/voice_design",
            json={
                "text": text,
                "language": language,
                "instruct": instruct,
            },
        )
        response.raise_for_status()

        if output_file:
            with open(output_file, "wb") as f:
                f.write(response.content)

        return response.content

    def load_model(self, model_type: str) -> dict:
        """Load a specific model."""
        response = requests.post(f"{self.base_url}/load/{model_type}")
        response.raise_for_status()
        return response.json()

    def get_info(self) -> dict:
        """Get server information."""
        response = requests.get(f"{self.base_url}/info")
        response.raise_for_status()
        return response.json()

    def health(self) -> dict:
        """Health check."""
        response = requests.get(f"{self.base_url}/health")
        response.raise_for_status()
        return response.json()


# Convenience functions for quick use
_default_client = None


def _get_client():
    global _default_client
    if _default_client is None:
        _default_client = TTSClient()
    return _default_client


def speak(
    text: str,
    speaker: str = "Sohee",
    language: str = "Korean",
    output_file: Optional[str] = None,
    model_size: str = "0.6b",
) -> bytes:
    """Quick TTS function."""
    return _get_client().speak(
        text=text,
        speaker=speaker,
        language=language,
        model_size=model_size,
        output_file=output_file,
    )


def clone(
    text: str,
    ref_audio: str,
    ref_text: str = "",
    language: str = "Korean",
    output_file: Optional[str] = None,
    model_size: str = "0.6b",
) -> bytes:
    """Quick voice clone function."""
    return _get_client().voice_clone(
        text=text,
        ref_audio=ref_audio,
        ref_text=ref_text,
        language=language,
        x_vector_only_mode=(ref_text == ""),
        model_size=model_size,
        output_file=output_file,
    )


# Example usage
if __name__ == "__main__":
    # Method 1: Using functions directly
    print("=== Function API ===")
    speak("안녕하세요, TTS 테스트입니다.", output_file="test_func.wav")
    print("Saved: test_func.wav")

    # Method 2: Using client class
    print("\n=== Client API ===")
    client = TTSClient()

    # Check server info
    info = client.get_info()
    print(f"Loaded models: {info['loaded_models']}")
    print(f"Available speakers: {info['available_speakers']}")

    # Generate speech
    client.speak(
        text="클라이언트 API 테스트입니다.",
        speaker="Sohee",
        language="Korean",
        model_size="0.6b",
        output_file="test_client.wav",
    )
    print("Saved: test_client.wav")
