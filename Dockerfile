# syntax=docker/dockerfile:1

# ---- Stage 1: download and verify the official signed .deb ----
FROM debian:bookworm-slim AS fetch

# Falls back to the committed VERSION file when no --build-arg is given, so a
# plain `docker build .` works; CI passes BRIDGE_VERSION explicitly so it
# always matches the VERSION file bump that triggered the build.
ARG BRIDGE_VERSION=""
COPY VERSION /VERSION

RUN apt-get update \
 && apt-get install -y --no-install-recommends wget ca-certificates gnupg \
 && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    version="${BRIDGE_VERSION:-$(cat /VERSION)}"; \
    deb="protonmail-bridge_${version#v}-1_amd64.deb"; \
    wget -q "https://github.com/ProtonMail/proton-bridge/releases/download/${version}/${deb}" -O /tmp/bridge.deb; \
    wget -q "https://github.com/ProtonMail/proton-bridge/releases/download/${version}/${deb}.sig" -O /tmp/bridge.deb.sig; \
    wget -q "https://github.com/ProtonMail/proton-bridge/releases/download/${version}/bridge_pubkey.gpg" -O /tmp/bridge_pubkey.gpg; \
    gpg --import /tmp/bridge_pubkey.gpg; \
    gpg --verify /tmp/bridge.deb.sig /tmp/bridge.deb

# ---- Stage 2: runtime image ----
FROM debian:bookworm-slim

# Only used for the LABEL below; the published image's real version label is
# set correctly by docker/metadata-action in CI regardless of this value.
ARG BRIDGE_VERSION=""
LABEL org.opencontainers.image.title="protonmail-bridge" \
      org.opencontainers.image.version="${BRIDGE_VERSION}" \
      org.opencontainers.image.source="https://github.com/ProtonMail/proton-bridge" \
      org.opencontainers.image.licenses="MIT"

COPY --from=fetch /tmp/bridge.deb /tmp/bridge.deb

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates gnupg pass libsecret-1-0 libfido2-1 \
 && apt-get install -y /tmp/bridge.deb \
 && rm -f /tmp/bridge.deb \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1000 bridge \
 && useradd -u 1000 -g bridge -m -d /home/bridge -s /usr/sbin/nologin bridge \
 && chown -R bridge:bridge /home/bridge

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV HOME=/home/bridge
USER bridge

VOLUME ["/home/bridge"]
EXPOSE 1143 1025

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD bash -c '(echo >/dev/tcp/127.0.0.1/1143) && (echo >/dev/tcp/127.0.0.1/1025)' || exit 1

ENTRYPOINT ["/entrypoint.sh"]
