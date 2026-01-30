#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NewAvata Lip-sync REST API Test
Uses /api/v2/lipsync endpoint instead of Socket.IO
"""

import requests
import time
import json
import sys

# Server URLs - Auto-detect local vs remote
import os

def detect_newavata_url():
    """Auto-detect NewAvata URL by trying multiple ports"""
    # Check environment variable first
    if os.environ.get('NEWAVATA_URL'):
        return os.environ.get('NEWAVATA_URL')

    # For local/Elice server, try ports 8001 and 5000
    if os.environ.get('LOCAL') == '1' or os.path.exists('/home/elicer'):
        for port in [8001, 5000]:
            try:
                r = requests.get(f'http://localhost:{port}/health', timeout=2)
                if r.status_code == 200:
                    return f'http://localhost:{port}'
            except:
                pass
        return 'http://localhost:8001'  # Default fallback
    else:
        # Remote access via tunnel
        return 'https://nzgwjxtxppjpasfr.tunnel.elice.io'

# Use environment variables if set, otherwise use defaults
if os.environ.get('LOCAL') == '1' or os.path.exists('/home/elicer'):
    TTS_URL = os.environ.get('TTS_URL', 'http://localhost:8000')
    NEWAVATA_URL = detect_newavata_url()
else:
    TTS_URL = os.environ.get('TTS_URL', 'https://rhbwsfctehtfacax.tunnel.elice.io')
    NEWAVATA_URL = os.environ.get('NEWAVATA_URL', 'https://nzgwjxtxppjpasfr.tunnel.elice.io')


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
            return False, []
    except Exception as e:
        print(f"[TTS] ERROR - Not reachable: {e}")
        return False, []

    # NewAvata Server
    try:
        r = requests.get(f"{NEWAVATA_URL}/api/availability", timeout=5)
        if r.status_code == 200:
            print(f"[NewAvata] OK - Running at {NEWAVATA_URL}")
        else:
            print(f"[NewAvata] ERROR: {r.status_code}")
            return False, []
    except Exception as e:
        print(f"[NewAvata] ERROR - Not reachable: {e}")
        return False, []

    # Check avatars
    avatars = []
    try:
        r = requests.get(f"{NEWAVATA_URL}/api/avatars", timeout=5)
        avatars = r.json()
        if avatars:
            print(f"[Avatars] OK - Found {len(avatars)} avatar(s)")
            for a in avatars[:5]:  # Show first 5
                print(f"    - {a.get('name', a)}")
            if len(avatars) > 5:
                print(f"    ... and {len(avatars) - 5} more")
            return True, avatars
        else:
            print(f"[Avatars] MISSING - No precomputed avatars found!")
            return False, []
    except Exception as e:
        print(f"[Avatars] Error: {e}")
        return False, []


def test_lipsync_rest(text, avatar="auto", tts_engine="qwen3tts"):
    """Test lip-sync using REST API"""
    print(f"\n=== Lip-sync REST API Test ===")
    print(f"Text: {text}")
    print(f"Avatar: {avatar}")
    print(f"TTS Engine: {tts_engine}")
    print(f"Endpoint: {NEWAVATA_URL}/api/v2/lipsync")
    print("")

    try:
        print("[Request] Sending lip-sync request...")
        start_time = time.time()

        r = requests.post(
            f"{NEWAVATA_URL}/api/v2/lipsync",
            json={
                "text": text,
                "avatar": avatar,
                "tts_engine": tts_engine,
                "resolution": "480p"       # Lower resolution for faster processing
            },
            timeout=300  # 5 minutes timeout
        )

        elapsed = time.time() - start_time

        if r.status_code == 200:
            result = r.json()
            if result.get('success'):
                print(f"\n=== SUCCESS ({elapsed:.1f}s) ===")
                print(f"Video URL: {NEWAVATA_URL}{result.get('video_url', '')}")
                print(f"Video Path: {result.get('video_path', '')}")
                print(f"Server Elapsed: {result.get('elapsed', 'N/A')}s")
                return result
            else:
                print(f"\n=== FAILED ({elapsed:.1f}s) ===")
                print(f"Error: {result.get('error', 'Unknown error')}")
                return None
        else:
            print(f"\n=== HTTP ERROR ({elapsed:.1f}s) ===")
            print(f"Status: {r.status_code}")
            print(f"Response: {r.text[:500]}")
            return None

    except requests.exceptions.Timeout:
        print(f"\n=== TIMEOUT ===")
        print("Request timed out after 5 minutes")
        return None
    except Exception as e:
        print(f"\n=== ERROR ===")
        print(f"Exception: {e}")
        import traceback
        traceback.print_exc()
        return None


def test_lipsync_with_external_audio(text, avatar="auto"):
    """Test lip-sync with external TTS audio (Qwen3-TTS)"""
    print(f"\n=== Lip-sync with Qwen3-TTS Test ===")
    print(f"Text: {text}")
    print(f"Avatar: {avatar}")
    print("")

    # Step 1: Generate TTS audio
    print("[1/2] Generating TTS audio with Qwen3-TTS...")
    try:
        r = requests.post(
            f"{TTS_URL}/tts/voice_clone",
            json={
                "text": text,
                "ref_audio": "https://github.com/mindvridge/Qwen3-TTS/raw/main/sample(1).mp3",
                "ref_text": "sample reference text"
            },
            timeout=120
        )

        if r.status_code != 200:
            print(f"[TTS] ERROR: {r.status_code} - {r.text[:200]}")
            return None

        audio_data = r.content
        print(f"[TTS] OK - Generated {len(audio_data)} bytes")

    except Exception as e:
        print(f"[TTS] ERROR: {e}")
        return None

    # Step 2: Send audio to NewAvata for lip-sync
    # Note: /api/v2/lipsync doesn't support external audio directly
    # We would need to use a different endpoint or upload the audio first
    print("[2/2] NewAvata doesn't support external audio in REST API directly")
    print("      Use the built-in TTS engines instead (edge, elevenlabs, etc.)")

    return None


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Test NewAvata lip-sync REST API")
    parser.add_argument("text", nargs="?", default="안녕하세요, 립싱크 테스트입니다.", help="Text to synthesize")
    parser.add_argument("--tts", "-t", default="qwen3tts", choices=["qwen3tts", "edge", "elevenlabs"], help="TTS engine to use")
    parser.add_argument("--avatar", "-a", default="auto", help="Avatar name or 'auto'")
    args = parser.parse_args()

    # Check servers
    ok, avatars = check_server_status()

    if not ok:
        print("\n" + "="*50)
        print("Cannot proceed: Server or avatars not available")
        print("="*50)
        return

    # Use first avatar if 'auto' and avatars exist
    avatar = args.avatar
    if avatar == "auto" and avatars:
        avatar = avatars[0].get('name', 'auto')

    # Test REST API
    result = test_lipsync_rest(args.text, avatar, args.tts)

    if result:
        print("\n" + "="*50)
        print("Test completed successfully!")
        print("="*50)


if __name__ == "__main__":
    main()
