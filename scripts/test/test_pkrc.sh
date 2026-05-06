#!/usr/bin/env bash
# pkrc helper 스크립트 단위 테스트 + wrapper smoke 테스트
# Usage: ./scripts/test/test_pkrc.sh

set -uo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$WS_ROOT/scripts/lib/pkrc_paths.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "[${GREEN}PASS${NC}] $*"; PASS=$((PASS+1)); }
fail() { echo -e "[${RED}FAIL${NC}] $*"; FAIL=$((FAIL+1)); }
assert_eq() { [[ "$1" == "$2" ]] && pass "$3" || fail "$3 — expected '$2' got '$1'"; }

# Isolated test root
TEST_ROOT=$(mktemp -d -t pkrc_test_XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT
export PKRC_DATA_DIR="$TEST_ROOT"

# shellcheck source=../lib/pkrc_paths.sh
source "$LIB"

# ─── Task 1: id 생성 ─────────────────────────────────────────
echo "== id 생성 =="

today=$(date +%Y%m%d)
assert_eq "$(pkrc_make_bag_id pier_test)" "${today}_pier_test" "bag-id = YYYYMMDD_<label>"

run_id=$(pkrc_make_run_id live)
[[ "$run_id" =~ ^[0-9]{8}_[0-9]{6}_live$ ]] \
  && pass "run-id 포맷 YYYYMMDD_HHMMSS_<label>" \
  || fail "run-id 포맷 — got '$run_id'"

# data dir 기본값 (env unset) — capture in subshell, assert in parent
default_data_dir=$(unset PKRC_DATA_DIR; pkrc_data_dir)
assert_eq "$default_data_dir" "$HOME/data" "PKRC_DATA_DIR unset → \$HOME/data"
assert_eq "$(pkrc_data_dir)" "$TEST_ROOT" "PKRC_DATA_DIR set → 그 값"

# ─── Task 2: 디렉토리 셋업 ──────────────────────────────────
echo "== 디렉토리 셋업 =="

# 첫 호출
pkrc_setup_dirs "20260506_alpha" "20260506_142233_live"
[[ -d "$TEST_ROOT/recordings/20260506_alpha/bag" ]] \
  && pass "bag/ 디렉토리 생성" || fail "bag/ 디렉토리 미생성"
[[ -d "$TEST_ROOT/recordings/20260506_alpha/runs/20260506_142233_live" ]] \
  && pass "runs/<run-id>/ 디렉토리 생성" || fail "runs/<run-id>/ 미생성"
[[ -L "$TEST_ROOT/recordings/20260506_alpha/runs/latest" ]] \
  && pass "runs/latest 심볼릭 링크 존재" || fail "latest 심볼릭 링크 없음"
assert_eq "$(readlink "$TEST_ROOT/recordings/20260506_alpha/runs/latest")" \
          "20260506_142233_live" "latest → 첫 run id"

assert_eq "${PKRC_RECORDING_DIR}" \
          "$TEST_ROOT/recordings/20260506_alpha" "PKRC_RECORDING_DIR 변수 set"
assert_eq "${PKRC_BAG_DIR}" \
          "$TEST_ROOT/recordings/20260506_alpha/bag" "PKRC_BAG_DIR 변수 set"
assert_eq "${PKRC_RUN_DIR}" \
          "$TEST_ROOT/recordings/20260506_alpha/runs/20260506_142233_live" "PKRC_RUN_DIR 변수 set"

# 두 번째 호출 (같은 bag-id, 새 run) → latest 갱신
pkrc_setup_dirs "20260506_alpha" "20260507_093011_replay_voxel0p2"
assert_eq "$(readlink "$TEST_ROOT/recordings/20260506_alpha/runs/latest")" \
          "20260507_093011_replay_voxel0p2" "latest → 새 run으로 재지정"
[[ -d "$TEST_ROOT/recordings/20260506_alpha/runs/20260506_142233_live" ]] \
  && pass "이전 run 디렉토리 보존됨" || fail "이전 run 디렉토리 사라짐"

# 멱등성: 같은 인자 두 번 호출 시 에러 없음
pkrc_setup_dirs "20260506_alpha" "20260507_093011_replay_voxel0p2" \
  && pass "멱등 호출 OK" || fail "멱등 호출 실패"

# ─── 결과 ────────────────────────────────────────────────────
echo
echo "Total: $((PASS+FAIL)) / Pass: $PASS / Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
