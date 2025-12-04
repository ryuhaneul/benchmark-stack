# Docker Test Stack

간단한 Docker 기반 테스트 프로젝트로 MySQL 데이터베이스와 CRUD API를 제공하며, HTTPS를 지원하고 클라우드 환경(EKS, RDS)으로 쉽게 마이그레이션 가능합니다.

## 🚀 빠른 시작

### 1. 환경 변수 설정

```bash
cp .env.example .env
# .env 파일을 편집하여 도메인과 데이터베이스 설정
nano .env
```

### 2. Docker Compose로 실행

```bash
# 모든 서비스 시작
docker compose up -d

# 로그 확인
docker compose logs -f
```

### 3. API 테스트

```bash
# Health check
curl http://localhost:3000/health

# 모든 아이템 조회
curl http://localhost:3000/api/items

# 아이템 생성
curl -X POST http://localhost:3000/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Item","description":"Test","quantity":10,"price":19.99}'

# 아이템 수정
curl -X PUT http://localhost:3000/api/items/1 \
  -H "Content-Type: application/json" \
  -d '{"quantity":20}'

# 아이템 삭제
curl -X DELETE http://localhost:3000/api/items/1
```

## 📋 환경 변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `DOMAIN` | 도메인 이름 (HTTPS 필수) | `localhost` |
| `ACME_EMAIL` | Let's Encrypt 이메일 | `admin@example.com` |
| `MYSQL_ROOT_PASSWORD` | MySQL root 비밀번호 | `rootpassword` |
| `MYSQL_DATABASE` | 데이터베이스 이름 | `testdb` |
| `MYSQL_USER` | 데이터베이스 사용자 | `testuser` |
| `MYSQL_PASSWORD` | 데이터베이스 비밀번호 | `testpassword` |

## 🔐 HTTPS 설정

### 로컬 개발 (Self-Signed)

`DOMAIN=localhost`로 설정하면 자동으로 자체 서명 인증서가 생성됩니다.

### 프로덕션 (Let's Encrypt)

1. 도메인 이름 설정:
```bash
# .env 파일에서
DOMAIN=yourdomain.com
ACME_EMAIL=your-email@example.com
```

2. DNS 설정:
   - A 레코드: `yourdomain.com` → 서버 IP
   - 포트 80, 443 오픈

3. 서비스 시작:
```bash
docker compose up -d
```

Nginx가 자동으로 Let's Encrypt 인증서를 발급받습니다.

## 🛠️ 서비스 구성

- **app**: Node.js Express API (포트 3000)
- **mysql**: MySQL 8.0 데이터베이스 (포트 3306)
- **nginx**: Nginx 리버스 프록시 with HTTPS (포트 80, 443)
- **acme-dns**: DNS-01 challenge용 (선택사항, 프로파일: `acme-dns`)

## 📡 API 엔드포인트

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/health` | 헬스 체크 |
| GET | `/api/items` | 모든 아이템 조회 |
| GET | `/api/items/:id` | 특정 아이템 조회 |
| POST | `/api/items` | 아이템 생성 |
| PUT | `/api/items/:id` | 아이템 수정 |
| DELETE | `/api/items/:id` | 아이템 삭제 |

## 🧪 데이터베이스 테스트

### MySQL CLI 접속

```bash
docker compose exec mysql mysql -u testuser -p testdb
# 비밀번호 입력: testpassword
```

### 쿼리 예제

```sql
-- 모든 데이터 조회
SELECT * FROM items;

-- 데이터 삽입
INSERT INTO items (name, description, quantity, price) 
VALUES ('New Item', 'Test description', 5, 15.99);

-- 데이터 수정
UPDATE items SET quantity = 20 WHERE id = 1;

-- 데이터 삭제
DELETE FROM items WHERE id = 1;
```

## ☁️ 클라우드 마이그레이션

프로젝트는 AWS EKS와 RDS로 쉽게 마이그레이션할 수 있도록 설계되었습니다.

자세한 내용은 [MIGRATION.md](MIGRATION.md)를 참조하세요.

### 빠른 가이드

1. **RDS 설정**: MySQL 호환 RDS 인스턴스 생성
2. **ECR에 이미지 푸시**: Docker 이미지 빌드 및 푸시
3. **EKS 배포**: `k8s/` 디렉토리의 매니페스트 사용
4. **환경 변수 업데이트**: ConfigMap과 Secret으로 DB 정보 설정

## 📁 프로젝트 구조

```
test-stack/
├── app/                    # Node.js 애플리케이션
│   ├── server.js          # Express 서버
│   ├── package.json       # 의존성
│   ├── Dockerfile         # 앱 이미지
│   └── db/
│       └── schema.sql     # 데이터베이스 스키마
├── nginx/                 # Nginx 설정
│   ├── Dockerfile
│   ├── nginx.conf.template
│   └── entrypoint.sh
├── k8s/                   # Kubernetes 매니페스트
│   ├── deployment.yml
│   ├── service.yml
│   ├── ingress.yml
│   ├── configmap.yml
│   └── secret.example.yml
├── acme-dns/              # acme-dns 설정
│   └── config.cfg
├── docker-compose.yml     # Docker Compose 설정
├── .env.example          # 환경 변수 템플릿
└── README.md
```

## 🔧 유용한 명령어

```bash
# 서비스 중지
docker compose down

# 볼륨 포함 완전 삭제
docker compose down -v

# 특정 서비스 재시작
docker compose restart app

# 로그 확인
docker compose logs app
docker compose logs nginx
docker compose logs mysql

# 컨테이너 상태 확인
docker compose ps
```

## 📝 라이센스

MIT License
