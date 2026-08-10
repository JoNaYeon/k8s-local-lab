# 쿠버네티스 핵심 개념

이 문서에서는 쿠버네티스의 핵심 리소스를 하나씩 설명한다.
각 개념마다 **비유**, **역할**, **실제 YAML 예시**를 함께 보여준다.

---

## 1. Pod (파드)

### 비유: 방 하나

```
Pod = 호텔의 방 하나
컨테이너 = 방 안의 사람

- 한 방에 여러 사람이 있을 수 있다 (보통은 1명)
- 같은 방의 사람들은 화장실(네트워크)을 공유한다
- 방이 폐쇄되면 안의 사람들도 모두 나가야 한다
```

### 역할
- 쿠버네티스에서 배포하는 **가장 작은 단위**
- 보통 1 Pod = 1 컨테이너
- 같은 Pod 안의 컨테이너는 `localhost`로 통신 가능
- Pod는 일회용 — 죽으면 새로 만든다 (직접 만들지 않고 Deployment가 관리)

### 확인 명령어
```bash
kubectl get pods -n seemedi-dev            # Pod 목록
kubectl describe pod <이름> -n seemedi-dev  # Pod 상세 정보
kubectl logs <이름> -n seemedi-dev          # Pod 로그
kubectl exec -it <이름> -n seemedi-dev -- sh  # Pod 안으로 접속
```

---

## 2. Deployment (디플로이먼트)

### 비유: 채용 공고

```
Deployment = "이런 사람(Pod)을 3명 항상 유지해주세요"라는 채용 공고

- 1명이 퇴사(Pod 죽음)하면 → 자동으로 새 사람을 채용
- 자격 조건이 바뀌면(이미지 변경) → 한 명씩 교체 (롤링 업데이트)
- 실수였으면 → 이전 조건으로 되돌리기 (롤백)
```

### 역할
- Pod의 **원하는 상태**를 선언 (복제본 수, 이미지, 리소스 등)
- 자동 복구, 롤링 업데이트, 롤백 담당
- 우리 앱(`sample-app`)은 Deployment로 배포한다

### 핵심 필드
```yaml
spec:
  replicas: 2                    # Pod 2개 유지
  template:
    spec:
      containers:
        - image: sample-app:v1   # 이 이미지로
          resources:
            requests:
              cpu: "100m"        # 최소 0.1 CPU 보장
            limits:
              memory: "256Mi"    # 최대 256MB 사용 가능
```

### 핵심 명령어
```bash
kubectl get deployments -n seemedi-dev
kubectl rollout status deployment/sample-app -n seemedi-dev   # 배포 상태
kubectl rollout undo deployment/sample-app -n seemedi-dev     # 롤백
kubectl scale deployment/sample-app --replicas=5 -n seemedi-dev  # 스케일링
```

---

## 3. Service (서비스)

### 비유: 대표 전화번호

```
Service = 회사의 대표 전화번호

- 직원(Pod)이 바뀌어도 대표번호(Service IP)는 변하지 않는다
- 전화가 오면 현재 근무 중인 직원 중 한 명에게 연결한다 (로드밸런싱)
- 내선번호(Pod IP)는 계속 바뀌지만, 대표번호는 고정
```

### 역할
- Pod에 **안정적인 네트워크 주소(DNS)** 제공
- Pod들에 **트래픽 분산** (로드밸런싱)
- Pod가 죽었다 살아나도 Service 주소는 변하지 않음

### 타입

| 타입 | 설명 | 사용 |
|------|------|------|
| ClusterIP | 클러스터 내부에서만 접근 | 기본값. 앱 간 통신 |
| NodePort | 노드 포트로 외부 접근 | 개발/테스트 |
| LoadBalancer | 클라우드 LB 연동 | 프로덕션 |
| Headless | DNS만 제공, IP 없음 | StatefulSet (DB 등) |

### 핵심 명령어
```bash
kubectl get svc -n seemedi-dev
kubectl describe svc sample-app -n seemedi-dev
```

---

## 4. Ingress (인그레스)

### 비유: 건물 안내 데스크

```
Ingress = 건물 1층 안내 데스크

방문자: "마케팅팀 가고 싶어요" (app.localhost/api)
안내원: "3층 302호로 가세요" (sample-app Service로 라우팅)

방문자: "인사팀 가고 싶어요" (hr.localhost)
안내원: "5층 501호로 가세요" (hr-app Service로 라우팅)
```

### 역할
- 클러스터 외부에서 오는 HTTP(S) 요청을 **도메인/경로 기반으로 라우팅**
- TLS(HTTPS) 종료
- Service 앞에서 동작

### 우리 설정
```
app.localhost → sample-app Service (port 80) → Pod (port 8000)
```

---

## 5. Namespace (네임스페이스)

### 비유: 건물의 층

```
Namespace = 건물의 각 층

- 1층(seemedi-dev): 앱 + DB
- 2층(monitoring): 모니터링 도구
- 각 층은 독립적으로 관리 가능
- 같은 층에서는 이름만으로 찾기 가능 (층이 다르면 전체 주소 필요)
```

### 역할
- 리소스를 **논리적으로 격리**
- 팀/환경/용도별 구분 (dev, staging, prod)
- RBAC(권한 제어)를 네임스페이스 단위로 적용 가능

### 우리 네임스페이스
- `seemedi-dev` — 앱 + DB
- `monitoring` — Prometheus

---

## 6. ConfigMap

### 비유: 게시판의 공지사항

```
ConfigMap = 사무실 게시판에 붙은 공지사항

- 비밀이 아닌 정보: 회의실 예약 규칙, 점심시간 안내 등
- 누구나 볼 수 있는 설정
- 변경하면 다음에 확인하는 사람부터 적용됨
```

### 역할
- 비밀이 아닌 설정값 저장 (앱 이름, 로그 레벨, 타임존 등)
- 코드에서 설정을 분리 (12-Factor App)
- 환경 변수 또는 파일로 Pod에 주입

---

## 7. Secret

### 비유: 금고

```
Secret = 사무실 금고

- 비밀 정보: DB 비밀번호, API 키, 인증서
- 접근 권한이 있는 사람만 열 수 있다
- ⚠️ 쿠버네티스 기본 Secret은 base64 인코딩 = 누구나 디코딩 가능!
  → 프로덕션에서는 반드시 암호화 솔루션(Vault, ESO) 사용
```

### 역할
- 민감한 정보 저장 (비밀번호, 토큰, 키)
- ConfigMap과 사용법은 동일하지만, 접근 제어가 더 엄격

---

## 8. StatefulSet (스테이트풀셋)

### 비유: 지정석이 있는 사무실

```
Deployment = 자유석 사무실 (누가 어디 앉든 상관없음)
StatefulSet = 지정석 사무실 (각자 고유한 자리와 사물함이 있음)

- postgres-0은 항상 0번 사물함(PVC)을 사용
- postgres-1은 항상 1번 사물함(PVC)을 사용
- 자리를 비우면(Pod 삭제) 사물함(데이터)은 남아있음
```

### 역할
- **상태를 가진 앱** (DB, 메시지 큐 등) 배포
- Pod 이름이 순서대로 (`postgres-0`, `postgres-1`, ...)
- 각 Pod에 고유한 PVC(저장소) 연결
- 순서대로 생성, 역순으로 삭제

### Deployment vs StatefulSet

| 특성 | Deployment | StatefulSet |
|------|------------|-------------|
| Pod 이름 | 랜덤 (app-7d8f9b-x2k9p) | 순서 (postgres-0, -1) |
| 저장소 | 공유 또는 없음 | 각 Pod별 고유 PVC |
| 교체 가능성 | 어떤 Pod든 동일 | 각 Pod가 고유 |
| 사용 대상 | 웹 서버, API | DB, 캐시, 메시지 큐 |

---

## 9. PersistentVolumeClaim (PVC)

### 비유: 사물함 신청서

```
PVC = "1GB짜리 사물함 하나 주세요" (요청)
PV  = 실제로 배정된 사물함 (제공)

- PVC로 요청하면 쿠버네티스가 PV를 할당
- Pod가 삭제되어도 사물함(PV)의 내용물은 유지
- k3d에서는 local-path provisioner가 자동으로 PV 생성
```

---

## 10. HorizontalPodAutoscaler (HPA)

### 비유: 마트 계산대 자동 조절

```
HPA = 마트 계산대 관리자

- 손님이 적으면: 계산대 2개만 운영 (minReplicas: 2)
- 손님이 몰리면: 최대 5개까지 오픈 (maxReplicas: 5)
- 기준: 계산원의 업무량(CPU)이 70% 초과하면 추가 오픈
```

---

## 전체 구조 한눈에 보기

```
┌─ 클러스터 (k3d-seemedi-local) ──────────────────────────────────┐
│                                                                   │
│  ┌─ Namespace: seemedi-dev ────────────────────────────────────┐  │
│  │                                                              │  │
│  │  Ingress (app.localhost)                                     │  │
│  │      │                                                       │  │
│  │      ▼                                                       │  │
│  │  Service (sample-app) ──▶ Pod (sample-app-xxx)              │  │
│  │      ↑                    Pod (sample-app-yyy)              │  │
│  │      │                        │                              │  │
│  │   ConfigMap + Secret          │ DB 연결                      │  │
│  │                               ▼                              │  │
│  │                          Service (postgres)                  │  │
│  │                               │                              │  │
│  │                          StatefulSet (postgres-0)            │  │
│  │                               │                              │  │
│  │                          PVC (postgres-data)                 │  │
│  │                                                              │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌─ Namespace: monitoring ─────────────────────────────────────┐  │
│  │  Prometheus → 메트릭 수집                                    │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

## 다음 단계

개념을 이해했다면, 실제로 로컬에 환경을 구축해보자.

→ [03-local-setup-guide.md](03-local-setup-guide.md)
