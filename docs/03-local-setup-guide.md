# 로컬 환경 구축 가이드

Ubuntu 기준으로 로컬 쿠버네티스 환경을 처음부터 구축하는 과정을 안내한다.
(macOS에서도 동일하게 동작한다 — setup.sh가 OS를 자동 감지한다.)

---

## 전제 조건

- Ubuntu 22.04+ (또는 macOS)
- sudo 권한

---

## Step 1: 도구 설치

```bash
make setup
```

이 명령은 `scripts/setup.sh`를 실행해서 다음 도구를 자동 설치한다:

| 도구 | 역할 | Ubuntu 설치 방식 |
|------|------|-----------------|
| **Docker** | 컨테이너 런타임 | apt (docker-ce) |
| **k3d** | k3s를 Docker 안에서 실행하는 도구 | 공식 install script |
| **kubectl** | 쿠버네티스 CLI | apt (kubernetes.io) |
| **helm** | 쿠버네티스 패키지 매니저 | 공식 install script |
| **kustomize** | YAML 매니페스트 관리 도구 | 공식 install script |

설치 후 버전이 출력되면 성공:
```
[INFO] === 설치된 도구 버전 ===
  Docker:     Docker version 27.x.x
  k3d:        k3d version v5.x.x
  kubectl:    Client Version: v1.31.x
  helm:       v3.x.x
  kustomize:  v5.x.x
```

### Docker 그룹 권한 (Ubuntu)

Docker 설치 후 처음이라면 그룹 권한 반영이 필요하다:
```bash
# 현재 세션에 docker 그룹 반영 (재로그인 대신)
newgrp docker

# 확인
docker ps
```

---

## Step 2: 클러스터 생성

```bash
make cluster-up
```

이 명령은 다음을 수행한다:
1. k3d로 `seemedi-local` 클러스터를 생성
2. 구성: **1 server (컨트롤 플레인) + 2 agents (워커 노드)**
3. 포트 매핑: 80(HTTP), 443(HTTPS)을 호스트에 연결
4. kubeconfig를 설정해서 `kubectl`이 이 클러스터에 연결

### 확인

```bash
kubectl get nodes
```

```
NAME                          STATUS   ROLES                  AGE   VERSION
k3d-seemedi-local-server-0    Ready    control-plane,master   1m    v1.30.x+k3s1
k3d-seemedi-local-agent-0     Ready    <none>                 1m    v1.30.x+k3s1
k3d-seemedi-local-agent-1     Ready    <none>                 1m    v1.30.x+k3s1
```

3개의 노드가 `Ready` 상태면 성공.

### 노드(Node)란?
- server = **컨트롤 플레인**: 클러스터를 관리하는 "두뇌" (스케줄링, API 서버)
- agent = **워커 노드**: 실제 Pod(앱)가 실행되는 "일꾼"
- 프로덕션(서버 이관 후)에서는 control-plane 3대(HA) + worker N대를 사용한다

---

## Step 3: 앱 이미지 빌드

```bash
make build
```

`app/Dockerfile`로 FastAPI 샘플 앱의 Docker 이미지를 빌드한다.

### 확인

```bash
docker images sample-app
```

```
REPOSITORY   TAG     IMAGE ID       CREATED          SIZE
sample-app   local   a1b2c3d4e5f6   10 seconds ago   ~150MB
```

---

## Step 4: 전체 배포

```bash
make deploy
```

이 명령은 다음을 순서대로 수행한다:
1. Docker 이미지 빌드 + k3d 클러스터에 import
2. 네임스페이스 생성 (`seemedi-dev`, `monitoring`)
3. Ingress Controller 설치 (nginx)
4. PostgreSQL 배포 (StatefulSet + PVC + ConfigMap + Secret)
5. 샘플 앱 배포 (Deployment + Service + Ingress + ConfigMap + Secret)

### 확인

```bash
make status
```

모든 Pod가 `Running` 상태여야 한다:
```
=== 네임스페이스: seemedi-dev ===
NAME                          READY   STATUS    RESTARTS   AGE
pod/sample-app-xxx-yyy        1/1     Running   0          1m
pod/sample-app-xxx-zzz        1/1     Running   0          1m
pod/postgres-0                1/1     Running   0          1m
```

---

## Step 5: 앱 동작 확인

### 방법 1: 포트포워딩 (권장)

```bash
make port-forward
```

그 후:
```bash
curl http://localhost:8000/healthz
# {"status": "ok"}

curl http://localhost:8000/
# {"service": "k8s-local-lab", "version": "0.1.0", ...}
```

### 방법 2: Ingress 경유

```bash
# /etc/hosts에 추가 (Ubuntu)
echo "127.0.0.1 app.localhost" | sudo tee -a /etc/hosts

curl http://app.localhost/healthz
# {"status": "ok"}
```

---

## Step 6: 모니터링 설치 (선택)

```bash
make deploy-monitoring
```

Helm으로 kube-prometheus-stack을 설치한다. 이후:

```bash
make port-forward
# Prometheus → http://localhost:9090
```

---

## 문제 해결

### Pod가 `Pending` 상태

```bash
kubectl describe pod <이름> -n seemedi-dev
```

`Events` 섹션을 확인한다. 주로:
- `Insufficient cpu/memory` → 리소스 부족. 서버 리소스 확인
- `no persistent volumes available` → PVC 문제

### Pod가 `CrashLoopBackOff` 상태

```bash
kubectl logs <이름> -n seemedi-dev
```

로그에서 에러 확인. 주로:
- 앱 코드 에러
- 환경 변수 누락
- DB 연결 실패

### Pod가 `ImagePullBackOff` 상태

```bash
kubectl describe pod <이름> -n seemedi-dev
```

- `imagePullPolicy: Never` 설정 확인 (로컬 이미지는 pull하면 안 됨)
- `make load`로 이미지가 k3d에 import되었는지 확인

### Docker 권한 오류 (Ubuntu)

```
Got permission denied while trying to connect to the Docker daemon socket
```

```bash
sudo usermod -aG docker $USER
newgrp docker
```

### 클러스터 완전 초기화

```bash
make clean       # 클러스터 삭제
make cluster-up  # 새로 생성
make deploy      # 다시 배포
```

---

## 다음 단계

환경이 구축되었으면, 일상적인 사용법을 익혀보자.

→ [04-usage-guide.md](04-usage-guide.md)
