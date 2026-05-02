#!/usr/bin/env bash
# 클린 환경 → 빌드 완료까지 원샷
# Usage: ./scripts/bootstrap.sh [--skip-rosdep-update] [--build-type Release|Debug]

set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WS_ROOT"

SKIP_ROSDEP_UPDATE=0
BUILD_TYPE="${BUILD_TYPE:-Release}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-rosdep-update) SKIP_ROSDEP_UPDATE=1; shift ;;
        --build-type) BUILD_TYPE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,4p' "$0"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[bootstrap]${NC} $*"; }
warn()  { echo -e "${YELLOW}[bootstrap]${NC} $*"; }
fail()  { echo -e "${RED}[bootstrap]${NC} $*" >&2; exit 1; }

info "Step 1/4: Environment check"
[[ -f /opt/ros/humble/setup.bash ]] || fail "ROS2 humble not found. Install: https://docs.ros.org/en/humble/Installation.html"
command -v vcs        >/dev/null || fail "vcstool not found. Install: sudo apt install python3-vcstool"
command -v colcon     >/dev/null || fail "colcon not found. Install: sudo apt install python3-colcon-common-extensions"
command -v rosdep     >/dev/null || fail "rosdep not found. Install: sudo apt install python3-rosdep"
info "  ROS2 humble, vcstool, colcon, rosdep OK"

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash

info "Step 2/4: Import packages via vcstool"
mkdir -p src
if find src -mindepth 1 -maxdepth 1 -type d | read -r; then
    warn "  src/ already populated. Running 'vcs pull' instead of import."
    vcs pull src
else
    vcs import src < pkrc.repos
fi

info "Step 3/4: Install system dependencies via rosdep"
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    info "  Initializing rosdep (requires sudo)"
    sudo rosdep init || warn "  rosdep already initialized"
fi
if [[ "$SKIP_ROSDEP_UPDATE" -eq 0 ]]; then
    rosdep update --rosdistro humble
fi
rosdep install --from-paths src --ignore-src -y --rosdistro humble

info "Step 4/4: Build workspace (build-type=$BUILD_TYPE)"
colcon build --symlink-install --cmake-args "-DCMAKE_BUILD_TYPE=$BUILD_TYPE"

cat <<EOF

${GREEN}[bootstrap] Complete.${NC}

Next steps:
  source install/setup.bash
  ros2 launch sonar_3d_reconstruction 3d_mapping.launch.py

Daily sync:
  ./scripts/sync.sh

Diagnostic:
  ./scripts/doctor.sh
EOF
