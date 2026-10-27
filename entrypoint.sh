#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/bridge
export GNUPGHOME=/home/bridge/.gnupg
export PASSWORD_STORE_DIR=/home/bridge/.password-store

# Bridge needs a secret-service backend to persist its vault (account keys /
# session). There's no DBus session or OS keyring in a headless container, so
# we use `pass` (GPG-backed) instead. Bridge falls back to `pass` on Linux
# when it can't reach a secret-service/dbus daemon.
#
# This has to run on every start, not just once at build time: the GPG key
# and pass store live on the mounted volume. On a fresh volume this creates
# them; on a volume that already has data, it must be skipped so Bridge can
# still decrypt the vault it wrote last time.
if [ ! -d "$PASSWORD_STORE_DIR" ]; then
    echo ">> First run: generating GPG key and initializing pass store..."
    gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 3072
Name-Real: ProtonBridge
Name-Email: bridge@localhost
Expire-Date: 0
%commit
EOF
    key_id=$(gpg --list-keys --with-colons | awk -F: '/^pub/ {print $5; exit}')
    pass init "$key_id"
fi

if [ "${1:-}" = "init" ]; then
    exec protonmail-bridge --cli
fi

exec protonmail-bridge --noninteractive
