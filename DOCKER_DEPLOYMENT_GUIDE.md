# Docker 배포 가이드

## 개요

Qwen3-TTS 서버를 Docker로 배포하는 가이드입니다.

**장점:**
- 환경 일관성 (Windows/Linux 동일)
- 의존성 격리
- 간단한 배포 및 스케일링
- GPU 최적화 (CUDA 12.4 + cuDNN9)

---

## 사전 요구사항

### 1. Docker 설치

**Ubuntu/Linux:**
```bash
# Docker 설치
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Docker Compose 설치
sudo apt-get install docker-compose-plugin

# 현재 사용자를 docker 그룹에 추가
sudo usermod -aG docker $USER
newgrp docker
```

**Windows:**
- Docker Desktop 설치: https://www.docker.com/products/docker-desktop/
- WSL2 활성화 필요

### 2. NVIDIA Container Toolkit 설치 (GPU 사용)

```bash
# NVIDIA Container Toolkit 설치
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker

# GPU 동작 확인
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

---

## 배포 옵션

### 옵션 A: TTS만 (기본) - 추천

가장 빠르고 간단한 배포 방법입니다.

```bash
cd Qwen3-TTS

# 1. 환경 설정
cp .env.example .env
# 필요 시 .env 파일 수정

# 2. Docker 이미지 빌드
docker-compose build

# 3. 서버 실행
docker-compose up -d

# 4. 로그 확인
docker-compose logs -f

# 5. 동작 확인
curl http://localhost:8000/health
```

**리소스 요구사항:**
- GPU: RTX 3060+ / A100 40GB
- VRAM: ~8GB
- 디스크: ~10GB

---

### 옵션 B: TTS + 비디오 (확장)

립싱크 비디오 생성을 포함한 완전한 배포입니다.

#### 1. 사전 준비

```bash
cd Qwen3-TTS

# MuseTalk 클론 (아직 안 했다면)
mkdir -p NewAvata
git clone https://github.com/TMElyralab/MuseTalk.git NewAvata/MuseTalk

# MuseTalk 모델 다운로드 (Linux)
cd NewAvata/MuseTalk
./download_weights.sh
cd ../..

# Windows에서는:
# cd NewAvata/MuseTalk
# download_weights.bat
# cd ../..

# 아바타 이미지 준비
mkdir -p avatars
# JPG/PNG 이미지를 avatars/ 폴더에 복사
```

#### 2. Docker 빌드 및 실행

```bash
# 환경 설정
cp .env.example .env
nano .env  # ENABLE_VIDEO=true 설정

# Docker 이미지 빌드 (비디오 포함)
docker-compose -f docker-compose.yml -f docker-compose.video.yml build

# 서버 실행
docker-compose -f docker-compose.yml -f docker-compose.video.yml up -d

# 로그 확인
docker-compose logs -f

# 동작 확인
curl http://localhost:8000/health
curl http://localhost:8000/video/avatars
```

**리소스 요구사항:**
- GPU: A100 80GB (권장)
- VRAM: ~25GB
- 디스크: ~30GB (모델 포함)

---

## 배포 후 확인

### Health Check
```bash
curl http://localhost:8000/health
```

예상 응답:
```json
{
  "status": "ok",
  "models_loaded": ["base_0.6b"]
}
```

### API 테스트 (TTS)
```bash
curl -X POST "http://localhost:8000/tts/voice_clone?model_size=0.6b" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "안녕하세요. 테스트입니다.",
    "language": "Korean",
    "ref_audio": "sample(1).mp3",
    "ref_text": "안녕하세요. 오늘 저의 면접에 참석해 주셔서 감사합니다."
  }' \
  --output test.wav
```

### API 테스트 (비디오 - 옵션 B만)
```bash
curl -X POST "http://localhost:8000/video/generate" \
  -F "text=안녕하세요. 테스트입니다." \
  -F "language=Korean" \
  -F "ref_audio=sample(1).mp3" \
  -F "ref_text=안녕하세요. 오늘 저의 면접에 참석해 주셔서 감사합니다." \
  -F "avatar_image=@avatars/interviewer.jpg" \
  --output test.mp4
```

---

## Docker 관리 명령어

### 기본 명령어
```bash
# 서버 시작
docker-compose up -d

# 서버 중지
docker-compose down

# 서버 재시작
docker-compose restart

# 로그 확인
docker-compose logs -f

# 컨테이너 상태 확인
docker-compose ps

# 컨테이너 내부 접속
docker-compose exec qwen3-tts bash
```

### 리소스 모니터링
```bash
# GPU 사용률 확인
docker exec qwen3-tts-server nvidia-smi

# 컨테이너 리소스 사용 확인
docker stats qwen3-tts-server

# 디스크 사용량 확인
docker system df
```

### 정리 명령어
```bash
# 컨테이너와 네트워크 삭제
docker-compose down

# 볼륨까지 삭제 (주의: 모델 파일도 삭제됨)
docker-compose down -v

# 이미지 삭제
docker rmi qwen3-tts:latest

# 빌드 캐시 정리
docker builder prune
```

---

## 엘리스 AI 클라우드 배포

엘리스 클라우드는 **Ubuntu LTS 기반 Docker 컨테이너 환경**을 제공합니다.
하지만 커스텀 Docker 이미지를 직접 배포하는 방식이 아니라, **사전 구성된 컨테이너 내부에서 개발하는 방식**입니다.

**배포 방법:**
1. 엘리스 클라우드에서 VSCode/SSH로 컨테이너 접속
2. Git clone 후 의존성 설치 및 서버 실행

**엘리스 AI 상세 배포 가이드:**
[ELICE_DEPLOYMENT_GUIDE.md](ELICE_DEPLOYMENT_GUIDE.md) 참고

**커스텀 Docker 이미지 배포 (이 가이드의 Docker 파일 사용):**
- RunPod: Docker 이미지 직접 배포 가능
- Vast.ai: Docker 이미지 직접 배포 가능
- AWS/GCP/Azure: ECS, Cloud Run, Kubernetes 사용

---

## Dockerfile 구조

### 베이스 이미지
```dockerfile
FROM nvidia/cuda:12.4.0-cudnn9-devel-ubuntu22.04
```
- CUDA 12.4
- cuDNN 9
- Ubuntu 22.04

### 주요 단계
1. 시스템 패키지 설치 (Python 3.10, FFmpeg 등)
2. Python 의존성 설치 (requirements.txt)
3. Flash Attention 설치 (optional, A100 최적화)
4. 비디오 의존성 설치 (optional, INSTALL_VIDEO=true 시)
5. 애플리케이션 코드 복사
6. 포트 8000 노출

---

## 환경 변수

`.env` 파일 또는 docker-compose.yml에서 설정:

```bash
# 서버 설정
TTS_HOST=0.0.0.0
TTS_PORT=8000

# GPU 설정
TTS_DEVICE=cuda:0
TTS_DTYPE=bfloat16

# 성능 최적화
TTS_USE_FLASH_ATTENTION=true
TTS_USE_TORCH_COMPILE=false

# 기본 모델
TTS_DEFAULT_MODEL=base_0.6b

# 비디오 생성 (optional)
ENABLE_VIDEO=false
NEWAVATA_PATH=NewAvata
VIDEO_AVATAR_DIR=avatars
VIDEO_OUTPUT_DIR=output
```

---

## 문제 해결

### 1. GPU를 찾을 수 없음
```
Error: could not select device driver "" with capabilities: [[gpu]]
```

**해결:**
```bash
# NVIDIA Container Toolkit 설치 확인
nvidia-ctk --version

# Docker 재시작
sudo systemctl restart docker

# GPU 테스트
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

---

### 2. 포트 충돌
```
Error: port is already allocated
```

**해결:**
```bash
# 포트 사용 중인 프로세스 확인
sudo lsof -i :8000

# docker-compose.yml에서 포트 변경
ports:
  - "8001:8000"  # 호스트 포트를 8001로 변경
```

---

### 3. 메모리 부족
```
CUDA out of memory
```

**해결:**
```bash
# 더 작은 모델 사용
echo "TTS_DEFAULT_MODEL=base_0.6b" >> .env

# 또는 GPU 메모리가 큰 환경 사용
# A100 40GB → A100 80GB
```

---

### 4. MuseTalk 모델이 없음
```
FileNotFoundError: Model file not found
```

**해결:**
```bash
cd NewAvata/MuseTalk

# Linux
./download_weights.sh

# Windows
download_weights.bat

# 수동 다운로드 (Hugging Face)
# https://huggingface.co/TMElyralab/MuseTalk
```

---

## 성능 최적화

### 1. 멀티스테이지 빌드 (고급)

```dockerfile
# Dockerfile.optimized
FROM nvidia/cuda:12.4.0-cudnn9-devel-ubuntu22.04 AS builder
# ... build dependencies ...

FROM nvidia/cuda:12.4.0-cudnn9-runtime-ubuntu22.04
# ... copy only runtime files ...
```

### 2. 캐싱 활용

```bash
# 모델을 호스트에 다운로드 후 volume mount
# docker-compose.yml:
volumes:
  - ./models:/app/models:ro  # 읽기 전용
```

### 3. GPU 할당 최적화

```yaml
# docker-compose.yml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          device_ids: ['0']  # 특정 GPU 지정
          capabilities: [gpu]
```

---

## 보안 권장사항

1. **최소 권한 원칙**: 컨테이너를 non-root 사용자로 실행
2. **네트워크 격리**: 불필요한 포트 노출 금지
3. **시크릿 관리**: `.env` 파일을 git에 커밋하지 않음
4. **정기 업데이트**: 베이스 이미지 및 의존성 업데이트

```bash
# .env 파일 권한 설정
chmod 600 .env
```

---

## 요약

**TTS만 배포 (간단):**
```bash
docker-compose up -d
```

**TTS + 비디오 배포 (완전):**
```bash
# 사전 준비
git clone https://github.com/TMElyralab/MuseTalk.git NewAvata/MuseTalk
cd NewAvata/MuseTalk && ./download_weights.sh && cd ../..

# 배포
docker-compose -f docker-compose.yml -f docker-compose.video.yml up -d
```

**접속:**
- API 문서: http://localhost:8000/docs
- Health Check: http://localhost:8000/health
- Web UI: http://localhost:8000/ui
