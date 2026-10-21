# anki-lite - lightweight Anki + AnkiConnect + noVNC stack on Alpine
#
# Why Alpine: the official Anki Linux tarball is glibc-linked (needs GLIBC_2.35),
# so it cannot run on musl/Alpine. But Alpine ships its own `anki` package
# (community/anki) built against musl with the same PyQt6/QtWebEngine stack.
#
# Process supervision uses s6-overlay (Alpine's native supervisor) instead of
# supervisor (not packaged for Alpine).
FROM alpine:edge

# - Runtime: anki (pulls PyQt6 + QtWebEngine/Chromium), xvfb, openbox, x11vnc,
#   novnc + websockify, fonts.
# - py3-truststore: Anki warns without it ("System certificate store and custom
#   SSL certificates may not work") and AnkiWeb sync is HTTPS-only.
# - No build tools, no -dev headers: nothing is compiled in this image.
RUN apk add --no-cache \
      anki \
      py3-truststore \
      py3-xdg \
      bash \
      xvfb \
      x11vnc \
      openbox \
      novnc \
      websockify \
      font-noto \
      font-noto-arabic \
      font-noto-symbols \
      font-noto-math \
      ca-certificates \
      tzdata \
      s6-overlay \
 && rm -rf /var/cache/apk/*

ENV DISPLAY=":99" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --disable-gpu" \
    ANKI_BASE=/data/anki \
    XDG_RUNTIME_DIR=/tmp/xdg

# The AnkiConnect addon is downloaded here, not committed to the repo, and is
# unpacked into the persistent profile base at boot by anki-launcher. An image
# update therefore never overwrites the user's addon config.
ARG ANKICONNECT_VERSION=23.10.29.0
RUN wget -qO /tmp/AnkiConnect.zip \
      "https://github.com/FooSoft/anki-connect/releases/download/${ANKICONNECT_VERSION}/AnkiConnect.zip" \
 && mkdir -p /usr/local/share/anki-connect/AnkiConnect \
 && unzip -q /tmp/AnkiConnect.zip -d /usr/local/share/anki-connect/AnkiConnect \
 && rm -f /tmp/AnkiConnect.zip

COPY anki-launcher /usr/local/bin/anki-launcher
COPY seed-prefs.py /usr/local/bin/seed-prefs.py
COPY s6-rc.d/ /etc/s6-overlay/s6-rc.d/
COPY user-bundles.d/ /etc/s6-overlay/user-bundles.d/

RUN chmod +x /usr/local/bin/anki-launcher \
 && chmod +x /etc/s6-overlay/s6-rc.d/*/run \
 && mkdir -p /data/anki

ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

EXPOSE 5900 8765 8780

ENTRYPOINT ["/init"]
