#!/usr/bin/env bash
# 모든 패키지 일괄 fetch+pull, 변경분만 재빌드
# Usage: ./scripts/sync.sh [--no-build]

set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WS_ROOT"

NO_BUILD=0
[[ "${1:-}" == "--no-build" ]] && NO_BUILD=1

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[sync]${NC} $*"; }
warn() { echo -e "${YELLOW}[sync]${NC} $*"; }

info "Pulling all packages"
vcs pull src

info "Status check"
vcs status src

if [[ "$NO_BUILD" -eq 1 ]]; then
    warn "Skipping build (--no-build)"
    exit 0
fi

# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
info "Rebuilding"
colcon build --symlink-install
info "Done. Run: source install/setup.bash"
