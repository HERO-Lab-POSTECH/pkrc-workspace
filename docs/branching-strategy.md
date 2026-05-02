# Branching Strategy

세 패키지 리포 모두 동일한 정책을 따릅니다.

## 원칙

1. **`main`은 항상 빌드 가능** — 깨진 코드는 절대 들어가지 않음
2. **`main` 직접 push 금지** — 반드시 PR 통해서만
3. **PR은 squash merge 기본** — main history를 깔끔하게 유지
4. **force-push to main 절대 금지**

## 브랜치 명명

| 패턴 | 용도 | 예시 |
|---|---|---|
| `feature/<scope>-<short>` | 새 기능 | `feature/iwlo-tilt-90` |
| `fix/<scope>-<short>` | 버그 수정 | `fix/qos-mismatch` |
| `refactor/<scope>-<short>` | 동작 변경 없는 리팩토링 | `refactor/extract-tile-storage` |
| `docs/<short>` | 문서 변경 | `docs/onboarding-update` |
| `chore/<short>` | 빌드·설정·잡일 | `chore/bump-eigen-version` |

`<scope>`는 패키지 또는 모듈 이름의 핵심 키워드 (예: `iwlo`, `qos`, `tile`).

## PR 워크플로우

```bash
# 1. 최신 main 받기
git checkout main && git pull

# 2. 브랜치 생성
git checkout -b feature/iwlo-tilt-90

# 3. 작업 → 커밋
git commit -m "feat(iwlo): add 90° tilt preset"

# 4. push + PR 생성
git push origin feature/iwlo-tilt-90
gh pr create --title "feat(iwlo): add 90° tilt preset" --body "..."

# 5. 리뷰 통과 → squash merge
# 6. 로컬 정리
git checkout main && git pull && git branch -d feature/iwlo-tilt-90
```

## Cross-Repo PR 의존성

여러 리포에 걸친 변경 (예: 메시지 타입 추가):

1. **의존되는 리포부터 PR 생성** (예: `sensor_packages`에 메시지 추가 PR `#A`)
2. **의존하는 리포 PR 본문에 명시**:
   ```markdown
   ## Dependencies
   Depends on HERO-Lab-POSTECH/sensor_packages#42
   ```
3. **머지 순서**: `#A` 머지 → 의존 PR 머지

`pkrc.repos`는 항상 `main`을 가리키므로 두 PR이 모두 머지된 시점부터 `./scripts/sync.sh`로 받아집니다.

## 충돌 해결

다른 협업자가 같은 파일을 먼저 머지한 경우:

```bash
git fetch origin
git rebase origin/main
# 충돌 → 수동 resolve → git add → git rebase --continue
git push --force-with-lease
```

`--force-with-lease`는 동료가 새로 push한 commit을 덮어쓰지 않도록 막는 안전망입니다. `--force` 단독 사용은 권장하지 않습니다.

## 핫픽스

현장 운영 중 긴급 수정이 필요한 경우:

```bash
git checkout main && git pull
git checkout -b hotfix/<issue>
# 최소 변경
git commit -m "fix(<scope>): <urgent description>"
git push origin hotfix/<issue>
gh pr create --label hotfix
```

리뷰는 1명만으로 머지 가능 (사후 회고는 정식 회의에서).

## 브랜치 보호 (GitHub 설정)

각 패키지 리포의 GitHub Settings → Branches → `main`:

- [x] Require a pull request before merging
- [x] Require approvals (1+)
- [x] Dismiss stale pull request approvals when new commits are pushed
- [x] Require linear history
- [x] Do not allow bypassing the above settings
