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
STREAM_NAME="${STREAM_NAME:-LAN Audio}"
STREAM_DESC="${STREAM_DESC:-Live audio via ALSA → FFmpeg → Icecast}"
STREAM_URL="${STREAM_URL:-}"
STREAM_GENRE="${STREAM_GENRE:-Live}"

case "${STREAM_CODEC}" in
  aac)
    MOUNT="${STREAM_MOUNT:-/stream.aac}"
    ICE_URL="icecast://source:${ICECAST_SOURCE_PASSWORD}@127.0.0.1:${PORT}${MOUNT}"
    ENC_OPTS="-c:a aac -profile:a aac_low -b:a ${BR} -sample_fmt fltp"
    MUX_OPTS="-f adts -content_type audio/aac -muxpreload 0 -muxdelay 0 -reset_timestamps 1"
    SAMPLE_OPTS=""
    ;;
  mp3)
    MOUNT="${STREAM_MOUNT:-/stream.mp3}"
    ICE_URL="icecast://source:${ICECAST_SOURCE_PASSWORD}@127.0.0.1:${PORT}${MOUNT}"
    ENC_OPTS="-c:a libmp3lame -b:a ${BR} -write_xing 0 -sample_fmt s16p"
    MUX_OPTS="-f mp3 -content_type audio/mpeg -muxpreload 0 -muxdelay 0 -reset_timestamps 1"
    SAMPLE_OPTS=""
    ;;
  opus)
    MOUNT="${STREAM_MOUNT:-/stream.ogg}"
    ICE_URL="icecast://source:${ICECAST_SOURCE_PASSWORD}@127.0.0.1:${PORT}${MOUNT}"
    ENC_OPTS="-c:a libopus -b:a ${BR} -application audio -frame_duration 20"
    MUX_OPTS="-f ogg -content_type application/ogg -muxpreload 0 -muxdelay 0 -reset_timestamps 1"
    SAMPLE_OPTS=""
    ;;
  *)
    echo "[entrypoint] ERROR: STREAM_CODEC must be one of aac|mp3|opus (got '${STREAM_CODEC}')" >&2
    exit 1
    ;;
esac

echo "[entrypoint] codec=${STREAM_CODEC}, mount=${MOUNT}, alsa=${ALSA_DEV} → ${ICE_URL}"

COMMON_IN_PRE="-hide_banner -nostats -fflags +genpts -f alsa -thread_queue_size 8192 -use_wallclock_as_timestamps 1 -i ${ALSA_DEV} -ac ${CH} -ar ${SR}"
COMMON_AF="-af aresample=async=1:min_hard_comp=0.100:first_pts=0"

ffmpeg ${COMMON_IN_PRE} ${COMMON_AF} ${SAMPLE_OPTS} \
  ${ENC_OPTS} \
  ${MUX_OPTS} \
  -ice_name "${STREAM_NAME}" \
  -ice_description "${STREAM_DESC}" \
  -ice_url "${STREAM_URL}" \
  -ice_genre "${STREAM_GENRE}" \
  "${ICE_URL}" &
FFMPEG_PID=$!

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
