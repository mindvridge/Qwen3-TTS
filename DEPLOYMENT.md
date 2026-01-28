# Qwen3-TTS A100 서버 배포 가이드

## 환경 요구사항
- **GPU**: NVIDIA A100 (CUDA 12.4)
- **Python**: 3.10 이상
- **OS**: Linux (Ubuntu 20.04/22.04 권장)
- **메모리**: 최소 16GB RAM
- **VRAM**: 최소 12GB (0.6B 모델), 24GB (1.7B 모델)

## 1. 프로젝트 클론 및 설정

```bash
# Git 저장소 클론
cd ~
git clone https://github.com/mindvridge/Qwen3-TTS.git
cd Qwen3-TTS

# Python 가상환경 생성
python3.10 -m venv venv
source venv/bin/activate
```

## 2. CUDA 12.4 환경 확인

```bash
# CUDA 버전 확인
nvcc --version
nvidia-smi

# 출력 예시:
# CUDA Version: 12.4
# GPU: NVIDIA A100-SXM4-40GB
```

## 3. 의존성 설치

```bash
# pip 업그레이드
pip install --upgrade pip

# CUDA 12.4용 PyTorch 및 의존성 설치
pip install -r requirements.txt

# (선택) Flash Attention 2 설치 - A100에서 2~3배 속도 향상
pip install -U flash-attn --no-build-isolation
```

## 4. 모델 다운로드

### 4-1. Hugging Face에서 자동 다운로드 (권장)
서버 시작 시 자동으로 다운로드됩니다. 첫 실행 시 시간이 걸립니다.

### 4-2. 수동 다운로드
```bash
# 0.6B Base 모델 (빠름, 4GB VRAM)
huggingface-cli download Qwen/Qwen3-TTS-12Hz-0.6B-Base --local-dir models/Qwen3-TTS-12Hz-0.6B-Base

# 1.7B Base 모델 (고품질, 6GB VRAM)
huggingface-cli download Qwen/Qwen3-TTS-12Hz-1.7B-Base --local-dir models/Qwen3-TTS-12Hz-1.7B-Base
```

## 5. 설정 파일 수정

### config.py 수정
```python
# Linux 경로로 변경
MODEL_0_6B_BASE = "/home/username/Qwen3-TTS/models/Qwen3-TTS-12Hz-0.6B-Base"
MODEL_1_7B_BASE = "/home/username/Qwen3-TTS/models/Qwen3-TTS-12Hz-1.7B-Base"

# Flash Attention 활성화 (A100에서 큰 속도 향상)
USE_FLASH_ATTENTION = True

# 외부 접속 허용
HOST = "0.0.0.0"
PORT = 8000
```

### sample(1).mp3 경로 업데이트
```python
# web/index.html (344번째 줄 근처)
refAudio: '/home/username/Qwen3-TTS/sample(1).mp3',
```

## 6. 방화벽 설정

```bash
# 포트 8000 개방 (UFW 사용 시)
sudo ufw allow 8000/tcp
sudo ufw reload
```

## 7. 서버 실행

### 개발 모드
```bash
python server.py
```

### 프로덕션 모드 (백그라운드 실행)
```bash
# screen 사용
screen -S qwen-tts
python server.py
# Ctrl+A, D로 detach

# 재접속
screen -r qwen-tts

# 또는 nohup 사용
nohup python server.py > server.log 2>&1 &
```

### systemd 서비스 등록 (권장)
```bash
# /etc/systemd/system/qwen-tts.service 생성
sudo nano /etc/systemd/system/qwen-tts.service
```

내용:
```ini
[Unit]
Description=Qwen3-TTS API Server
After=network.target

[Service]
Type=simple
User=your_username
WorkingDirectory=/home/your_username/Qwen3-TTS
Environment="PATH=/home/your_username/Qwen3-TTS/venv/bin"
ExecStart=/home/your_username/Qwen3-TTS/venv/bin/python server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

서비스 활성화:
```bash
sudo systemctl daemon-reload
sudo systemctl enable qwen-tts
sudo systemctl start qwen-tts
sudo systemctl status qwen-tts
```

## 8. 접속 확인

```bash
# 로컬 확인
curl http://localhost:8000/health

# 원격 확인 (서버 IP가 192.168.1.100인 경우)
curl http://192.168.1.100:8000/health

# Web UI 접속
http://192.168.1.100:8000/ui
```

## 9. 성능 최적화 팁

### A100에서 최대 성능을 위한 설정

1. **Flash Attention 2 활성화** (가장 중요)
   ```python
   USE_FLASH_ATTENTION = True
   ```

2. **bfloat16 사용** (A100 최적화)
   ```python
   DTYPE = "bfloat16"  # A100에서 float16보다 안정적
   ```

3. **배치 크기 조정** (여러 요청 동시 처리 시)
   - 현재는 단일 요청 처리이지만, 필요 시 배치 처리 구현

4. **모니터링**
   ```bash
   # GPU 사용률 모니터링
   watch -n 1 nvidia-smi

   # 서버 로그 실시간 확인
   tail -f server.log
   ```

## 10. 트러블슈팅

### CUDA out of memory
```python
# config.py에서 더 작은 모델 사용
DEFAULT_MODEL = "base_0.6b"  # 1.7b 대신
```

### Flash Attention 설치 실패
```bash
# CUDA toolkit 확인
apt-get install nvidia-cuda-toolkit

# 재시도
MAX_JOBS=4 pip install -U flash-attn --no-build-isolation
```

### 느린 생성 속도
- Flash Attention 활성화 확인
- `nvidia-smi`로 GPU 사용 확인
- 로그에서 `[DEBUG]` 메시지 확인

## 11. 보안 권장사항

1. **방화벽 설정**
   - 특정 IP만 접속 허용

2. **API 키 추가** (선택)
   - FastAPI에서 API key 미들웨어 추가

3. **HTTPS 설정** (프로덕션)
   - Nginx 리버스 프록시 + Let's Encrypt SSL

## 12. 모니터링

```bash
# 서버 상태 확인
systemctl status qwen-tts

# 로그 확인
journalctl -u qwen-tts -f

# GPU 메모리 사용량
nvidia-smi --query-gpu=memory.used,memory.total --format=csv -l 1
```

## 문의
- GitHub Issues: https://github.com/mindvridge/Qwen3-TTS/issues
- 로그 파일: `server.log` (문제 발생 시 첨부)
