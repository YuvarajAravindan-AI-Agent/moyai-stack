#!/usr/bin/env bash
# Morning: scale GKE nodes to 2, wait for Substrate + LiteLLM + edge, start Moyai on Netcup.
set -euo pipefail
P=project-287c53a0-e18a-40e8-824; ZONE=us-east1-b; CLUSTER=moyai-substrate
export KUBECONFIG=$HOME/.kube/moyai-substrate.yaml

echo "== 1/4 scale node pool to 2"
gcloud container clusters resize "$CLUSTER" --node-pool default-pool --num-nodes 2 \
  --zone "$ZONE" --project "$P" --quiet
echo "== 2/4 wait for nodes"
kubectl wait --for=condition=Ready node --all --timeout=600s
echo "== 3/4 wait for Substrate, LiteLLM, edge"
kubectl -n ate-system rollout status statefulset/postgres --timeout=600s
for d in ate-api-server ate-controller atenet-router atenet-egress; do kubectl -n ate-system rollout status deploy/$d --timeout=600s; done
kubectl -n ate-system rollout status ds --timeout=600s 2>/dev/null || true
kubectl -n moyai wait --for=condition=Ready pod --all --timeout=600s
kubectl -n litellm rollout status deploy/litellm --timeout=600s
kubectl -n edge rollout status deploy/caddy --timeout=600s
echo "== 4/5 refresh Substrate API token on Netcup (24h, never printed)"
kubectl -n ate-system create token ate-client --audience=api.ate-system.svc --duration=24h | \
  ssh jk-box 'umask 077; sudo tee ~/moyai-stack/substrate-token >/dev/null && sudo chown 10001:10001 ~/moyai-stack/substrate-token && sudo chmod 600 ~/moyai-stack/substrate-token'
echo "== 5/5 start Moyai on Netcup"
ssh jk-box 'cd ~/moyai-stack && docker compose up -d moyai'
echo "Up. https://moyai.ai-agentic-enterprises.com (cluster costs ~Rs36/h while running)"
echo "Budget plan: 2 nodes ~5 h/day (~Rs270/day all-in). Run moyai-down.sh by $(date -d '+5 hours' +%H:%M)."
