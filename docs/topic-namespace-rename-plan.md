# Topic Namespace Unification — `/slam/...` Rename Plan

**상태**: 실행 대기 (in-flight PR 머지 후 진행)
**최종 결정**: 2026-05-07 — 모든 SLAM 관련 토픽을 `/localization/...`, `cartographer_2d/...`, `/fast_lio/debug/...`에서 `/slam/<stack>/<output>` 컨벤션으로 통일.

---

## 1. 동기

현재 워크스페이스에 **세 가지 네임스페이스가 공존**:
- `/localization/fast_lio/*`, `/localization/fast_lio_loc/*`, `/localization/cartographer/odometry` (7th audit에서 부분 도입)
- `cartographer_2d/*` (cartographer 원본 컨벤션, odometry 빼고 그대로)
- `/fast_lio/debug/*` (FAST-LIO 원본 잔재)

`/localization/`은 fast_lio mapping 모드(odometry+mapping이지 localization 아님)에 의미적으로 부정확하고, `cartographer_2d/`는 fast_lio와 컨벤션이 다름. 통일 필요.

**선택된 컨벤션**: `/slam/<stack>/<output>` — 도메인(SLAM) 기반, future-proof, repo 이름에 종속 안 됨.

---

## 2. Rename Mapping

### 2.1 fast_lio mapping
| Old | New |
|---|---|
| `/localization/fast_lio/odometry` | `/slam/fast_lio/odometry` |
| `/localization/fast_lio/points_body` | `/slam/fast_lio/points_body` |
| `/fast_lio/debug/points_world` | `/slam/fast_lio/debug/points_world` |
| `/fast_lio/debug/points_effected` | `/slam/fast_lio/debug/points_effected` |
| `/fast_lio/debug/map` | `/slam/fast_lio/debug/map` |
| `/fast_lio/debug/path` | `/slam/fast_lio/debug/path` |

### 2.2 fast_lio_loc
| Old | New |
|---|---|
| `/localization/fast_lio_loc/odometry` | `/slam/fast_lio_loc/odometry` |
| `/localization/fast_lio_loc/confidence` | `/slam/fast_lio_loc/confidence` |
| `/localization/fast_lio_loc/occupancy_grid` | `/slam/fast_lio_loc/occupancy_grid` |
| `/localization/fast_lio_loc/map` | `/slam/fast_lio_loc/map` |

### 2.3 cartographer
| Old | New |
|---|---|
| `cartographer_2d/map` | `/slam/cartographer/map` |
| `cartographer_2d/scan_matched_points2` | `/slam/cartographer/scan_matched_points2` |
| `cartographer_2d/submaps` | `/slam/cartographer/submaps` |
| `cartographer_2d/tracked_pose` | `/slam/cartographer/tracked_pose` |
| `cartographer_2d/trajectory_nodes` | `/slam/cartographer/trajectory_nodes` |
| `cartographer_2d/trajectory_nodes_filtered` | `/slam/cartographer/trajectory_nodes_filtered` |
| `cartographer_2d/landmark_poses` | `/slam/cartographer/landmark_poses` |
| `cartographer_2d/constraints` | `/slam/cartographer/constraints` |
| `/localization/cartographer/odometry` | `/slam/cartographer/odometry` |

---

## 3. 사전 조건 — 머지 대기 PR

이 rename은 다음 PR들이 모두 머지된 **후** 진행:

| PR | repo | 내용 | 상태 |
|---|---|---|---|
| [#12](https://github.com/HERO-Lab-POSTECH/pkrc_visualizer/pull/12) | pkrc_visualizer | viz가 production 토픽으로 마이그레이션 | open |
| [#28](https://github.com/HERO-Lab-POSTECH/lidar_slam/pull/28) | lidar_slam | mapping 모드 `map→odom` static TF | open |
| [#29](https://github.com/HERO-Lab-POSTECH/lidar_slam/pull/29) | lidar_slam | debug 토픽 기본 비활성 (#28 stacked) | open |

**머지 순서**: #12 → #28 → #29 → (이 rename PR 시리즈)

---

## 4. 변경 파일 인벤토리

### 4.1 `lidar_slam` (단일 PR)

#### fast_lio 코드 (publisher/subscriber 토픽명 직접 변경)
- `fast_lio/src/slam/laserMapping.cpp`
  - L995: `/localization/fast_lio/odometry` pub → `/slam/fast_lio/odometry`
  - L996: `/localization/fast_lio/points_body` pub → `/slam/fast_lio/points_body`
  - L1002: `/fast_lio/debug/points_world` pub → `/slam/fast_lio/debug/points_world`
  - L1005: `/fast_lio/debug/points_effected` pub → `/slam/fast_lio/debug/points_effected`
  - L1008: `/fast_lio/debug/map` pub → `/slam/fast_lio/debug/map`
  - L1011: `/fast_lio/debug/path` pub → `/slam/fast_lio/debug/path`
- `fast_lio/src/localization/localization_node.cpp`
  - L180: pub `/localization/fast_lio_loc/odometry` → `/slam/fast_lio_loc/odometry`
  - L181: pub `/localization/fast_lio_loc/confidence` → `/slam/fast_lio_loc/confidence`
  - L185: sub `/localization/fast_lio/odometry` → `/slam/fast_lio/odometry`
  - L189: sub `/localization/fast_lio/points_body` → `/slam/fast_lio/points_body`
- `fast_lio/src/localization/tf_publisher.cpp`
  - L32: pub `/localization/fast_lio_loc/map` → `/slam/fast_lio_loc/map`
  - L37: pub `/localization/fast_lio_loc/occupancy_grid` → `/slam/fast_lio_loc/occupancy_grid`

#### fast_lio launch/config/rviz/scripts (참조 갱신)
- `fast_lio/launch/mapping.launch.py` — docstring L44–51
- `fast_lio/launch/localization.launch.py` — docstring L30–42
- `fast_lio/rviz/fastlio.rviz` — L93, L121, L153, L187, L221
- `fast_lio/rviz/localization.rviz` — L81, L113, L147, L163, L203, L242
- `fast_lio/config/slam/mid360.yaml` — comments L66–73
- `fast_lio/scripts/regression_test.sh` — L23 ODOM_TOPIC default
- `fast_lio/scripts/regression_test_localization.sh` — L23, L27
- `fast_lio/scripts/regression_test_path_buffer.sh` — L28 PATH_TOPIC default
- `fast_lio/scripts/regression_compare.py` — L5 docstring, L73 arg default
- `fast_lio/scripts/regression_plot.py` — L30 function default

#### cartographer_slam 코드 (constants — 8개 한 번에)
- `cartographer_slam/include/cartographer_slam/node_constants.h`
  - L35: comment 갱신 ("with cartographer_2d prefix" → "under /slam/cartographer namespace")
  - L36–43: 7개 상수값 + L40 odometry 상수 모두 `/slam/cartographer/...`로

#### cartographer_slam launch/config/rviz
- `cartographer_slam/launch/slam.launch.py`
  - L47–49: docstring
  - L212: `('map', '/cartographer_2d/map')` → `('map', '/slam/cartographer/map')`
  - L240–241: trajectory_node_list 리매핑 타깃
- `cartographer_slam/config/slam_2d.lua` — L66 comment
- `cartographer_slam/rviz/livox_mid360.rviz` — L32, L74, L85

#### lidar_slam README
- `README.md` — L67–69 (fast_lio outputs), L75–77 (cartographer outputs)

### 4.2 `pkrc_visualizer` (단일 PR)

- `pkrc_visualizer/topic_config.py`
  - L25 comment, L27 slam_cloud, L28 slam_prior_grid, L32 pose_odom, L33 pose_loc_odom, L34 pose_confidence, L36 comment
- `pkrc_visualizer/ros_client.py` — L246 docstring
- `pkrc_visualizer/pages/slam_page.py` — L1 docstring
- `pkrc_visualizer/pages/pose_page.py` — L2 docstring
- `README.md` — L29, L30, L53

### 4.3 `sonar_3d_reconstruction` (단일 PR)

- `launch/3d_mapping.launch.py` — L58–60, L66 (ODOMETRY_CONFIG, CONFIDENCE_CONFIG dicts)
- `launch/robot_3d_mapping.launch.py` — L64–66, L72 (동일 dict)
- `scripts/config.py` — L260 `topics.odometry` ParameterDef default
- `config/bag_record_qos_override.yaml` — L40, L42, L44, L46, L48 (4개 fast_lio debug + 1개 fast_lio production)
- `rviz/3d_mapping.rviz` — L238, L446, L502
- `README.md` — L250
- `docs/source/design/slam_quality_gating_design.md` — L197, L244
- `docs/source/reference/qos-policy.md` — L37, L40, L48, L122
- `docs/source/release-notes/2026-03-28-qos-stabilization.md` — L44

### 4.4 `sensor_packages` (선택 — 문서만)

- `README.md` — L216–218 (3개 references — fast_lio outputs 문서)

---

## 5. PR 시리즈 순서

세 PR을 동시에 열되, **머지는 의존 순서로**:

```
1. lidar_slam rename PR  (모든 publisher 측 토픽명 변경 — 컨벤션 권한자)
   ↓ 머지 후 ↓
2. pkrc_visualizer rename PR  (subscribers 갱신)
   ↓ 머지 후 ↓
3. sonar_3d_reconstruction rename PR  (subscribers + bag QoS overrides + rviz + docs)
```

각 PR은 자기 repo의 모든 변경을 한 번에 처리. 중간 머지 상태에선 일시적으로 publisher가 새 토픽으로 옮겼는데 subscriber는 옛 토픽을 보는 구간이 생김 (≤1일 정도 예상). **그 사이 시각화/매핑 동작 멈춤 — 운영 다운타임 윈도우 필요**.

대안: 모든 패키지가 양쪽 토픽 모두 publish/subscribe하는 transitional 단계를 두는 것 (hybrid mode). 비용/복잡도가 너무 커서 권장 안 함 — 30분 정도의 다운타임이 더 실용적.

---

## 6. 검증 (각 PR마다)

### lidar_slam PR
- [ ] `colcon build --packages-select fast_lio cartographer_slam` 성공
- [ ] `grep -rn "/localization\|cartographer_2d/" src/lidar_slam --include="*.cpp" --include="*.hpp" --include="*.py"` → 0 hits (CHANGELOG 제외)
- [ ] `colcon test --packages-select fast_lio cartographer_slam` 통과
- [ ] mapping launch 실행 후 `ros2 topic list | grep slam/fast_lio` → 모든 production 토픽 노출
- [ ] localization launch 실행 후 동일 검증 + `/slam/fast_lio_loc/*` 노출

### pkrc_visualizer PR
- [ ] `colcon build --packages-select pkrc_visualizer` 성공
- [ ] `colcon test --packages-select pkrc_visualizer` 137/137 통과 (테스트 mock에 신규 토픽명 반영 필요할 수 있음)
- [ ] live: viz가 `/slam/fast_lio/points_body` 구독 → SLAM 페이지 클라우드 정상

### sonar_3d_reconstruction PR
- [ ] `colcon build --packages-select sonar_3d_reconstruction` 성공
- [ ] `colcon test --packages-select sonar_3d_reconstruction` 통과
- [ ] `ros2 launch sonar_3d_reconstruction 3d_mapping.launch.py odometry:=fast_lio` → `/slam/fast_lio/odometry` 구독 확인
- [ ] bag record + QoS override yaml 적용 확인

---

## 7. 외부 follow-up

워크스페이스 src/ 밖의 외부 노드들도 갱신 필요:

| 노드 | 사용 중인 옛 이름 | 필요 작업 |
|---|---|---|
| `hero_main_control` | `/cartographer_2d/odometry`, `/fast_lio/odometry` (이미 두 단계 뒤떨어진 상태) | 별도 repo 찾아 PR로 `/slam/cartographer/odometry`, `/slam/fast_lio/odometry` 적용 |
| (그 외 외부 노드 발견 시) | — | `ros2 topic info`로 publisher/subscriber 매핑 후 패치 |

`hero_main_control`은 현재도 publisher 0인 옛 이름을 구독 중 — 이 rename PR 머지 전에도 이미 동작 안 함. 이 rename은 그 상황을 더 악화시키지 않음.

---

## 8. 트레이드오프 / 주의사항

- **운영 다운타임**: 세 PR 머지 사이 일시적 토픽 미스매치 — 보트 운용 비활성 시간대에 머지하는 것 권장.
- **bag 호환성**: 기존 ros2 bag은 옛 토픽명으로 기록됨. 재생 시 옛 토픽으로 publish됨 → 새 코드는 이를 못 받음. **재생 호환 필요시 launch에서 remap 적용** (예: `ros2 bag play <bag> --remap /localization/fast_lio/odometry:=/slam/fast_lio/odometry`).
- **외부 노드 호환성**: 위 §7 참조. 머지 직후 외부 노드 미반영 상태 일시 발생.
- **CHANGELOG 업데이트**: 각 패키지 CHANGELOG.md에 rename 기록 (이전 7th audit이 그랬듯).

---

## 9. 실행 시 명령 템플릿

각 repo에서 brunch + 작업 (in-flight 머지 후):

```bash
# lidar_slam
cd src/lidar_slam
git checkout main && git pull
git checkout -b refactor/topics-slam-namespace-unification
# ...edits per §4.1...
colcon build --packages-select fast_lio cartographer_slam --merge-install
colcon test --packages-select fast_lio cartographer_slam
# commit + push + PR

# pkrc_visualizer (lidar_slam PR 머지 후)
cd ../pkrc_visualizer
git checkout main && git pull
git checkout -b refactor/topics-slam-namespace-unification
# ...edits per §4.2...
# build, test, commit, push, PR

# sonar_3d_reconstruction (pkrc_visualizer PR 머지 후)
cd ../sonar_3d_reconstruction
git checkout main && git pull
git checkout -b refactor/topics-slam-namespace-unification
# ...edits per §4.3...
# build, test, commit, push, PR
```

각 PR 제목 (Conventional Commits):
- `refactor(fast_lio,cartographer_slam): unify topic namespace under /slam/`
- `refactor(pkrc_visualizer): subscribe to /slam/* topics after lidar_slam rename`
- `refactor(sonar_3d_reconstruction): subscribe to /slam/* topics + update bag QoS + rviz + docs`
