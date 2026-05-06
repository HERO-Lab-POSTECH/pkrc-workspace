#!/usr/bin/env bash
# pkrc 데이터 트리 helper — bag/run id 생성 및 디렉토리 셋업
# Sourced by scripts/pkrc_record.sh, pkrc_replay.sh, test/test_pkrc.sh
# 환경변수:
#   PKRC_DATA_DIR  새 컨벤션 트리의 root (기본 $HOME/data)

# pkrc_data_dir : 트리 root 경로 echo
pkrc_data_dir() {
  echo "${PKRC_DATA_DIR:-$HOME/data}"
}

# pkrc_make_bag_id <label> : YYYYMMDD_<label>
pkrc_make_bag_id() {
  local label="${1:?label required}"
  printf '%s_%s\n' "$(date +%Y%m%d)" "$label"
}

# pkrc_make_run_id <label> : YYYYMMDD_HHMMSS_<label>
pkrc_make_run_id() {
  local label="${1:?label required}"
  printf '%s_%s\n' "$(date +%Y%m%d_%H%M%S)" "$label"
}

# pkrc_setup_dirs <bag-id> <run-id>
# - $PKRC_DATA_DIR/recordings/<bag-id>/{bag, runs/<run-id>} mkdir -p
# - $PKRC_DATA_DIR/recordings/<bag-id>/runs/latest 심볼릭 링크를 <run-id>로 (재)설정
# - 다음 변수를 export: PKRC_RECORDING_DIR, PKRC_BAG_DIR, PKRC_RUN_DIR
pkrc_setup_dirs() {
  local bag_id="${1:?bag-id required}"
  local run_id="${2:?run-id required}"
  local base; base=$(pkrc_data_dir)
  PKRC_RECORDING_DIR="$base/recordings/$bag_id"
  PKRC_BAG_DIR="$PKRC_RECORDING_DIR/bag"
  PKRC_RUN_DIR="$PKRC_RECORDING_DIR/runs/$run_id"
  export PKRC_RECORDING_DIR PKRC_BAG_DIR PKRC_RUN_DIR
  mkdir -p "$PKRC_BAG_DIR" "$PKRC_RUN_DIR"
  ln -sfn "$run_id" "$PKRC_RECORDING_DIR/runs/latest"
}
