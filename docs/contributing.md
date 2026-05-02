# Contributing

PKRC 프로젝트에 기여하는 방법.

## 시작 전

- [Onboarding](onboarding.md) 완료
- [Branching Strategy](branching-strategy.md) 숙지
- 이슈가 없는 작업이면 먼저 이슈를 등록해 컨텍스트 공유

## 커밋 메시지 — Conventional Commits

```
<type>(<scope>): <subject>

<body>

<footer>
```

| type | 의미 | 예 |
|---|---|---|
| `feat` | 새 기능 | `feat(iwlo): add 30° tilt preset` |
| `fix` | 버그 수정 | `fix(qos): align driver and subscriber to BEST_EFFORT` |
| `refactor` | 동작 변경 없는 구조 변경 | `refactor(tile): extract OctreeStorage` |
| `docs` | 문서만 | `docs: add deployment runbook` |
| `chore` | 빌드·설정·잡일 | `chore: bump eigen to 3.4.0` |
| `perf` | 성능 개선 | `perf(mapper): batch ray-casting` |
| `test` | 테스트만 | `test(iwlo): add saturation cap test` |

규칙:
- subject는 50자 이내, 명령형 (`add`, `fix`, `update` ...)
- body는 **왜** 변경했는지에 초점 (무엇을 변경했는지는 diff에 있음)
- 끝 마침표 없음, 첫 글자 소문자

예시:
```
feat(3d_mapper): add depth filter cutoff parameter

소나 reflection이 약한 원거리에서 false positive가 누적되는 문제를
완화하기 위해 강도 임계값 기반 cutoff 도입.

운영 시 config/presets/tilt_*.yaml의 depth_filter_cutoff_db 조정 가능.

Refs: #42
```

## PR 체크리스트

PR 생성 시 다음을 확인합니다 (PR 템플릿이 자동으로 띄움):

- [ ] `colcon build` 통과
- [ ] 새 함수/클래스면 README 또는 docs 갱신
- [ ] 좌표 변환 코드면 frame을 코멘트로 명시
- [ ] 매직 넘버를 명명된 상수로 추출
- [ ] 임시 파일 (`test_*.py`, `temp_*`) 삭제
- [ ] 커밋 메시지가 Conventional Commits 형식

## 코딩 스타일

각 패키지의 코딩 스타일은 해당 리포의 가이드를 따릅니다:

- 일반 ROS2/Python/C++ 스타일은 워크스페이스 상위 `CLAUDE.md` 또는 `.claude/rules/coding-style.md` 참조
- 함수 ≤ 50줄, 파라미터 ≤ 4개, 중첩 ≤ 3단계
- 매직 넘버 금지 (`0`, `1`, `-1`, 인덱스 제외)
- ROS2 노드는 `*_node.py` 접미사

## 리뷰 정책

| 항목 | 정책 |
|---|---|
| 리뷰어 수 | 1명 이상 approve 필요 |
| 응답 시간 | 1차 응답 24시간 이내 |
| 자체 머지 | 본인 PR 본인이 approve 금지 |
| 핫픽스 | 1명 approve로 머지 가능 |

## 패키지 변경 시 부수 작업

| 변경 내용 | 추가로 갱신할 곳 |
|---|---|
| 새 노드/launch 추가 | 패키지 README |
| 새 메시지 타입 | `architecture-overview.md`의 데이터 흐름 |
| QoS 정책 변경 | `sonar_3d_reconstruction/docs/source/reference/qos-policy.md` |
| 배포 절차 변경 | `sonar_3d_reconstruction/docs/source/operations/deployment-runbook.md` |
| 빌드 의존성 추가 | 해당 패키지 `package.xml`의 `<depend>` |

## 데이터 안전 — 절대 금지

`bag`, `db3`, `metadata.yaml` 파일은 **백업 없이 삭제·수정 금지**. 이동(`mv`)만 허용됩니다.

## 라이선스 동의

PR을 머지하면 본 리포의 [LICENSE](../LICENSE)에 따라 기여물을 공개하는 것에 동의하는 것으로 간주됩니다.
