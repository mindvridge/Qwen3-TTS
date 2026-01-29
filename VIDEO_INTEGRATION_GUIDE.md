# TTS + 립싱크 비디오 통합 가이드

## 개요

Qwen3-TTS 서버는 **NewAvata 기반 선택적 비디오 생성 기능**을 제공합니다:
- **TTS만**: 음성 생성 API (기본)
- **TTS + 비디오**: 음성 + NewAvata 립싱크 영상 생성 (확장)

**기술 스택:**
- TTS: Qwen3-TTS (0.6B/1.7B)
- 립싱크: NewAvata (https://github.com/mindvridge/NewAvata)
- 통합: FastAPI REST API

**통합 모드:**
- **API 모드** (권장): NewAvata를 별도 서비스로 실행, REST API로 통신
- **임베디드 모드**: MuseTalk을 Qwen3-TTS 프로세스에서 직접 실행

---

## 아키텍처

### TTS 전용 모드 (기본)
```
텍스트 → TTS API → WAV 오디오
```

### TTS + 비디오 모드 (확장)
```
텍스트 + 아바타 이미지 → TTS → 오디오 → NewAvata → MP4 비디오
```

---

## 설치 방법

### 옵션 A: TTS만 사용 (가볍게)

```bash
cd Qwen3-TTS
pip install -r requirements.txt
pip install -U flash-attn --no-build-isolation

# .env 설정
cp .env.example .env
# ENABLE_VIDEO=false (기본값)

python server.py
```

**활성화되는 엔드포인트:**
- `POST /tts/voice_clone` - 음성만 생성
- `POST /tts/voice_clone/sse` - 스트리밍 음성 생성

---

### 옵션 B: TTS + 비디오 사용 - API 모드 (권장, A100 80GB)

**장점:** 메모리 효율적, 독립 스케일링, TensorRT 최적화 포함

```bash
# === 터미널 1: Qwen3-TTS 서버 ===
cd Qwen3-TTS

# 1. TTS 의존성 설치
pip install -r requirements.txt
pip install -U flash-attn --no-build-isolation

# 2. .env 설정 (API 모드)
cp .env.example .env
nano .env
```

`.env` 파일 (API 모드):
```bash
# TTS 설정
TTS_USE_FLASH_ATTENTION=true
TTS_DEVICE=cuda:0
TTS_DTYPE=bfloat16

# 비디오 설정 (API 모드)
ENABLE_VIDEO=true
USE_NEWAVATA_API=true
NEWAVATA_API_URL=http://localhost:8001
VIDEO_AVATAR_DIR=avatars
```

```bash
# 3. 아바타 이미지 준비
mkdir -p avatars
# avatars/ 폴더에 이미지 복사

# 4. TTS 서버 시작 (포트 8000)
python server.py
```

```bash
# === 터미널 2: NewAvata 서버 ===
# 5. NewAvata 클론 및 배포
git clone https://github.com/mindvridge/NewAvata.git
cd NewAvata/realtime-interview-avatar

# 6. A100 최적화 배포 (자동 설정)
chmod +x deploy_a100.sh
./deploy_a100.sh

# 7. NewAvata 서버 시작 (포트 8001)
bash run_server.sh
```

---

### 옵션 C: TTS + 비디오 사용 - 임베디드 모드 (A100 40GB)

**장점:** 단일 프로세스, 설정 간단
**단점:** 메모리 공유로 긴 영상에서 OOM 가능

```bash
cd Qwen3-TTS

# 1. TTS 의존성 설치
pip install -r requirements.txt
pip install -U flash-attn --no-build-isolation

# 2. 비디오 의존성 설치
pip install -r requirements-video.txt

# 3. MuseTalk 클론 및 모델 다운로드
mkdir -p NewAvata
git clone https://github.com/TMElyralab/MuseTalk.git NewAvata/MuseTalk
cd NewAvata/MuseTalk
python scripts/download_models.py
cd ../..

# 4. .env 설정 (임베디드 모드)
cp .env.example .env
nano .env
```

`.env` 파일 (임베디드 모드):
```bash
# TTS 설정
TTS_USE_FLASH_ATTENTION=true
TTS_DEVICE=cuda:0
TTS_DTYPE=bfloat16

# 비디오 설정 (임베디드 모드)
ENABLE_VIDEO=true
USE_NEWAVATA_API=false
NEWAVATA_PATH=NewAvata
VIDEO_AVATAR_DIR=avatars
VIDEO_OUTPUT_DIR=output
```

```bash
# 5. 아바타 디렉토리 생성 및 이미지 추가
mkdir -p avatars
# 아바타 이미지(JPG/PNG)를 avatars/ 폴더에 복사

# 6. 서버 시작
python server.py
```

**추가 활성화되는 엔드포인트:**
- `POST /video/generate` - 음성 + 립싱크 영상 생성
- `GET /video/avatars` - 사용 가능한 아바타 목록

---

## API 사용 예시

### 1. TTS만 사용 (항상 가능)

```bash
curl -X POST "http://localhost:8000/tts/voice_clone?model_size=0.6b" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "안녕하세요. AI 면접관입니다. 먼저 간단히 자기소개를 부탁드립니다.",
    "language": "Korean",
    "ref_audio": "sample(1).mp3",
    "ref_text": "안녕하세요. 오늘 저의 면접에 참석해 주셔서 감사합니다."
  }' \
  --output audio.wav
```

---

### 2. TTS + 비디오 사용 (ENABLE_VIDEO=true 필요)

```bash
curl -X POST "http://localhost:8000/video/generate" \
  -F "text=안녕하세요. AI 면접관입니다. 먼저 간단히 자기소개를 부탁드립니다." \
  -F "language=Korean" \
  -F "ref_audio=sample(1).mp3" \
  -F "ref_text=안녕하세요. 오늘 저의 면접에 참석해 주셔서 감사합니다." \
  -F "avatar_image=@avatars/interviewer.jpg" \
  -F "model_size=0.6b" \
  --output video.mp4
```

---

### 3. 사용 가능한 아바타 목록 조회

```bash
curl http://localhost:8000/video/avatars
```

응답:
```json
{
  "avatars": [
    "interviewer.jpg",
    "doctor.png",
    "teacher.jpg"
  ]
}
```

---

## MuseTalk 통합 구현

### video_generator.py - 구현 완료 ✅

`video_generator.py`는 **MuseTalk API를 사용하여 완전히 구현**되었습니다:

**주요 기능:**
1. **모델 로딩** - MuseTalk VAE, UNet, PE 모델 (lazy loading)
2. **오디오 처리** - Whisper 기반 오디오 피처 추출
3. **립싱크 생성** - 25 FPS, 256×256 해상도
4. **비디오 출력** - MP4 형식, 오디오 임베딩

**사용하는 MuseTalk 모듈:**
```python
from musetalk.utils.utils import load_all_model
from musetalk.inference import inference
```

**생성 파라미터:**
- `bbox_shift=0` - 바운딩 박스 조정
- `extra_margin=10` - 턱 움직임 범위
- `parsing_mode="jaw"` - 턱 중심 파싱 모드

**모델 다운로드:**
```bash
cd NewAvata/MuseTalk
python scripts/download_models.py
# Hugging Face에서 자동 다운로드:
# - musetalk.pth (~3GB)
# - dwpose.pth (~200MB)
# - 기타 모델 파일
```

---

## 리소스 요구사항

### TTS만
- GPU: A100 40GB
- 메모리: ~8GB VRAM
- 시간당 비용: ₩1,380 (엘리스 클라우드)

### TTS + 비디오
- GPU: A100 80GB (권장)
- 메모리: ~25GB VRAM (TTS 8GB + 립싱크 15GB)
- 시간당 비용: ₩2,000 (엘리스 클라우드)

---

## 문제 해결

### 1. MuseTalk를 찾을 수 없음
```
FileNotFoundError: MuseTalk not found at NewAvata/MuseTalk
```

**해결:**
```bash
mkdir -p NewAvata
git clone https://github.com/TMElyralab/MuseTalk.git NewAvata/MuseTalk
cd NewAvata/MuseTalk
python scripts/download_models.py
# .env에서 NEWAVATA_PATH=NewAvata 확인
```

---

### 2. 비디오 엔드포인트가 나타나지 않음
```
[Server] Video generation disabled
```

**원인:**
- `ENABLE_VIDEO=false` (기본값)
- requirements-video.txt 미설치
- MuseTalk 클론 안 함

**해결:**
```bash
# .env 확인
cat .env | grep ENABLE_VIDEO
# ENABLE_VIDEO=true로 설정되어야 함

# 의존성 설치
pip install -r requirements-video.txt

# MuseTalk 확인
ls NewAvata/MuseTalk/
```

---

### 3. MuseTalk 모델 파일을 찾을 수 없음

```
FileNotFoundError: Model file not found
```

**해결:**
```bash
cd NewAvata/MuseTalk
python scripts/download_models.py

# 수동 다운로드 (필요 시)
# Hugging Face에서 다운로드:
# https://huggingface.co/TMElyralab/MuseTalk
```

---

### 4. CUDA out of memory

**원인:** TTS + MuseTalk 동시 실행 시 메모리 부족

**해결:**
```bash
# A100 80GB 사용 (40GB로는 부족할 수 있음)
# 또는 0.6B 모델 사용하여 TTS 메모리 절약
echo "TTS_DEFAULT_MODEL=base_0.6b" >> .env
```

---

## 다음 단계

### 1. 로컬 테스트 (Windows - 선택사항)
- [ ] requirements-video.txt 설치
- [ ] MuseTalk 클론 및 모델 다운로드
- [ ] 아바타 이미지 준비
- [ ] ENABLE_VIDEO=true로 설정
- [ ] 로컬에서 비디오 생성 테스트

### 2. A100 엘리스 AI 배포

**옵션 A: TTS만 먼저 배포 (추천)**
- [ ] VSCode (CUDA 12.4) 환경 선택
- [ ] A100 40GB로 TTS 배포
- [ ] 문장 분할 기능 테스트
- [ ] 음성 품질 확인

**옵션 B: TTS + 비디오 통합 배포**
- [ ] A100 80GB 환경 선택
- [ ] TTS 설치 (requirements.txt)
- [ ] MuseTalk 설치 (requirements-video.txt)
- [ ] 모델 다운로드 (~20GB)
- [ ] 아바타 이미지 업로드
- [ ] ENABLE_VIDEO=true 설정
- [ ] 비디오 생성 테스트

### 3. 프로덕션 최적화 (선택사항)
- [ ] TensorRT 최적화 (MuseTalk 2-4배 속도 향상)
- [ ] 비디오 생성 캐싱
- [ ] 비동기 처리 구현

---

## 참고 자료

- **Qwen3-TTS**: https://github.com/QwenLM/Qwen3-TTS
- **NewAvata**: https://github.com/mindvridge/NewAvata (A100 최적화 립싱크)
- **MuseTalk (원본)**: https://github.com/TMElyralab/MuseTalk
- **엘리스 배포 가이드**: [ELICE_DEPLOYMENT_GUIDE.md](ELICE_DEPLOYMENT_GUIDE.md)

---

## 요약

✅ **완료된 작업:**
- video_generator.py NewAvata API 통합 완료 (API 모드 + 임베디드 모드)
- requirements-video.txt 비디오 의존성 정의
- server.py /video/generate 엔드포인트 구현
- .env.example 비디오 설정 추가 (USE_NEWAVATA_API, NEWAVATA_API_URL)
- 문서 작성 (배포 가이드, 통합 가이드)

📋 **사용 방법:**
1. **TTS만**: `pip install -r requirements.txt` → `python server.py`
2. **TTS + 비디오 (API 모드)**: NewAvata 서버 별도 실행 + `USE_NEWAVATA_API=true`
3. **TTS + 비디오 (임베디드)**: MuseTalk 클론 + `USE_NEWAVATA_API=false`

🎯 **권장 배포 순서:**
1. TTS만 먼저 A100 40GB에 배포하여 검증
2. 검증 완료 후 A100 80GB로 업그레이드
3. NewAvata 별도 배포 (API 모드 권장)

📊 **모드 비교:**
| 모드 | GPU 요구 | 장점 | 단점 |
|------|----------|------|------|
| API 모드 | 80GB 권장 | 독립 스케일링, TensorRT 최적화 | 두 서버 관리 필요 |
| 임베디드 | 40GB 가능 | 단일 프로세스, 간단한 설정 | 메모리 공유, 긴 영상 OOM |

Sources:
- [NewAvata (A100 최적화)](https://github.com/mindvridge/NewAvata)
- [MuseTalk (원본)](https://github.com/TMElyralab/MuseTalk)
