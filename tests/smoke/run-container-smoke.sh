#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE_TAG="${1:-linein-radio:smoke}"
MOCKS_DIR="${ROOT_DIR}/tests/mocks"
WORK_DIR="${ROOT_DIR}/tests/smoke/.tmp"
BASE_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "${expected}" "${file}"; then
    echo "ASSERTION FAILED: ${expected}" >&2
    echo "--- file: ${file} ---" >&2
    cat "${file}" >&2
    exit 1
  fi
}

run_case() {
  local name="$1"
  local expected_exit="$2"
  local expect_args_file="$3"
  shift 3

  local case_dir="${WORK_DIR}/${name}"
  local state_dir="${case_dir}/state"
  local args_file="${case_dir}/ffmpeg-args.txt"
  local log_file="${case_dir}/container.log"

  rm -rf "${case_dir}"
  mkdir -p "${state_dir}"

  set +e
  docker run --rm \
    -e PATH="/mocks:${BASE_PATH}" \
    -e ICECAST_SOURCE_PASSWORD=test-source-pass \
    -e ICECAST_ADMIN_PASSWORD=test-admin-pass \
    -e MOCK_ICECAST_READY_FILE=/state/icecast-ready \
    -e MOCK_FFMPEG_ARGS_FILE=/artifacts/ffmpeg-args.txt \
    -v "${MOCKS_DIR}:/mocks:ro" \
    -v "${case_dir}:/artifacts" \
    -v "${state_dir}:/state" \
    "$@" \
    "${IMAGE_TAG}" >"${log_file}" 2>&1
  status=$?
  set -e

  if [ "${status}" -ne "${expected_exit}" ]; then
    echo "ASSERTION FAILED: case ${name} exit code ${status} (expected ${expected_exit})" >&2
    echo "--- case log: ${log_file} ---" >&2
    cat "${log_file}" >&2
    exit 1
  fi

  if [ "${expect_args_file}" = "yes" ] && [ ! -s "${args_file}" ]; then
    echo "ASSERTION FAILED: ffmpeg args file missing for case ${name}" >&2
    echo "--- case log: ${log_file} ---" >&2
    cat "${log_file}" >&2
    exit 1
  fi

  if [ "${expect_args_file}" = "no" ] && [ -s "${args_file}" ]; then
    echo "ASSERTION FAILED: ffmpeg args file should not exist for case ${name}" >&2
    echo "--- file: ${args_file} ---" >&2
    cat "${args_file}" >&2
    exit 1
  fi

  case "${name}" in
    single)
      assert_contains "${args_file}" "-f adts"
      assert_contains "${args_file}" "-b:a 192k"
      assert_contains "${args_file}" "icecast://source:test-source-pass@127.0.0.1:8000/single.aac"
      ;;
    multi)
      assert_contains "${args_file}" "-c:a aac"
      assert_contains "${args_file}" "-c:a libmp3lame"
      assert_contains "${args_file}" "icecast://source:test-source-pass@127.0.0.1:8000/multi.aac"
      assert_contains "${args_file}" "icecast://source:test-source-pass@127.0.0.1:8000/multi.mp3"
      ;;
    ffmpeg_nonzero_exit)
      assert_contains "${args_file}" "icecast://source:test-source-pass@127.0.0.1:8000/fail.aac"
      ;;
    icecast_early_exit)
      assert_contains "${log_file}" "ERROR: icecast exited before becoming ready"
      ;;
  esac
}

mkdir -p "${WORK_DIR}"

run_case single 0 yes \
  -e STREAM_CODEC=aac \
  -e STREAM_CODECS= \
  -e STREAM_MOUNT=/single.aac \
  -e STREAM_BITRATE=192k

run_case multi 0 yes \
  -e STREAM_CODECS=aac,mp3 \
  -e STREAM_MOUNT_AAC=/multi.aac \
  -e STREAM_MOUNT_MP3=/multi.mp3 \
  -e STREAM_BITRATE_AAC=192k \
  -e STREAM_BITRATE_MP3=160k

run_case ffmpeg_nonzero_exit 17 yes \
  -e STREAM_CODEC=aac \
  -e STREAM_CODECS= \
  -e STREAM_MOUNT=/fail.aac \
  -e MOCK_FFMPEG_EXIT_CODE=17 \
  -e MOCK_FFMPEG_SLEEP_SECONDS=0.05

run_case icecast_early_exit 1 no \
  -e MOCK_ICECAST_EXIT_IMMEDIATELY=1

echo "Smoke tests passed"
