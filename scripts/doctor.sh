#!/usr/bin/env bash
# 환경/워크스페이스 자가진단
# Usage: ./scripts/doctor.sh

set -uo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WS_ROOT"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "[${GREEN}OK${NC}]   $*"; }
warn() { echo -e "[${YELLOW}WARN${NC}] $*"; }
fail() { echo -e "[${RED}FAIL${NC}] $*"; }

echo "== Environment =="
if [[ -f /opt/ros/humble/setup.bash ]]; then
    ok "ROS2 distro: humble"
else
    fail "ROS2 humble not found. Install: https://docs.ros.org/en/humble/Installation.html"
fi
if command -v python3 >/dev/null; then
    ok "Python: $(python3 --version | awk '{print $2}')"
else
    fail "python3 not found"
fi
for cmd in vcs colcon rosdep; do
    if command -v "$cmd" >/dev/null; then
        ok "$cmd installed"
    else
        fail "$cmd not found"
    fi
done
case "${LANG:-}" in
    en_US.UTF-8|C.UTF-8) ok "LANG=$LANG" ;;
    "") warn "LANG unset — colcon recommends en_US.UTF-8" ;;
    *) warn "LANG=$LANG — colcon recommends en_US.UTF-8" ;;
esac

echo
echo "== Workspace =="
if [[ -f pkrc.repos ]]; then
    ok "pkrc.repos found"
    expected_pkgs=$(grep -c '^  [a-z]' pkrc.repos 2>/dev/null || echo 0)
    if [[ -d src ]]; then
        actual_pkgs=$(find src -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        if [[ "$actual_pkgs" -eq "$expected_pkgs" ]]; then
            ok "src/ has $actual_pkgs/$expected_pkgs expected packages"
        else
            warn "src/ has $actual_pkgs packages, expected $expected_pkgs (run vcs import or sync.sh)"
        fi

        for pkg_dir in src/*/; do
            pkg=$(basename "$pkg_dir")
            if [[ -d "$pkg_dir/.git" ]]; then
                branch=$(git -C "$pkg_dir" branch --show-current)
                dirty=$(git -C "$pkg_dir" status --porcelain | wc -l)
                ahead_behind=$(git -C "$pkg_dir" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || echo "? ?")
                if [[ "$dirty" -eq 0 ]]; then
                    ok "src/$pkg (branch=$branch, ahead/behind=$ahead_behind)"
                else
                    warn "src/$pkg has $dirty uncommitted changes"
                fi
            fi
        done
    else
        warn "src/ does not exist — run ./scripts/bootstrap.sh"
    fi
else
    fail "pkrc.repos not found — are you in the workspace root?"
fi

echo
echo "== Build artifacts =="
if [[ -d install ]]; then
    last_build=$(stat -c %Y install 2>/dev/null || echo 0)
    if [[ "$last_build" -gt 0 ]]; then
        age_hours=$(( ($(date +%s) - last_build) / 3600 ))
        ok "install/ exists (last modified ${age_hours}h ago)"
    fi
else
    warn "install/ not found — run ./scripts/bootstrap.sh"
fi

echo
echo "== Disk =="
free_gb=$(df -BG --output=avail . | tail -1 | tr -dc '0-9')
if [[ "$free_gb" -ge 5 ]]; then
    ok "Free disk: ${free_gb}GB"
else
    warn "Low disk space: ${free_gb}GB free"
fi
