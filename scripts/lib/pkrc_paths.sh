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
