# coding=utf-8
# Qwen3-TTS API Client Example

import requests
import base64
import json

# Server URL
BASE_URL = "http://localhost:8000"


def save_audio_from_base64(audio_base64: str, filename: str):
    """Save base64 encoded audio to file."""
    audio_data = base64.b64decode(audio_base64)
    with open(filename, "wb") as f:
        f.write(audio_data)
    print(f"Saved: {filename}")


def test_health():
    """Test health endpoint."""
    response = requests.get(f"{BASE_URL}/health")
    print("Health:", response.json())


def test_info():
    """Get server info."""
    response = requests.get(f"{BASE_URL}/info")
    print("Info:", json.dumps(response.json(), indent=2))


def test_custom_voice():
    """Test custom voice generation."""
    print("\n=== Custom Voice Test ===")

    # Single text
    response = requests.post(
        f"{BASE_URL}/tts/custom_voice",
        json={
            "text": "Hello, this is a test of the Qwen3 TTS system.",
            "language": "English",
            "speaker": "Ryan",
            "instruct": "Speak in a friendly tone.",
        }
    )

    if response.headers.get("content-type") == "audio/wav":
        with open("output_custom_voice.wav", "wb") as f:
            f.write(response.content)
        print("Saved: output_custom_voice.wav")
    else:
        result = response.json()
        print(f"Generated {result['audio_count']} audio(s)")
        for i, audio in enumerate(result["audio_data"]):
            save_audio_from_base64(audio, f"output_custom_voice_{i}.wav")


def test_custom_voice_korean():
    """Test Korean custom voice."""
    print("\n=== Korean Custom Voice Test ===")

    response = requests.post(
        f"{BASE_URL}/tts/custom_voice",
        json={
            "text": "안녕하세요, Qwen3 TTS 시스템 테스트입니다.",
            "language": "Korean",
            "speaker": "Sohee",
            "instruct": "",
        }
    )

    if response.headers.get("content-type") == "audio/wav":
        with open("output_korean.wav", "wb") as f:
            f.write(response.content)
        print("Saved: output_korean.wav")


def test_voice_design():
    """Test voice design generation."""
    print("\n=== Voice Design Test ===")

    response = requests.post(
        f"{BASE_URL}/tts/voice_design",
        json={
            "text": "The weather is beautiful today.",
            "language": "English",
            "instruct": "A warm, gentle female voice with a slight British accent, speaking slowly and clearly.",
        }
    )

    if response.headers.get("content-type") == "audio/wav":
        with open("output_voice_design.wav", "wb") as f:
            f.write(response.content)
        print("Saved: output_voice_design.wav")


def test_voice_clone():
    """Test voice clone generation."""
    print("\n=== Voice Clone Test ===")

    # Using example reference audio from Qwen
    response = requests.post(
        f"{BASE_URL}/tts/voice_clone",
        json={
            "text": "Good morning, how are you today?",
            "language": "English",
            "ref_audio": "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo/clone_2.wav",
            "ref_text": "Okay. Yeah. I resent you. I love you. I respect you. But you know what? You blew it! And thanks to you.",
            "x_vector_only_mode": False,
        }
    )

    if response.headers.get("content-type") == "audio/wav":
        with open("output_voice_clone.wav", "wb") as f:
            f.write(response.content)
        print("Saved: output_voice_clone.wav")


def test_simple_speak():
    """Test simple GET endpoint."""
    print("\n=== Simple Speak Test ===")

    response = requests.get(
        f"{BASE_URL}/tts/speak",
        params={
            "text": "This is a quick test.",
            "speaker": "Aiden",
            "language": "English",
        }
    )

    with open("output_simple.wav", "wb") as f:
        f.write(response.content)
    print("Saved: output_simple.wav")


def test_batch():
    """Test batch generation."""
    print("\n=== Batch Generation Test ===")

    response = requests.post(
        f"{BASE_URL}/tts/custom_voice",
        json={
            "text": ["Hello, how are you?", "Goodbye, see you later!"],
            "language": ["English", "English"],
            "speaker": ["Ryan", "Aiden"],
            "instruct": ["Happy tone", "Sad tone"],
        }
    )

    result = response.json()
    print(f"Generated {result['audio_count']} audio(s)")
    for i, audio in enumerate(result["audio_data"]):
        save_audio_from_base64(audio, f"output_batch_{i}.wav")


if __name__ == "__main__":
    print("Qwen3-TTS API Client Example")
    print("=" * 40)

    # Test endpoints
    test_health()
    test_info()

    # Uncomment to test TTS endpoints
    # test_custom_voice()
    # test_custom_voice_korean()
    # test_voice_design()
    # test_voice_clone()
    # test_simple_speak()
    # test_batch()

    print("\nDone! Uncomment test functions to generate audio.")
