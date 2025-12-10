# 범용 클라우드 Kubernetes 마이그레이션 가이드

이 가이드는 특정 클라우드 벤더(AWS, GCP, Azure 등)의 전용 CLI 도구를 사용하지 않고, **웹 콘솔(Web Console)**과 **표준 도구(Docker, kubectl)**만을 사용하여 애플리케이션을 마이그레이션하는 절차를 설명합니다. 이 방법은 CLI가 지원되지 않거나 제한적인 모든 클라우드 플랫폼(NHN Cloud, KT Cloud, Naver Cloud 등 포함)에 적용 가능합니다.

## 📋 목차

1. [사전 준비](#1-사전-준비)
2. [Kubernetes 클러스터 연결](#2-kubernetes-클러스터-연결)
3. [컨테이너 이미지 준비](#3-컨테이너-이미지-준비)
4. [데이터베이스 설정](#4-데이터베이스-설정)
5. [애플리케이션 배포](#5-애플리케이션-배포)
6. [외부 접속 설정 (LoadBalancer)](#6-외부-접속-설정-loadbalancer)
7. [문제 해결](#7-문제-해결)

---

## 1. 사전 준비

### 1.1 로컬 필수 도구 설치 (Rocky Linux 기준)

클라우드 벤더의 CLI(aws-cli, gcloud 등)는 필요하지 않지만, 다음 표준 도구는 로컬 컴퓨터에 설치되어 있어야 합니다.

#### 1. Docker 설치
```bash
# Docker 저장소 추가 및 설치
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 서비스 시작 및 자동 실행 설정
sudo systemctl start docker
sudo systemctl enable docker

# sudo 없이 docker 사용 설정 (로그아웃 후 재로그인 필요)
sudo usermod -aG docker $USER

# Shell Completion (Docker는 설치 시 자동 포함됨)
# 적용이 안 될 경우:
source /usr/share/bash-completion/completions/docker
```

#### 2. kubectl 설치
```bash
# Kubernetes 저장소 추가 (v1.29 기준)
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

# 설치
sudo dnf install -y kubectl

# Shell Completion 설정
sudo dnf install -y bash-completion
echo 'source <(kubectl completion bash)' >> ~/.bashrc
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
source ~/.bashrc
```

#### 3. MySQL Client 설치
```bash
sudo dnf install -y mysql
```

### 1.2 데이터 백업

현재 로컬 Docker 환경의 데이터를 백업합니다.

```bash
# 전체 데이터베이스 백업 (스키마 + 데이터)
docker compose exec mysql mysqldump -uroot -prootpassword --all-databases > full_backup.sql

# 또는 특정 데이터베이스만 백업
docker compose exec mysql mysqldump -uroot -prootpassword testdb > testdb_backup.sql
```

---

## 2. Kubernetes 클러스터 연결

### 2.1 [웹 콘솔] 클러스터 생성

1.  **Kubernetes Service** (EKS, NKS, GKE 등) 메뉴로 이동합니다.
2.  클러스터를 생성합니다.
    *   **Worker Node**: 2개 이상 권장
    *   **CNI/Network**: 기본값 사용

### 2.2 [로컬] kubectl 연결 설정

클라우드 CLI 없이 `kubectl`을 연결하려면 **Kubeconfig** 파일이 필요합니다.

1.  웹 콘솔의 클러스터 상세 화면에서 **"Kubeconfig 다운로드"** 또는 **"설정 파일 보기"** 버튼을 찾습니다.
2.  파일을 다운로드하여 `~/.kube/config` 경로에 저장하거나, 내용을 복사하여 해당 파일에 붙여넣습니다.
    *   *주의: 기존 설정이 있다면 덮어쓰지 말고 백업하거나 `KUBECONFIG` 환경변수를 활용하세요.*

```bash
# 연결 테스트
kubectl get nodes
```

> **💡 팁: 여러 클러스터를 동시에 관리하려면?**
>
> 매번 `KUBECONFIG` 환경변수를 바꾸거나 파일을 덮어쓸 필요가 없습니다.
>
> 1. **설정 파일 병합**: 환경변수에 여러 경로를 콜론(`:`)으로 구분하여 지정합니다.
>    ```bash
>    export KUBECONFIG=~/.kube/config:~/.kube/config-aws:~/.kube/config-gcp
>    ```
> 2. **컨텍스트(Context) 전환**: `kubectl` 명령어로 쉽게 클러스터를 오갈 수 있습니다.
>    ```bash
>    # 등록된 클러스터(Context) 목록 확인
>    kubectl config get-contexts
>
>    # 특정 클러스터로 전환
>    kubectl config use-context <CONTEXT_NAME>
>    ```

---

## 3. 컨테이너 이미지 준비

### 3.1 [웹 콘솔] 레지스트리 생성

1.  클라우드 콘솔에서 **Container Registry** (ECR, NCR, GCR 등) 메뉴로 이동합니다.
2.  새로운 레지스트리(또는 레포지토리)를 생성합니다. (예: `test-stack-app`)
3.  레지스트리 주소를 복사합니다. (예: `myregistry.kr.ncr.ntruss.com/test-stack-app`)

### 3.2 [로컬] 환경변수 설정

대부분의 클라우드 레지스트리는 웹 콘솔에서 "로그인 방법" 가이드를 제공합니다. 보통 Docker 로그인 비밀번호로 사용할 수 있는 **API Key**나 **Token**을 발급받을 수 있습니다.
보안을 위해 발급받은 레지스트리 접속 정보와 주소를 셸 환경변수로 설정합니다.

```bash
# 레지스트리 및 이미지 정보 설정
export REGISTRY_URL="myregistry.kr.ncr.ntruss.com"
export IMAGE_NAME="test-stack-app"
export IMAGE_TAG="v1"
export REGISTRY_USER="<ACCESS_KEY_ID>"
export REGISTRY_PASSWORD="<SECRET_ACCESS_KEY>"
```

### 3.3 [옵션] Docker Compose로 로컬 테스트

푸시하기 전에 로컬에서 이미지를 빌드하고 실행하여 테스트할 수 있습니다.
`docker-compose.yml`이 환경변수를 참조하도록 설정되어 있어, 빌드 시 자동으로 레지스트리 태그가 붙습니다.

```bash
# 이미지 빌드 및 실행 (환경변수 적용됨)
docker compose up -d --build

# 테스트 완료 후 종료
docker compose down
```

### 3.4 [로컬] Docker 로그인 및 푸시

테스트가 완료된 이미지를 레지스트리에 푸시합니다.

```bash
# 1. 레지스트리 로그인 (Registry URL 사용)
echo $REGISTRY_PASSWORD | docker login $REGISTRY_URL -u $REGISTRY_USER --password-stdin

# 2. 이미지 푸시 (이미 빌드된 이미지 사용)
docker push $REGISTRY_URL/$IMAGE_NAME:$IMAGE_TAG
```

---

### 3.5 [로컬] Kubernetes Image Pull Secret 생성

Kubernetes가 비공개 레지스트리에서 이미지를 가져올 수 있도록 접속 정보를 담은 Secret을 생성합니다.
(이미지 푸시를 위해 설정했던 환경변수를 그대로 사용합니다.)

```bash
kubectl create secret docker-registry regcred \
  --docker-server=$REGISTRY_URL \
  --docker-username=$REGISTRY_USER \
  --docker-password=$REGISTRY_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## 4. 데이터베이스 설정

운영 환경에 맞게 다음 두 가지 옵션 중 하나를 선택하여 진행합니다.

- **[옵션 A] 관리형 데이터베이스 (RDS, Cloud SQL 등) 사용**: (권장) 백업, 고가용성, 보안 관리가 용이하지만 비용이 발생합니다.
- **[옵션 B] Kubernetes 내 MySQL 컨테이너 실행**: 비용이 저렴하고 설정이 간단하지만, 스토리지 및 백업을 직접 관리해야 합니다.

---

### [옵션 A] 관리형 데이터베이스 사용 (권장)

#### 4.A.1 [웹 콘솔] 관리형 데이터베이스 생성

1.  클라우드 관리 콘솔에 로그인합니다.
2.  **RDS** 또는 **Database** 서비스 메뉴로 이동합니다.
3.  **MySQL 인스턴스 생성**을 클릭합니다.
    *   **버전**: MySQL 8.0 권장 (현재 프로젝트와 동일)
    *   **사양**: 테스트용이면 최소 사양(1 vCPU, 2GB RAM 등) 선택
    *   **네트워크**: Kubernetes 클러스터와 통신 가능한 VPC/Subnet 선택 (보통 'Private' 권장)
    *   **접속 정보**: Master Username과 Password를 설정하고 **반드시 기록**해둡니다.

#### 4.A.2 [웹 콘솔] 외부 접속 허용 (데이터 이관용)

데이터를 넣기 위해 **일시적으로** 외부 접속을 허용해야 합니다.

1.  **DB 연결 정보 환경변수 설정**
    생성된 DB의 엔드포인트 주소를 환경변수로 설정합니다. (이후 배포 단계에서 사용됩니다.)

    ```bash
    export DB_HOST="<RDS_ENDPOINT_ADDRESS>"
    export DB_PORT="3306"
    export DB_NAME="testdb"
    export DB_USER="admin"
    export DB_PASSWORD="<DB_PASSWORD>"
    ```
2.  생성된 DB의 **보안 그룹(Security Group/ACG)** 설정으로 이동합니다.
3.  **Inbound 규칙**에 내 PC의 IP(또는 `0.0.0.0/0`)에서 `3306` 포트 접속을 허용하는 규칙을 추가합니다.
4.  DB 설정에서 **Public Access(공인 IP 접속)** 기능을 켭니다. (데이터 이관 후 다시 끌 것입니다)
5.  DB의 **접속 주소(Endpoint/Host)**와 **포트**를 확인합니다.

#### 4.A.3 [로컬] 데이터 복원

로컬 터미널에서 원격 DB로 데이터를 밀어넣습니다.

```bash
# 원격 DB 접속 테스트
mysql -h <DB_HOST> -P <DB_PORT> -u <DB_USER> -p

# 데이터 복원
mysql -h <DB_HOST> -P <DB_PORT> -u <DB_USER> -p < testdb_backup.sql

# 초기화 스키마
mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p < app/db/schema.sql
```

#### 4.A.4 [웹 콘솔] 보안 강화

1.  데이터 복원이 완료되면 DB의 **Public Access**를 끕니다.
2.  보안 그룹에서 내 PC의 IP 허용 규칙을 삭제합니다.
3.  대신 **Kubernetes 클러스터의 대역(CIDR)**이나 **Worker Node들의 보안 그룹**에서의 접근만 허용하도록 규칙을 수정합니다.

---

### [옵션 B] Kubernetes 내 MySQL 컨테이너 실행

관리형 DB를 사용하지 않고, 클러스터 내부에 MySQL 파드를 띄워 사용하는 방법입니다.

#### 4.B.1 스토리지 설정 (StorageClass & PVC)

NHN Cloud(NKS)와 Gabia Cloud(GKS) 환경에 맞춰 이미 `k8s/overlays` 디렉토리에 스토리지 설정이 완료되어 있습니다.
Kustomize를 사용하여 배포 시 자동으로 적절한 스토리지 클래스가 적용됩니다.

- **NKS**: `k8s/overlays/nks/storage-class.yml` (`general-bs`)
- **GKS**: `k8s/overlays/gks/kustomization.yaml` (`ssd-iscsi` 패치)

#### 4.B.2 배포 및 데이터 설정

MySQL 파드를 띄워서 데이터를 넣기 위해, 애플리케이션 스택 전체를 먼저 배포합니다.

**1. DB 연결 정보 설정**
```bash
export DB_HOST="mysql"
export DB_PORT="3306"
export DB_NAME="testdb"
export DB_USER="testuser"
export DB_PASSWORD="testpassword"
export DB_ROOT_PASSWORD="rootpassword" # MySQL 루트 비밀번호
```

**2. 스택 배포 (Kustomize)**

환경에 맞는 명령어를 실행하여 배포합니다. (이때 App과 DB가 모두 배포됩니다)

```bash
# NKS (NHN Cloud)
kubectl kustomize k8s/overlays/nks/mysql | envsubst | kubectl apply -f -

# GKS (Gabia Cloud)
kubectl kustomize k8s/overlays/gks/mysql | envsubst | kubectl apply -f -
```

**3. 파드 상태 확인**
```bash
# MySQL 파드가 Running 상태가 될 때까지 대기
kubectl get pods -l app=mysql
```

**4. 데이터 설정 (택 1)**

먼저 MySQL 파드의 이름을 변수에 저장합니다.
```bash
export MYSQL_POD=$(kubectl get pods -l app=mysql -o jsonpath="{.items[0].metadata.name}")
```

**[Case 1] 기존 데이터 가져오기 (마이그레이션)**
로컬의 백업 파일을 사용하여 데이터를 복원합니다.

```bash
# 1. 로컬 덤프 파일을 파드로 복사
kubectl cp testdb_backup.sql $MYSQL_POD:/tmp/backup.sql

# 2. 데이터 복원 실행 (Pod 내부에서 리다이렉션 실행)
kubectl exec -it $MYSQL_POD -- sh -c 'mysql -uroot -prootpassword testdb < /tmp/backup.sql'
```

**[Case 2] 빈 데이터베이스로 시작하기 (초기화)**
기존 데이터 없이 테이블 구조(Schema)만 생성하여 새로 시작합니다.

```bash
# 1. 스키마 파일 복사 (프로젝트 내 app/db/schema.sql 사용)
kubectl cp app/db/schema.sql $MYSQL_POD:/tmp/schema.sql

# 2. 스키마 적용 (Pod 내부에서 리다이렉션 실행)
kubectl exec -it $MYSQL_POD -- sh -c 'mysql -uroot -prootpassword testdb < /tmp/schema.sql'
```

---

## 5. 애플리케이션 배포

### 5.1 [로컬] 배포 파일 수정 및 적용

`k8s/` 디렉토리(base, overlays)의 리소스들은 환경변수를 참조하도록 설정되어 있습니다.
Kustomize를 통해 구조를 병합하고, `envsubst`를 통해 환경 변수를 주입하여 배포합니다.

**1. DB 연결 정보 및 필수 변수 확인**
(이전 단계에서 설정한 변수들이 유효한지 확인합니다.)

```bash
echo $DB_HOST
echo $REGISTRY_URL
# 설정값들이 출력되어야 합니다.
```

**2. 애플리케이션 시크릿 생성 (필수)**
DB 비밀번호 등 민감한 정보를 담은 Secret을 생성합니다. (`app-secret`이 없으면 파드가 생성되지 않습니다.)

```bash
kubectl create secret generic app-secret \
  --from-literal=db_user=$DB_USER \
  --from-literal=db_password=$DB_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -
```

**3. 애플리케이션 배포 (Kustomize + envsubst)**

4단계에서 선택한 옵션에 맞는 명령어를 실행합니다.

> **⚠️ 주의: 옵션을 변경하는 경우**
> 이전에 다른 옵션(예: MySQL → RDS)으로 배포했다면, 먼저 기존 리소스를 삭제해야 합니다:
> ```bash
> # MySQL 관련 리소스 삭제 (RDS로 전환 시)
> kubectl delete deployment mysql
> kubectl delete svc mysql
> kubectl delete pvc mysql-pvc
> ```

**[옵션 A] RDS/관리형 DB 사용 시:**
```bash
# 이미지 태그 확인
./scripts/check-image.sh

# NKS (NHN Cloud) - RDS 사용
kubectl kustomize k8s/overlays/nks/rds | envsubst | kubectl apply -f -

# GKS (Gabia Cloud) - 향후 RDS 지원 시
kubectl kustomize k8s/overlays/gks/rds | envsubst | kubectl apply -f -
```

**[옵션 B] Kubernetes 내 MySQL 컨테이너 사용 시:**
```bash
# 이미지 태그 확인
./scripts/check-image.sh

# NKS (NHN Cloud) - MySQL 컨테이너
kubectl kustomize k8s/overlays/nks/mysql | envsubst | kubectl apply -f -

# GKS (Gabia Cloud) - MySQL 컨테이너
kubectl kustomize k8s/overlays/gks/mysql | envsubst | kubectl apply -f -
```

**4. 배포 확인**
```bash
kubectl get all
kubectl get pvc  # MySQL 옵션 사용 시에만 PVC가 생성됩니다
```
옵션 B(MySQL 컨테이너)를 선택한 경우에만 `mysql-pvc`가 생성됩니다.

---

## 6. 외부 접속 설정 (LoadBalancer)

클라우드 CLI나 복잡한 Ingress Controller 설정 없이 가장 쉽게 외부 접속을 여는 방법은 `LoadBalancer` 타입의 서비스를 사용하는 것입니다.

### 6.1 Service 수정 및 적용

`k8s/service.yml` 파일을 열어 `type`을 `LoadBalancer`로 변경합니다. (기본 `ClusterIP`인 경우)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: test-app
spec:
  type: LoadBalancer  # 중요: 클라우드 로드밸런서 자동 생성
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
  selector:
    app: test-app
```

```bash
# 기존 Service 설정 업데이트 (ClusterIP -> LoadBalancer)
kubectl apply -f k8s/service.yml
```

### 6.2 접속 주소 확인

```bash
kubectl get svc test-app -w
```

`EXTERNAL-IP` 항목에 IP 주소나 도메인이 할당될 때까지 기다립니다. (몇 분 소요될 수 있음)
할당된 주소(`http://<EXTERNAL-IP>`)를 브라우저에 입력하여 접속합니다.

---

## 7. 문제 해결

### Pod가 ImagePullBackOff 상태일 때
*   **원인**: Kubernetes가 비공개 레지스트리 이미지를 가져오지 못함.
*   **해결**:
    1.  `kubectl create secret docker-registry` 명령으로 레지스트리 접속용 Secret 생성.
    2.  Deployment YAML의 `spec.template.spec` 아래에 `imagePullSecrets` 추가.

### DB 연결 실패 (CrashLoopBackOff)
*   **원인**: Pod에서 DB로 네트워크 접근이 막혀있음.
*   **해결**:
    1.  DB의 보안 그룹(ACG) 설정 확인.
    2.  Kubernetes Worker Node들의 IP 대역이나 보안 그룹이 DB 접속 허용 목록에 있는지 확인.
    3.  `kubectl logs <pod-name>` 으로 에러 메시지 확인.

### LoadBalancer IP가 할당되지 않을 때 (Pending)
*   **원인**: 클라우드 플랫폼의 리소스 부족, 권한 부족, 또는 지원하지 않는 기능.
*   **해결**:
    1.  `kubectl describe svc test-app` 명령으로 이벤트 로그 확인.
    2.  일부 클라우드는 `NodePort` 방식을 사용해야 할 수도 있음.

### LoadBalancer 접속 시 응답 없음 (ERR_EMPTY_RESPONSE / Timeout)
*   **원인**: Worker Node의 보안 그룹(ACG)에서 NodePort 대역(30000-32767)에 대한 접근을 차단하고 있음.
*   **해결**:
    1.  NHN Cloud 콘솔 > **Network** > **Security Groups** (또는 ACG)로 이동.
    2.  Kubernetes Worker Node에 적용된 보안 그룹을 선택.
    3.  **Inbound 규칙**에 `TCP` 프로토콜, 포트 범위 `30000-32767` (또는 전체 `1-65535`)에 대해 `0.0.0.0/0` (또는 LoadBalancer 서브넷) 허용 규칙 추가.
    4.  `kubectl get svc test-app` 명령으로 할당된 NodePort(예: `80:31234/TCP`라면 31234)가 열려 있는지 확인.
