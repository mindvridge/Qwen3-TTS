# 엘리스 클라우드 배포 가이드 (VSCode CUDA 12.4)

## ✅ 배포 환경 확정
- **실행 환경**: VSCode (CUDA 12.4)
- **GPU**: A100 40GB/80GB
- **OS**: Linux (Ubuntu)
- **Python**: 3.10

---

## 📦 1단계: 프로젝트 업로드

### 방법 1: Git Clone (권장)
```bash
# 엘리스 클라우드 터미널에서 실행
cd ~
git clone https://github.com/mindvridge/Qwen3-TTS.git
cd Qwen3-TTS
```

### 방법 2: 파일 직접 업로드
엘리스 클라우드 파일 탐색기에서 프로젝트 폴더 업로드

---

## 🔧 2단계: 환경 설정

### 2-1. 의존성 설치
```bash
# pip 업그레이드
pip install --upgrade pip

# CUDA 12.4용 패키지 설치
pip install -r requirements.txt

# Flash Attention 설치 (A100 최적화 - 2~3배 속도 향상)
pip install -U flash-attn --no-build-isolation
```

### 2-2. Flash Attention 활성화
```bash
# .env 파일 생성
cp .env.example .env

# .env 파일 편집
nano .env
```

`.env` 파일 내용:
```bash
TTS_USE_FLASH_ATTENTION=true
TTS_DEVICE=cuda:0
TTS_DTYPE=bfloat16
```

---

## 📁 3단계: 참조 음성 파일 업로드

`sample(1).mp3` 파일을 프로젝트 루트에 업로드하거나 경로 확인:
```bash
ls sample\(1\).mp3
# 또는
ls "sample(1).mp3"
```

---

## 🚀 4단계: 서버 실행

### 개발 모드 (테스트용)
```bash
python server.py
```

### 백그라운드 실행
```bash
nohup python server.py > server.log 2>&1 &

# 로그 확인
tail -f server.log
```

---

## 🌐 5단계: 포트 공개

### 엘리스 클라우드 설정
1. 프로젝트 설정 → **네트워크**
2. 포트 **8000** 공개
3. 접속 URL 확인: `https://your-project-id.elice.app`

---

## ✅ 6단계: 동작 확인

### Health Check
```bash
# 로컬 확인
curl http://localhost:8000/health

# 외부 URL 확인
curl https://your-project-id.elice.app/health
```

예상 응답:
```json
{
  "status": "ok",
  "models_loaded": ["base_0.6b"]
}
```

### Web UI 접속
```
https://your-project-id.elice.app/ui
```

### API 테스트
```bash
curl -X POST "https://your-project-id.elice.app/tts/voice_clone?model_size=0.6b" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "안녕하세요. 테스트입니다.",
    "language": "Korean",
    "ref_audio": "sample(1).mp3",
    "ref_text": "안녕하세요. 오늘 저의 면접에 참석해 주셔서 감사합니다. 저는 박현준 팀장입니다."
  }' \
  --output test.wav
```

---

## 🔍 7단계: 성능 확인

### GPU 사용률 모니터링
```bash
# 실시간 GPU 모니터링
watch -n 1 nvidia-smi

# 또는 한 번만 확인
nvidia-smi
```

### 생성 속도 확인
서버 로그에서 확인:
```
[VoiceClone] Generated in 5.234s (2 sentence(s))
```

**목표 성능**:
- A100 + Flash Attention: 문장당 3~8초
- A100 (Flash Attention 없음): 문장당 8~15초

---

## 🐛 트러블슈팅

### 문제 1: Flash Attention 설치 실패
```bash
# CUDA toolkit 확인
nvcc --version

# 재설치 시도
MAX_JOBS=4 pip install -U flash-attn --no-build-isolation
```

### 문제 2: 모델 다운로드 실패
```bash
# 수동 다운로드
huggingface-cli download Qwen/Qwen3-TTS-12Hz-0.6B-Base \
  --local-dir models/Qwen3-TTS-12Hz-0.6B-Base
```

### 문제 3: CUDA out of memory
```bash
# .env 파일에서 더 작은 모델 사용
TTS_DEFAULT_MODEL=base_0.6b
```

### 문제 4: 음성이 잘림
서버 로그 확인:
```bash
tail -f server.log | grep "DEBUG"
```

출력 예시:
```
[DEBUG] Split text into 2 sentence(s)
[DEBUG] Generating sentence 1/2: '첫 번째 문장...'
[DEBUG] Generating sentence 2/2: '두 번째 문장...'
[DEBUG] Concatenating 2 sentence audios
```

---

## 📊 성능 최적화 팁

### 1. Flash Attention 활성화 (필수)
```bash
TTS_USE_FLASH_ATTENTION=true
```

### 2. bfloat16 사용 (A100 최적화)
```bash
TTS_DTYPE=bfloat16
```

### 3. 동시 요청 처리
엘리스 클라우드의 동적 GPU 할당으로 자동 스케일링

---

## 💰 비용 관리

### A100 40GB 기준
- **시간당**: 1,380원
- **하루 (24시간)**: 33,120원
- **실제 사용**: 요청 시만 과금 (Idle 시 자동 해제)

### 비용 절감 팁
1. 사용하지 않을 때 프로젝트 중지
2. 0.6B 모델 사용 (1.7B보다 빠름)
3. 배치 처리로 여러 요청 동시 처리

---

## 📝 최종 체크리스트

배포 전:
- [x] VSCode (CUDA 12.4) 환경 선택
- [x] requirements.txt CUDA 12.4용 준비 완료
- [x] config.py 경로 자동 감지 기능 추가
- [x] server.py 문장 분할 로직 추가
- [ ] sample(1).mp3 파일 업로드
- [ ] Flash Attention 설치
- [ ] 포트 8000 공개

배포 후:
- [ ] `/health` 엔드포인트 응답 확인
- [ ] Web UI 접속 확인
- [ ] 음성 생성 테스트 (긴 문장)
- [ ] GPU 사용률 확인
- [ ] 생성 속도 측정

---

## 🎯 완료!

모든 단계가 완료되면 다음 URL로 접속 가능:
- **API 문서**: `https://your-project-id.elice.app/docs`
- **Web UI**: `https://your-project-id.elice.app/ui`
- **Health Check**: `https://your-project-id.elice.app/health`

문제 발생 시:
1. 서버 로그 확인: `tail -f server.log`
2. GPU 상태 확인: `nvidia-smi`
3. GitHub Issues: https://github.com/mindvridge/Qwen3-TTS/issues
