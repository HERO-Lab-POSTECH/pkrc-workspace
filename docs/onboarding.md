# Onboarding

> 신규 협업자의 첫날 가이드 — 약 15분 소요.

## Day 0 체크리스트

- [ ] Ubuntu 22.04 머신 (네이티브 또는 듀얼부트, WSL2도 가능하나 ROS2 DDS 디스커버리 이슈 있음)
- [ ] [ROS2 Humble 설치](https://docs.ros.org/en/humble/Installation.html)
- [ ] GitHub `HERO-Lab-POSTECH` 조직 가입 (admin에게 초대 요청)
- [ ] SSH key 등록 또는 PAT 생성
- [ ] Git identity 설정 (`git config --global user.name`, `user.email`)

## 워크스페이스 셋업 (5분)

```bash
git clone https://github.com/HERO-Lab-POSTECH/pkrc-workspace.git
cd pkrc-workspace
./scripts/bootstrap.sh
```

`bootstrap.sh`가 다음을 자동 수행합니다:

1. ROS2 humble, vcstool, colcon, rosdep 설치 확인
2. 세 패키지 리포 clone (`vcs import`)
3. 시스템 의존성 설치 (`rosdep install`)
4. `colcon build --symlink-install`

## 첫 실행 (5분)

```bash
source install/setup.bash

# 데모: 3D 매핑 노드 실행
ros2 launch sonar_3d_reconstruction 3d_mapping.launch.py
```

별도 터미널에서:

```bash
source install/setup.bash
rviz2  # 또는 ros2 topic list로 토픽 확인
```

## 학습 자료

| 주제 | 위치 |
|---|---|
| 시스템 전체 구조 | [architecture-overview.md](architecture-overview.md) |
| 좌표계 규약 | [architecture-overview.md#coordinate-frames](architecture-overview.md#좌표계) |
| Sonar 3D 매핑 알고리즘 | `src/sonar_3d_reconstruction/docs/source/design/iwlo_design.md` |
| Out-of-core 타일 매퍼 | `src/sonar_3d_reconstruction/docs/source/design/outofcore_design.md` |
| Cartographer SLAM | `src/lidar_slam/cartographer_slam/README.md` |

## 첫 PR 만들어 보기

워크플로우 친숙해지려면 사소한 PR 하나가 가장 효과적입니다 (예: 오타 수정).

```bash
cd src/sonar_3d_reconstruction
git checkout -b docs/<your-name>-typo-fix
# README나 docs 파일 한 줄 고치기
git commit -m "docs: fix typo in README"
git push origin docs/<your-name>-typo-fix
gh pr create
```

리뷰어가 24시간 내에 1차 응답합니다 — 머지되면 워크플로우 통과.

## 도움 요청

- **빌드/환경 문제**: `./scripts/doctor.sh` → [troubleshooting.md](troubleshooting.md) 검색 → 그래도 안 풀리면 이슈 등록
- **시스템 동작 질문**: 슬랙 또는 미팅 안건으로
- **긴급 (현장)**: 담당자 직접 연락
