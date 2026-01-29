# NewAvata 아바타 설정 가이드

## 문제
NewAvata 립싱크 서버는 실행 중이지만, 사전계산된 아바타 파일(.pkl)이 없어서 비디오 생성이 불가능합니다.

## 현재 서버 상태
- TTS Server: https://rhbwsfctehtfacax.tunnel.elice.io ✓
- NewAvata: https://nzgwjxtxppjpasfr.tunnel.elice.io ✓
- 아바타 목록: **비어있음** ✗

## 해결 방법

### 방법 1: Elice 터미널에서 직접 실행

Elice Cloud 터미널에서 다음 명령어를 실행하세요:

```bash
# 1. NewAvata 디렉토리로 이동
cd ~/NewAvata/realtime-interview-avatar

# 2. 가상환경 활성화
source venv/bin/activate

# 3. 샘플 아바타 영상 다운로드
mkdir -p assets
python3 << 'EOF'
import urllib.request
import os

url = 'https://github.com/mindvridge/NewAvata/releases/download/v0.1/sample_avatar.mp4'
output = os.path.expanduser('~/NewAvata/realtime-interview-avatar/assets/sample_avatar.mp4')

print(f'Downloading sample avatar video...')
urllib.request.urlretrieve(url, output)
print(f'Downloaded: {os.path.getsize(output)/1024/1024:.1f}MB')
EOF

# 4. 아바타 사전계산 (5-10분 소요)
mkdir -p precomputed
python scripts/precompute_avatar.py \
    --video assets/sample_avatar.mp4 \
    --output precomputed/sample_avatar.pkl

# 5. 서버 재시작
tmux kill-session -t newavata
cd ~/Qwen3-TTS
bash start_full.sh
```

### 방법 2: setup_avatar.sh 스크립트 사용

```bash
# Elice 서버에서 실행
cd ~/Qwen3-TTS
bash setup_avatar.sh
```

## 자신만의 아바타 사용하기

1. 5-10초 길이의 영상 준비 (정면을 보고 자연스럽게 말하는 모습)
2. 영상을 `~/NewAvata/realtime-interview-avatar/assets/` 에 업로드
3. 사전계산 실행:
   ```bash
   cd ~/NewAvata/realtime-interview-avatar
   source venv/bin/activate
   python scripts/precompute_avatar.py \
       --video assets/your_video.mp4 \
       --output precomputed/your_avatar.pkl
   ```

## 아바타 확인 방법

```bash
# 사전계산된 아바타 목록 확인
ls -la ~/NewAvata/realtime-interview-avatar/precomputed/*.pkl

# API로 확인
curl https://nzgwjxtxppjpasfr.tunnel.elice.io/api/avatars
```

## 테스트

아바타 설정 후 테스트:

```bash
# Windows (로컬)
python test_lipsync_full.py "안녕하세요, 립싱크 테스트입니다."

# 또는 curl로 직접 테스트
curl -X POST "https://rhbwsfctehtfacax.tunnel.elice.io/video/generate?text=안녕하세요&avatar_path=auto"
```

## 예상 결과

아바타 설정 후 `/api/avatars` 응답:
```json
[
  {
    "name": "sample_avatar",
    "path": "precomputed/sample_avatar.pkl",
    "size": "1.3GB"
  }
]
```

## 문제 해결

### "No avatars found" 에러
- precomputed 디렉토리에 .pkl 파일이 있는지 확인
- NewAvata 서버 재시작 필요

### 사전계산 실패
- GPU 메모리 확인 (최소 8GB 권장)
- 입력 영상이 유효한 mp4 파일인지 확인
- face-parse-bisent 모델 다운로드 확인: `bash fix_faceparse.sh`

### 립싱크 품질 저하
- 720p 이상의 고화질 영상 사용
- 정면을 보고 자연스럽게 말하는 영상 사용
- 조명이 밝은 환경에서 촬영
