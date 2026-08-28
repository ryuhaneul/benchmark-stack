# --------------------------------------------------------
# [Stage 1] Builder: 의존성 설치 전용 (최종 이미지에 포함 안됨)
# --------------------------------------------------------
FROM node:24-alpine AS builder

WORKDIR /usr/src/app

# 패키지 파일만 먼저 복사 (캐시 효율 극대화)
COPY package*.json ./

# 프로덕션 의존성 설치 (lock 파일 있으면 ci, 없으면 install)
RUN ([ -f package-lock.json ] && npm ci --only=production || npm install --production)

# --------------------------------------------------------
# [Stage 2] Production: 실제 실행용 경량 이미지
# --------------------------------------------------------
FROM node:24-alpine

# 1. OS 보안 패치 + 불필요한 도구 제거
RUN apk upgrade --no-cache && \
    rm -rf /opt/yarn /usr/local/bin/yarn /usr/local/bin/yarnpkg

WORKDIR /usr/src/app

# 2. Builder에서 node_modules만 복사 (npm 캐시, 임시파일 제외)
COPY --from=builder /usr/src/app/node_modules ./node_modules

# 3. 애플리케이션 코드 복사
COPY . .

# 4. 보안: Non-root 사용자 생성 및 권한 설정
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /usr/src/app

USER nodejs

EXPOSE 3000

# 헬스체크
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# npm start 대신 node 직접 실행 (메모리 효율)
CMD ["node", "server.js"]
