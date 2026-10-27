# docker-protonmail-bridge

A Docker image for [Proton Mail Bridge](https://github.com/ProtonMail/proton-bridge),
built from Proton's official signed `.deb` release and published automatically to
GitHub Container Registry whenever a new upstream version ships.

- **Architecture:** `linux/amd64` only — Proton only publishes amd64 Linux binaries.
- **Image:** `ghcr.io/aarnaud/docker-protonmail-bridge:latest` (also tagged with the
  Bridge version, e.g. `:v3.27.1`).
- **Runs as a non-root user** (`bridge`, uid 1000).
- **Ports:** `1143` (IMAP), `1025` (SMTP) — Bridge's native non-privileged ports.

## Why this exists

Proton Mail Bridge has no headless/env-var login — credentials are entered once
through its interactive CLI, after which the session is persisted to disk. This
image automates everything except that one manual step: building a minimal image
around the official binary, verifying its GPG signature, and giving it a secret
storage backend (`pass`, GPG-backed) that works without a desktop keyring or D-Bus
session.

## First-time setup

Bridge takes an exclusive lock on its vault, so the interactive login step must run
**before** the long-running daemon container starts (a plain `docker exec` into an
already-running daemon container will fail with "another instance is running").
Log in first, using a one-off container against the same volume:

```bash
docker volume create bridge-data

docker run --rm -it \
  -v bridge-data:/home/bridge \
  ghcr.io/aarnaud/docker-protonmail-bridge:latest \
  init
```

This drops you into Bridge's interactive CLI. From there:

```
login
```

...enter your Proton credentials (and 2FA if enabled). Once logged in, run:

```
info
```

to read the IMAP/SMTP username and Bridge-generated app password for your mail
client (this is **not** your Proton account password — Bridge generates a separate
one per account). Then `exit` the CLI session — this releases the vault lock and
stops the one-off container (`--rm` cleans it up).

Now start the long-running daemon, reusing the same volume:

```bash
docker run -d \
  --name protonmail-bridge \
  -v bridge-data:/home/bridge \
  -p 127.0.0.1:1143:1143 \
  -p 127.0.0.1:1025:1025 \
  ghcr.io/aarnaud/docker-protonmail-bridge:latest
```

Your vault/session is now stored in the `bridge-data` volume — restarting the
container does not require logging in again.

### Using docker compose instead

```bash
docker compose run --rm bridge init   # log in first, daemon not started yet
docker compose up -d                  # then start the long-running daemon
```

## Day-to-day use

Point any IMAP/SMTP mail client at `127.0.0.1:1143` / `127.0.0.1:1025` using the
credentials from `info`. The container's main process is `protonmail-bridge
--noninteractive`, which just keeps running; `docker restart` reuses the persisted
vault without re-login.

To re-check credentials or re-run `info` later, **stop the daemon first** — Bridge's
vault lock means the CLI and the daemon can never run against the same volume at
the same time:

```bash
docker stop protonmail-bridge
docker run --rm -it -v bridge-data:/home/bridge ghcr.io/aarnaud/docker-protonmail-bridge:latest init
docker start protonmail-bridge
```

## How the image is kept up to date

- **`.github/workflows/check-release.yml`** runs weekly (and on demand), checks
  Proton's latest GitHub release, and commits a bump to the `VERSION` file when a
  new version is found.
- **`.github/workflows/build.yml`** builds and pushes the image to GHCR whenever
  `VERSION`, the `Dockerfile`, or the entrypoint changes, on manual dispatch, and on
  its own weekly schedule (to pick up Debian base-image security patches even
  between Bridge releases). Each build is scanned with Trivy; results are uploaded
  to the repo's Security tab.

## Building locally

```bash
docker build --build-arg BRIDGE_VERSION=$(cat VERSION) -t protonmail-bridge:local .
```
