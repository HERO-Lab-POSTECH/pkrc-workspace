# Troubleshooting

자주 마주치는 빌드/런타임 이슈와 해결 방법.

## 빌드

### `vcs: command not found`

```bash
sudo apt install python3-vcstool
```

### `colcon: command not found`

```bash
sudo apt install python3-colcon-common-extensions
```

### `rosdep: command not found` 또는 `rosdep init` 실패

```bash
sudo apt install python3-rosdep
sudo rosdep init  # 한 번만
rosdep update
```

`rosdep init` 시 "already exists" 에러가 나면 정상이고 무시해도 됩니다.

### 빌드 중 `oculus_sonar_msgs not found` 또는 메시지 패키지 누락

```bash
# 메시지 패키지를 먼저 빌드
colcon build --packages-select marine_acoustic_msgs oculus_sonar_msgs ping360_sonar_msgs
source install/setup.bash
colcon build  # 나머지 패키지
```

`./scripts/bootstrap.sh`는 의존성 그래프를 따르므로 정상 동작합니다. 수동 빌드 시에만 발생.

### `Could not find package "OctoMap"` 등 시스템 라이브러리 누락

```bash
rosdep install --from-paths src --ignore-src -y --rosdistro humble
```

### `LANG` 관련 colcon 경고

```bash
sudo locale-gen en_US.UTF-8
echo 'export LANG=en_US.UTF-8' >> ~/.bashrc
source ~/.bashrc
```

## 런타임

### DDS 디스커버리 안 됨 (다른 머신에서 토픽 안 보임)

1. 두 머신이 같은 LAN에 있는지 확인
2. 같은 `ROS_DOMAIN_ID` 사용 (`echo $ROS_DOMAIN_ID`)
3. 방화벽 multicast 차단 여부 확인 (`sudo ufw status`)
4. WSL2 사용 시 — DDS 디스커버리에 한계가 있어 native Linux 권장

### 노드는 떴는데 토픽 메시지가 안 옴 (QoS mismatch)

소나 드라이버는 `BEST_EFFORT`로 publish합니다. subscriber도 `BEST_EFFORT`여야 매칭됩니다. 현재 정책: 센서·SLAM·odometry는 모두 `BEST_EFFORT`, 맵 토픽 3개만 `RELIABLE + TRANSIENT_LOCAL`.

상세: [QoS 정책](https://github.com/HERO-Lab-POSTECH/sonar_3d_reconstruction/blob/main/docs/source/reference/qos-policy.md)

### 시리얼 디바이스 권한 거부 (`/dev/ttyUSB0: Permission denied`)

```bash
sudo usermod -aG dialout $USER
# 로그아웃 후 다시 로그인
```

### `sonar_stamp - odom_stamp` 시간차 큼

운영 환경에서 sonar↔odom stamp_diff가 임계값(0.1s)을 초과하면 프레임이 드롭됩니다. `3d_mapper_node`의 `MAX_STAMP_DIFF` 파라미터를 환경에 맞춰 조정하세요. 자세한 분석은 [release-note 2026-03-28](https://github.com/HERO-Lab-POSTECH/sonar_3d_reconstruction/blob/main/docs/source/release-notes/2026-03-28-qos-stabilization.md) 참조.

## Git / 동기화

### `vcs pull` 시 `not a fast-forward` 에러

해당 패키지에 미커밋 또는 로컬 commit이 있어서입니다. 수동 처리:

```bash
cd src/<package>
git status   # 변경사항 확인
git stash    # 또는 commit
git pull --rebase
git stash pop  # stash 했다면
```

### `Repository not found` (sonar_3d_reconstruction)

옛 URL을 참조하고 있을 수 있습니다 (이전됨: `luckkim123` → `HERO-Lab-POSTECH`). GitHub redirect로 한동안 동작하지만 명시적 갱신 권장:

```bash
cd src/sonar_3d_reconstruction
git remote set-url origin https://github.com/HERO-Lab-POSTECH/sonar_3d_reconstruction.git
```

## 환경 진단

위 내용 외 문제는 자가 진단 스크립트로 시작:

```bash
./scripts/doctor.sh
```

해결되지 않으면 GitHub 이슈로 등록 — 템플릿이 필요한 정보(환경, 재현 단계, 로그)를 안내합니다.

## 왜 Docker를 쓰지 않나

- 실 운영 환경(boat Jetson, Local PC)이 native ROS2 humble 설치
- Docker 레이어 추가 시 DDS 디스커버리, 디바이스 패스스루, GUI 통과 등에서 환경 차이가 누적되어 디버깅이 어려워짐
- vcstool + bootstrap.sh 조합으로 native 셋업이 충분히 빠름

미래에 멀티-distro 지원이나 클린룸 빌드가 필요해지면 별도 PR로 도입 가능.
