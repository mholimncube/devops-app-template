#!/bin/sh
# ============================================================
# 02-deploy.sh
# ============================================================
# Deploys hello-app to a namespace with a specific image tag.
#
# Usage:
#   ./scripts/02-deploy.sh <namespace> <tag>
#
# Examples:
#   ./scripts/02-deploy.sh dev sha-fafc10f
#   ./scripts/02-deploy.sh uat uat
#   ./scripts/02-deploy.sh prod v1.0.0
#
# Prerequisites:
#   - kubectl configured and pointing to a cluster
#   - Namespaces created (run 00-setup-cluster.sh first)
#   - GHCR_PAT environment variable set (recommended) for
#     refreshing the imagePullSecret. If not set, the script
#     will only proceed if a secret already exists.
#   - Run from the repo root
# ============================================================

set -eu

# ---------- Args ----------
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <namespace> <tag>"
  echo "Example: $0 uat uat"
  exit 1
fi

NAMESPACE="$1"
TAG="$2"

# ---------- Validate namespace ----------
case "$NAMESPACE" in
  dev|uat|prod) ;;
  *)
    echo "ERROR: namespace must be one of: dev, uat, prod"
    exit 1
    ;;
esac

# ---------- Validate tag ----------
if [ -z "$TAG" ]; then
  echo "ERROR: tag cannot be empty"
  exit 1
fi

# ---------- Sanity checks ----------
if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl not found in PATH"
  exit 1
fi

for f in k8s/deployment.yaml k8s/service.yaml k8s/ingress.yaml; do
  if [ ! -f "$f" ]; then
    echo "ERROR: $f not found. Run from repo root."
    exit 1
  fi
done

# ---------- Check namespace exists ----------
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "ERROR: namespace '$NAMESPACE' does not exist."
  echo "       Run ./scripts/00-setup-cluster.sh first."
  exit 1
fi

# ---------- Image pull secret ----------
# If GHCR_PAT is set, always apply the secret (create or update).
# This makes token rotation self-healing.
if [ -n "${GHCR_PAT:-}" ]; then
  echo "[*] Applying imagePullSecret in $NAMESPACE..."
  kubectl create secret docker-registry ghcr-credentials \
    --docker-server=ghcr.io \
    --docker-username=mholimncube \
    --docker-password="$GHCR_PAT" \
    --docker-email=mholi.mncube@gmail.com \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  if kubectl get secret ghcr-credentials -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "[*] imagePullSecret already present in $NAMESPACE (GHCR_PAT not set, skipping refresh)"
  else
    echo "ERROR: imagePullSecret missing in $NAMESPACE and GHCR_PAT not set."
    echo "       Export your token first:"
    echo "         export GHCR_PAT=\$(cat ~/.secrets/ghcr-pat)"
    exit 1
  fi
fi

# ---------- Summary ----------
IMAGE="ghcr.io/mholimncube/devops-app-template:${TAG}"

echo ""
echo "============================================================"
echo " Deploying hello-app"
echo "============================================================"
echo "Namespace: $NAMESPACE"
echo "Image:     $IMAGE"
echo ""

# ---------- Apply manifests ----------
echo "[*] Applying deployment..."
sed "s|TAG_PLACEHOLDER|${TAG}|g" k8s/deployment.yaml \
  | kubectl apply -n "$NAMESPACE" -f -

echo "[*] Applying service..."
kubectl apply -f k8s/service.yaml -n "$NAMESPACE"

echo "[*] Applying ingress..."
kubectl apply -f k8s/ingress.yaml -n "$NAMESPACE"

# ---------- Wait for rollout ----------
echo "[*] Waiting for rollout to complete..."
kubectl rollout status deployment/hello-app -n "$NAMESPACE" --timeout=120s

# ---------- Report ----------
echo ""
echo "============================================================"
echo " Deployed"
echo "============================================================"
kubectl get pods -n "$NAMESPACE" -l app=hello-app
echo ""
echo "Access via: kubectl port-forward -n kube-system svc/traefik 8080:80"
