#!/usr/bin/env bash
# 오프라인 replay용 — 기존 recording에 새 run 디렉토리 생성, ros2 bag play 실행
# Usage: ./scripts/pkrc_replay.sh <bag-id> [--label <label>] [-- <ros2 bag play extra args>]
#
# 동작:
#   1. $PKRC_DATA_DIR/recordings/<bag-id>/runs/YYYYMMDD_HHMMSS_<label>/ 생성 (label 기본값: 'replay')
#   2. PKRC_MAP_DIR 후보값을 stdout으로 출력
#   3. ros2 bag play <bag_dir> 실행
#
# Launch는 호출하지 않음. SLAM 실행은 사용자가 별도 터미널에서:
#   export PKRC_MAP_DIR=<위에서 안내된 경로>
#   ros2 launch fast_lio mapping.launch.py use_sim_time:=true

set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/pkrc_paths.sh
source "$WS_ROOT/scripts/lib/pkrc_paths.sh"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \?//'
  exit 1
}

[[ $# -ge 1 ]] || usage
bag_id="$1"; shift

# --label 파싱
label="replay"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) label="${2:?--label needs a value}"; shift 2 ;;
    --) shift; break ;;
    -h|--help) usage ;;
    *) break ;;
  esac
done

# bag-id 존재 확인
recording_dir="$(pkrc_data_dir)/recordings/$bag_id"
bag_dir="$recording_dir/bag"
if [[ ! -d "$bag_dir" ]]; then
  echo "Error: bag-id '$bag_id' 의 bag 디렉토리가 없음: $bag_dir" >&2
  echo "       사용 가능한 recordings:" >&2
  ls -1 "$(pkrc_data_dir)/recordings" 2>/dev/null | sed 's/^/         /' >&2 || true
  exit 1
fi

run_id=$(pkrc_make_run_id "$label")
pkrc_setup_dirs "$bag_id" "$run_id"

cat <<EOF
📁 New run: $PKRC_RUN_DIR
👉 다른 터미널에서 SLAM 실행 시 아래 export 후 launch:
    export PKRC_MAP_DIR=$PKRC_RUN_DIR
▶ ros2 bag play 시작...
EOF

exec ros2 bag play "$PKRC_BAG_DIR" "$@"
