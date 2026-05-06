#!/usr/bin/env bash
# 라이브 실험용 — recording 디렉토리 + 첫 run 디렉토리 생성, ros2 bag record 실행
# Usage: ./scripts/pkrc_record.sh <label> [-- <ros2 bag record extra args>]
#
# 동작:
#   1. $PKRC_DATA_DIR/recordings/YYYYMMDD_<label>/{bag, runs/YYYYMMDD_HHMMSS_live}/ 생성
#   2. PKRC_MAP_DIR 후보값을 stdout으로 출력 (사용자가 다른 터미널에서 export 후 launch)
#   3. ros2 bag record 실행 (Ctrl-C로 종료)
#
# Launch는 호출하지 않음. SLAM 실행은 사용자가 별도 터미널에서:
#   export PKRC_MAP_DIR=<위에서 안내된 경로>
#   ros2 launch fast_lio mapping.launch.py

set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/pkrc_paths.sh
source "$WS_ROOT/scripts/lib/pkrc_paths.sh"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit 1
}

[[ $# -ge 1 ]] || usage
label="$1"; shift
[[ "${1:-}" == "--" ]] && shift

bag_id=$(pkrc_make_bag_id "$label")
run_id=$(pkrc_make_run_id "live")
pkrc_setup_dirs "$bag_id" "$run_id"

cat <<EOF
📁 Recording:  $PKRC_RECORDING_DIR
📁 First run:  $PKRC_RUN_DIR
👉 다른 터미널에서 SLAM 실행 시 아래 export 후 launch:
    export PKRC_MAP_DIR=$PKRC_RUN_DIR
▶ ros2 bag record 시작...
EOF

exec ros2 bag record -o "$PKRC_BAG_DIR" "$@"
