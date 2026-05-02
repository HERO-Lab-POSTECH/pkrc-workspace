# Deployment

실 환경(boat + Jetson + Local PC) 통합 시스템 기동 절차는 단일 소스(Single Source of Truth)에서 관리됩니다.

## 표준 배포 가이드

→ [`sonar_3d_reconstruction/docs/source/operations/deployment-runbook.md`](https://github.com/HERO-Lab-POSTECH/sonar_3d_reconstruction/blob/main/docs/source/operations/deployment-runbook.md)

해당 문서에 다음이 포함되어 있습니다:

- 사전 조건 (네트워크, 맵 저장 경로 등)
- Phase 1: Boat 측 SSH 세션
- Phase 2: Local PC Terminal 1 (입력 + Lidar)
- Phase 3: Local PC Terminal 2 (SLAM + 매핑)
- 종료 절차
- 트러블슈팅 링크

## 왜 여기에 본문이 없는가

배포 절차는 `sonar_3d_reconstruction` 패키지의 운영 책임 영역입니다. 메타-리포에 복제하면 다음 문제가 생깁니다:

- 두 곳을 동시에 갱신해야 함 (drift 발생)
- 어느 쪽이 최신인지 모호해짐
- PR 리뷰 시 두 곳 모두 검토 필요

본 메타-리포는 **링크만** 제공하고, 운영 절차는 패키지 내 문서에서 단일 관리합니다.

## QoS 정책 (참고)

→ [`sonar_3d_reconstruction/docs/source/reference/qos-policy.md`](https://github.com/HERO-Lab-POSTECH/sonar_3d_reconstruction/blob/main/docs/source/reference/qos-policy.md)
