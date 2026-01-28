# Qwen3-TTS + MuseTalk 통합 가이드

## 아키텍처 개요

### 사용 패턴
- **TTS 단독**: 음성만 생성 (API 응답, 대시보드 등)
- **TTS + MuseTalk**: 음성 + 립싱크 영상 생성 (AI 면접 등)

### 설계 원칙
1. TTS는 **독립적으로 동작** (MuseTalk 없이도 완전 기능)
2. MuseTalk는 **선택적 확장 기능** (필요시에만 설치)
3. 의존성 분리로 **충돌 방지**

---

## 프로젝트 구조

```
Qwen3-TTS/
├── Core (항상 필요)
│   ├── server.py              # 통합 FastAPI 서버
│   ├── config.py              # 설정
│   ├── models.py              # TTS 모델 관리
│   ├── schemas.py             # API 스키마
│   └── requirements.txt       # TTS 의존성
│
├── Optional (MuseTalk 사용 시)
│   ├── requirements-musetalk.txt  # MuseTalk 의존성
│   ├── musetalk/              # Git submodule
│   │   ├── __init__.py
│   │   ├── models/
│   │   └── inference.py
│   └── video_generator.py     # MuseTalk 래퍼
│
├── Deployment
│   ├── .env.example
│   ├── start_server.sh
│   └── ELICE_DEPLOYMENT_GUIDE.md
│
└── Reference
    └── sample(1).mp3
```

---

## 설치 가이드

### 1. TTS만 사용 (기본)

```bash
# 엘리스 AI 클라우드
cd ~
git clone https://github.com/mindvridge/Qwen3-TTS.git
cd Qwen3-TTS

# TTS 의존성만 설치
pip install -r requirements.txt
pip install -U flash-attn --no-build-isolation

# .env 설정
cp .env.example .env
nano .env  # TTS_USE_FLASH_ATTENTION=true

# 서버 시작 (TTS만)
python server.py
```

**활성화되는 엔드포인트:**
- `POST /tts/voice_clone`
- `POST /tts/voice_clone/sse`
- `GET /health`
- `GET /info`

---

### 2. TTS + MuseTalk 사용 (확장)

```bash
# 위의 TTS 설치 후 추가로...

# MuseTalk 의존성 설치
pip install -r requirements-musetalk.txt

# MuseTalk submodule 초기화
git submodule update --init --recursive

# 또는 수동으로 MuseTalk clone
git clone https://github.com/TMElyralab/MuseTalk.git musetalk

# .env에 MuseTalk 활성화
echo "ENABLE_MUSETALK=true" >> .env

# 서버 시작 (TTS + MuseTalk)
python server.py
```

**추가 활성화되는 엔드포인트:**
- `POST /video/generate` - TTS + 립싱크 영상 생성

---

## API 사용 예시

### TTS만 사용
```bash
curl -X POST "http://localhost:8000/tts/voice_clone?model_size=0.6b" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "안녕하세요. 테스트입니다.",
    "language": "Korean",
    "ref_audio": "sample(1).mp3",
    "ref_text": "안녕하세요. 오늘 저의 면접에 참석해 주셔서 감사합니다."
  }' \
  --output audio.wav
```

### TTS + MuseTalk 사용
```bash
curl -X POST "http://localhost:8000/video/generate" \
  -F "text=안녕하세요. 테스트입니다." \
  -F "language=Korean" \
  -F "ref_audio=@sample(1).mp3" \
  -F "ref_text=안녕하세요. 오늘 저의 면접에 참석해 주셔서 감사합니다." \
  -F "avatar_image=@interviewer.jpg" \
  --output video.mp4
```

---

## 구현 상세

### server.py 구조

```python
from fastapi import FastAPI
import config

app = FastAPI()

# TTS 엔드포인트 (항상 활성화)
@app.post("/tts/voice_clone")
async def voice_clone(...):
    # 기존 TTS 로직
    pass

# MuseTalk 엔드포인트 (조건부 활성화)
if config.ENABLE_MUSETALK:
    try:
        from video_generator import VideoGenerator
        video_gen = VideoGenerator()

        @app.post("/video/generate")
        async def generate_video(
            text: str,
            ref_audio: str,
            avatar_image: UploadFile
        ):
            # 1. TTS로 음성 생성
            audio_bytes = await voice_clone(...)

            # 2. MuseTalk로 영상 생성
            video_bytes = video_gen.generate(
                audio=audio_bytes,
                image=avatar_image
            )

            return Response(content=video_bytes, media_type="video/mp4")
    except ImportError:
        print("[WARNING] MuseTalk not installed, /video endpoint disabled")
```

---

## 의존성 관리

### requirements.txt (TTS Core)
```txt
# CUDA 12.4 compatible
torch>=2.5.1
--extra-index-url https://download.pytorch.org/whl/cu124

qwen-tts>=0.0.4
transformers==4.57.3
fastapi==0.128.0
soundfile>=0.12.1
```

### requirements-musetalk.txt (Optional)
```txt
# MuseTalk dependencies
opencv-python>=4.8.0
mmcv>=2.0.0
face-alignment>=1.4.0
# (MuseTalk 필요 패키지 추가)
```

---

## Git Submodule 설정

```bash
# MuseTalk를 submodule로 추가
cd Qwen3-TTS
git submodule add https://github.com/TMElyralab/MuseTalk.git musetalk

# .gitmodules 확인
cat .gitmodules

# 커밋
git add .gitmodules musetalk
git commit -m "Add MuseTalk as optional submodule"
```

---

## .env 설정

```bash
# TTS 설정
TTS_USE_FLASH_ATTENTION=true
TTS_DEVICE=cuda:0
TTS_DTYPE=bfloat16

# MuseTalk 설정 (선택사항)
ENABLE_MUSETALK=true
MUSETALK_MODEL_PATH=musetalk/models
```

---

## 배포 시나리오

### 시나리오 1: TTS만 필요 (대시보드, API)
- A100 40GB: ₩1,380/시간
- 메모리 사용: ~8GB
- 설치 시간: 5분

### 시나리오 2: TTS + MuseTalk (AI 면접)
- A100 80GB: ₩2,000/시간
- 메모리 사용: ~25GB (TTS 8GB + MuseTalk 15GB)
- 설치 시간: 10분

---

## 장점

✅ **TTS 단독 사용 시**
- 가벼운 설치 (불필요한 의존성 없음)
- 빠른 배포
- 낮은 메모리 사용

✅ **TTS + MuseTalk 사용 시**
- 한 번의 API 호출로 음성+영상 생성
- 내부 통신으로 빠른 처리
- 통합 설정 관리

✅ **유지보수**
- MuseTalk 업데이트: `git submodule update --remote`
- 독립적인 디버깅 가능
- 의존성 충돌 최소화

---

## 다음 단계

1. `requirements-musetalk.txt` 작성
2. `video_generator.py` 구현 (MuseTalk 래퍼)
3. `server.py`에 `/video/generate` 엔드포인트 추가
4. Git submodule 설정
5. 엘리스 AI에서 테스트
