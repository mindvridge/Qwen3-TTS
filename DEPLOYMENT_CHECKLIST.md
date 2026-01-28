# A100 서버 배포 체크리스트

## 배포 전 준비사항

### ✅ 1. 환경 확인
- [ ] A100 GPU 접근 가능 (VSCode CUDA 12.4 환경 선택 완료)
- [ ] Python 3.10+ 설치 확인
- [ ] Git 설치 확인
- [ ] 충분한 디스크 공간 (최소 20GB)

### ✅ 2. 코드 수정 필요 사항

#### config.py 수정
현재 Windows 경로를 Linux 경로로 변경 필요:

```python
# 변경 전 (Windows)
MODEL_0_6B_BASE = "c:/Qwen3-TTS/models/Qwen3-TTS-12Hz-0.6B-Base"

# 변경 후 (Linux)
MODEL_0_6B_BASE = "/home/username/Qwen3-TTS/models/Qwen3-TTS-12Hz-0.6B-Base"
```

또는 환경 변수 사용 (권장):
```python
MODEL_0_6B_BASE = os.getenv("MODEL_0_6B_BASE", "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
```

#### config.py - Flash Attention 활성화
```python
# A100에서 2~3배 속도 향상
USE_FLASH_ATTENTION = True
```

#### web/index.html 수정
Line 344 근처:
```javascript
// 변경 전
refAudio: 'c:/Qwen3-TTS/sample(1).mp3',

// 변경 후
refAudio: '/home/username/Qwen3-TTS/sample(1).mp3',
```

### ✅ 3. 파일 업로드

다음 파일들을 A100 서버로 업로드:
```bash
├── config.py (경로 수정 완료)
├── server.py ✅
├── models.py ✅
├── schemas.py ✅
├── requirements.txt ✅ (CUDA 12.4용으로 업데이트 완료)
├── start_server.bat → start_server.sh (Linux용 스크립트 필요)
├── web/
│   └── index.html (경로 수정 필요)
├── sample(1).mp3 ✅
└── .env.example ✅
```

### ✅ 4. Linux 시작 스크립트 생성

`start_server.sh` 생성 필요:
```bash
#!/bin/bash
echo "============================================"
echo " Qwen3-TTS Server Launcher"
echo "============================================"
echo ""

# Activate virtual environment if exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Kill existing server
echo "[1/2] Stopping existing server..."
pkill -f "python server.py" || true
sleep 2
echo "  Done."
echo ""

# Start server
echo "[2/2] Starting server..."
LOCAL_IP=$(hostname -I | awk '{print $1}')
echo "  Local:  http://localhost:8000"
echo "  LAN:    http://$LOCAL_IP:8000"
echo "  Web UI: http://$LOCAL_IP:8000/ui"
echo ""
echo "============================================"
echo " Press Ctrl+C to stop"
echo "============================================"
echo ""

python server.py
```

### ✅ 5. 배포 단계

#### Step 1: 서버 접속 및 프로젝트 설정
```bash
# VSCode에서 터미널 열기
cd ~
git clone https://github.com/mindvridge/Qwen3-TTS.git
cd Qwen3-TTS

# 가상환경 생성
python3.10 -m venv venv
source venv/bin/activate
```

#### Step 2: 의존성 설치
```bash
pip install --upgrade pip
pip install -r requirements.txt

# Flash Attention 설치 (A100 최적화)
pip install -U flash-attn --no-build-isolation
```

#### Step 3: 설정 파일 수정
```bash
# config.py 편집
nano config.py

# 수정 사항:
# 1. MODEL_*_BASE 경로를 Linux 경로로 변경
# 2. USE_FLASH_ATTENTION = True 설정
# 3. HOST = "0.0.0.0" 확인

# web/index.html 편집
nano web/index.html

# 수정 사항:
# Line 344: refAudio 경로를 Linux 경로로 변경
```

#### Step 4: 서버 실행 테스트
```bash
python server.py

# 다른 터미널에서 테스트
curl http://localhost:8000/health
```

#### Step 5: 프로덕션 배포 (systemd)
```bash
# systemd 서비스 파일 생성
sudo nano /etc/systemd/system/qwen-tts.service

# 내용은 DEPLOYMENT.md 참고

# 서비스 활성화
sudo systemctl daemon-reload
sudo systemctl enable qwen-tts
sudo systemctl start qwen-tts
sudo systemctl status qwen-tts
```

### ✅ 6. 검증

#### 기능 테스트
- [ ] `/health` 엔드포인트 응답 확인
- [ ] `/info` 엔드포인트에서 모델 로딩 확인
- [ ] Web UI 접속 확인 (http://SERVER_IP:8000/ui)
- [ ] 음성 생성 테스트 (긴 문장으로 잘림 현상 없는지 확인)
- [ ] 스트리밍 생성 테스트

#### 성능 테스트
- [ ] Flash Attention 활성화 확인 (로그에서 `flash_attention_2` 확인)
- [ ] 생성 시간 측정 (목표: 5~10초 이내)
- [ ] GPU 메모리 사용량 확인 (`nvidia-smi`)
- [ ] 동시 요청 처리 테스트

### ✅ 7. 모니터링 설정

```bash
# GPU 모니터링
watch -n 1 nvidia-smi

# 서버 로그 실시간 확인
sudo journalctl -u qwen-tts -f

# 또는 nohup 사용 시
tail -f server.log
```

### ✅ 8. 보안

- [ ] 방화벽 설정 (`sudo ufw allow 8000/tcp`)
- [ ] CORS 설정 확인 (필요 시 특정 도메인만 허용)
- [ ] API 키 인증 추가 (선택사항)

## 트러블슈팅

### 모델 경로 오류
```
FileNotFoundError: [Errno 2] No such file or directory: 'c:/Qwen3-TTS/...'
```
**해결**: config.py의 모든 경로를 Linux 형식으로 변경

### Flash Attention 미활성화
로그에 `Using sdpa` 출력 시:
```bash
pip install -U flash-attn --no-build-isolation
# config.py에서 USE_FLASH_ATTENTION = True 확인
```

### CUDA out of memory
```bash
# 더 작은 모델 사용
DEFAULT_MODEL = "base_0.6b"
```

## 완료 후 확인사항

✅ 모든 체크리스트 항목 완료
✅ 서버가 정상 동작 중
✅ 성능 요구사항 충족
✅ 모니터링 설정 완료

배포 완료! 🎉
