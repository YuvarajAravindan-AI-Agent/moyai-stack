#!/usr/bin/env bash
# Run this yourself. Reads the Modal token that `modal setup` saved in ~/.modal.toml
# (profile founder-5300) and writes it into Moyai's moyai.env on Netcup over ssh.
# Nothing is printed except whether each value was set. The default sandbox vendor
# stays Substrate; Claude switches the default for the multi-vendor test.
set -euo pipefail
PROFILE=${1:-founder-5300}
read -r TID TSEC < <(~/modal-venv/bin/python - "$PROFILE" <<'EOF'
import sys, toml, os
cfg = toml.load(os.path.expanduser("~/.modal.toml"))[sys.argv[1]]
print(cfg["token_id"], cfg["token_secret"])
EOF
)
[ -n "$TID" ] && [ -n "$TSEC" ] || { echo "Token not found in ~/.modal.toml for profile $PROFILE"; exit 1; }
printf '%s\n%s\n' "$TID" "$TSEC" | ssh jk-box 'set -e; cd ~/moyai-stack
read -r TID; read -r TSEC
set_kv(){ if grep -qE "^$1=" moyai.env; then sed -i "s|^$1=.*|$1=$2|" moyai.env; else echo "$1=$2" >> moyai.env; fi; }
cp moyai.env moyai.env.bak-before-modal; chmod 600 moyai.env.bak-before-modal
set_kv MODAL_TOKEN_ID "$TID"
set_kv MODAL_TOKEN_SECRET "$TSEC"
set_kv MODAL_APP_NAME moyai-sandboxes
chmod 600 moyai.env
docker compose up -d --force-recreate moyai >/dev/null 2>&1
for i in $(seq 1 40); do docker compose ps --format "{{.Status}}" | grep -q healthy && break; sleep 3; done
echo "Moyai restarted: $(docker compose ps --format "{{.Status}}")"
echo "Modal values set: id=$(grep -c "^MODAL_TOKEN_ID=.\+" moyai.env) secret=$(grep -c "^MODAL_TOKEN_SECRET=.\+" moyai.env)"'
unset TID TSEC
echo "Done. Tell Claude: modal connected"
