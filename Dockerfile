FROM alpine:3 AS builder

ARG IGLOO_REPO=https://gitlab.xiph.org/xiph/icecast-libigloo.git
ARG IGLOO_REF=v0.9.4
ARG IGLOO_COMMIT=d3a8ca99cc3dc551653fbbc8ce135c02b841447a
ARG ICECAST_REPO=https://gitlab.xiph.org/xiph/icecast-server.git
ARG ICECAST_REF=v2.5.0-rc1
ARG ICECAST_COMMIT=02d5298a994fb86db8f3fd2b23c50f66304a3ab5

RUN apk add --no-cache \
    autoconf \
    automake \
    bash \
    build-base \
    curl-dev \
    git \
    gnutls-dev \
    jansson-dev \
    libogg-dev \
    libtheora-dev \
    libtool \
    libvorbis-dev \
    libxml2-dev \
    libxslt-dev \
    opus-dev \
    pkgconf \
    rhash-dev \
    speex-dev

WORKDIR /usr/src/igloo
RUN git clone --depth 1 --branch "${IGLOO_REF}" --single-branch "${IGLOO_REPO}" . && \
    git checkout "${IGLOO_COMMIT}" && \
    test "$(git rev-parse HEAD)" = "${IGLOO_COMMIT}" && \
    ./autogen.sh && \
    ./configure --prefix=/usr && \
    make -j"$(nproc)" && \
    make install && \
    DESTDIR=/tmp/install make install

WORKDIR /usr/src/icecast
RUN git clone --depth 1 --branch "${ICECAST_REF}" --single-branch --recurse-submodules "${ICECAST_REPO}" . && \
    git checkout "${ICECAST_COMMIT}" && \
    test "$(git rev-parse HEAD)" = "${ICECAST_COMMIT}"

RUN ./autogen.sh && \
    ./configure --prefix=/usr && \
    make -j"$(nproc)" && \
    DESTDIR=/tmp/install make install

FROM alpine:3

RUN apk add --no-cache \
    bash \
    coreutils \
    curl \
    ffmpeg \
    gettext \
    gnutls \
    jansson \
    libogg \
    libtheora \
    libvorbis \
    libxml2 \
    libxslt \
    mailcap \
    opus \
    rhash \
    speex \
    su-exec \
    tini

COPY --from=builder /tmp/install/ /

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
