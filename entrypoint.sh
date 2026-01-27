#!/usr/bin/env bash
set -euo pipefail

envsubst < /etc/icecast/icecast.xml.tmpl > /etc/icecast/icecast.xml
chown icecast:icecast /etc/icecast/icecast.xml

echo "[entrypoint] starting icecast..."
su-exec icecast:icecast icecast -c /etc/icecast/icecast.xml &
ICECAST_PID=$!

# Wait for Icecast
PORT="${ICECAST_LISTEN_PORT:-8000}"
echo "[entrypoint] waiting for icecast on port ${PORT}..."
for i in {1..60}; do
  if nc -z 127.0.0.1 "${PORT}" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

ALSA_DEV="${ALSA_DEVICE:-hw:1,0}"
SR="${SAMPLE_RATE:-48000}"
CH="${CHANNELS:-2}"
BR="${STREAM_BITRATE:-320k}"
STREAM_CODEC="${STREAM_CODEC:-aac}"
STREAM_CODECS="${STREAM_CODECS:-}"
STREAM_NAME="${STREAM_NAME:-LAN Audio}"
STREAM_DESC="${STREAM_DESC:-Live audio via ALSA → FFmpeg → Icecast}"
STREAM_URL="${STREAM_URL:-}"
STREAM_GENRE="${STREAM_GENRE:-Live}"

if [ -z "${STREAM_CODECS}" ]; then
  STREAM_CODECS="${STREAM_CODEC}"
fi

IFS=',' read -ra CODEC_LIST <<< "${STREAM_CODECS}"
CODEC_COUNT=0
declare -A SEEN_CODECS=()

get_override() {
  local base="$1"
  local fallback="$2"
  local codec="$3"
  local var="${base}_${codec^^}"
  local val="${!var:-}"
  if [ -n "${val}" ]; then
    printf '%s' "${val}"
  else
    printf '%s' "${fallback}"
  fi
}

get_mount() {
  local codec="$1"
  local fallback="$2"
  local var="STREAM_MOUNT_${codec^^}"
  local val="${!var:-}"
  if [ -n "${val}" ]; then
    printf '%s' "${val}"
    return
  fi
  if [ "${CODEC_COUNT}" -eq 1 ] && [ -n "${STREAM_MOUNT:-}" ]; then
    printf '%s' "${STREAM_MOUNT}"
    return
  fi
  printf '%s' "${fallback}"
}

get_bitrate() {
  local codec="$1"
  local var="STREAM_BITRATE_${codec^^}"
  local val="${!var:-}"
  if [ -n "${val}" ]; then
    printf '%s' "${val}"
  else
    printf '%s' "${BR}"
  fi
}

OUTPUTS_DESC=()
FF_OUTPUTS=()
MOUNTS=()

for raw_codec in "${CODEC_LIST[@]}"; do
  codec="${raw_codec//[[:space:]]/}"
  codec="${codec,,}"
  if [ -z "${codec}" ]; then
    continue
  fi
  if [ -n "${SEEN_CODECS[${codec}]:-}" ]; then
    echo "[entrypoint] ERROR: duplicate codec '${codec}' in STREAM_CODECS" >&2
    exit 1
  fi
  SEEN_CODECS["${codec}"]=1
  CODEC_COUNT=$((CODEC_COUNT + 1))
done

if [ "${CODEC_COUNT}" -eq 0 ]; then
  echo "[entrypoint] ERROR: STREAM_CODECS is empty" >&2
  exit 1
fi

for raw_codec in "${CODEC_LIST[@]}"; do
  codec="${raw_codec//[[:space:]]/}"
  codec="${codec,,}"
  if [ -z "${codec}" ]; then
    continue
  fi

  case "${codec}" in
    aac)
      default_mount="/stream.aac"
      ;;
    mp3)
      default_mount="/stream.mp3"
      ;;
    opus)
      default_mount="/stream.ogg"
      ;;
    *)
      echo "[entrypoint] ERROR: STREAM_CODECS must be a comma-separated list of aac|mp3|opus (got '${codec}')" >&2
      exit 1
      ;;
  esac

  MOUNT="$(get_mount "${codec}" "${default_mount}")"
  BR_CODEC="$(get_bitrate "${codec}")"
  NAME_CODEC="$(get_override STREAM_NAME "${STREAM_NAME}" "${codec}")"
  DESC_CODEC="$(get_override STREAM_DESC "${STREAM_DESC}" "${codec}")"
  URL_CODEC="$(get_override STREAM_URL "${STREAM_URL}" "${codec}")"
  GENRE_CODEC="$(get_override STREAM_GENRE "${STREAM_GENRE}" "${codec}")"

  ICE_URL="icecast://source:${ICECAST_SOURCE_PASSWORD}@127.0.0.1:${PORT}${MOUNT}"
  OUTPUTS_DESC+=("codec=${codec}, mount=${MOUNT}, alsa=${ALSA_DEV} → ${ICE_URL}")
  MOUNTS+=("${MOUNT}")

  case "${codec}" in
    aac)
      ENC_OPTS=(-c:a aac -profile:a aac_low -b:a "${BR_CODEC}" -sample_fmt fltp)
      MUX_OPTS=(-f adts -content_type audio/aac -muxpreload 0 -muxdelay 0 -reset_timestamps 1 -metadata title="${STREAM_NAME}")
      ;;
    mp3)
      ENC_OPTS=(-c:a libmp3lame -b:a "${BR_CODEC}" -write_xing 0 -sample_fmt s16p)
      MUX_OPTS=(-f mp3 -content_type audio/mpeg -muxpreload 0 -muxdelay 0 -reset_timestamps 1 -id3v2_version 3 -write_id3v2 1 -metadata title="${STREAM_NAME}")
      ;;
    opus)
      ENC_OPTS=(-c:a libopus -b:a "${BR_CODEC}" -application audio -frame_duration 20)
      MUX_OPTS=(-f ogg -content_type application/ogg -muxpreload 0 -muxdelay 0 -reset_timestamps 1 -metadata title="${STREAM_NAME}")
      ;;
  esac

  FF_OUTPUTS+=(
    "${ENC_OPTS[@]}"
    "${MUX_OPTS[@]}"
    -ice_name "${NAME_CODEC}"
    -ice_description "${DESC_CODEC}"
    -ice_url "${URL_CODEC}"
    -ice_genre "${GENRE_CODEC}"
    "${ICE_URL}"
  )
done

echo "[entrypoint] outputs: ${OUTPUTS_DESC[*]}"

COMMON_IN_PRE=(-hide_banner -nostats -fflags +genpts -f alsa -thread_queue_size 8192 -use_wallclock_as_timestamps 1 -i "${ALSA_DEV}" -ac "${CH}" -ar "${SR}")
# COMMON_AF="-af aresample=async=1:first_pts=0,arnndn=m=/models/std.rnnn:mix=0.85,lowpass=f=17000"
COMMON_AF=(-af "aresample=async=1:min_hard_comp=0.100:first_pts=0")

ffmpeg "${COMMON_IN_PRE[@]}" "${COMMON_AF[@]}" \
  "${FF_OUTPUTS[@]}" &
FFMPEG_PID=$!

set_mount_title() {
  local mount="$1"
  local title="$2"
  local admin_pass="${ICECAST_ADMIN_PASSWORD:-}"
  if [ -z "${admin_pass}" ]; then
    echo "[entrypoint] WARN: ICECAST_ADMIN_PASSWORD not set; skipping metadata update for ${mount}" >&2
    return 0
  fi
  for i in {1..20}; do
    if curl -fsS -u "admin:${admin_pass}" "http://127.0.0.1:${PORT}/admin/metadata" \
      --data-urlencode "mount=${mount}" \
      --data-urlencode "mode=updinfo" \
      --data-urlencode "song=${title}" >/dev/null; then
      echo "[entrypoint] set mount metadata: ${mount} -> ${title}"
      return 0
    fi
    sleep 0.5
  done
  echo "[entrypoint] WARN: failed to set metadata for ${mount}" >&2
  return 1
}

for i in "${!MOUNTS[@]}"; do
  set_mount_title "${MOUNTS[$i]}" "${STREAM_NAME}" || true
done

term_handler() {
  echo "[entrypoint] stopping..."
  kill -TERM "${FFMPEG_PID}" 2>/dev/null || true
  kill -TERM "${ICECAST_PID}" 2>/dev/null || true
  wait "${FFMPEG_PID}" 2>/dev/null || true
  wait "${ICECAST_PID}" 2>/dev/null || true
}
trap term_handler SIGTERM SIGINT

wait -n || true
term_handler
