# acme-dns 사용 가이드

acme-dns를 사용하면 DNS-01 challenge를 통해 Let's Encrypt 인증서를 발급받을 수 있습니다. 특히 와일드카드 인증서(`*.yourdomain.com`)를 발급받을 때 필요합니다.

## 📋 acme-dns란?

acme-dns는 Let's Encrypt의 DNS-01 challenge를 위한 간단한 DNS 서버입니다. 메인 DNS 제공업체의 API 키를 노출하지 않고 안전하게 인증서를 발급받을 수 있습니다.

## 🚀 빠른 시작

### 1단계: acme-dns 서비스 시작

```bash
# acme-dns 프로파일로 서비스 시작
docker compose --profile acme-dns up -d acme-dns
```

### 2단계: acme-dns에 등록

```bash
# acme-dns API로 새 계정 등록
curl -X POST http://localhost:8080/register

# 응답 예시:
# {
#   "username": "eabcdb41-d89f-4580-b91b-bc5c1a6f00f9",
#   "password": "pbkdf2_sha512$210000$...",
#   "fulldomain": "d5ac3a66-0f6d-4a35-a9ed-a8e6c3d8e9f4.auth.example.org",
#   "subdomain": "d5ac3a66-0f6d-4a35-a9ed-a8e6c3d8e9f4",
#   "allowfrom": []
# }
```

**중요**: 이 정보를 안전한 곳에 저장하세요!

### 3단계: DNS 레코드 설정

메인 도메인의 DNS에 CNAME 레코드를 추가합니다:

```
_acme-challenge.yourdomain.com. CNAME d5ac3a66-0f6d-4a35-a9ed-a8e6c3d8e9f4.auth.example.org.
```

**와일드카드 인증서**를 원하면:
```
_acme-challenge.yourdomain.com. CNAME d5ac3a66-0f6d-4a35-a9ed-a8e6c3d8e9f4.auth.example.org.
```

### 4단계: 환경 변수 설정

`.env` 파일에 acme-dns 정보 추가:

```bash
# Let's Encrypt 활성화
USE_LETSENCRYPT=true

# acme-dns 활성화
USE_ACME_DNS=true
ACME_DNS_API_URL=http://acme-dns:8080

# acme-dns 인증 정보 (2단계에서 받은 값)
ACME_DNS_USERNAME=eabcdb41-d89f-4580-b91b-bc5c1a6f00f9
ACME_DNS_PASSWORD=pbkdf2_sha512$210000$...
ACME_DNS_FULLDOMAIN=d5ac3a66-0f6d-4a35-a9ed-a8e6c3d8e9f4.auth.example.org
ACME_DNS_SUBDOMAIN=d5ac3a66-0f6d-4a35-a9ed-a8e6c3d8e9f4

# 도메인 설정
DOMAIN=yourdomain.com
ACME_EMAIL=your-email@example.com
```

## 🔧 수동 인증서 발급

자동화가 어려운 경우 수동으로 발급:

### certbot 수동 모드

```bash
# nginx 컨테이너 접속
docker compose exec nginx sh

# certbot 수동 모드로 실행
certbot certonly \
  --manual \
  --preferred-challenges dns \
  --email your-email@example.com \
  --agree-tos \
  -d yourdomain.com

# DNS TXT 레코드 추가 요청이 나오면:
# acme-dns API로 업데이트
curl -X POST http://acme-dns:8080/update \
  -H "X-Api-User: eabcdb41-d89f-4580-b91b-bc5c1a6f00f9" \
  -H "X-Api-Key: pbkdf2_sha512$210000$..." \
  -d '{"subdomain": "d5ac3a66-0f6d-4a35-a9ed-a8e6c3d8e9f4", "txt": "인증값"}'

# DNS 전파 대기 (1-2분)
# 그 후 certbot에서 계속 진행
```

## 🌐 공개 acme-dns 서비스 사용

자체 acme-dns 서버 대신 공개 서비스 사용:

```bash
# .env 파일에서
USE_ACME_DNS=true
ACME_DNS_API_URL=https://auth.acme-dns.io

# 등록
curl -X POST https://auth.acme-dns.io/register
```

## 📝 acme-dns 설정 파일

`acme-dns/config.cfg` 파일을 수정하여 커스터마이징:

```toml
[general]
listen = ":53"
protocol = "both"
# 자신의 도메인으로 변경
domain = "auth.yourdomain.com"
nsname = "auth.yourdomain.com"
nsadmin = "admin.yourdomain.com"

[database]
engine = "sqlite3"
connection = "/var/lib/acme-dns/acme-dns.db"

[api]
ip = "0.0.0.0"
port = "8080"
tls = "none"
# CORS 설정 (필요시)
corsorigins = ["*"]

[logconfig]
loglevel = "info"
logtype = "stdout"
```

## 🔐 보안 권장사항

1. **IP 제한**: acme-dns API 접근을 특정 IP로 제한
   ```bash
   curl -X POST http://localhost:8080/register \
     -d '{"allowfrom": ["1.2.3.4/32"]}'
   ```

2. **방화벽**: acme-dns 포트(53, 8080)를 필요한 곳에서만 열기

3. **인증 정보**: username과 password를 안전하게 보관

4. **정기 갱신**: Let's Encrypt 인증서는 90일마다 갱신 필요

## 🔄 인증서 자동 갱신

### certbot 갱신 훅 설정

```bash
# /etc/letsencrypt/renewal-hooks/deploy/acme-dns-update.sh
#!/bin/bash
# 인증서 갱신 후 nginx 재시작
docker compose restart nginx
```

### cron 설정

```bash
# 매일 인증서 갱신 확인
0 0 * * * docker compose exec nginx certbot renew --quiet
```

## 🧪 테스트

### DNS 레코드 확인

```bash
# CNAME 레코드 확인
dig _acme-challenge.yourdomain.com CNAME

# acme-dns 응답 확인
dig @localhost -p 53 d5ac3a66-0f6d-4a35-a9ed-a8e6c3d8e9f4.auth.example.org TXT
```

### API 테스트

```bash
# 등록 테스트
curl -X POST http://localhost:8080/register

# 업데이트 테스트
curl -X POST http://localhost:8080/update \
  -H "X-Api-User: your-username" \
  -H "X-Api-Key: your-password" \
  -d '{"subdomain": "your-subdomain", "txt": "test-value"}'
```

## ❓ 문제 해결

### acme-dns 서비스가 시작되지 않음

```bash
# 로그 확인
docker compose logs acme-dns

# 포트 충돌 확인
sudo netstat -nlp | grep :53
sudo netstat -nlp | grep :8080
```

### DNS 전파 확인

```bash
# 여러 DNS 서버에서 확인
dig @8.8.8.8 _acme-challenge.yourdomain.com CNAME
dig @1.1.1.1 _acme-challenge.yourdomain.com CNAME
```

### certbot 실패

```bash
# 디버그 모드로 실행
certbot certonly --manual --preferred-challenges dns \
  -d yourdomain.com --dry-run --debug
```

## 📚 참고 자료

- [acme-dns GitHub](https://github.com/joohoi/acme-dns)
- [Let's Encrypt DNS-01 Challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge)
- [certbot DNS Plugins](https://eff-certbot.readthedocs.io/en/stable/using.html#dns-plugins)
