#!/usr/bin/env bash
# End-of-day: stop Moyai, suspend every sandbox (snapshots keep their state), scale GKE nodes to 0.
# Idle cost afterwards: ~Rs270/day (cluster fee + disks + static IP). Nothing is deleted.
set -uo pipefail
P=project-287c53a0-e18a-40e8-824; ZONE=us-east1-b; CLUSTER=moyai-substrate
export KUBECONFIG=$HOME/.kube/moyai-substrate.yaml
ATE=$HOME/Apps/bin/kubectl-ate

echo "== 1/4 stop Moyai on Netcup (no new sandboxes)"
ssh jk-box 'cd ~/moyai-stack && docker compose stop moyai' || echo "WARN: could not stop Moyai"

echo "== 2/4 suspend all sandboxes (awake ones are CRASHED and lose state if their node vanishes)"
for a in $($ATE get actors --atespace moyai -o json 2>/dev/null | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
items=d.get('items',d if isinstance(d,list) else [])
for i in items:
    st=str(i.get('state',i.get('status',{}).get('state',''))).upper()
    if 'RUNNING' in st or 'ACTIVE' in st or 'RESUM' in st: print(i['metadata']['name'])"); do
  echo "suspend $a"; $ATE suspend actor "$a" --atespace moyai || echo "WARN: $a not suspended"
done

echo "== 3/4 drop the 0-disruption PDB that otherwise blocks node drain for ~1 h"
kubectl -n ate-system delete pdb ate-api-server --ignore-not-found

echo "== 4/4 scale node pool to 0"
gcloud container clusters resize "$CLUSTER" --node-pool default-pool --num-nodes 0 \
  --zone "$ZONE" --project "$P" --quiet
echo "Down. Idle cost ~Rs270/day. Start again with moyai-up.sh"
