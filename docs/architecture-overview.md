# Architecture Overview

PKRC 수중 3D 재구성 시스템은 표면 플랫폼이 LiDAR로 자기위치를 추정하면서 하부 소나로 수중 지형을 매핑하고, 그 지형 안에서 ROV를 검출·추적합니다.

## 데이터 흐름

```
[Livox MID360]──┐                      ┌─▶ /fast_lio/odometry
                ├──▶ [fast_lio]────────┤
[IMU]───────────┘                      └─▶ /fast_lio/cloud_registered_body
                                              │
                                              ▼
[Oculus M750D] ──▶ [oculus_driver] ──▶ /sensor/sonar/oculus/*/image
                                              │
                                              ▼
                                       [3d_mapper_node]
                                              │
                                              ├─▶ /sonar_3d_mapper/point_cloud
                                              ├─▶ /sonar_3d_mapper/occupancy_grid
                                              └─▶ /sonar_3d_mapper/updated_tile_indices
                                                        │
                                                        ▼
                                                 [robot_detection_node]
                                                        │
                                                        └─▶ /rov/pose
```

[Cartographer]는 별도로 2D occupancy grid를 생산해 표면 위치 보정을 돕습니다.

## 패키지 책임 경계

세 리포는 **단일 책임 원칙**으로 분리되어 있습니다. 새 코드를 어디에 둘지 헷갈릴 때 이 표를 기준으로 하세요.

| 리포 | 책임 | 두지 말 것 |
|---|---|---|
| **sensor_packages** | 하드웨어 드라이버, 메시지 타입 정의, 센서 publisher만 | 매핑 알고리즘, 시각화, 융합 |
| **lidar_slam** | LiDAR 기반 자기위치 추정, 2D occupancy | 소나 처리, 카메라 |
| **sonar_3d_reconstruction** | 3D 확률 매핑(IWLO), out-of-core 타일, ROV 검출, 시각화 | 드라이버 코드, SLAM 알고리즘 본체 |

## 좌표계

세 개의 frame이 사용됩니다.

| Frame | 축 방향 | 비고 |
|---|---|---|
| `sonar` | +X 전·+Y 우·+Z 하 | 센서 로컬 |
| `boat` | sonar에서 R_base로 회전 | 플랫폼 로컬 |
| `map` / `world_ned` | NED (North-East-Down) | **Z > 0 = 수중** |

```python
# sensor → boat 회전
R_base = np.array([
    [ 0, 0, 1],
    [ 0, 1, 0],
    [-1, 0, 0],
])
```

`map`과 `world_ned`의 Z 부호 의미가 반대이니 변환 시 부호 반전 주의. 자세한 내용은 `src/sonar_3d_reconstruction/docs/source/` 참조.

## 빌드 의존성

ROS2 메시지 패키지가 사용 패키지보다 먼저 빌드되어야 합니다. `colcon build`는 의존성 그래프로 자동 처리하지만 `--packages-select`로 단일 빌드 시 수동 순서가 필요할 수 있습니다.

```
marine_acoustic_msgs ──┐
oculus_sonar_msgs    ──┼──▶ oculus_sonar (driver) ──▶ sonar_3d_reconstruction
ping360_sonar_msgs   ──┘
```

## 배포 구성

| 위치 | 노드 |
|---|---|
| Boat (Jetson) | oculus 드라이버, ping360 드라이버 |
| Local PC | livox 드라이버, fast_lio, cartographer, sonar 3D 매퍼, robot detection |

자세한 실행 순서는 [deployment.md](deployment.md) 참조.
