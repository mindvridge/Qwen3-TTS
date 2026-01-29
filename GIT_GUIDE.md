# Git 명령어 가이드

Qwen3-TTS 프로젝트의 Git 사용법입니다.

---

## 기본 명령어

### 저장소 클론 (최초 1회)
```bash
cd ~
git clone https://github.com/mindvridge/Qwen3-TTS.git
cd Qwen3-TTS
```

### 최신 코드 받기
```bash
git pull
```

### 현재 상태 확인
```bash
git status
```

### 변경 내역 확인
```bash
git diff
```

### 커밋 기록 확인
```bash
git log --oneline -10
```

---

## 변경사항 커밋 & 푸시

### 1. 변경된 파일 확인
```bash
git status
```

### 2. 파일 스테이징
```bash
# 특정 파일
git add server.py

# 여러 파일
git add server.py config.py

# 모든 변경 파일
git add .
```

### 3. 커밋
```bash
git commit -m "커밋 메시지"
```

### 4. 푸시
```bash
git push
```

### 한 줄로 실행
```bash
git add . && git commit -m "커밋 메시지" && git push
```

---

## 충돌 해결

### 로컬 변경사항 버리고 원격 코드로 덮어쓰기
```bash
# 특정 파일만
git checkout -- start.sh

# 모든 로컬 변경 버리고 원격으로 리셋
git fetch origin && git reset --hard origin/main
```

### 로컬 변경사항 임시 저장 후 pull
```bash
# 변경사항 임시 저장
git stash

# 최신 코드 받기
git pull

# 임시 저장한 변경사항 복원
git stash pop
```

### merge 충돌 발생 시
```bash
# 충돌 파일 확인
git status

# 파일 직접 수정 후
git add <충돌_해결된_파일>
git commit -m "Resolve merge conflict"
```

---

## 브랜치 관련

### 현재 브랜치 확인
```bash
git branch
```

### 새 브랜치 생성 및 전환
```bash
git checkout -b feature/new-feature
```

### 브랜치 전환
```bash
git checkout main
```

### 브랜치 삭제
```bash
git branch -d feature/new-feature
```

---

## 되돌리기

### 마지막 커밋 취소 (변경사항 유지)
```bash
git reset --soft HEAD~1
```

### 마지막 커밋 취소 (변경사항 삭제)
```bash
git reset --hard HEAD~1
```

### 특정 파일을 마지막 커밋 상태로 복원
```bash
git checkout -- <파일명>
```

### 모든 변경사항 버리기
```bash
git checkout -- .
```

---

## Elice 환경 전용

### 서버 중지 후 최신 코드 받기
```bash
# Ctrl+C로 서버 중지 후
git pull
bash start.sh
```

### 로컬 충돌 무시하고 강제 업데이트
```bash
git fetch origin && git reset --hard origin/main
bash start.sh
```

### .env 파일은 git에서 제외됨
`.env` 파일은 `.gitignore`에 포함되어 있어 커밋되지 않습니다.
서버마다 별도로 설정해야 합니다.

```bash
# .env 설정
cp .env.example .env
sed -i 's/TTS_USE_FLASH_ATTENTION=false/TTS_USE_FLASH_ATTENTION=true/' .env
```

---

## GitHub 인증

### HTTPS 인증 (토큰 방식)
```bash
# 푸시 시 사용자명과 Personal Access Token 입력
git push
# Username: your-username
# Password: ghp_xxxxxxxxxxxx (Personal Access Token)
```

### GitHub CLI 인증
```bash
# gh CLI 설치 후
gh auth login
```

---

## 자주 발생하는 문제

### 문제 1: `error: Your local changes would be overwritten by merge`
```bash
# 해결: 로컬 변경사항 버리기
git checkout -- <파일명>
git pull
```

### 문제 2: `fatal: not a git repository`
```bash
# 해결: git 저장소 디렉토리로 이동
cd ~/Qwen3-TTS
```

### 문제 3: `Permission denied (publickey)`
```bash
# 해결: HTTPS로 클론 (SSH 대신)
git clone https://github.com/mindvridge/Qwen3-TTS.git
```

### 문제 4: 대용량 파일 푸시 실패
```bash
# .gitignore에 추가
echo "*.whl" >> .gitignore
echo "models/" >> .gitignore
```

---

## 유용한 별칭 설정

```bash
# ~/.bashrc 또는 ~/.zshrc에 추가
alias gs='git status'
alias gp='git pull'
alias gpp='git push'
alias ga='git add .'
alias gc='git commit -m'
alias glog='git log --oneline -10'
```

사용 예:
```bash
gs        # git status
gp        # git pull
ga && gc "메시지" && gpp  # add, commit, push
```

---

## 요약: 일반적인 작업 흐름

```bash
# 1. 최신 코드 받기
git pull

# 2. 작업 수행
# ... 코드 수정 ...

# 3. 변경사항 확인
git status
git diff

# 4. 커밋 & 푸시
git add .
git commit -m "변경 내용 설명"
git push
```
