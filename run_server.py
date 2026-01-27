#!/usr/bin/env python
# coding=utf-8
# Qwen3-TTS Server Launcher

import uvicorn
import config

if __name__ == "__main__":
    print("Starting Qwen3-TTS Server...")
    print(f"Host: {config.HOST}")
    print(f"Port: {config.PORT}")
    print(f"API Docs: http://{config.HOST}:{config.PORT}/docs")

    uvicorn.run(
        "server:app",
        host=config.HOST,
        port=config.PORT,
        reload=False,
        workers=1,  # Single worker for GPU models
    )
