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

# ─── 결과 ────────────────────────────────────────────────────
echo
echo "Total: $((PASS+FAIL)) / Pass: $PASS / Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
