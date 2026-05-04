# pkrc-workspace

PKRC 수중 3D 재구성 프로젝트의 ROS2 워크스페이스 부트스트랩.
네 개의 패키지 리포(`sonar_3d_reconstruction`, `sensor_packages`, `lidar_slam`, `pkrc_visualizer`)를 한 번에 clone·빌드·동기화합니다.

## 빠른 시작

```bash
git clone https://github.com/HERO-Lab-POSTECH/pkrc-workspace.git
cd pkrc-workspace
./scripts/bootstrap.sh
source install/setup.bash
```

## 사전 요구사항

- Ubuntu 22.04
- ROS2 Humble (`/opt/ros/humble`)
- Python 3.10+

부족한 도구는 `bootstrap.sh`가 검사 후 설치 명령을 안내합니다.

## 주요 명령

| 명령 | 용도 |
|---|---|
| `./scripts/bootstrap.sh` | 클린 환경 → 빌드 완료 (최초 1회) |
| `./scripts/sync.sh` | 모든 패키지 fetch+pull, 변경분 재빌드 |
| `./scripts/doctor.sh` | 환경/워크스페이스 상태 자가진단 |

## 디렉토리 구조

```
pkrc-workspace/
├── pkrc.repos          # 패키지 manifest
├── scripts/            # bootstrap, sync, doctor
├── docs/               # 협업 가이드
├── .github/            # 이슈·PR 템플릿
├── src/                # vcstool이 채우는 패키지 소스 (gitignored)
├── build/ install/ log/  # colcon 산출물 (gitignored)
└── README.md
```

## 협업 가이드

- 신규 인원: [`docs/onboarding.md`](docs/onboarding.md)
- 시스템 구조: [`docs/architecture-overview.md`](docs/architecture-overview.md)
- 브랜치/PR 규약: [`docs/branching-strategy.md`](docs/branching-strategy.md)
- 커밋 컨벤션: [`docs/contributing.md`](docs/contributing.md)
- 실 환경 배포: [`docs/deployment.md`](docs/deployment.md)
- 문제 해결: [`docs/troubleshooting.md`](docs/troubleshooting.md)

## 패키지 리포

| 패키지 | 책임 |
|---|---|
| [sonar_3d_reconstruction](https://github.com/HERO-Lab-POSTECH/sonar_3d_reconstruction) | 3D 확률 매핑, ROV 검출 |
| [sensor_packages](https://github.com/HERO-Lab-POSTECH/sensor_packages) | 센서 드라이버, 메시지 타입 |
| [lidar_slam](https://github.com/HERO-Lab-POSTECH/lidar_slam) | Fast-LIO, Cartographer 2D SLAM |
| [pkrc_visualizer](https://github.com/HERO-Lab-POSTECH/pkrc_visualizer) | PyQt5 통합 시각화 (SLAM·Pose·Sonar Map·Image) |

## 라이선스

[MIT](LICENSE)
