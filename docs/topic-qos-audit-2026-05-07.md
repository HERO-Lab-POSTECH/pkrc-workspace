# PKRC Workspace 정합성 감사 — 2026-05-07

워크스페이스 7개 패키지 + sensor_packages 하위 4개의 토픽 / QoS / TF 정합성을 정적 분석한 종합 리포트. 이 세션에서 식별된 모든 문제를 카테고리별로 정리하고 우선순위와 권장 조치를 명시.

> **분석 범위**: 소스(`*.cpp`/`*.hpp`/`*.py`), launch(`launch/*.py`), config(`*.yaml`, `*.lua`). 런타임(`ros2 topic list`, `ros2 doctor`) 미포함.
> **분석 대상 패키지**: `boat_description`, `cartographer_slam`, `fast_lio`, `pkrc_visualizer`, `ping1d_ros2`, `sonoptix_ros2`, `sonar_3d_reconstruction`, `livox_ros2`, `oculus_ros2`.
> **관련 문서**: [`topic-namespace-rename-plan.md`](topic-namespace-rename-plan.md) — 이 audit의 후속으로 결정된 `/slam/...` 통합 컨벤션 실행 계획.

---

## TL;DR

| 카테고리 | 발견 | 즉시 차단 | 잠재 footgun |
|---|---|---|---|
| QoS 호환성 (Pub/Sub 연결) | 17개 매칭 분석 | 0건 | 1건 (의미 비일관) |
| 토픽 이름 컨벤션 | 4건 | 0건 | 4건 → **`/slam/...` 통합 rename으로 처리 결정** |
| TF 프레임 정합성 | 5건 | **1건 (mapping 단독)** ← PR #28에서 수정 | 3건 |
| 운용 모드 결합 | 5건 | 0건 | 5건 |
| 아키텍처 중복 | 1건 | 0건 | 1건 → PR #12에서 처리 |
| 고아 publisher | 11+개 | 0건 | 1건 (ping1d 통째로) |

### 이 세션에서 진행된 PR (3개 in-flight)

| PR | repo | 내용 | 상태 |
|---|---|---|---|
| [#12](https://github.com/HERO-Lab-POSTECH/pkrc_visualizer/pull/12) | pkrc_visualizer | viz가 production 토픽으로 마이그레이션 (debug 의존 끊음) | open |
| [#28](https://github.com/HERO-Lab-POSTECH/lidar_slam/pull/28) | lidar_slam | mapping 모드 `map→odom` static identity TF | open |
| [#29](https://github.com/HERO-Lab-POSTECH/lidar_slam/pull/29) | lidar_slam | debug 토픽 기본 비활성 (#28 stacked) | open |

### 후속 결정: 통합 네임스페이스 rename

- audit §3 (이름 컨벤션 이슈), §6 (운용 모드 footgun)에서 식별된 모든 토픽명 비일관을 한 번에 해결하기로 결정.
- 모든 SLAM 관련 토픽을 **`/slam/<stack>/<output>`** 컨벤션으로 통일 (`/localization/...`, `cartographer_2d/...`, `/fast_lio/debug/...` 모두 흡수).
- 실행: 위 3개 PR 머지 → `topic-namespace-rename-plan.md`에 정의된 3-PR 시리즈.
- 외부 노드(예: `hero_main_control`)가 옛 이름을 구독 중이라면 별도 follow-up.

---

## 1. 분석 방법

1. 각 패키지를 병렬 sub-agent로 정적 추출 — pub/sub 호출, QoS 프로파일, launch remapping, config 파라미터 모두 수집.
2. 토픽 그래프를 구성 후 ROS2 QoS 호환성 매트릭스(부록 A) 적용.
3. TF broadcaster / listener 식별 후 frame 권한 매트릭스 작성.
4. `docs/architecture-overview.md` 의도와 실제 구현 비교.
5. 운용 모드 조합(예: `odometry=cartographer/fast_lio/fast_lio_loc`)별 데이터 흐름 검증.

QoS 호환성 룰:
- Pub `RELIABLE` ↔ Sub `BEST_EFFORT` = 호환 (다운그레이드)
- Pub `BEST_EFFORT` ↔ Sub `RELIABLE` = **비호환** (연결 안 됨)
- Pub `TRANSIENT_LOCAL` ↔ Sub `VOLATILE` = 호환
- Pub `VOLATILE` ↔ Sub `TRANSIENT_LOCAL` = **비호환**

---

## 2. 토픽 매칭 매트릭스

### 2.1 정상 매칭 (런타임 OK)

| Topic | Pub QoS | Sub QoS | 비고 |
|---|---|---|---|
| `/sensor/lidar/livox_mid360/points` | livox_ros2: BEST_EFFORT | fast_lio, cartographer: SensorDataQoS | ✓ |
| `/sensor/ins/livox_mid360/imu` | livox_ros2: BEST_EFFORT | fast_lio, cartographer: BEST_EFFORT | ✓ |
| `/localization/fast_lio/odometry` | fast_lio: RELIABLE depth=10 | visualizer, fast_lio_loc, sonar_3d: RELIABLE | ✓ |
| `/localization/fast_lio/points_body` | fast_lio: BEST_EFFORT depth=5 | fast_lio_loc: BEST_EFFORT | ✓ (fast_lio_loc 내부) |
| `/localization/fast_lio_loc/odometry` | fast_lio_loc: RELIABLE depth=10 | visualizer, sonar_3d: RELIABLE | ✓ |
| `/localization/fast_lio_loc/confidence` | fast_lio_loc: RELIABLE | visualizer, sonar_3d: RELIABLE | ✓ |
| `/localization/cartographer/odometry` | cartographer: depth=10 (default=RELIABLE) | sonar_3d: RELIABLE | ✓ (단, cartographer는 명시적 QoS 미지정) |
| `/initialpose` | visualizer: depth=10 (default=RELIABLE) | fast_lio_loc: RELIABLE | ✓ |
| `/sensor/sonar/oculus/{model}/image` | oculus fan_imager: BEST_EFFORT | sonar_3d 3d_mapper: BEST_EFFORT depth=5 | ✓ (단, `sonar_model` launch arg 양쪽 일치 필요) |
| `/sensor/sonar/oculus/{model}/param/range` | oculus: RELIABLE+TRANSIENT_LOCAL+depth=1 | sonar_3d: RELIABLE+TRANSIENT_LOCAL+depth=1 | ✓ EXACT |
| `/perception/sonar_3d/points` | sonar_3d: BEST_EFFORT depth=5 | visualizer: BEST_EFFORT depth=5 | ✓ |
| `/perception/sonar_3d_visualizer/markers` | sonar_3d map_visualizer: BEST_EFFORT depth=5 | visualizer: BEST_EFFORT depth=5 | ✓ |
| `/perception/sonar_3d/tile_indices` | sonar_3d 3d_mapper: RELIABLE+TRANSIENT_LOCAL+depth=1 | sonar_3d map_visualizer: 동일 | ✓ EXACT |
| `/cartographer_2d/submaps` | cartographer node: depth=10 | cartographer occupancy_grid: depth=10 | ✓ 내부 |
| `/sensor/sonar/sonoptix/data` | sonoptix echo.py: BEST_EFFORT | sonoptix echo_imager.py: BEST_EFFORT | ✓ 내부 |
| `/fast_lio/debug/path` | fast_lio: BEST_EFFORT depth=5 | visualizer: BEST_EFFORT depth=5 | ✓ (단, 이름 컨벤션 깨짐 — §3.1) |
| `/fast_lio/debug/points_world` | fast_lio: BEST_EFFORT depth=5 | visualizer: BEST_EFFORT depth=5 | ✓ (단, 이름 + 아키텍처 — §3.1, §5) |

### 2.2 호환되지만 의미 비일관

| Topic | Pub | Sub | 문제 |
|---|---|---|---|
| `/localization/fast_lio_loc/occupancy_grid` | fast_lio_loc: **RELIABLE+TRANSIENT_LOCAL+depth=1** (latched) | visualizer: **BEST_EFFORT+TRANSIENT_LOCAL+depth=10** | RELIABLE → BEST_EFFORT 다운그레이드 + depth 불일치. 정적 점유 격자 = RELIABLE이 자연스러움. |

### 2.3 차단 (Pub BEST_EFFORT ↔ Sub RELIABLE)

**없음.**

### 2.4 고아 Publisher (워크스페이스 내 소비자 0)

RViz 컨피그가 외부에서 사용할 가능성은 있으나 정적으로는 미확인:

- **ping1d_ros2 모든 출력** (`/sensor/sonar/ping1d/range`, `/data`, `/param/*`) — 워크스페이스 어디에서도 구독 안 함. **죽은 코드 또는 미완성 통합.**
- `/cartographer_2d/{map,scan_matched_points2,landmark_poses,constraints,tracked_pose}` — RViz only.
- `/perception/sonar_3d/markers`, `/perception/sonar_3d_visualizer/{points,octomap}` — RViz only (visualizer는 `_visualizer/markers` 사용).
- `/perception/sonar_3d/diagnostics` — rqt 등 진단 도구.
- `/localization/fast_lio_loc/map` — RViz only.
- `/sensor/sonar/oculus/{model}/{metadata,raw_data,fan_image}` — 진단 / RViz.
- `/perception/map_diff/*` — `map_diff.launch.py` 별도 모드.
- `/robot_detection/*` (filtered_image, point_cloud, occupancy_grid, updated_tile_indices) — RViz only (mapper 출력의 remap).

---

## 3. 이름 컨벤션 이슈

> **상태 업데이트**: 이 절의 (a)/(b) 권장은 후속 결정으로 **둘 다 채택**되어 통합 처리됨.
> - **(b) 의존 제거**: pkrc_visualizer #12 (머지 대기) — viz가 production 토픽 + TF로 마이그레이션.
> - **(a) 리네이밍**: `topic-namespace-rename-plan.md` — 단, 타깃이 `/localization/...`이 아니라 **`/slam/...`** (의미 정확성 + 통일).

### 3.1 `/fast_lio/debug/*` 네임스페이스 깨짐

**현재 분포**:
```
/localization/fast_lio*/        ← 정합 (production 출력)
  /localization/fast_lio/odometry
  /localization/fast_lio/points_body
  /localization/fast_lio_loc/odometry
  /localization/fast_lio_loc/confidence
  /localization/fast_lio_loc/occupancy_grid
  /localization/fast_lio_loc/map

/fast_lio/debug/*               ← 컨벤션 깨짐
  /fast_lio/debug/path           ← visualizer 실제 구독 (production!)
  /fast_lio/debug/points_world   ← visualizer 실제 구독 (production!)
  /fast_lio/debug/points_effected  ← 기본 비활성, 소비자 0
  /fast_lio/debug/map              ← 기본 비활성, 소비자 0
```

**문제**:
- production 시각화 입력(`path`, `points_world`)이 "debug" 라벨에 숨어 있음.
- `localization.launch.py:114-118`은 `publish.scan_publish_en=True`를 강제 오버라이드해서 `/fast_lio/debug/points_world`를 활성화함. 이 코멘트가 이미 "debug 토픽이 visualizer에 필수"임을 인정하고 있음.

**개선 권장 (두 가지 대안)**:

**(a) 단순 리네이밍** — 의존 구조는 그대로, 이름만 정리:
```
/fast_lio/debug/path           → /localization/fast_lio/path
/fast_lio/debug/points_world   → /localization/fast_lio/points_world
/fast_lio/debug/points_effected, /map  → 사용처 0이면 삭제, 또는 유지 시 그대로
```

**(b) 의존 제거** (더 깊은 리팩토링) — visualizer가 production 토픽으로 갈아탐:
- pkrc_visualizer는 이미 30초 decay 버퍼를 자체 구현 중 (`pyvista_view.py:191`, `_accum_chunks` deque). RViz의 Decay Time 패턴과 동일.
- 즉 `/localization/fast_lio/points_body` (이미 publish 중) + TF lookup `odom←base_link` + 자체 decay 누적 → 현재와 시각적 동등.
- `/fast_lio/debug/path` 도 `/localization/fast_lio/odometry` (RELIABLE) 메시지를 시간순 누적으로 path 자체 구성 가능.
- 결과: `/fast_lio/debug/points_world`, `/fast_lio/debug/path`가 **진짜 debug-only**가 됨 → 기본 비활성, 사용처 0 → 삭제 가능.

**(b)의 트레이드오프**: visualizer에 TF 변환 코드 추가(몇 줄). points_body는 base_link 기준이므로 visualizer가 `odom←base_link` lookup을 매 프레임 수행해야 함 — 이미 `map←odom` lookup 인프라 있으므로 추가 비용 미미.

**권장**: (b)를 장기 목표로 삼되, (a)를 단기 처방으로 즉시 적용.

### 3.2 fast_lio mapping 모드 구성 비일관 (수정 완료)

**문제**: `mapping.launch.py` docstring은 `map → odom → base_link` TF 트리를 광고했지만 실제로 `map → odom` broadcaster가 없었음. 또한 `mid360.yaml`의 `scan_publish_en=false` 기본값이 `/fast_lio/debug/points_world`를 침묵시켜 visualizer 입력 차단.

**이 세션 수정**: ✅ §7 참조.

---

## 4. TF 프레임 정합성

### 4.1 프레임 권한 매트릭스

| Frame | Broadcaster | Listener / 헤더 사용자 |
|---|---|---|
| `map` | cartographer (`map→odom`), fast_lio_loc (`map→odom`), **fast_lio mapping (이번 세션 수정 후 identity, 옵트아웃 가능)** | sonar_3d (header), pkrc_visualizer (lookup, /initialpose 헤더) |
| `odom` | fast_lio mapping (`odom→base_link`), cartographer (`provide_odom_frame=true`) | fast_lio_loc, RViz |
| `base_link` | URDF (boat_description) | fast_lio (`body_frame`), cartographer (`published_frame`), sonar_3d (`frames.base`) |
| `sonar_link` | URDF, sonar_3d (정적 `base_link→sonar_link` if `frames.publish_tf=true`) | oculus driver (`frame_id`), sonar_3d (`frames.sonar`) |
| `livox_link` | URDF | livox driver (preprocess.cpp:913 **하드코딩**), cartographer (`tracking_frame`) |

### 4.2 TF 이슈

| # | 이슈 | 심각도 | 상태 |
|---|---|---|---|
| TF-1 | fast_lio mapping 단독 시 `map` 프레임 미정의 → visualizer/sonar_3d lookup 실패 | High | ✅ **수정 완료** (§7) |
| TF-2 | `sonar_3d/scripts/config.py:345` OutOfCore 모드 `frames.map` fallback이 `'camera_init'` (FAST-LIO 잔재). 다른 모든 곳 `'map'`. launch 미사용 시 깨짐 | Medium | ⏳ 대기 |
| TF-3 | cartographer + fast_lio mapping 동시 실행 시 `odom→base_link` 권한 충돌 (둘 다 broadcast) | Medium | ⏳ 대기 |
| TF-4 | livox 드라이버 `frame_id="livox_link"` 하드코딩 (`preprocess.cpp:913`). cartographer Lua의 `tracking_frame="livox_link"`도 하드코딩. | Low | ⏳ 대기 |
| TF-5 | mapping.launch.py docstring이 사실과 달랐음 (URDF가 `map→odom`을 제공한다고 광고했으나 URDF는 base_link 하위만 제공) | Low | ✅ docstring 갱신 (TF-1 수정과 함께) |

---

## 5. 아키텍처 중복 — pkrc_visualizer ↔ fast_lio

### 발견

pkrc_visualizer는 이미 RViz의 Decay Time과 동일한 시간 기반 누적 버퍼를 구현 중 (`pyvista_view.py:184, 191`):
```python
self._accum_chunks: deque[tuple[float, np.ndarray]] = deque()
self.decay_seconds = 30.0
```

그럼에도 pre-accumulated `/fast_lio/debug/points_world`를 구독함. 데이터 흐름상:
- `/localization/fast_lio/points_body` (production) + TF + 자체 decay = `/fast_lio/debug/points_world` + 자체 decay (시각적 동등).

**단순 리네이밍이 아니라 토픽 자체 제거 가능 — §3.1(b) 참조.**

### 동일 패턴 가능성 검토 필요

- `/perception/sonar_3d/points`: sonar_3d mapper가 매 프레임 누적 클라우드를 publish하는지, current voxel만 publish하는지에 따라 visualizer가 같은 패턴으로 갈 수 있는지 결정됨. (정적 분석으로 미확정.)

---

## 6. 운용 모드 footgun

토픽은 정합되지만 **launch 파라미터 조합이 어긋나면** 깨지는 케이스. 정적 분석으로는 잡히지 않고, launch 검증 레이어가 필요.

| # | 시나리오 | 결과 |
|---|---|---|
| OP-1 | oculus 드라이버 `sonar_model=m750d` + sonar_3d launch `sonar_model=m3000d` | `topics.sonar` 미존재 토픽 → mapper 입력 0 |
| OP-2 | livox 드라이버 `multi_topic=1` 활성화 | fast_lio/cartographer가 `_{IP}` 없는 단일 토픽 가리킴 → 입력 0 |
| OP-3 | sonar_3d `odometry=fast_lio` + cartographer만 띄움 | mapper가 `/localization/fast_lio/odometry` 대기 (없음) → 메시지 0 |
| OP-4 | `robot_3d_mapping.launch.py` 사용 시 visualizer가 `/perception/sonar_3d/points` 구독 | mapper가 `/robot_detection/point_cloud`로 remap → visualizer는 NEW 스캔 못 받음 (old 맵은 별도 map_visualizer 노드에서 받음) |
| OP-5 | mapping.launch.py + cartographer 결합 시 `publish_map_tf:=false` 잊음 | `map→odom` 두 broadcaster 충돌 → undefined behavior |

**완화 권장**: launch 조합 검증을 위한 가이드 문서(`docs/deployment.md` 보강) 또는 wrapper launch 도입.

---

## 7. 이 세션에서 적용한 수정 (TF-1)

### 변경 파일
- `src/lidar_slam/fast_lio/launch/mapping.launch.py`

### 변경 내용
1. **docstring 갱신**: TF 트리 표기를 standalone vs combined 두 케이스로 분리. 토픽 출력 목록에 `/fast_lio/debug/points_world` 추가.
2. **launch arg 추가**: `publish_map_tf` (default `'true'`).
3. **scan_publish_en 강제 오버라이드**: fast_lio 노드 파라미터에 `'publish.scan_publish_en': True` 추가 — 이전엔 mid360.yaml의 `scan_publish_en=false` 때문에 mapping 모드에서 `/fast_lio/debug/points_world`가 침묵했음. localization.launch.py가 이미 같은 이유로 동일 오버라이드를 하고 있어 mapping 측도 일관시킴.
4. **static_transform_publisher 추가**: `publish_map_tf=true`일 때 `map → odom` identity TF를 broadcast. fast_lio mapping의 odom-frame 출력이 visualizer/sonar_3d의 `map` frame lookup과 자연스럽게 정합됨.

### 결과 (양 모드 매트릭스)

| Launch | `map → odom` Broadcaster | visualizer 동작 | sonar_3d 동작 |
|---|---|---|---|
| `localization.launch.py` (loc 모드) | fast_lio_loc (실제 정합 변환) | ✓ 종전과 동일 | ✓ 종전과 동일 |
| `mapping.launch.py` (단독, 신규 default) | static identity (이번 수정) | ✓ **신규 동작** (이전엔 lookup 실패) | ✓ **신규 동작** |
| `mapping.launch.py` + cartographer (`publish_map_tf:=false`) | cartographer | ✓ | ✓ |
| `mapping.launch.py` + fast_lio_loc 별도 launch (`publish_map_tf:=false`) | fast_lio_loc | ✓ | ✓ |

### 검증 방법 (수동)
1. `ros2 launch fast_lio mapping.launch.py` 실행.
2. `ros2 run tf2_ros tf2_echo map odom` — identity transform이 보여야 함.
3. `ros2 topic hz /fast_lio/debug/points_world` — non-zero rate.
4. pkrc_visualizer 띄우고 누적 클라우드가 그려지는지 확인.
5. Bag replay로 cartographer를 함께 띄우는 시나리오: `ros2 launch fast_lio mapping.launch.py publish_map_tf:=false` + cartographer launch → `tf2_echo map odom`이 cartographer의 동적 TF를 보여줘야 함.

---

## 8. 권장 조치 (상태)

### 처리됨 / 머지 대기 (3개 in-flight PR)

| 항목 | 처리 PR | 상태 |
|---|---|---|
| §3.1(b) 의존 제거 — viz를 production 토픽으로 | pkrc_visualizer#12 | open |
| TF-1 fast_lio mapping `map→odom` static TF | lidar_slam#28 | open |
| §3.1 debug 토픽 기본 비활성 | lidar_slam#29 (#28 stacked) | open |

### 후속 통합 처리 — 통합 rename PR 시리즈

상세는 [`topic-namespace-rename-plan.md`](topic-namespace-rename-plan.md) 참조. 한 번의 작업으로 처리되는 항목:

| 항목 | 비고 |
|---|---|
| §3.1(a) `/fast_lio/debug/*` 리네이밍 | `/slam/fast_lio/debug/*`로 통일 |
| §3.2 cartographer `cartographer_2d/*` 옛 컨벤션 잔재 | `/slam/cartographer/*`로 통일 |
| 범용 `/localization/*` → `/slam/*` 통일 | fast_lio mapping 모드에 의미 정확 |

### 잔여 권장 조치

**High**
1. **TF-2**: `sonar_3d_reconstruction/scripts/config.py:345` `frames.map` fallback `'camera_init'` → `'map'` 변경.

**Medium**
2. **§2.2**: `/slam/fast_lio_loc/occupancy_grid` (rename 후 이름) visualizer 측 QoS를 `RELIABLE+TRANSIENT_LOCAL+depth=1`로 통일 (현재 BEST_EFFORT+depth=10).
3. **§2.4**: ping1d_ros2 운명 결정 — 통합 작업 진행 또는 패키지 disable.
4. **TF-3**: cartographer Lua의 `provide_odom_frame=true` 와 fast_lio mapping의 `odom→base_link` 권한 충돌 — launch 차원에서 동시 실행 차단 또는 Lua 옵션 변경 검토. (mapping.launch.py에 `publish_map_tf:=false`처럼 cartographer launch에도 `provide_odom_frame:=false` 옵션 추가 가능.)
5. **OP-1~5**: launch 조합 검증 가이드를 `docs/deployment.md`에 추가, 또는 상위 wrapper launch 도입.
6. **외부 노드**: `hero_main_control` 등 워크스페이스 외부 구독자가 옛 토픽명 그대로 — rename 후 별도 follow-up.

**Low**
7. **§3.1**: `/slam/fast_lio/debug/{points_effected,map}` (rename 후) — 사용처 0이고 기본 비활성 → 삭제 검토. (FAST-LIO 업스트림 호환을 원하면 유지.)
8. **TF-4**: livox 드라이버 `frame_id` 파라미터화. cartographer Lua의 `tracking_frame` 도 동일.

---

## 부록 A — QoS 호환성 매트릭스

**Reliability**
| Pub \ Sub | RELIABLE | BEST_EFFORT |
|---|---|---|
| RELIABLE | ✓ | ✓ (다운그레이드) |
| BEST_EFFORT | ✗ 비호환 | ✓ |

**Durability**
| Pub \ Sub | TRANSIENT_LOCAL | VOLATILE |
|---|---|---|
| TRANSIENT_LOCAL | ✓ | ✓ |
| VOLATILE | ✗ 비호환 | ✓ |

**History/Depth**: 호환에 무관 — 큐 사이즈일 뿐.

## 부록 B — sonar_3d_reconstruction 운용 모드별 토픽 매트릭스

| odometry= | 구독 odom 토픽 | 구독 confidence 토픽 | map frame broadcaster |
|---|---|---|---|
| `cartographer` | `/localization/cartographer/odometry` | (없음) | cartographer |
| `fast_lio` | `/localization/fast_lio/odometry` | (없음) | fast_lio mapping (이번 수정 후 identity) |
| `fast_lio_loc` | `/localization/fast_lio_loc/odometry` | `/localization/fast_lio_loc/confidence` | fast_lio_loc |

`sonar_model=` 별 sonar 토픽:
| sonar_model= | 구독 sonar 토픽 | 자동 derive된 range 토픽 |
|---|---|---|
| `m750d` | `/sensor/sonar/oculus/m750d/image` | `/sensor/sonar/oculus/m750d/param/range` |
| `m3000d` | `/sensor/sonar/oculus/m3000d/image` | `/sensor/sonar/oculus/m3000d/param/range` |

oculus 드라이버 측 `topic_prefix`도 같은 `sonar_model`로 맞춰야 함 — launch arg가 양쪽에서 수동 일치 (자동 강제 없음).

## 부록 C — 분석 시점 / 범위 한계

- 분석 시점: 2026-05-07 워크스페이스 HEAD.
- 미포함:
  - 런타임 토픽/TF echo 검증.
  - 외부 RViz 컨피그가 기대하는 토픽 목록.
  - launch 조합 매트릭스의 자동 검증.
  - 메시지 타입 호환성 (예: livox `multi_topic=1` 시 `xfer_format`별 메시지 타입 변동).
