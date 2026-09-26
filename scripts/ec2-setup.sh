#!/usr/bin/env bash
#
# Sets up the Sathiyaa API on a fresh Amazon Linux 2023 instance.
#
# Run it as ec2-user, after copying these two into /tmp:
#   sathiyaa-backend.tar.gz
#   ec2.env            (with the four placeholders filled in)
#
#   bash /tmp/ec2-setup.sh
#
# Safe to run again: every step either checks first or is idempotent.

set -euo pipefail

say() { printf '\n\033[36m== %s\033[0m\n' "$1"; }
ok()  { printf '   \033[32mok\033[0m   %s\n' "$1"; }
die() { printf '\n\033[31mSTOP: %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- inputs
say "checking what was copied up"
[ -f /tmp/sathiyaa-backend.tar.gz ] || die "/tmp/sathiyaa-backend.tar.gz is not there. Copy it up first."
[ -f /tmp/ec2.env ] || die "/tmp/ec2.env is not there. Copy it up first."

# Better to fail here than after npm has spent two minutes installing.
if grep -q '<SATHIYAA_' /tmp/ec2.env; then
    printf '\n\033[31mThese placeholders are still unfilled in ec2.env:\033[0m\n' >&2
    grep -o '<SATHIYAA_[A-Z_]*>' /tmp/ec2.env >&2
    die "Fill them in on your own machine, copy the file up again, and re-run."
fi
ok "archive and .env are present, no placeholders left"

# ---------------------------------------------------------------- node
say "node"
if ! command -v node >/dev/null 2>&1; then
    sudo dnf install -y nodejs20 nodejs20-npm >/dev/null 2>&1 \
        || sudo dnf install -y nodejs npm >/dev/null
fi
# The versioned package installs as /usr/bin/node-20 and does not always claim
# the plain `node` name. The systemd unit below calls /usr/bin/node, so make
# sure that exists rather than leaving it to chance.
if ! command -v node >/dev/null 2>&1 && [ -x /usr/bin/node-20 ]; then
    sudo alternatives --install /usr/bin/node node /usr/bin/node-20 90
fi
command -v node >/dev/null 2>&1 || die "node still is not on PATH. Run: sudo dnf search nodejs"
ok "node $(node -v), npm $(npm -v)"

case "$(node -v)" in
    v18.*|v20.*|v22.*|v24.*) ;;
    *) printf '   \033[33mnote\033[0m %s\n' "untested Node version -- 20 or newer is what this was built against" ;;
esac

# ---------------------------------------------------------------- folders
say "folders"
sudo mkdir -p /opt/sathiyaa /var/lib/sathiyaa/uploads
sudo chown -R ec2-user:ec2-user /opt/sathiyaa /var/lib/sathiyaa
ok "/opt/sathiyaa and /var/lib/sathiyaa/uploads"

# ---------------------------------------------------------------- rds ca
# Uploads and the database both cross a network here. This bundle is what turns
# the database connection from "encrypted" into "encrypted and verified".
say "RDS certificate bundle"
curl -fsS -o /opt/sathiyaa/global-bundle.pem \
    https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
grep -q 'BEGIN CERTIFICATE' /opt/sathiyaa/global-bundle.pem \
    || die "the downloaded bundle is not a certificate file"
ok "$(grep -c 'BEGIN CERTIFICATE' /opt/sathiyaa/global-bundle.pem) certificates"

# ---------------------------------------------------------------- code
say "backend"
tar -xzf /tmp/sathiyaa-backend.tar.gz -C /opt/sathiyaa
install -m 600 /tmp/ec2.env /opt/sathiyaa/backend/.env
shred -u /tmp/ec2.env 2>/dev/null || rm -f /tmp/ec2.env
ok "unpacked, .env in place and readable only by ec2-user"

cd /opt/sathiyaa/backend
say "dependencies"
npm ci --omit=dev
ok "installed"

# ---------------------------------------------------------------- database
say "migrate"
npm run migrate

say "seed"
npm run seed

# ---------------------------------------------------------------- service
say "service"
sudo tee /etc/systemd/system/sathiyaa-api.service >/dev/null <<'UNIT'
[Unit]
Description=Sathiyaa API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/sathiyaa/backend
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now sathiyaa-api
sleep 3
sudo systemctl restart sathiyaa-api
sleep 4

if ! systemctl is-active --quiet sathiyaa-api; then
    printf '\n\033[31mThe service did not start. The last 40 lines:\033[0m\n' >&2
    sudo journalctl -u sathiyaa-api -n 40 --no-pager >&2
    die "read the message above -- preflight names the setting that is wrong"
fi
ok "sathiyaa-api is running"

# ---------------------------------------------------------------- proof
say "answering locally"
curl -fsS localhost:4000/health && echo
ok "done -- CloudFront can take it from here"
