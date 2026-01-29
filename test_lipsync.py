#!/usr/bin/env python3
"""
NewAvata Lip-sync Test Script
Tests the lip-sync video generation via Socket.IO
"""

import socketio
import time
import json
import sys

# NewAvata server URL
NEWAVATA_URL = "https://nzgwjxtxppjpasfr.tunnel.elice.io"

# Create Socket.IO client
sio = socketio.Client()

result_received = False
video_url = None

@sio.event
def connect():
    print(f"[Connected] to {NEWAVATA_URL}")

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
    global result_received
    print(f"\n[Video Error]")
    print(json.dumps(data, indent=2, ensure_ascii=False))
    result_received = True

@sio.on('generation_progress')
def on_progress(data):
    print(f"[Progress] {data}")

@sio.on('queue_status')
def on_queue(data):
    print(f"[Queue] {data}")

@sio.on('*')
def catch_all(event, data):
    print(f"[Event: {event}] {data}")

def main():
    global result_received

    text = sys.argv[1] if len(sys.argv) > 1 else "안녕하세요, 립싱크 테스트입니다."

    print(f"=== NewAvata Lip-sync Test ===")
    print(f"Server: {NEWAVATA_URL}")
    print(f"Text: {text}")
    print()

    try:
        # Connect to NewAvata
        print("Connecting...")
        sio.connect(NEWAVATA_URL, transports=['websocket', 'polling'])

        # Wait for connection
        time.sleep(1)

        # Request lip-sync generation
        print("Requesting lip-sync generation...")
        sio.emit('generate_lipsync', {
            'text': text,
            'avatar_path': 'auto',
            'tts_engine': 'external',
            'quality': 'medium'
        })

        # Wait for result (max 120 seconds)
        timeout = 120
        start = time.time()
        while not result_received and time.time() - start < timeout:
            time.sleep(1)
            elapsed = int(time.time() - start)
            if elapsed % 10 == 0:
                print(f"  Waiting... ({elapsed}s)")

        if not result_received:
            print(f"\n[Timeout] No response after {timeout}s")
        elif video_url:
            print(f"\n=== Success ===")
            print(f"Video URL: {video_url}")

        sio.disconnect()

    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
