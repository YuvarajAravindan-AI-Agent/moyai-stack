#!/usr/bin/env bash
# Run this yourself after creating the Slack app. Secrets are typed silently, sent over ssh
# straight into moyai.env on Netcup (mode 600), and never echoed or stored locally.
set -euo pipefail
read -r -p "Slack Client ID (Basic Information page): " CID
read -r -s -p "Slack Client Secret (hidden): " CSEC; echo
read -r -s -p "Slack Signing Secret (hidden): " SSEC; echo
read -r -p "Who may start sessions? Slack user IDs comma-separated, or * for the whole workspace [*]: " USERS
USERS=${USERS:-*}
[ -n "$CID" ] && [ -n "$CSEC" ] && [ -n "$SSEC" ] || { echo "All three Slack values are required"; exit 1; }

printf '%s\n%s\n%s\n%s\n' "$CID" "$CSEC" "$SSEC" "$USERS" | ssh jk-box 'set -e; cd ~/moyai-stack
read -r CID; read -r CSEC; read -r SSEC; read -r USERS
set_kv(){ if grep -qE "^$1=" moyai.env; then sed -i "s|^$1=.*|$1=$2|" moyai.env; else echo "$1=$2" >> moyai.env; fi; }
cp moyai.env moyai.env.bak-before-slack
set_kv SLACK_CLIENT_ID "$CID"
set_kv SLACK_CLIENT_SECRET "$CSEC"
set_kv SLACK_SIGNING_SECRET "$SSEC"
set_kv SLACK_BOT_ENABLED true
set_kv SLACK_SESSION_USERS "$USERS"
set_kv SLACK_THREAD_CHAT_ENABLED true
set_kv SLACK_DM_ENABLED true
chmod 600 moyai.env moyai.env.bak-before-slack
docker compose up -d --force-recreate moyai >/dev/null 2>&1
for i in $(seq 1 40); do docker compose ps --format "{{.Status}}" | grep -q healthy && break; sleep 3; done
echo "Moyai restarted: $(docker compose ps --format "{{.Status}}")"
echo "Slack values set: id=$(grep -c "^SLACK_CLIENT_ID=.\+" moyai.env) secret=$(grep -c "^SLACK_CLIENT_SECRET=.\+" moyai.env) signing=$(grep -c "^SLACK_SIGNING_SECRET=.\+" moyai.env)"'
echo "Done. Tell Claude: slack secrets set"
