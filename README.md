# linein-radio

Dockerized Icecast + FFmpeg pipeline for streaming ALSA audio to Icecast.

## Features
- Stream audio from an ALSA device to Icecast.
- Supports multiple codecs/mounts from one FFmpeg process (AAC, MP3, Opus).
- Optional Icecast metadata (icy-title) set from `STREAM_NAME`.

## Quick start
1) Build the image (or use any tag and update `compose.yml`):
```
docker build -t ghcr.io/eriksremess/linein-radio:latest .
```

2) Or pull the prebuilt image:
```
docker pull ghcr.io/eriksremess/linein-radio:latest
```

3) Update `compose.yml` placeholders (`<PORT>`, `<ICECAST_LISTEN_PORT>`, `<HOST-IP-or-HOSTNAME>`) as needed.

4) Start the service:
```
docker compose up -d
```

5) Open in a client (use the host port from the `ports:` mapping):
- MP3: `http://<HOST-IP-or-HOSTNAME>:<PORT>/stream.mp3`
- AAC: `http://<HOST-IP-or-HOSTNAME>:<PORT>/stream.aac`
- Opus: `http://<HOST-IP-or-HOSTNAME>:<PORT>/stream.ogg`

## Configuration
All settings are environment variables. The defaults are in `Dockerfile` and can be overridden in
`compose.yml`.

### Port configuration
Icecast listens on `ICECAST_LISTEN_PORT` (default `8000`). Expose the same port in your compose file:
```
ports:
  - "<PORT>:<ICECAST_LISTEN_PORT>"
```

### Single-stream (backwards compatible)
If `STREAM_CODECS` is unset, the service uses `STREAM_CODEC` and the single-stream variables.

Common single-stream variables:
- `STREAM_CODEC` (aac|mp3|opus)
- `STREAM_MOUNT` (e.g., `/stream.mp3`)
- `STREAM_BITRATE` (e.g., `192k`)
- `STREAM_NAME`, `STREAM_DESC`, `STREAM_URL`, `STREAM_GENRE`

### Multi-stream
Set `STREAM_CODECS` to a comma-separated list (e.g., `aac,mp3`). Each codec can have overrides:
- `STREAM_MOUNT_AAC`, `STREAM_MOUNT_MP3`, `STREAM_MOUNT_OPUS`
- `STREAM_BITRATE_AAC`, `STREAM_BITRATE_MP3`, `STREAM_BITRATE_OPUS`
- `STREAM_NAME_AAC`, `STREAM_NAME_MP3`, `STREAM_NAME_OPUS` (optional; used for Icecast stream name)
- `STREAM_DESC_AAC`, `STREAM_DESC_MP3`, `STREAM_DESC_OPUS`
- `STREAM_URL_AAC`, `STREAM_URL_MP3`, `STREAM_URL_OPUS`
- `STREAM_GENRE_AAC`, `STREAM_GENRE_MP3`, `STREAM_GENRE_OPUS`

Title metadata (icy-title / tags) is always set to `STREAM_NAME` for all mounts.

## Audio input
Set `ALSA_DEVICE` to match your input device (e.g., `hw:1,0`).
You can list devices with:
```
arecord -l
```

## Troubleshooting
- Verify Icecast status: `http://<HOST-IP-or-HOSTNAME>:<PORT>/`
- Check mount headers:
```
curl -I http://<HOST-IP-or-HOSTNAME>:<PORT>/stream.mp3
```
- Test playback with mpv:
```
mpv http://<HOST-IP-or-HOSTNAME>:<PORT>/stream.mp3
```
- Confirm the container can access the ALSA device and that `/dev/snd` is mapped.

## Files
- `entrypoint.sh`: Builds and runs FFmpeg + Icecast.
- `icecast.xml.tmpl`: Icecast config template.
- `compose.yml`: Example service configuration.
