# k8s-local-lab — Claude Code 운영 규칙

## Overview

SEEMEDI 로컬 Kubernetes 테스트 환경. 프로덕션 self-managed k8s 구축 전 개념 검증과
팀 학습을 위한 로컬 k3d(k3s) 기반 실습 레포다. 서버 이관 시 표준 k8s(kubeadm)로 전환 예정.

## Route Table

| 상황 | 참조 문서 |
|------|----------|
| k8s 개념 학습 | `docs/01-kubernetes-intro.md`, `docs/02-key-concepts.md` |
| 로컬 환경 구축 | `docs/03-local-setup-guide.md` |
| 배포·디버깅·운영 | `docs/04-usage-guide.md` |
| 로컬 ↔ 프로덕션 매핑 | `docs/05-production-mapping.md` |
| Dockerfile 생성·리뷰 | ai-ops-harness `/dockerfile` 스킬 컨벤션 |
| 코드 작성 컨벤션 | ai-ops-harness `code-conventions/` |
| Git 브랜치·커밋 | ai-ops-harness `code-conventions/by-task/git-workflow.md` |

## Tech Stack

- k3d (k3s in Docker) — 로컬 k8s 클러스터. 서버 전환 시 kubeadm 사용
- FastAPI + Python 3.12 — 샘플 앱
- PostgreSQL 15 — 데이터베이스
- Prometheus — 모니터링
- Kustomize — 매니페스트 관리

## Security Rules

- NEVER read, open, or cat any .env file. Use .env.example for reference.
- NEVER include API keys, tokens, or secrets in code, comments, or commit messages.
- Secret YAML의 값은 학습용 더미만 사용. 실제 크레덴셜 커밋 금지.
- `config/ops.config.yml`은 gitignored — 예시 파일(`*.example`)만 커밋.

## Conventions

- 커밋: `type: Korean description` (feat, fix, refactor, chore, docs, style)
- 문서: 한국어. 코드 주석·식별자: 영어.
- YAML indent: 2 spaces
- Python: ruff (line-length=100), Python 3.12
- 로깅: KST (Asia/Seoul), structlog + ECS JSON
