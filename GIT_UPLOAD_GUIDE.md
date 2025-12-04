# Git 업로드 가이드 및 보안 검토

이 가이드는 프로젝트의 보안 검토 결과와 Git에 업로드하는 단계별 절차를 설명합니다.

## 1. 보안 검토 결과

비밀번호, API 키 등 민감한 정보가 있는지 프로젝트를 스캔했습니다.

### ✅ 업로드해도 안전함
- **`.env` 파일**: 실제 비밀번호와 키가 들어있는 파일입니다. **이미 `.gitignore` 파일에 포함되어 있어**, Git이 자동으로 이 파일을 무시합니다. 아주 잘 설정되어 있습니다.
- **`k8s/secret.yml`**: 이 파일도 `.gitignore`에 의해 무시됩니다.
- **`nginx/certs/`**: SSL 인증서 파일들도 무시되도록 설정되어 있습니다.

### ⚠️ 참고 사항
- **`docker-compose.yml`**: 이 파일에는 `MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:-rootpassword}`와 같은 기본값이 포함되어 있습니다.
  - **위험도**: 낮음. `:-rootpassword` 부분은 설정이 없을 때 사용하는 기본값(fallback)입니다. 누군가 코드를 다운로드하면 "rootpassword"라는 기본값을 보게 됩니다.
  - **권장사항**: 개발 환경에서는 흔한 설정입니다. 다만, 이 파일 내의 `${...}` 부분을 실제 비밀번호로 직접 수정해서 올리지 않도록 주의하세요. 실제 비밀번호는 항상 `.env` 파일에서 관리해야 합니다.

## 2. Git 설정 (최초 1회)

Git을 처음 사용하신다면 사용자 정보를 설정해야 합니다. Git은 누가 코드를 변경했는지 기록하기 위해 이 정보가 필요합니다.

터미널에 아래 명령어를 입력하세요 (본인의 정보로 변경해서 입력):

```bash
git config --global user.name "본인 이름"
git config --global user.email "본인_이메일@example.com"
```

## 3. 단계별 업로드 절차

아래 순서대로 따라 하시면 됩니다.

### 1단계: Git 초기화
현재 폴더를 Git이 관리하는 저장소로 만듭니다.

```bash
cd /root/test-stack
git init
```

### 2단계: 상태 확인
Git이 어떤 파일들을 인식하고 있는지 확인합니다.

```bash
git status
```
*빨간색으로 파일 목록이 뜰 것입니다. 이때 목록에 `.env` 파일이 **없어야** 합니다.*

### 3단계: 파일 추가
모든 파일을 업로드 대기 상태(Stage)로 만듭니다.

```bash
git add .
```

### 4단계: 커밋 (저장)
현재 상태를 스냅샷으로 저장합니다.

```bash
git commit -m "첫 커밋: Docker와 K8s 설정이 포함된 프로젝트 초기화"
```

### 5단계: GitHub/GitLab 저장소 생성
1. [GitHub.com](https://github.com) (또는 사용하려는 사이트)에 로그인합니다.
2. **"New Repository"** (새 저장소 만들기) 버튼을 클릭합니다.
3. 저장소 이름(예: `test-stack`)을 입력합니다.
4. "Initialize with README", "Add .gitignore", "Add license" 옵션은 **체크하지 마세요** (이미 파일이 있으니까요).
5. **"Create repository"** 버튼을 누릅니다.

### 6단계: 연결 및 업로드 (Push)
GitHub에서 생성된 주소를 복사합니다 (예: `https://github.com/사용자명/test-stack.git`).

아래 명령어들을 순서대로 입력하세요 (주소는 본인의 것으로 변경):

```bash
# 기본 브랜치 이름을 main으로 변경 (요즘 표준입니다)
git branch -M main

# 내 컴퓨터의 저장소와 GitHub 저장소를 연결
git remote add origin https://github.com/본인_아이디/저장소_이름.git

# 코드 업로드
git push -u origin main
```

## 4. 확인
업로드가 끝나면 GitHub 페이지를 새로고침 해보세요. 파일들이 올라간 것을 볼 수 있습니다. 웹사이트 파일 목록에 `.env` 파일이 **없는지** 꼭 다시 한번 확인하세요.
