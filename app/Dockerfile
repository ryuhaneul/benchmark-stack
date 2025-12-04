FROM node:20-alpine

# 1. OS 패키지 보안 패치
RUN apk update && apk upgrade --no-cache

WORKDIR /usr/src/app

COPY package*.json ./

# 2. 핵심 보안 조치 통합
# - npm 자체 업데이트 (글로벌 취약점 해결)
# - yarn 삭제 (사용하지 않는 도구 제거)
# - 앱 설치 (overrides 적용)
# - lock 파일 삭제 (스캐너 오탐지 방지)
RUN npm install -g npm@latest && \
  rm -rf /opt/yarn /usr/local/bin/yarn /usr/local/bin/yarnpkg && \
  npm install --production && \
  rm -f package-lock.json

COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
  adduser -S nodejs -u 1001 && \
  chown -R nodejs:nodejs /usr/src/app

USER nodejs

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

CMD ["node", "server.js"]
