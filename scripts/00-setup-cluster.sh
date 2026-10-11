#!/bin/sh
# ============================================================
# 00-setup-cluster.sh
# ============================================================
# Applies namespaces and RBAC to the current Kubernetes cluster.
# Idempotent - safe to re-run.
#
# Usage:
#   ./scripts/00-setup-cluster.sh
#
# Prerequisites:
#   - kubectl configured and pointing to a cluster
#   - Run from the repo root
# ============================================================

set -eu

# ---------- Sanity checks ----------
if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl not found in PATH"
  exit 1
fi

if [ ! -f "k8s/namespaces.yaml" ] || [ ! -f "k8s/rbac.yaml" ]; then
  echo "ERROR: Must be run from the repo root (k8s/ not found)"
  exit 1
fi

# ---------- Show current context ----------
echo "============================================================"
echo " Cluster Setup"
echo "============================================================"
echo "Current context: $(kubectl config current-context)"
echo ""

# ---------- Apply namespaces ----------
echo "[*] Applying namespaces..."
kubectl apply -f k8s/namespaces.yaml

echo ""

# ---------- Apply RBAC ----------
echo "[*] Applying RBAC (ServiceAccounts, Roles, RoleBindings)..."
kubectl apply -f k8s/rbac.yaml

echo ""

# ---------- Report ----------
echo "============================================================"
echo " Namespaces"
echo "============================================================"
kubectl get namespaces | grep -E "NAME|dev|uat|prod"

echo ""
echo "============================================================"
echo " Setup complete"
echo "============================================================"
echo "Run ./scripts/01-verify-cluster.sh to validate."
