# TTS + 립싱크 비디오 통합 가이드

## 개요

Qwen3-TTS 서버는 **선택적 비디오 생성 기능**을 제공합니다:
- **TTS만**: 음성 생성 API (기본)
- **TTS + 비디오**: 음성 + 립싱크 영상 생성 (확장)

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

### 옵션 B: TTS + 비디오 사용 (완전 기능)

```bash
cd Qwen3-TTS

# 1. TTS 의존성 설치
pip install -r requirements.txt
pip install -U flash-attn --no-build-isolation

# 2. 비디오 의존성 설치
pip install -r requirements-video.txt

# 3. NewAvata 클론
git clone https://github.com/mindvridge/NewAvata.git

# 4. .env 설정
cp .env.example .env
nano .env
```

`.env` 파일 설정:
```bash
# TTS 설정
TTS_USE_FLASH_ATTENTION=true
TTS_DEVICE=cuda:0
TTS_DTYPE=bfloat16

# 비디오 설정
ENABLE_VIDEO=true
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

## NewAvata 통합 구현

### video_generator.py 수정 필요

현재 `video_generator.py`는 **NewAvata API 호출 부분이 플레이스홀더**로 되어 있습니다.
NewAvata 저장소의 실제 API에 맞게 구현이 필요합니다:

```python
# video_generator.py의 generate() 메서드에서

# PLACEHOLDER 부분을 실제 NewAvata API로 교체:
from newavata import inference  # NewAvata의 실제 모듈 import

video_path = inference.generate_video(
    audio_path=audio_temp_path,
    image_path=str(avatar_image_path),
    output_path=output_path or tempfile.mktemp(suffix='.mp4')
)
```

**NewAvata 저장소 확인 필요:**
1. NewAvata의 주요 추론 함수 확인
2. 필요한 파라미터 확인 (fps, 해상도 등)
3. 모델 파일 다운로드 경로 확인

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

### 1. NewAvata를 찾을 수 없음
```
FileNotFoundError: NewAvata not found at NewAvata
```

**해결:**
```bash
git clone https://github.com/mindvridge/NewAvata.git
# .env에서 NEWAVATA_PATH 확인
```

---

### 2. 비디오 엔드포인트가 나타나지 않음
```
[Server] Video generation disabled
```

**원인:**
- `ENABLE_VIDEO=false` (기본값)
- requirements-video.txt 미설치
- NewAvata 클론 안 함

**해결:**
```bash
# .env 확인
cat .env | grep ENABLE_VIDEO
# true로 설정되어야 함

# 의존성 설치
pip install -r requirements-video.txt

# NewAvata 확인
ls NewAvata/
```

---

### 3. NotImplementedError: NewAvata integration not yet implemented

**현재 상태:**
`video_generator.py`의 NewAvata API 호출이 플레이스홀더입니다.

**해결:**
NewAvata 저장소에서 실제 API 확인 후 구현 필요:

1. NewAvata 저장소 README 확인
2. `inference.py` 또는 `main.py`에서 추론 함수 찾기
3. `video_generator.py`의 `generate()` 메서드 완성

---

## 다음 단계

### 1. NewAvata 저장소 접근 확인
- [ ] https://github.com/mindvridge/NewAvata가 public인지 확인
- [ ] 로컬에 클론 가능한지 테스트

### 2. NewAvata API 확인
- [ ] NewAvata의 주요 추론 함수 식별
- [ ] 필요한 모델 파일 다운로드
- [ ] API 파라미터 확인

### 3. video_generator.py 완성
- [ ] NewAvata API 호출 구현
- [ ] 테스트 실행

### 4. 엘리스 AI 배포
- [ ] TTS만 먼저 배포 및 테스트
- [ ] NewAvata 추가 및 비디오 기능 활성화

---

## 참고 자료

- Qwen3-TTS: https://github.com/QwenLM/Qwen3-TTS
- NewAvata: https://github.com/mindvridge/NewAvata
- 엘리스 배포 가이드: [ELICE_DEPLOYMENT_GUIDE.md](ELICE_DEPLOYMENT_GUIDE.md)
