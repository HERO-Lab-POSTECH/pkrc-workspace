# 셋업 이슈 로그

`bootstrap.sh`로 fresh 환경에서 워크스페이스를 처음 셋업할 때 마주친 이슈와 워크어라운드를 기록합니다.

대부분은 upstream 패키지의 `package.xml` 버그 또는 누락된 빌드 의존성이고, 일부는 환경/도구 호환성 문제입니다. 각 이슈가 upstream에서 해결되면 이 문서에서 해당 항목을 제거하세요.

**최초 기록일**: 2026-05-04 (Ubuntu 22.04, ROS2 Humble, fresh 환경)

---

## 1. `bootstrap.sh`가 ROS2 setup.bash source 시 unbound variable로 실패

**증상**

```
/opt/ros/humble/setup.bash: line 8: AMENT_TRACE_SETUP_FILES: unbound variable
BOOTSTRAP_EXIT=1
```

**원인**

`bootstrap.sh:5`에 `set -euo pipefail`이 활성화되어 있고, `:37`에서 ROS2 setup.bash를 source합니다. ROS humble의 `/opt/ros/humble/setup.bash:8`은 `[ -n "$AMENT_TRACE_SETUP_FILES" ]` 패턴을 사용 — 이건 `set -u` 모드에서 변수가 미정의면 즉시 실패합니다. ROS2 setup 스크립트는 일반적으로 `set -u` 친화적이지 않습니다.

**워크어라운드 (이미 적용됨)**

`scripts/bootstrap.sh`에서 source 라인을 `set +u` / `set -u`로 감쌌습니다:

```bash
set +u
source /opt/ros/humble/setup.bash
set -u
```

**Upstream fix**

(이미 이 레포에 적용됨.) 향후 ROS humble의 setup.bash가 `[ -n "${AMENT_TRACE_SETUP_FILES:-}" ]`처럼 POSIX-safe 형태로 수정되면 `set +u` wrapper 제거 가능.

---

## 2. 비대화형 셸에서 `sudo`가 비밀번호를 받지 못함 (SSH/스크립트 자동화)

**증상**

```
sudo: a terminal is required to read the password; either use the -S option
to read from standard input or configure an askpass helper
```

**원인**

`bootstrap.sh:51`의 `sudo rosdep init`과 `rosdep install`이 내부적으로 호출하는 `sudo apt install`은 둘 다 bare `sudo`를 사용합니다. 비대화형 셸(SSH, 스크립트, CI 등)에서는 TTY가 없어 비밀번호 프롬프트를 띄울 수 없습니다.

대화형 SSH 셸에서는 `bootstrap.sh`를 직접 실행하면 정상 동작 — 첫 sudo 호출 때 비밀번호가 한 번 물어보고 캐시됩니다. **이 이슈는 자동화 환경(예: ansible, claude code, CI)에서만 발생**합니다.

**워크어라운드**

자동화 환경에서는 다음 셋 중 하나:

1. **인터랙티브로 첫 sudo만 미리 실행**한 뒤 `bootstrap.sh` 실행 — 가장 단순.
   ```bash
   sudo -v   # 한 번 비밀번호 입력 → 자격 캐시
   ./scripts/bootstrap.sh
   ```

2. **`SUDO_ASKPASS` 패턴**: 비밀번호를 출력하는 helper script를 만들고 `sudo -A`로 호출. `bootstrap.sh`가 bare `sudo`를 쓰기 때문에 이 패턴을 쓰려면 스크립트 수정이 필요합니다.

3. **PATH `sudo` shim**: 임시로 PATH 앞쪽에 `echo PW | /usr/bin/sudo -S "$@"` 패턴의 wrapper를 두고 실행. 시스템 sudoers 변경 없이 가능, 단 비밀번호가 임시 파일에 평문으로 들어가므로 `chmod 700` + 작업 후 즉시 삭제.

**Upstream fix**

`bootstrap.sh`에 `--non-interactive` 옵션을 추가해 `sudo -A` 또는 `SUDO_ASKPASS` 호환 모드로 동작하게 하면 자동화 친화적이 됩니다.

---

## 3. `rosdep install`이 3개 키 해결 실패 (upstream `package.xml` 버그)

**증상**

```
ERROR: the following packages/stacks could not have their rosdep keys resolved
to system dependencies:
sonar_3d_reconstruction: Cannot locate rosdep definition for [liboctomap1.9]
liboculus: Cannot locate rosdep definition for [g3log]
oculus_sonar: Cannot locate rosdep definition for [opencv]
```

**원인**

각 패키지의 `package.xml`에 적힌 의존성 키가 ROS rosdistro의 rosdep DB에 등록되어 있지 않습니다:

| 패키지 | 잘못된 키 | 올바른 키 (rosdep 등록됨) | 비고 |
|---|---|---|---|
| `sonar_3d_reconstruction` | `liboctomap1.9` (apt 패키지명을 직접 적음) | `liboctomap-dev` | apt에 같은 이름이 있긴 하나 rosdep 키는 아님 |
| `oculus_sonar` | `opencv` | `libopencv-dev` 또는 `python3-opencv` | "opencv"라는 키는 없음 |
| `liboculus`, `oculus_sonar` | `g3log` | (rosdep 키 없음) | g3log는 워크스페이스 안에 vendored — Issue 4 참고 |

**워크어라운드**

```bash
# 시스템 패키지 직접 설치
sudo apt install -y liboctomap-dev liboctomap1.9 libopencv-dev libomp-dev

# 위 3개 키 skip한 상태로 rosdep install
rosdep install --from-paths src --ignore-src -y --rosdistro humble \
    --skip-keys "liboctomap1.9 g3log opencv"
```

**Upstream fix (각 레포에 PR 필요)**

- `sonar_3d_reconstruction/package.xml`: `<exec_depend>liboctomap1.9</exec_depend>` → `<exec_depend>liboctomap-dev</exec_depend>` (또는 제거 — `<build_depend>liboctomap-dev</build_depend>`로 이미 커버됨).
- `sensor_packages/oculus_ros2/oculus_sonar/package.xml`: `<depend>opencv</depend>` → `<depend>libopencv-dev</depend>`.
- `g3log` 처리는 Issue 4 참고.

---

## 4. `g3log`이 vendored되어 있지만 `package.xml` 없음 → colcon이 빌드 안 함

**증상**

`liboculus`/`oculus_sonar`의 `find_package(g3log REQUIRED)`가 실패. 시스템 어디에도 g3log이 설치되어 있지 않음.

**원인**

`sensor_packages/oculus_ros2/g3log/`에 [KjellKod/g3log](https://github.com/KjellKod/g3log) 소스가 vendored되어 있습니다. 하지만:

- `package.xml`이 없어 colcon이 ament/cmake 패키지로 인식 안 함 → 빌드 안 됨.
- `liboculus/CMakeLists.txt`도 `add_subdirectory(g3log)`를 하지 않고 `find_package(g3log REQUIRED)`만 호출 → 시스템에서 찾으려 함.
- apt에는 `g3log` 패키지 없음.

결과: g3log이 vendored되어 있는데도 빌드/링크 불가능한 어정쩡한 상태.

**워크어라운드**

vendored 소스를 수동으로 cmake 빌드 후 system install:

```bash
cd src/sensor_packages/oculus_ros2/g3log
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo make install   # /usr/local/lib에 설치
sudo ldconfig
```

설치 결과 검증:
```bash
ls /usr/local/lib/cmake/g3log/   # g3logConfig.cmake 등 있어야 함
ls /usr/local/lib/libg3log*      # libg3log.so 있어야 함
```

**제거 (필요 시)**:
```bash
cd src/sensor_packages/oculus_ros2/g3log/build
sudo make uninstall
```

**Upstream fix (선택지 2개, `sensor_packages` 레포에 PR)**

**옵션 A — vendored를 진짜 vendored ament cmake 패키지로 만들기** (권장)

`g3log/` 디렉터리에 다음 `package.xml` 추가:

```xml
<?xml version="1.0"?>
<package format="3">
  <name>g3log</name>
  <version>2.6.0</version>
  <description>Vendored g3log async logging library (KjellKod/g3log)</description>
  <maintainer email="...">HERO Lab POSTECH</maintainer>
  <license>UNLICENSE</license>
  <buildtool_depend>cmake</buildtool_depend>
  <export>
    <build_type>cmake</build_type>
  </export>
</package>
```

이렇게 하면 colcon이 g3log을 첫 번째로 빌드하고, 후속 패키지의 `find_package(g3log REQUIRED)`가 워크스페이스 install/ 안에서 찾을 수 있게 됩니다. system 설치 불필요.

**옵션 B — vendored 디렉터리 제거 + system 의존성으로 명시**

`g3log/` 삭제, `bootstrap.sh`에 g3log을 source에서 빌드하는 단계 명시 추가, `liboculus`/`oculus_sonar`의 `package.xml`에 `<depend>g3log</depend>` 대신 의존성 표기 안 하거나 system pkg-config 사용. 간단하지만 환경에 따라 g3log 설치 위치/버전 차이 위험.

---

## 5. `pip`이 시스템에 없어서 rosdep의 일부 Python 의존성 설치 실패

**증상**

```
ERROR: the following rosdeps failed to install
  pip: pip is not installed
```

**원인**

`ping1d_sonar` 등 일부 패키지가 `<exec_depend>` 또는 rosdistro의 매핑을 통해 pypi 패키지(예: `bluerobotics-ping`)에 의존합니다. rosdep은 이를 `pip3 install ...`로 설치하려 하지만 시스템에 `python3-pip`이 없으면 실패합니다.

Ubuntu 22.04는 기본 설치에 `pip`이 없을 수 있습니다.

**워크어라운드**

```bash
sudo apt install -y python3-pip
rosdep install --from-paths src --ignore-src -y --rosdistro humble  # 재시도
```

**Upstream fix**

`bootstrap.sh`의 Step 1 환경 검증에 `python3-pip` 존재 확인 + 자동 설치 또는 명시적 안내 추가:

```bash
command -v pip3 >/dev/null || fail "pip3 not found. Install: sudo apt install python3-pip"
```

또는 `apt`로만 설치 가능한 ROS 패키지가 있는지 점검 후 pypi 의존성 자체를 제거.

---

## 6. `livox_driver`: ROS2용 `package.xml` 누락 + `livox_sdk`: `package.xml` 자체 없음

**증상**

```
CMake Error: File /home/hero/ros2_ws/src/sensor_packages/livox_ros2/livox_driver/package.xml does not exist.
```

8개 패키지가 livox 의존성 체인 때문에 abort (`livox_driver`, `livox_sdk`, `marine_*_msgs`, `apl_msgs`, `oculus_sonar_msgs`, `ping360_sonar_msgs`, `g3log` 등).

**원인**

`livox_ros2` 디렉터리는 ROS1/ROS2 공용 레포에서 fork된 흔적이 그대로 남아 있습니다:

- `livox_driver/`에 `package_ROS1.xml`과 `package_ROS2.xml`이 있고 `package.xml`은 **없음**. 이는 ROS1/ROS2 dual-target 패키지의 흔한 관례 — `build.sh ROS2`가 적절한 파일을 활성화하도록 되어 있습니다. 하지만 이 `build.sh`는 워크스페이스의 `build/`, `devel/`, `install/`을 통째로 `rm -rf`하므로 `pkrc-workspace`의 다른 패키지를 박살냅니다 → 직접 사용 불가.
- `livox_sdk/`는 `package.xml` 자체가 없어 colcon이 인식 못 함. plain CMake 프로젝트로 vendored되어 있음 (g3log과 동일 패턴, Issue 4 참고).

**워크어라운드 (이미 적용됨)**

```bash
LIVOX_DIR=src/sensor_packages/livox_ros2

# livox_driver: ROS2 변환 (build.sh의 destructive 파트 빼고 본질만)
cd $LIVOX_DIR/livox_driver
cp package_ROS2.xml package.xml
cp -r launch_ROS2 launch

# livox_sdk: ament-cmake용 package.xml 추가
cat > $LIVOX_DIR/livox_sdk/package.xml << 'EOF'
<?xml version="1.0"?>
<package format="3">
  <name>livox_sdk</name>
  <version>2.3.0</version>
  <description>Vendored Livox SDK</description>
  <maintainer email="setup@local">PKRC Workspace Setup</maintainer>
  <license>BSD-3-Clause</license>
  <buildtool_depend>cmake</buildtool_depend>
  <export>
    <build_type>cmake</build_type>
  </export>
</package>
EOF
```

빌드 시 build.sh가 사용하는 cmake 플래그도 같이:

```bash
colcon build --symlink-install \
    --cmake-args -DROS_EDITION=ROS2 -DHUMBLE_ROS=humble -DCMAKE_BUILD_TYPE=Release
```

**Upstream fix (`sensor_packages/livox_ros2`)**

옵션 A — Livox 공식 ROS2 fork(`Livox-SDK/livox_ros_driver2`)로 교체. 해당 fork는 ROS2 전용으로 정리되어 있고 dual-target 의 잔재가 없습니다. `pkrc.repos`의 `sensor_packages` 매니페스트에서 livox 항목을 새 URL로 교체.

옵션 B — 현재 fork를 ROS2 전용으로 정리. `package_ROS1.xml` 제거, `package_ROS2.xml`을 `package.xml`로 rename, `launch_ROS1/`/`build.sh` 제거. `livox_sdk`에 `package.xml` 추가.

옵션 A가 장기적으로 단순. 옵션 B는 필요한 변경만 즉시 적용.

---

## 빌드 결과 빠른 검증

위 모든 워크어라운드 적용 후:

```bash
cd ~/ros2_ws
colcon build --symlink-install --cmake-args -DROS_EDITION=ROS2 -DHUMBLE_ROS=humble -DCMAKE_BUILD_TYPE=Release
source install/setup.bash
ros2 pkg list | grep -iE 'sonar|lidar|livox|oculus|ping|marine|fast_lio|cartographer|boat'
./scripts/doctor.sh
```

`doctor.sh` 결과가 모두 `[OK]`이면 셋업 정상.

---

## 환경 / 도구 버전 (이슈 발생 시점)

- Ubuntu 22.04 (jammy)
- ROS2 Humble (`/opt/ros/humble`)
- Python 3.10.12
- `python3-vcstool` 0.3.0-1
- `python3-rosdep` 0.26.0-1
- `g3log` (vendored) 2.6.0

```bash
# 위 환경 재현/검증
./scripts/doctor.sh
```
