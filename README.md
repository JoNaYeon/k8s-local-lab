# k8s-local-lab

SEEMEDI 로컬 Kubernetes 테스트 환경. 프로덕션 self-managed k8s 구축 전 개념 검증과 팀 학습을 위한 레포.

## 구성

- **k3d** (k3s in Docker) — 로컬 k8s 클러스터 (1 server + 2 agents)
- **FastAPI** 샘플 앱 — health-check 서비스
- **PostgreSQL 15** — StatefulSet으로 배포
- **Prometheus** — 모니터링 (Helm)
- **Kustomize** — 매니페스트 관리
- **Nginx Ingress** — HTTP 라우팅

## 빠른 시작 (5분)

```bash
# 1. 도구 설치 (k3d, kubectl, helm, kustomize)
make setup

# 2. 클러스터 생성
make cluster-up

# 3. 전체 배포 (이미지 빌드 + k3d 로드 + 매니페스트 적용)
make deploy

# 4. 동작 확인
curl http://app.localhost/healthz
# {"status": "ok"}

# 5. 상태 확인
make status
```

## 전제 조건

- Ubuntu 22.04+ (또는 macOS)
- sudo 권한
- `make setup`이 Docker, k3d, kubectl, helm, kustomize를 자동 설치함

## Makefile 명령

| 명령 | 설명 |
|------|------|
| `make help` | 사용 가능한 명령 목록 |
| `make setup` | 도구 설치 (k3d, kubectl, helm, kustomize) |
| `make cluster-up` | k3d 클러스터 생성 |
| `make cluster-down` | k3d 클러스터 삭제 |
| `make build` | Docker 이미지 빌드 |
| `make load` | 이미지 빌드 + k3d 클러스터에 로드 |
| `make deploy` | 전체 배포 (빌드 + 로드 + 매니페스트 적용) |
| `make deploy-app` | 앱만 재배포 |
| `make deploy-db` | DB만 재배포 |
| `make deploy-monitoring` | Prometheus 설치 (Helm) |
| `make port-forward` | 포트포워딩 (앱:8000, DB:5432, Prometheus:9090) |
| `make logs` | 앱 로그 실시간 확인 |
| `make status` | 전체 리소스 상태 확인 |
| `make clean` | 전체 삭제 (클러스터 포함) |

## 문서 (초보자용)

DevOps 기초 지식이 부족해도 따라갈 수 있도록 작성했다.

| 문서 | 내용 |
|------|------|
| [01-kubernetes-intro.md](docs/01-kubernetes-intro.md) | 쿠버네티스란? 왜 쓰는가? |
| [02-key-concepts.md](docs/02-key-concepts.md) | Pod, Deployment, Service 등 핵심 개념 |
| [03-local-setup-guide.md](docs/03-local-setup-guide.md) | 로컬 환경 구축 step-by-step |
| [04-usage-guide.md](docs/04-usage-guide.md) | 배포, 디버깅, 스케일링, 롤백 |
| [05-production-mapping.md](docs/05-production-mapping.md) | 로컬 ↔ 프로덕션 대응표 |

## 디렉토리 구조

```
k8s-local-lab/
├── app/                    # 샘플 FastAPI 앱 + Dockerfile
├── manifests/              # Kubernetes 매니페스트 (Kustomize)
│   ├── base/               #   네임스페이스
│   ├── app/                #   앱 (Deployment, Service, Ingress, ...)
│   ├── database/           #   PostgreSQL (StatefulSet, PVC, ...)
│   └── monitoring/         #   Prometheus (Helm)
├── scripts/                # 자동화 스크립트
├── docs/                   # 한국어 학습 문서
├── Makefile                # 명령 통합
└── CLAUDE.md               # Claude Code 운영 규칙
```

## 기술 스택 (SEEMEDI 표준)

- Python 3.12 + FastAPI + uvicorn
- ruff (line-length=100)
- KST (Asia/Seoul) 타임존
- 구조화 로깅 (structlog + ECS)
- Conventional Commits (`type: Korean description`)
