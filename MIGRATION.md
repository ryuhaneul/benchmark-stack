# Cloud Migration Guide

이 문서는 로컬 Docker 환경에서 AWS 클라우드(EKS + RDS)로 마이그레이션하는 단계별 가이드입니다.

## 📋 마이그레이션 개요

```
로컬 Docker 환경                     클라우드 환경
─────────────────                    ─────────────
Docker Compose       →               AWS EKS
MySQL Container      →               AWS RDS (MySQL)
Nginx (Let's Encrypt) →              ALB + ACM
```

## 🗄️ 1단계: MySQL → AWS RDS 마이그레이션

### 1.1 RDS 인스턴스 생성

```bash
# AWS CLI로 RDS 생성 (또는 콘솔 사용)
aws rds create-db-instance \
  --db-instance-identifier test-mysql \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username admin \
  --master-user-password YourSecurePassword \
  --allocated-storage 20 \
  --vpc-security-group-ids sg-xxxxx \
  --db-subnet-group-name your-subnet-group \
  --publicly-accessible false \
  --backup-retention-period 7 \
  --engine-version 8.0
```

### 1.2 데이터 백업 및 마이그레이션

```bash
# 로컬 MySQL 데이터 백업
docker compose exec mysql mysqldump -u testuser -p testdb > backup.sql

# RDS로 데이터 복원
mysql -h your-rds-endpoint.region.rds.amazonaws.com \
      -u admin -p testdb < backup.sql

# 또는 스키마만 복원
mysql -h your-rds-endpoint.region.rds.amazonaws.com \
      -u admin -p testdb < app/db/schema.sql
```

### 1.3 연결 테스트

```bash
# RDS 연결 확인
mysql -h your-rds-endpoint.region.rds.amazonaws.com \
      -u admin -p testdb

# 데이터 확인
SELECT * FROM items;
```

## 🐳 2단계: Docker 이미지 빌드 및 ECR 푸시

### 2.1 ECR 레포지토리 생성

```bash
# ECR 레포지토리 생성
aws ecr create-repository --repository-name test-app

# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.ap-northeast-2.amazonaws.com
```

### 2.2 이미지 빌드 및 푸시

```bash
# 이미지 빌드
cd app
docker build -t test-app:latest .

# 태그
docker tag test-app:latest \
  123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/test-app:latest

# 푸시
docker push 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/test-app:latest
```

## ☸️ 3단계: EKS 클러스터 설정

### 3.1 EKS 클러스터 생성

```bash
# eksctl로 클러스터 생성
eksctl create cluster \
  --name test-cluster \
  --region ap-northeast-2 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed
```

### 3.2 kubectl 설정

```bash
# kubeconfig 업데이트
aws eks update-kubeconfig --region ap-northeast-2 --name test-cluster

# 클러스터 확인
kubectl get nodes
```

### 3.3 AWS Load Balancer Controller 설치

```bash
# IAM 정책 생성
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Helm으로 설치
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=test-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

## 🚀 4단계: Kubernetes 배포

### 4.1 ConfigMap 및 Secret 생성

```bash
# ConfigMap 수정
# k8s/configmap.yml 파일에서 RDS 엔드포인트 업데이트
nano k8s/configmap.yml
# db_host를 RDS 엔드포인트로 변경

# ConfigMap 적용
kubectl apply -f k8s/configmap.yml

# Secret 생성 (실제 비밀번호 사용)
kubectl create secret generic app-secret \
  --from-literal=db_user=admin \
  --from-literal=db_password=YourSecurePassword
```

### 4.2 Deployment 수정 및 배포

```bash
# k8s/deployment.yml에서 이미지 경로 업데이트
nano k8s/deployment.yml
# image 필드를 ECR 이미지로 변경

# 배포
kubectl apply -f k8s/deployment.yml
kubectl apply -f k8s/service.yml

# 확인
kubectl get pods
kubectl get svc
```

### 4.3 Ingress 설정 (선택사항)

```bash
# ACM 인증서 생성
aws acm request-certificate \
  --domain-name yourdomain.com \
  --validation-method DNS \
  --region ap-northeast-2

# k8s/ingress.yml 수정
# - certificate-arn을 실제 ARN으로 변경
# - host를 실제 도메인으로 변경
nano k8s/ingress.yml

# Ingress 적용
kubectl apply -f k8s/ingress.yml

# ALB 생성 확인
kubectl get ingress
kubectl describe ingress test-app-ingress
```

## 🔍 5단계: 검증 및 테스트

### 5.1 서비스 상태 확인

```bash
# Pod 상태
kubectl get pods -w

# 로그 확인
kubectl logs -f deployment/test-app

# Pod 내부 접속
kubectl exec -it deployment/test-app -- sh
```

### 5.2 API 테스트

```bash
# 포트 포워딩으로 로컬 테스트
kubectl port-forward svc/test-app 8080:80

# API 테스트
curl http://localhost:8080/health
curl http://localhost:8080/api/items

# 또는 Ingress를 통한 외부 접속
# ALB DNS 주소 확인
kubectl get ingress test-app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# 외부에서 테스트
curl https://yourdomain.com/health
curl https://yourdomain.com/api/items
```

## 📊 6단계: 모니터링 및 오토스케일링

### 6.1 Horizontal Pod Autoscaler 설정

```bash
# Metrics Server 설치
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# HPA 생성
kubectl autoscale deployment test-app \
  --cpu-percent=70 \
  --min=2 \
  --max=10

# HPA 확인
kubectl get hpa
```

### 6.2 CloudWatch 모니터링

```bash
# Container Insights 활성화
aws eks create-addon \
  --cluster-name test-cluster \
  --addon-name amazon-cloudwatch-observability

# RDS 모니터링
# AWS 콘솔 > RDS > 모니터링 탭에서 확인
```

## 🔄 7단계: 롤백 계획

### 로컬로 롤백

마이그레이션 중 문제가 발생하면 로컬 환경으로 롤백:

```bash
# RDS에서 데이터 백업
mysqldump -h rds-endpoint.amazonaws.com -u admin -p testdb > rds_backup.sql

# 로컬 Docker 재시작
docker compose up -d

# 필요시 RDS 데이터를 로컬로 복원
docker compose exec -T mysql mysql -u testuser -p testdb < rds_backup.sql
```

## ✅ 체크리스트

마이그레이션 전 확인사항:

- [ ] RDS 인스턴스 생성 및 보안 그룹 설정
- [ ] 로컬 데이터 백업 완료
- [ ] ECR 레포지토리 생성 및 이미지 푸시
- [ ] EKS 클러스터 생성 및 kubectl 설정
- [ ] ConfigMap/Secret에 RDS 정보 설정
- [ ] ACM 인증서 발급 (HTTPS 필요시)
- [ ] ALB Ingress Controller 설치
- [ ] DNS 레코드 설정 (도메인 사용시)
- [ ] 모니터링 및 로깅 설정

## 💰 비용 최적화 팁

1. **RDS**: 개발 환경은 `db.t3.micro` 사용, 프로덕션은 필요에 따라 스케일업
2. **EKS**: Spot 인스턴스 사용으로 비용 절감
3. **ALB**: 사용하지 않을 때는 Ingress 삭제
4. **백업**: RDS 백업 주기를 필요에 맞게 조정 (7일 → 3일)

## 🔐 보안 권장사항

1. **RDS**: VPC 내부에 배치, public 접근 불가
2. **Secrets**: AWS Secrets Manager와 통합 고려
3. **IAM**: 최소 권한 원칙 적용
4. **네트워크**: Security Group으로 접근 제한
5. **암호화**: RDS 암호화 활성화

## 📚 추가 리소스

- [AWS EKS 문서](https://docs.aws.amazon.com/eks/)
- [AWS RDS 문서](https://docs.aws.amazon.com/rds/)
- [Kubernetes 문서](https://kubernetes.io/docs/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
