FROM ubuntu:latest

# Buildx provides TARGETARCH (amd64 / arm64); Anki's release assets use x86_64 / aarch64
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Base deps for Anki's Qt GUI + a lightweight headless X stack:
#   Xvfb (virtual display) + openbox (WM) + x11vnc (VNC server) + noVNC (browser client)
RUN apt-get update && apt-get install -y --no-install-recommends \
      locales ca-certificates wget zstd xz-utils tar unzip xdg-utils \
      libxcb-xinerama0 libxcb-cursor0 libnss3 libxcb-icccm4 libxcb-keysyms1 \
      libegl-dev libsnappy-dev libopus-dev libxdamage-dev libwebp-dev \
      libasound-dev libminizip-dev liblcms2-dev \
      libgbm1 libxkbcommon-x11-0 libgl1 libegl1 libxcomposite1 libxdamage1 \
      libxrandr2 libxfixes3 libxcursor1 libxtst6 libxi6 libxkbfile1 \
      libxcb-shape0 libxcb-shm0 libxcb-render-util0 \
      fonts-dejavu-core \
      xvfb x11vnc x11-utils xdotool openbox novnc python3-websockify supervisor \
    && rm -rf /var/lib/apt/lists/*

# Install Anki from the official release tarball (auto-arch matching via ARG)
RUN case "${TARGETARCH}" in \
      amd64) ANKI_ARCH=x86_64 ;; \
      arm64) ANKI_ARCH=aarch64 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && cd /tmp \
 && wget -q "https://github.com/ankitects/anki/releases/download/26.09.3/anki-26.09.3-linux-${ANKI_ARCH}.tar.zst" \
 && tar xaf anki-*.tar.zst \
 && cd anki-*.tar \
 && ./install.sh \
 && rm -rf /tmp/anki-*

# Bundle the AnkiConnect plugin; a startup script copies it into the
# persistent profile base (so we get the while keeping user config).
ARG ANKICONNECT_VERSION=23.10.29.0
RUN wget -qO /tmp/AnkiConnect.zip \
      "https://github.com/FooSoft/anki-connect/releases/download/${ANKICONNECT_VERSION}/AnkiConnect.zip" \
 && mkdir -p /usr/local/share/anki-connect/AnkiConnect \
 && unzip -q /tmp/AnkiConnect.zip -d /usr/local/share/anki-connect/AnkiConnect \
 && rm -f /tmp/AnkiConnect.zip \
 && printf '{\n  "webBindAddress": "0.0.0.0",\n  "webBindPort": 8765\n}\n' \
      > /usr/local/share/anki-connect/AnkiConnect/config.json

RUN printf 'export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:-} --no-sandbox --disable-gpu"\n' > /usr/local/bin/anki-env && \
    chmod +x /usr/local/bin/anki-env

COPY anki-launcher /usr/local/bin/anki-launcher
COPY seed-prefs.py /usr/local/bin/seed-prefs.py
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chmod +x /usr/local/bin/anki-launcher

EXPOSE 5900 8765 8780

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
