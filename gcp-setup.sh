#!/usr/bin/env bash
# One-time GCP setup for Moyai on Agent Substrate (GKE 1.36) + LiteLLM's Vertex SA.
# Mirrors agent-substrate/substrate tools/setup-gcp (bootstrap) using plain gcloud.
# Run it yourself: it creates a cluster and IAM grants, which Claude's auto mode can't.
set -euo pipefail

P=project-287c53a0-e18a-40e8-824
PN=$(gcloud projects describe "$P" --format='value(projectNumber)')
REGION=us-east1
ZONE=us-east1-b
CLUSTER=moyai-substrate
VERSION=1.36.4-gke.1391000
BUCKET=moyai-substrate-snapshots-$PN
AR_REPO=moyai

gcloud config set account yaravindan@gmail.com >/dev/null
echo "== 1/7 Enable APIs"
gcloud services enable --project "$P" \
  container.googleapis.com artifactregistry.googleapis.com storage.googleapis.com \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com logging.googleapis.com \
  monitoring.googleapis.com cloudtrace.googleapis.com telemetry.googleapis.com \
  networkconnectivity.googleapis.com cloudbuild.googleapis.com aiplatform.googleapis.com

echo "== 2/7 GKE $VERSION cluster (beta cert APIs at creation, Workload Identity, node-upgrade exclusion)"
if ! gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$P" >/dev/null 2>&1; then
  gcloud container clusters create "$CLUSTER" --project "$P" --zone "$ZONE" \
    --cluster-version "$VERSION" --release-channel regular \
    --enable-kubernetes-unstable-apis=certificates.k8s.io/v1beta1/podcertificaterequests,certificates.k8s.io/v1beta1/clustertrustbundles \
    --workload-pool "$P.svc.id.goog" --enable-dataplane-v2 \
    --managed-otel-scope=COLLECTION_AND_INSTRUMENTATION_COMPONENTS \
    --machine-type n2-standard-4 --num-nodes 2 --enable-nested-virtualization \
    --disk-type pd-balanced --disk-size 60 \
    --enable-autorepair
fi
# New projects can't opt out of release channels, so node auto-upgrade is blocked
# with a maintenance exclusion instead (Substrate: never upgrade worker nodes under live actors).
if ! gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$P" \
     --format='value(maintenancePolicy.window.maintenanceExclusions)' | grep -q substrate-no-node-upgrades; then
  gcloud container clusters update "$CLUSTER" --project "$P" --zone "$ZONE" \
    --add-maintenance-exclusion-name substrate-no-node-upgrades \
    --add-maintenance-exclusion-scope no_minor_or_node_upgrades \
    --add-maintenance-exclusion-until-end-of-support
fi

echo "== 3/7 Snapshot bucket gs://$BUCKET"
gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://$BUCKET" --project "$P" --location "$REGION" \
    --uniform-bucket-level-access --public-access-prevention

echo "== 4/7 Artifact Registry repo $AR_REPO (sandbox + Substrate images)"
gcloud artifacts repositories describe "$AR_REPO" --location "$REGION" --project "$P" >/dev/null 2>&1 || \
  gcloud artifacts repositories create "$AR_REPO" --repository-format docker \
    --location "$REGION" --project "$P"

echo "== 5/7 Substrate Workload Identity grants (as documented in setup-gcp/README.md)"
WI="principal://iam.googleapis.com/projects/$PN/locations/global/workloadIdentityPools/$P.svc.id.goog/subject/ns/ate-system/sa"
ATELET="$WI/atelet"; ATE_API="$WI/ate-api-server"; NODE_SA="$PN-compute@developer.gserviceaccount.com"
for b in "$ATELET roles/storage.objectAdmin" "$ATELET roles/artifactregistry.reader" \
         "serviceAccount:$NODE_SA roles/storage.objectViewer" "serviceAccount:$NODE_SA roles/artifactregistry.reader"; do
  set -- $b
  gcloud projects add-iam-policy-binding "$P" --member "$1" --role "$2" --condition=None --format=none
done
for M in "$ATELET" "$ATE_API"; do
  for R in roles/storage.objectAdmin roles/storage.bucketViewer; do
    gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --member "$M" --role "$R" --format=none
  done
done

echo "== 6/7 LiteLLM Vertex access via Workload Identity (no key file: org policy blocks SA keys)"
gcloud projects add-iam-policy-binding "$P" --condition=None --format=none --role roles/aiplatform.user \
  --member "principal://iam.googleapis.com/projects/$PN/locations/global/workloadIdentityPools/$P.svc.id.goog/subject/ns/litellm/sa/litellm"

echo "== 7/7 kubeconfig -> ~/.kube/moyai-substrate.yaml"
KUBECONFIG=$HOME/.kube/moyai-substrate.yaml gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$P"

echo "Done. Tell Claude: setup finished."
