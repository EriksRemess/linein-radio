FROM alpine:3

RUN apk add --no-cache \
    bash \
    coreutils \
    ffmpeg \
    gettext \
    icecast \
    mailcap \
    su-exec \
    tini

ENV ALSA_DEVICE=hw:1,0 \
    CHANNELS=2 \
    ICECAST_ADMIN_PASSWORD=adminpass \
    ICECAST_HOSTNAME=localhost \
    ICECAST_LISTEN_PORT=8000 \
    ICECAST_RELAY_PASSWORD=relaypass \
    ICECAST_SOURCE_PASSWORD=sourcepass \
    SAMPLE_RATE=48000 \
    STREAM_BITRATE=256k \
    STREAM_CODEC=aac \
    STREAM_DESC="Live audio via ALSA → FFmpeg → Icecast" \
    STREAM_GENRE="Live" \
    STREAM_MOUNT=/stream.aac \
    STREAM_NAME="My FFmpeg Stream" \
    STREAM_URL="http://localhost:8000/stream.aac"

COPY icecast.xml.tmpl /etc/icecast/icecast.xml.tmpl
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/entrypoint.sh"]
