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

# ─── Task 3: pkrc_record.sh smoke test ──────────────────────
echo "== pkrc_record.sh smoke =="

# Mock ros2: PATH 앞에 mock dir 추가, 호출된 인자만 stdout으로 echo
MOCK_BIN=$(mktemp -d -t pkrc_mockbin_XXXXXX)
trap 'rm -rf "$TEST_ROOT" "$MOCK_BIN"' EXIT
cat > "$MOCK_BIN/ros2" <<'MOCK'
#!/usr/bin/env bash
echo "MOCK_ROS2: $*"
MOCK
chmod +x "$MOCK_BIN/ros2"

out=$(PATH="$MOCK_BIN:$PATH" "$WS_ROOT/scripts/pkrc_record.sh" beta_test 2>&1)
today=$(date +%Y%m%d)

# 출력 검증
echo "$out" | grep -q "📁 Recording:.*${today}_beta_test" \
  && pass "record stdout: Recording 경로" || fail "record stdout: Recording 경로 — got: $out"
echo "$out" | grep -q "👉" \
  && pass "record stdout: export PKRC_MAP_DIR 안내" || fail "record stdout: export 안내 누락"
echo "$out" | grep -q "export PKRC_MAP_DIR=" \
  && pass "record stdout: export PKRC_MAP_DIR= 라인" || fail "export 라인 누락"
echo "$out" | grep -q "MOCK_ROS2: bag record" \
  && pass "record가 ros2 bag record 호출" || fail "ros2 bag record 호출 누락 — out: $out"

# 디렉토리 검증
[[ -d "$TEST_ROOT/recordings/${today}_beta_test/bag" ]] \
  && pass "record가 bag 디렉토리 생성" || fail "bag 디렉토리 미생성"
[[ -L "$TEST_ROOT/recordings/${today}_beta_test/runs/latest" ]] \
  && pass "record가 latest 심볼릭 링크 생성" || fail "latest 심볼릭 링크 없음"

# 인자 누락 시 사용법 출력 + non-zero exit
PATH="$MOCK_BIN:$PATH" "$WS_ROOT/scripts/pkrc_record.sh" >/dev/null 2>&1
rc=$?
[[ $rc -ne 0 ]] && pass "label 인자 없으면 exit non-zero (rc=$rc)" || fail "label 없는데 0으로 exit"

# ─── Task 4: pkrc_replay.sh smoke test ──────────────────────
echo "== pkrc_replay.sh smoke =="

# Task 3에서 만든 ${today}_beta_test recording 재사용
out=$(PATH="$MOCK_BIN:$PATH" "$WS_ROOT/scripts/pkrc_replay.sh" \
        "${today}_beta_test" --label voxel0p3 2>&1)

echo "$out" | grep -q "📁 New run:.*_voxel0p3" \
  && pass "replay stdout: New run 경로 + label" || fail "replay stdout 형식 — got: $out"
echo "$out" | grep -q "export PKRC_MAP_DIR=" \
  && pass "replay stdout: export PKRC_MAP_DIR 라인" || fail "replay export 라인 누락"
echo "$out" | grep -q "MOCK_ROS2: bag play.*${today}_beta_test/bag" \
  && pass "replay가 ros2 bag play <bag_dir> 호출" || fail "ros2 bag play 호출 누락 — out: $out"

# latest 심볼릭 링크가 새 run으로 갱신
new_latest=$(readlink "$TEST_ROOT/recordings/${today}_beta_test/runs/latest")
[[ "$new_latest" == *_voxel0p3 ]] \
  && pass "replay가 latest 심볼릭 링크 갱신" || fail "latest 갱신 안 됨 — got: $new_latest"

# 존재하지 않는 bag-id → non-zero exit
PATH="$MOCK_BIN:$PATH" "$WS_ROOT/scripts/pkrc_replay.sh" no_such_bag >/dev/null 2>&1
rc=$?
[[ $rc -ne 0 ]] && pass "존재하지 않는 bag-id → non-zero exit (rc=$rc)" || fail "존재 안 하는 bag-id인데 0으로 exit"

# label 없이 실행 시 기본 라벨 'replay' 사용 — New run 라인의 끝이 _replay여야 함
out=$(PATH="$MOCK_BIN:$PATH" "$WS_ROOT/scripts/pkrc_replay.sh" "${today}_beta_test" 2>&1)
echo "$out" | grep -qE "New run:.*_replay$" \
  && pass "label 미지정 시 기본값 'replay' 적용" || fail "기본 label 적용 안 됨 — got: $out"

# ─── 결과 ────────────────────────────────────────────────────
echo
echo "Total: $((PASS+FAIL)) / Pass: $PASS / Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
