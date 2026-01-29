#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Full Lip-sync Test with External TTS
1. Generate audio using Qwen3-TTS
2. Send audio to NewAvata for lip-sync
"""

import socketio
import requests
import time
import json
import sys
import base64
import io

# Server URLs
TTS_URL = "https://rhbwsfctehtfacax.tunnel.elice.io"
NEWAVATA_URL = "https://nzgwjxtxppjpasfr.tunnel.elice.io"

# Create Socket.IO client
sio = socketio.Client()

result_received = False
video_url = None
error_message = None

@sio.event
def connect():
    print(f"[Connected] to NewAvata")

@sio.event
def disconnect():
    print("[Disconnected]")

@sio.on('video_ready')
def on_video_ready(data):
    global result_received, video_url
    print(f"\n[Video Ready!]")
    print(json.dumps(data, indent=2, ensure_ascii=False))
    if 'video_url' in data:
        video_url = data['video_url']
    result_received = True

@sio.on('video_error')
def on_video_error(data):
    global result_received, error_message
    print(f"\n[Video Error]")
    print(json.dumps(data, indent=2, ensure_ascii=False))
    error_message = data.get('error', 'Unknown error')
    result_received = True

@sio.on('generation_progress')
def on_progress(data):
    print(f"[Progress] {data}")

@sio.on('queue_status')
def on_queue(data):
    print(f"[Queue] Position: {data.get('position', '?')}")

@sio.on('tts_complete')
def on_tts_complete(data):
    print(f"[TTS Complete] {data}")

@sio.on('lipsync_progress')
def on_lipsync_progress(data):
    print(f"[Lipsync] {data}")

@sio.on('*')
def catch_all(event, data):
    if event not in ['connected', 'video_ready', 'video_error', 'generation_progress', 'queue_status']:
        print(f"[Event: {event}] {str(data)[:200]}")


def check_server_status():
    """Check both servers and avatar status"""
    print("=== Server Status Check ===\n")

    # TTS Server
    try:
        r = requests.get(f"{TTS_URL}/health", timeout=5)
        if r.status_code == 200:
            print(f"[TTS] OK - Running at {TTS_URL}")
        else:
            print(f"[TTS] ERROR: {r.status_code}")
    except Exception as e:
        print(f"[TTS] ERROR - Not reachable: {e}")
        return False

    # NewAvata Server
    try:
        r = requests.get(f"{NEWAVATA_URL}/api/availability", timeout=5)
        if r.status_code == 200:
            print(f"[NewAvata] OK - Running at {NEWAVATA_URL}")
        else:
            print(f"[NewAvata] ERROR: {r.status_code}")
            return False
    except Exception as e:
        print(f"[NewAvata] ERROR - Not reachable: {e}")
        return False

    # Check avatars
    try:
        r = requests.get(f"{NEWAVATA_URL}/api/avatars", timeout=5)
        avatars = r.json()
        if avatars:
            print(f"[Avatars] OK - Found {len(avatars)} avatar(s)")
            for a in avatars:
                print(f"    - {a.get('name', a)}")
            return True
        else:
            print(f"[Avatars] MISSING - No precomputed avatars found!")
            print("")
            print("  To create an avatar:")
            print("  1. Upload a video to ~/NewAvata/realtime-interview-avatar/assets/")
            print("  2. Run: bash setup_avatar.sh")
            print("  3. Restart NewAvata server")
            return False
    except Exception as e:
        print(f"[Avatars] Error: {e}")
        return False


def generate_tts(text):
    """Generate TTS audio using Qwen3-TTS"""
    print(f"\n[TTS] Generating audio for: '{text[:50]}...'")

    try:
        r = requests.post(
            f"{TTS_URL}/tts/voice_clone",
            json={
                "text": text,
                "ref_audio": "https://github.com/mindvridge/Qwen3-TTS/raw/main/sample(1).mp3",
                "ref_text": "샘플 음성 참조 텍스트입니다."
            },
            timeout=120
        )

        if r.status_code == 200:
            audio_data = r.content
            print(f"[TTS] OK - Generated {len(audio_data)} bytes of audio")
            return audio_data
        else:
            print(f"[TTS] ERROR: {r.status_code} - {r.text[:200]}")
            return None
    except Exception as e:
        print(f"[TTS] ERROR: {e}")
        return None


def test_lipsync_with_tts(text):
    """Test lip-sync using external TTS audio"""
    global result_received, video_url, error_message
    result_received = False
    video_url = None
    error_message = None

    print(f"\n=== Lip-sync Test (External TTS) ===")
    print(f"Text: {text}")
    print(f"TTS: {TTS_URL}")
    print(f"NewAvata: {NEWAVATA_URL}")
    print("")

    # Generate TTS audio first
    audio_data = generate_tts(text)
    if not audio_data:
        print("Failed to generate TTS audio")
        return

    # Convert to base64
    audio_base64 = base64.b64encode(audio_data).decode('utf-8')

    try:
        # Connect to NewAvata
        print("\n[Socket] Connecting to NewAvata...")
        sio.connect(NEWAVATA_URL, transports=['websocket', 'polling'])
        time.sleep(1)

        # Request lip-sync with external audio
        print("[Socket] Sending generate_lipsync with external audio...")
        sio.emit('generate_lipsync', {
            'text': text,
            'avatar_path': 'auto',
            'tts_engine': 'external',
            'audio_data': audio_base64,  # Base64 encoded audio
            'audio_format': 'wav',
            'quality': 'medium'
        })

        # Wait for result
        timeout = 180
        start = time.time()
        while not result_received and time.time() - start < timeout:
            time.sleep(1)
            elapsed = int(time.time() - start)
            if elapsed % 15 == 0 and elapsed > 0:
                print(f"  Waiting... ({elapsed}s)")

        if not result_received:
            print(f"\n[Timeout] No response after {timeout}s")
        elif video_url:
            print(f"\n=== SUCCESS ===")
            print(f"Video URL: {video_url}")
        elif error_message:
            print(f"\n=== FAILED ===")
            print(f"Error: {error_message}")

        sio.disconnect()

    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()


def test_lipsync_simple(text):
    """Test lip-sync with internal TTS (qwen3tts engine)"""
    global result_received, video_url, error_message
    result_received = False
    video_url = None
    error_message = None

    print(f"\n=== Lip-sync Test (Internal TTS) ===")
    print(f"Text: {text}")
    print(f"TTS Engine: qwen3tts")
    print("")

    try:
        print("[Socket] Connecting to NewAvata...")
        sio.connect(NEWAVATA_URL, transports=['websocket', 'polling'])
        time.sleep(1)

        print("[Socket] Sending generate_lipsync...")
        sio.emit('generate_lipsync', {
            'text': text,
            'avatar_path': 'auto',
            'tts_engine': 'qwen3tts',
            'tts_url': TTS_URL,  # Provide TTS server URL
            'quality': 'medium'
        })

        timeout = 180
        start = time.time()
        while not result_received and time.time() - start < timeout:
            time.sleep(1)
            elapsed = int(time.time() - start)
            if elapsed % 15 == 0 and elapsed > 0:
                print(f"  Waiting... ({elapsed}s)")

        if not result_received:
            print(f"\n[Timeout] No response after {timeout}s")
        elif video_url:
            print(f"\n=== SUCCESS ===")
            print(f"Video URL: {video_url}")
        elif error_message:
            print(f"\n=== FAILED ===")
            print(f"Error: {error_message}")

        sio.disconnect()

    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()


def main():
    text = sys.argv[1] if len(sys.argv) > 1 else "안녕하세요, 립싱크 테스트입니다."

    # Check server status first
    has_avatars = check_server_status()

    if not has_avatars:
        print("\n" + "="*50)
        print("Cannot proceed: No avatars available")
        print("="*50)
        print("\nNewAvata requires precomputed avatar files (.pkl)")
        print("to generate lip-sync videos.")
        print("\nTo create an avatar on Elice server:")
        print("  1. SSH into the server")
        print("  2. Run: bash ~/Qwen3-TTS/setup_avatar.sh")
        print("  3. Restart the servers")
        return

    # Test with internal TTS
    test_lipsync_simple(text)


if __name__ == "__main__":
    main()
