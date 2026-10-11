#!/bin/sh
# ============================================================
# 01-verify-cluster.sh
# ============================================================
# Verifies that the cluster matches the expected state after
# running 00-setup-cluster.sh.
#
# Usage:
#   ./scripts/01-verify-cluster.sh
#
# Prerequisites:
#   - kubectl configured and pointing to a cluster
#   - 00-setup-cluster.sh has been run
# ============================================================

set -u

FAIL=0

check() {
  label="$1"
  result="$2"
  expected="$3"
  if [ "$result" = "$expected" ]; then
    echo "  [PASS] $label: $result"
  else
    echo "  [FAIL] $label: got '$result', expected '$expected'"
    FAIL=1
  fi
}

echo "============================================================"
echo " Cluster Verification"
echo "============================================================"
echo "Context: $(kubectl config current-context)"
echo ""

# ---------- Node ----------
echo "[*] Node status"
NODE_STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
check "Node Ready" "$NODE_STATUS" "True"
echo ""

# ---------- Namespaces ----------
echo "[*] Namespaces"
for NS in dev uat prod; do
  STATUS=$(kubectl get namespace "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "missing")
  check "Namespace $NS" "$STATUS" "Active"
done
echo ""

# ---------- ServiceAccounts ----------
echo "[*] ServiceAccounts"
for NS in dev uat prod; do
  SA=$(kubectl get sa github-actions -n "$NS" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "missing")
  check "SA $NS/github-actions" "$SA" "github-actions"
done
echo ""

# ---------- Roles ----------
echo "[*] Roles"
ROLE_DEV=$(kubectl get role dev-admin -n dev -o jsonpath='{.metadata.name}' 2>/dev/null || echo "missing")
ROLE_UAT=$(kubectl get role uat-admin -n uat -o jsonpath='{.metadata.name}' 2>/dev/null || echo "missing")
ROLE_PROD=$(kubectl get role prod-readonly -n prod -o jsonpath='{.metadata.name}' 2>/dev/null || echo "missing")
check "Role dev/dev-admin" "$ROLE_DEV" "dev-admin"
check "Role uat/uat-admin" "$ROLE_UAT" "uat-admin"
check "Role prod/prod-readonly" "$ROLE_PROD" "prod-readonly"
echo ""

# ---------- RoleBindings ----------
echo "[*] RoleBindings"
for NS in dev uat prod; do
  RB=$(kubectl get rolebinding github-actions-binding -n "$NS" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "missing")
  check "Binding $NS" "$RB" "github-actions-binding"
done
echo ""

# ---------- RBAC Scoping ----------
echo "[*] RBAC scoping"
CAN_DEV=$(kubectl auth can-i create deployments -n dev --as=system:serviceaccount:dev:github-actions)
CAN_UAT=$(kubectl auth can-i create deployments -n uat --as=system:serviceaccount:uat:github-actions)
CAN_PROD=$(kubectl auth can-i create deployments -n prod --as=system:serviceaccount:prod:github-actions)
CAN_DELETE=$(kubectl auth can-i delete pods -n uat --as=system:serviceaccount:uat:github-actions)
check "dev can create deployments" "$CAN_DEV" "yes"
check "uat can create deployments" "$CAN_UAT" "yes"
check "prod can create deployments" "$CAN_PROD" "no"
check "uat cannot delete pods" "$CAN_DELETE" "no"
echo ""

# ---------- Result ----------
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  echo " [PASS] All checks passed"
  echo "============================================================"
  exit 0
else
  echo " [FAIL] Some checks failed - review above"
  echo "============================================================"
  exit 1
fi
