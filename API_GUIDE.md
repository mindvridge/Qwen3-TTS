# Qwen3-TTS API 가이드

외부에서 Qwen3-TTS API를 사용하는 방법을 설명합니다.

---

## 기본 정보

| 항목 | 값 |
|------|-----|
| Base URL | `https://[프로젝트ID].elice.app` |
| API 문서 | `https://[프로젝트ID].elice.app/docs` |
| Web UI | `https://[프로젝트ID].elice.app/ui` |

---

## 1. Health Check

서버 상태 확인

### Request
```bash
curl https://[BASE_URL]/health
```

### Response
```json
{
  "status": "ok",
  "models_loaded": ["base_0.6b"]
}
```

---

## 2. 서버 정보 조회

### Request
```bash
curl https://[BASE_URL]/info
```

### Response
```json
{
  "loaded_models": ["base_0.6b"],
  "available_models": ["base_0.6b", "base_1.7b"],
  "available_speakers": [...],
  "supported_languages": ["Korean", "English", "Chinese", "Japanese", "Auto"]
}
```

---

## 3. TTS 음성 생성 (Voice Clone)

참조 음성을 기반으로 새로운 텍스트를 음성으로 변환합니다.

### Endpoint
```
POST /tts/voice_clone?model_size=0.6b
```

### Request Body
```json
{
  "text": "안녕하세요. 음성 합성 테스트입니다.",
  "language": "Korean",
  "ref_audio": "sample(1).mp3",
  "ref_text": "참조 음성에서 말한 텍스트 내용",
  "x_vector_only_mode": false,
  "generation_params": {
    "max_new_tokens": 2048,
    "temperature": 0.7,
    "top_k": 30,
    "top_p": 0.8,
    "repetition_penalty": 1.1
  }
}
```

### Parameters

| 파라미터 | 타입 | 필수 | 기본값 | 설명 |
|---------|------|------|--------|------|
| `text` | string | ✅ | - | 합성할 텍스트 |
| `language` | string | ❌ | "Auto" | 언어 (Korean, English, Chinese, Japanese, Auto) |
| `ref_audio` | string | ✅ | - | 참조 음성 파일 경로 |
| `ref_text` | string | ✅ | - | 참조 음성의 텍스트 |
| `x_vector_only_mode` | bool | ❌ | false | X-vector 모드 사용 |
| `model_size` | string | ❌ | "0.6b" | 모델 크기 ("0.6b" 또는 "1.7b") |

### cURL 예시

```bash
# WAV 파일로 저장
curl -X POST "https://[BASE_URL]/tts/voice_clone?model_size=0.6b" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "안녕하세요. 테스트입니다.",
    "language": "Korean",
    "ref_audio": "sample(1).mp3",
    "ref_text": "참조 음성 텍스트"
  }' \
  --output output.wav
```

### Response
- **Content-Type**: `audio/wav`
- **Headers**:
  - `X-Generation-Time`: 생성 시간 (초)

---

## 4. TTS SSE 스트리밍

Server-Sent Events를 통한 실시간 진행 상황 업데이트

### Endpoint
```
POST /tts/voice_clone/sse?model_size=0.6b&streaming=true
```

### cURL 예시

```bash
curl -X POST "https://[BASE_URL]/tts/voice_clone/sse?model_size=0.6b" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{
    "text": "안녕하세요. 테스트입니다.",
    "language": "Korean",
    "ref_audio": "sample(1).mp3",
    "ref_text": "참조 음성 텍스트"
  }'
```

### SSE Events

**1. meta event** - 생성 시작
```
event: meta
data: {"status": "generating", "text": "안녕하세요. 테스트입니다."}
```

**2. audio event** - 오디오 데이터 (Base64)
```
event: audio
data: {
  "chunk_index": 0,
  "audio": "UklGR...(Base64 WAV)",
  "sample_rate": 24000,
  "generation_time": 3.5
}
```

**3. done event** - 완료
```
event: done
data: {"total_time": 3.5, "total_chunks": 1}
```

### JavaScript 예시

```javascript
const eventSource = new EventSource('/tts/voice_clone/sse?model_size=0.6b', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    text: '안녕하세요.',
    language: 'Korean',
    ref_audio: 'sample(1).mp3',
    ref_text: '참조 텍스트'
  })
});

eventSource.addEventListener('audio', (e) => {
  const data = JSON.parse(e.data);
  const audioBlob = base64ToBlob(data.audio, 'audio/wav');
  playAudio(audioBlob);
});

eventSource.addEventListener('done', (e) => {
  console.log('Generation complete:', JSON.parse(e.data));
  eventSource.close();
});
```

---

## 5. 비디오 생성 (선택사항)

TTS + 립싱크 비디오 생성 (ENABLE_VIDEO=true 필요)

### Endpoint
```
POST /video/generate
```

### Request (multipart/form-data)

```bash
curl -X POST "https://[BASE_URL]/video/generate" \
  -F "text=안녕하세요. 비디오 테스트입니다." \
  -F "language=Korean" \
  -F "ref_audio=sample(1).mp3" \
  -F "ref_text=참조 음성 텍스트" \
  -F "avatar_image=@avatar.jpg" \
  -F "model_size=0.6b" \
  --output output.mp4
```

### Response
- **Content-Type**: `video/mp4`
- **Headers**:
  - `X-Generation-Time`: 총 생성 시간
  - `X-TTS-Time`: TTS 생성 시간

---

## 6. 아바타 목록 조회

### Request
```bash
curl https://[BASE_URL]/video/avatars
```

### Response
```json
{
  "avatars": ["avatar1.jpg", "avatar2.png"]
}
```

---

## 프로그래밍 언어별 예시

### Python

```python
import requests

BASE_URL = "https://[프로젝트ID].elice.app"

# TTS 생성
response = requests.post(
    f"{BASE_URL}/tts/voice_clone",
    params={"model_size": "0.6b"},
    json={
        "text": "안녕하세요. 파이썬 테스트입니다.",
        "language": "Korean",
        "ref_audio": "sample(1).mp3",
        "ref_text": "참조 음성 텍스트"
    }
)

# WAV 파일 저장
with open("output.wav", "wb") as f:
    f.write(response.content)

print(f"생성 시간: {response.headers.get('X-Generation-Time')}초")
```

### JavaScript (Node.js)

```javascript
const fetch = require('node-fetch');
const fs = require('fs');

const BASE_URL = 'https://[프로젝트ID].elice.app';

async function generateTTS() {
  const response = await fetch(`${BASE_URL}/tts/voice_clone?model_size=0.6b`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      text: '안녕하세요. Node.js 테스트입니다.',
      language: 'Korean',
      ref_audio: 'sample(1).mp3',
      ref_text: '참조 음성 텍스트'
    })
  });

  const buffer = await response.buffer();
  fs.writeFileSync('output.wav', buffer);

  console.log(`생성 시간: ${response.headers.get('X-Generation-Time')}초`);
}

generateTTS();
```

### JavaScript (Browser)

```javascript
async function generateAndPlayTTS() {
  const response = await fetch('/tts/voice_clone?model_size=0.6b', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      text: '안녕하세요. 브라우저 테스트입니다.',
      language: 'Korean',
      ref_audio: 'sample(1).mp3',
      ref_text: '참조 음성 텍스트'
    })
  });

  const audioBlob = await response.blob();
  const audioUrl = URL.createObjectURL(audioBlob);

  const audio = new Audio(audioUrl);
  audio.play();
}
```

---

## 에러 응답

### 400 Bad Request
```json
{
  "detail": "Invalid model type"
}
```

### 500 Internal Server Error
```json
{
  "detail": "Error message describing the issue"
}
```

---

## 참고사항

1. **참조 음성 품질**: 깨끗하고 잡음 없는 음성 파일 권장 (3-10초)
2. **모델 선택**:
   - `0.6b`: 빠른 생성 (3-5초/문장), 8GB VRAM
   - `1.7b`: 높은 품질 (5-10초/문장), 15GB VRAM
3. **긴 텍스트**: 자동으로 문장 단위 분할 후 생성
4. **지원 언어**: Korean, English, Chinese, Japanese, Auto
