# 일상 사용 가이드

로컬 환경이 구축된 후, 자주 사용하는 작업들을 정리한다.

---

## 1. 앱 코드 수정 후 재배포

코드를 수정했을 때 변경사항을 반영하는 과정:

```bash
# 1. 이미지 다시 빌드
make build

# 2. k3d에 이미지 로드
make load

# 3. 앱만 재배포
make deploy-app
```

또는 한 번에:
```bash
make load && make deploy-app
```

---

## 2. 로그 확인

### 실시간 로그 (tail -f 같은 것)
```bash
make logs
# 또는
kubectl logs -f deployment/sample-app -n seemedi-dev
```

### 특정 Pod의 로그
```bash
# Pod 이름 확인
kubectl get pods -n seemedi-dev

# 해당 Pod 로그
kubectl logs sample-app-xxx-yyy -n seemedi-dev

# 이전 크래시 로그 (Pod가 재시작된 경우)
kubectl logs sample-app-xxx-yyy -n seemedi-dev --previous
```

---

## 3. Pod 안에 접속 (디버깅)

```bash
# Pod 안에 셸로 접속
kubectl exec -it <pod-name> -n seemedi-dev -- sh

# 예: 앱 Pod 접속
kubectl exec -it deployment/sample-app -n seemedi-dev -- sh

# 접속 후 할 수 있는 것들:
#   ls                    # 파일 확인
#   env                   # 환경 변수 확인
#   python -c "..."       # Python 코드 실행
#   exit                  # 나가기
```

### PostgreSQL 접속
```bash
kubectl exec -it postgres-0 -n seemedi-dev -- psql -U seemedi -d seemedi

# SQL 실행
# \dt           — 테이블 목록
# \d 테이블명   — 테이블 구조
# SELECT * FROM health_check;
# \q            — 나가기
```

---

## 4. 스케일링 (Pod 수 조절)

### 수동 스케일링
```bash
# 3개로 늘리기
kubectl scale deployment/sample-app --replicas=3 -n seemedi-dev

# 확인
kubectl get pods -n seemedi-dev

# 1개로 줄이기
kubectl scale deployment/sample-app --replicas=1 -n seemedi-dev
```

### 자동 스케일링 (HPA)

HPA가 설정되어 있으면 CPU 사용률에 따라 자동으로 조절된다:
```bash
# HPA 상태 확인
kubectl get hpa -n seemedi-dev

# 결과 예시:
# NAME             REFERENCE              TARGETS   MINPODS   MAXPODS   REPLICAS
# sample-app-hpa   Deployment/sample-app   15%/70%   2         5         2
```

---

## 5. 롤링 업데이트와 롤백

### 업데이트 과정 관찰
```bash
# 배포 진행 상황 실시간 확인
kubectl rollout status deployment/sample-app -n seemedi-dev
```

### 롤백 (이전 버전으로 되돌리기)
```bash
# 배포 이력 확인
kubectl rollout history deployment/sample-app -n seemedi-dev

# 바로 이전 버전으로 롤백
kubectl rollout undo deployment/sample-app -n seemedi-dev

# 특정 리비전으로 롤백
kubectl rollout undo deployment/sample-app --to-revision=1 -n seemedi-dev
```

---

## 6. 리소스 상태 확인

### 전체 상태
```bash
make status
```

### 상세 조회 명령어 모음
```bash
# 노드 상태
kubectl get nodes -o wide

# 모든 리소스
kubectl get all -n seemedi-dev

# Pod 상세 정보 (이벤트, 조건 등)
kubectl describe pod <이름> -n seemedi-dev

# 리소스 사용량 (CPU/메모리)
kubectl top nodes
kubectl top pods -n seemedi-dev
```

---

## 7. ConfigMap/Secret 수정

### ConfigMap 수정 후 적용
```bash
# 1. manifests/app/configmap.yml 수정
# 2. 적용
kubectl apply -f manifests/app/configmap.yml

# 3. Pod 재시작 (환경 변수는 재시작해야 반영됨)
kubectl rollout restart deployment/sample-app -n seemedi-dev
```

### 실행 중인 ConfigMap 직접 확인
```bash
kubectl get configmap sample-app-config -n seemedi-dev -o yaml
```

---

## 8. 자주 쓰는 kubectl 요약

| 명령 | 설명 |
|------|------|
| `kubectl get pods -n seemedi-dev` | Pod 목록 |
| `kubectl get all -n seemedi-dev` | 모든 리소스 |
| `kubectl describe pod <name> -n seemedi-dev` | Pod 상세 정보 |
| `kubectl logs <name> -n seemedi-dev` | 로그 보기 |
| `kubectl logs -f <name> -n seemedi-dev` | 로그 실시간 |
| `kubectl exec -it <name> -n seemedi-dev -- sh` | Pod 접속 |
| `kubectl apply -f <file>` | 리소스 적용 |
| `kubectl delete -f <file>` | 리소스 삭제 |
| `kubectl port-forward svc/<name> 8000:80 -n seemedi-dev` | 포트포워딩 |

### kubectl 단축 설정 (선택)

`~/.zshrc`에 추가:
```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kl='kubectl logs -f'
```

---

## 다음 단계

로컬 환경의 각 구성 요소가 프로덕션에서 어떻게 변하는지 확인해보자.

→ [05-production-mapping.md](05-production-mapping.md)
