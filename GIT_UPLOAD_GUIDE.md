# Git 업로드 및 다운로드 가이드

이 가이드는 프로젝트의 보안 검토 결과, Git 업로드 절차(인증 포함), 다른 서버에서 다운로드하는 방법, 그리고 **업데이트 관리 방법**을 설명합니다.

## 1. 보안 검토 결과

비밀번호, API 키 등 민감한 정보가 있는지 프로젝트를 스캔했습니다.

### ✅ 업로드해도 안전함
- **`.env` 파일**: 실제 비밀번호와 키가 들어있는 파일입니다. **이미 `.gitignore` 파일에 포함되어 있어**, Git이 자동으로 이 파일을 무시합니다. 아주 잘 설정되어 있습니다.
- **`k8s/secret.yml`**: 이 파일도 `.gitignore`에 의해 무시됩니다.
- **`nginx/certs/`**: SSL 인증서 파일들도 무시되도록 설정되어 있습니다.

### ⚠️ 참고 사항
- **`docker-compose.yml`**: 이 파일에는 `MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:-rootpassword}`와 같은 기본값이 포함되어 있습니다.
  - **위험도**: 낮음. `:-rootpassword` 부분은 설정이 없을 때 사용하는 기본값(fallback)입니다.
  - **권장사항**: 실제 비밀번호는 항상 `.env` 파일에서 관리해야 합니다.

## 2. Git 설정 (최초 1회)

Git을 처음 사용하신다면 사용자 정보를 설정해야 합니다.

```bash
git config --global user.name "본인 이름"
git config --global user.email "본인_이메일@example.com"
```

### 💡 꿀팁: 로그인 정보 저장하기 (매번 입력 안 하기)
매번 아이디와 토큰을 입력하기 귀찮다면 아래 명령어를 입력하세요. 한 번만 로그인하면 정보를 저장해 둡니다.

```bash
git config --global credential.helper store
```
*주의: 공용 컴퓨터에서는 사용하지 마세요.*

**정보가 저장되는 위치:**
사용자 홈 디렉토리의 `.git-credentials` 파일에 평문(암호화되지 않음)으로 저장됩니다. (`~/.git-credentials`)

**저장된 정보 삭제하는 법:**
잘못된 정보를 입력했거나 보안을 위해 삭제하고 싶다면 이 파일을 지우면 됩니다.

```bash
rm ~/.git-credentials
```
삭제 후 다시 `git push`를 하면 아이디와 비밀번호를 새로 물어봅니다.

## 3. 단계별 업로드 절차 (처음 올릴 때)

### 1단계: Git 초기화
```bash
cd /root/test-stack
git init
```

### 2단계: 상태 확인
```bash
git status
```
*목록에 `.env` 파일이 **없어야** 합니다.*

### 3단계: 파일 추가 및 커밋
```bash
git add .
git commit -m "첫 커밋: 프로젝트 초기화"
```

### 4단계: GitHub 저장소 생성
1. [GitHub.com](https://github.com)에 로그인하고 **"New Repository"**를 클릭합니다.
2. 저장소 이름을 입력하고 **"Private" (비공개)** 또는 "Public"을 선택합니다.
3. **"Create repository"**를 누릅니다.

### 5단계: 연결 및 업로드
GitHub 주소를 복사한 후 아래 명령어를 입력합니다.

```bash
git branch -M main
git remote add origin https://github.com/본인_아이디/저장소_이름.git
git push -u origin main
```
*(로그인 시 비밀번호 대신 **Personal Access Token**을 사용하세요)*

---

## 4. 다른 서버에서 다운로드하기 (Clone)

새로운 서버에서 프로젝트를 받아 실행하는 방법입니다.

### 1단계: 프로젝트 다운로드
```bash
git clone https://github.com/본인_아이디/저장소_이름.git
cd 저장소_이름
```

### 2단계: 비밀 설정 파일 복구 (가장 중요!)
다운로드한 프로젝트에는 `.env` 파일이 없습니다. **직접 다시 만들어줘야 합니다.**

```bash
cp .env.example .env
vi .env
# DB_PASSWORD 등을 실제 값으로 수정하세요.
```

### 3단계: 실행
```bash
docker-compose up -d
```

---

## 5. 프로젝트 수정 및 업데이트 방법 (유지보수)

코드를 수정했을 때 서버에 반영하는 절차입니다.

### 1단계: 내 컴퓨터에서 수정하고 올리기 (Push)
코드를 수정한 후 다음 3단계를 수행합니다.

```bash
# 1. 변경된 파일 담기 (수정, 생성, 삭제된 파일 모두 포함)
git add .

# 2. 변경 내용 설명 적기 (커밋)
git commit -m "기능 추가: 로그인 페이지 디자인 변경"

# 3. GitHub로 보내기
git push
```

### 2단계: 서버에서 내려받기 (Pull)
운영 중인 서버로 접속해서 최신 코드를 받습니다.

```bash
# 1. 프로젝트 폴더로 이동
cd /path/to/project

# 2. 최신 코드 받기
git pull
```

### 3단계: 변경 사항 반영하기
코드가 바뀌었으니 실행 중인 프로그램을 재시작해야 할 수 있습니다.

```bash
# Docker 컨테이너를 새로 빌드하고 재시작 (코드 변경 시 필수)
docker-compose up -d --build
```
