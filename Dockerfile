FROM alpine:3.20

RUN apk add --no-cache \
    icecast \
    mailcap \
    ffmpeg \
    bash \
    tini \
    su-exec \
    coreutils \
    gettext

ENV ICECAST_SOURCE_PASSWORD=sourcepass \
    ICECAST_ADMIN_PASSWORD=adminpass \
    ICECAST_RELAY_PASSWORD=relaypass \
    ICECAST_LISTEN_PORT=8000 \
    ICECAST_HOSTNAME=localhost \
    STREAM_MOUNT=/stream.mp3 \
    STREAM_NAME="My FFmpeg Stream" \
    STREAM_DESC="Live audio via ALSA → FFmpeg → Icecast" \
    STREAM_URL="http://localhost:8000/stream.mp3" \
    STREAM_GENRE="Live" \
    STREAM_BITRATE=256k \
    SAMPLE_RATE=48000 \
    CHANNELS=2 \
    ALSA_DEVICE=hw:Generic_1,0

COPY icecast.xml.tmpl /etc/icecast/icecast.xml.tmpl
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/entrypoint.sh"]
