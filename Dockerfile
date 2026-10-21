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
      ca-certificates \
      tzdata \
      s6-overlay \
 && rm -rf /var/cache/apk/*

# Optional extra fonts, disabled by default.
#
# Most deployments only use the AnkiConnect API and the MCP server, and never
# render a card, so the language fonts are pure overhead (the CJK set alone is
# 88 MB). Enable only what the collection actually needs, e.g. in
# compose.yaml:
#
#     build:
#       args:
#         FONT_ARABIC: "true"
#         FONT_CJK: "true"
#
# Each flag adds one Alpine font package:
#   FONT_ARABIC   font-noto-arabic      18 MB  Arabic, Persian, Urdu
#   FONT_CJK      font-noto-cjk         88 MB  Chinese, Japanese, Korean
#   FONT_HEBREW   font-noto-hebrew       2 MB  Hebrew
#   FONT_THAI     font-noto-thai         5 MB  Thai
#   FONT_DEVANAGARI font-noto-devanagari 26 MB  Hindi, Nepali, Sanskrit
#   FONT_BENGALI  font-noto-bengali     18 MB  Bengali, Assamese
#   FONT_SYMBOLS  font-noto-symbols      3 MB  maths, arrows, symbols
#   FONT_MATH     font-noto-math         1 MB  mathematical notation
#
# The flags are build args, so changing one means a rebuild
# (docker compose up -d --build).
ARG FONT_ARABIC=false
ARG FONT_CJK=false
ARG FONT_HEBREW=false
ARG FONT_THAI=false
ARG FONT_DEVANAGARI=false
ARG FONT_BENGALI=false
ARG FONT_SYMBOLS=false
ARG FONT_MATH=false

RUN set -eu; \
    for pair in \
      "FONT_ARABIC:font-noto-arabic" \
      "FONT_CJK:font-noto-cjk" \
      "FONT_HEBREW:font-noto-hebrew" \
      "FONT_THAI:font-noto-thai" \
      "FONT_DEVANAGARI:font-noto-devanagari" \
      "FONT_BENGALI:font-noto-bengali" \
      "FONT_SYMBOLS:font-noto-symbols" \
      "FONT_MATH:font-noto-math" \
    ; do \
      flag="${pair%%:*}"; pkg="${pair##*:}"; \
      eval "enabled=\${$flag}"; \
      if [ "$enabled" = "true" ]; then \
        echo "Installing optional font: $pkg"; \
        apk add --no-cache "$pkg"; \
      fi; \
    done; \
    rm -rf /var/cache/apk/*; \
    fc-cache -f >/dev/null 2>&1 || true

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
