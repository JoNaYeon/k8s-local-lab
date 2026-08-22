# k8s-local-lab — Claude Code 운영 규칙

<!-- 하네스(ai-ops-harness) 전역 설치를 전제로 한다. 조직 조각의 import 는 여기가 아니라
     CLAUDE.local.md(gitignore)에 있고 scripts/set-context.sh 가 관리한다 — `@` 줄을 손으로
     넣지 않는다. 아래 선언 주석도 그 스크립트가 쓴다. 로드 확인: /context -->

<!-- harness: org=study role=none -->

## Overview

로컬 Kubernetes 학습·개념 검증 레포. k3d(k3s in Docker) 기반이며, 서버 이관 후 표준
kubeadm 으로 전환한 후속이 k8s-server-lab 이다. 이 레포는 **학습 기록**으로 남긴다 —
실서비스 구축은 후속 레포가 맡는다.

컨텍스트는 `study`(개인 공부) — 조직 업무 규칙(seemediai)이 아니라 vault 공부 기록 규칙을
따른다. 여기서 얻은 일반화 지식은 `{vault.path}/{vault.study_subdir}` 로 채집한다.

## Route Table (이 프로젝트)

| 상황 | 참조 문서 |
|------|----------|
| k8s 개념 학습 | `docs/01-kubernetes-intro.md`, `docs/02-key-concepts.md` |
| 로컬 환경 구축 | `docs/03-local-setup-guide.md` |
| 배포·디버깅·운영 | `docs/04-usage-guide.md` |
| 로컬 ↔ 프로덕션 매핑 | `docs/05-production-mapping.md` |
| 실서비스 방식(kubeadm) | 후속 레포 k8s-server-lab |

코드 컨벤션·Git 규약·보안 규칙은 하네스가 얹는다 — general 조각과 study 조직 조각의
Route Table 을 따른다. 여기에 다시 적지 않는다.

## Tech Stack

- k3d (k3s in Docker) — 로컬 k8s 클러스터
- FastAPI + Python 3.12 (샘플 앱) · PostgreSQL 15 · Prometheus · Kustomize

## 프로젝트 특이 규칙 (하네스 규칙의 구체화)

- Secret YAML 의 값은 **학습용 더미만** 쓴다. 실제 크레덴셜·kubeconfig 는 커밋도 출력도 하지 않는다 —
  general Security Rules 의 이 레포 구체화다.
- 로컬 클러스터 컨텍스트는 `{environments.cluster_staging}` — 실값은 `config/ops.config.yml`(gitignored).
- Python: ruff (line-length=100), Python 3.12. YAML indent 2. 로깅 KST(Asia/Seoul), structlog + ECS JSON.
