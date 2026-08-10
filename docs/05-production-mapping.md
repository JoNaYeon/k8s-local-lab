# 로컬 ↔ 프로덕션 대응표

이 문서는 로컬 테스트 환경의 각 구성 요소가 서버(프로덕션)에서 어떻게 변하는지를 설명한다.
로컬에서 연습한 것이 서버 이관 시 어떻게 연결되는지 이해하는 것이 목표다.

---

## 전체 대응표

| 구분 | 로컬 (k3d/k3s) | 서버 프로덕션 (kubeadm 표준 k8s) |
|------|---------------|-------------------------------------|
| **k8s 배포판** | k3s (경량) | **kubeadm (표준)** |
| **클러스터 실행** | k3d (Docker 컨테이너 위) | 베어메탈/VM 위 kubeadm |
| **노드** | 1 server + 2 agents (Docker) | 3+ control-plane (HA) + N workers (실제 서버) |
| **kubectl / YAML** | **동일** | **동일** |
| **Ingress** | nginx-ingress (app.localhost) | Nginx Ingress + 실 도메인 + TLS |
| **로드밸런서** | k3d 내장 (Docker port-mapping) | MetalLB 또는 하드웨어 LB |
| **스토리지** | local-path (로컬 디스크) | Ceph, NFS, 또는 AWS EBS |
| **레지스트리** | 로컬 이미지 (k3d import) | GHCR 또는 ECR |
| **DB** | PostgreSQL StatefulSet (1 replica) | RDS 또는 HA PostgreSQL (Patroni) |
| **Secret** | base64 YAML (더미값) | External Secrets Operator + Vault/AWS SM |
| **모니터링** | Prometheus (Helm, 최소 설정) | Prometheus + Grafana + Alertmanager (전체) |
| **CI/CD** | 수동 (make deploy) | GitHub Actions → ArgoCD 또는 Flux |
| **네트워크** | 단일 Docker bridge | 병원망 + 기업망 + AWS VPC |
| **네임스페이스** | seemedi-dev, monitoring | dev, staging, prod + monitoring + system |
| **RBAC** | 없음 (로컬이므로) | 역할별 접근 제어 (admin/developer/viewer) |

---

## 핵심: k3s → kubeadm 전환 시 뭐가 변하는가?

### 변하지 않는 것 (대부분)

로컬에서 작성한 **매니페스트 YAML, kubectl 명령, 배포 흐름**은 그대로 사용된다.

```
이 레포의 manifests/ 디렉토리:
  ├── app/deployment.yml     → 서버에서도 그대로 사용 ✅
  ├── app/service.yml        → 그대로 ✅
  ├── app/ingress.yml        → host만 실 도메인으로 변경 ✅
  ├── app/configmap.yml      → 환경별 값만 변경 ✅
  ├── database/              → 서버에서는 RDS로 대체 가능
  └── monitoring/            → 값만 조정 후 그대로 사용 ✅
```

### 변하는 것 (인프라 레벨)

| 항목 | k3s (로컬) | kubeadm (서버) | 비고 |
|------|-----------|---------------|------|
| 클러스터 설치 | `k3d cluster create` | `kubeadm init` + `kubeadm join` | 서버별 직접 실행 |
| 컨트롤 플레인 | 단일 프로세스 (k3s) | API Server, Scheduler, Controller Manager, etcd 분리 | HA 구성 |
| 데이터스토어 | SQLite (k3s 기본) | etcd (독립 클러스터) | etcd 백업 필수 |
| 네트워크 플러그인 | Flannel (k3s 내장) | Calico, Cilium 등 선택 | 네트워크 정책 지원 |
| 인그레스 | Traefik(비활성화) → nginx | nginx 또는 Traefik | 큰 차이 없음 |

**요약: 앱 개발자 입장에서는 거의 변하지 않고, 클러스터 관리자 입장에서 설치/구성 방식이 달라진다.**

---

## 주요 변경점 상세 설명

### 1. 클러스터: Docker 컨테이너 → 실제 서버

**로컬**: Docker 컨테이너 안에서 k3s가 실행됨. `make cluster-up`으로 1분 만에 생성.

**서버**:
```
서버 3대 (컨트롤 플레인, HA 구성)
  ├── kubeadm init (첫 번째 노드)
  ├── kubeadm join --control-plane (2번째)
  └── kubeadm join --control-plane (3번째)

서버 N대 (워커 노드)
  ├── kubeadm join (worker 1)
  ├── kubeadm join (worker 2)
  └── ...
```
- 컨트롤 플레인 3대 → 1대가 죽어도 클러스터 유지 (HA)
- etcd 백업 필수 (클러스터 전체 상태가 여기 저장됨)

### 2. 스토리지: local-path → 분산 스토리지

**로컬**: k3d가 Docker 볼륨에 데이터 저장. 클러스터 삭제하면 데이터도 삭제.

**서버**:
- **Ceph/Rook**: 서버 디스크를 묶어서 분산 스토리지 구성
- **NFS**: 기존 NAS(192.168.20.201)를 PV로 연결
- **AWS EBS**: 클라우드 블록 스토리지
- 스냅샷/백업 정책 적용

### 3. Secret: base64 → 암호화 솔루션

**로컬**: Secret YAML에 base64로 더미값 저장 (학습용).

**서버**:
```
AWS Secrets Manager (또는 Vault)
    ↓ (자동 동기화)
External Secrets Operator (ESO)
    ↓ (k8s Secret 생성)
Pod에 환경 변수로 주입
```
- Secret YAML을 git에 커밋하지 않음
- 비밀번호 로테이션 자동화 가능

### 4. Ingress: localhost → 실 도메인 + TLS

**로컬**: `app.localhost`로 접근, HTTP만.

**서버**:
```yaml
spec:
  tls:
    - hosts:
        - app.seemedi.dev
      secretName: seemedi-tls        # cert-manager가 자동 발급
  rules:
    - host: app.seemedi.dev
```
- cert-manager로 Let's Encrypt TLS 인증서 자동 발급/갱신

### 5. DB: StatefulSet → 관리형 DB

**로컬**: PostgreSQL을 k8s StatefulSet으로 직접 운영.

**서버** (두 가지 선택지):
1. **AWS RDS** — 관리형 DB (백업, HA, 모니터링 자동)
2. **자체 운영** — Patroni + PostgreSQL (온프레미스 병원망)

### 6. CI/CD: 수동 → 자동화

**로컬**: `make build && make deploy` 수동 실행.

**서버**:
```
git push → GitHub Actions → Docker build → GHCR push
    → ArgoCD가 감지 → 자동 배포 (GitOps)
```

---

## SEEMEDI 특수 환경: 하이브리드 네트워크

```
┌─ 병원 폐쇄망 (9.x.x.x) ───────────┐
│ 원본 환자 데이터 (L4, PHI)           │
│ PostgreSQL (EMR DB)                  │
│ ※ 외부 반출 절대 금지                 │
└──────────┬───────────────────────────┘
           │ VPN (익명화된 데이터만)
           │
┌──────────▼───────────────────────────┐
│ 기업망 (20.x.x.x)                    │
│ 개발 서버, K8s 클러스터 (kubeadm)     │
│ AI 학습용 익명화 데이터               │
└──────────┬───────────────────────────┘
           │
┌──────────▼───────────────────────────┐
│ AWS (ap-northeast-2)                  │
│ RDS, S3, ECR                          │
│ AI 서비스 배포                        │
└───────────────────────────────────────┘
```

로컬 환경은 이 복잡한 네트워크를 **단일 k3d 클러스터의 네임스페이스**로 단순화한 것이다.
서버에서는 네트워크 존별로 별도 클러스터 또는 엄격한 네트워크 정책을 적용한다.

---

## 마무리: 로컬에서 익혀야 할 것

로컬 환경에서 이것들을 자유롭게 할 수 있으면, 서버 전환 준비가 된 것이다:

- [ ] `kubectl get/describe/logs` 로 상태 파악
- [ ] `make deploy`로 전체 배포 수행
- [ ] 코드 수정 → 이미지 빌드 → 재배포 사이클 반복
- [ ] Pod 스케일링 (수동 + HPA 확인)
- [ ] 롤백 수행
- [ ] Pod 안에 접속해서 디버깅
- [ ] ConfigMap/Secret 수정 후 적용
- [ ] 로그 확인 및 문제 해결
