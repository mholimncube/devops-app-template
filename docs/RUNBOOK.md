# devops-app-template: Runbook

Author: Banks (mholimncube)
Last Updated: 2026-10-11
Status: Working pipeline; three environments deployed

---

## 1. Purpose

This document describes how to operate the devops-app-template from a
developer machine. It covers the full flow: code -> GitHub -> CI build
-> GHCR -> cluster deployment -> promotion between environments.

It is written to be reproducible by a human or an automation agent.

---

## 2. Architecture Overview

### The Pipeline

    Developer writes code (Visual Studio / VS Code)
        |
        v
    Push to GitHub (single branch: main)
        |
        v
    GitHub Actions builds image -> pushes to GHCR
        (tags: sha-<short>, main, latest)
        |
        v
    Manual promotion workflow retags image for a target environment
        (tags: uat, v1.0.0, etc.)
        |
        v
    Cluster pulls from GHCR using imagePullSecret
        |
        v
    App runs in dev / uat / prod namespaces

### Principles

- Single source branch (main). No dev/uat/prod branches.
- Same image bytes across environments. Promotion = retag, never rebuild.
- Immutable SHA tags for traceability: image -> commit -> issue.
- Human approval gates on promotion to uat and prod.
- All state in Git. Scripts in scripts/, manifests in k8s/.

### Components

| Layer | What | Version |
|-------|------|---------|
| Host | Windows 11 | - |
| Container runtime host | Rancher Desktop (WSL2) | 1.23.1 |
| Kubernetes | k3s via Rancher Desktop | v1.36.2+k3s1 |
| Ingress | Traefik (ships with k3s) | - |
| Registry | GitHub Container Registry | ghcr.io |
| CI/CD | GitHub Actions | - |

---

## 3. Repository Structure

    devops-app-template/
    |-- .github/
    |   `-- workflows/
    |       |-- build-push.yaml       # CI: build + push on push to main
    |       `-- promote.yaml          # Manual: retag image for promotion
    |-- k8s/
    |   |-- namespaces.yaml           # dev, uat, prod
    |   |-- rbac.yaml                 # SAs, Roles, RoleBindings
    |   |-- deployment.yaml           # uses TAG_PLACEHOLDER
    |   |-- service.yaml
    |   `-- ingress.yaml
    |-- scripts/
    |   |-- 00-setup-cluster.sh       # applies namespaces + RBAC
    |   |-- 01-verify-cluster.sh      # validates cluster state
    |   `-- 02-deploy.sh              # deploy app to a namespace + tag
    |-- src/
    |   `-- index.html                # static landing page
    |-- docs/
    |   `-- RUNBOOK.md                # this file
    |-- Dockerfile
    `-- README.md

---

## 4. Prerequisites

### Windows host

- Rancher Desktop installed and running
- Kubernetes enabled (Rancher Desktop -> Preferences -> Kubernetes)
- Container engine: dockerd (moby)
- WSL2 up to date (`wsl --update`)
- `%USERPROFILE%\.wslconfig` with at least:

      [wsl2]
      memory=4GB
      processors=4

### Accounts

- GitHub account with access to `mholimncube/devops-app-template`
- GitHub PAT with `read:packages` scope, stored at `~/.secrets/ghcr-pat`
  (chmod 600)

### WSL tooling

- kubectl (Rancher Desktop provides it)
- git
- sh (busybox or dash is fine; scripts are POSIX)

---

## 5. Cluster Setup

Run once after Rancher Desktop is healthy.

### 5.1 Verify cluster is reachable

    kubectl get nodes
    # Expected: single node "mholim" Ready

### 5.2 Create namespaces and RBAC

    cd /mnt/c/Users/mholi/Desktop/workspace/Apps/devops-app-template
    ./scripts/00-setup-cluster.sh

This creates:
- Namespaces: dev, uat, prod
- ServiceAccount `github-actions` in each namespace
- Roles: dev-admin (full), uat-admin (limited write), prod-readonly
- RoleBindings mapping each SA to its Role

### 5.3 Verify

    ./scripts/01-verify-cluster.sh

Expected output ends with: [PASS] All checks passed

---

## 6. Registry Setup (GHCR)

### 6.1 CI authentication

GitHub Actions uses the built-in `GITHUB_TOKEN`. No secret needed.

### 6.2 Cluster authentication

The cluster needs a separate PAT to pull private images.

Create a classic PAT with only `read:packages` scope. Save it:

    mkdir -p ~/.secrets
    printf '%s' 'YOUR_TOKEN' > ~/.secrets/ghcr-pat
    chmod 600 ~/.secrets/ghcr-pat

The deploy script (02-deploy.sh) reads `GHCR_PAT` from the environment:

    export GHCR_PAT=$(cat ~/.secrets/ghcr-pat)

It then creates or updates the `ghcr-credentials` docker-registry secret
in the target namespace.

Rotating the token: update ~/.secrets/ghcr-pat and re-run the deploy
script. The script refreshes the secret automatically.

---

## 7. Day-to-Day Development Flow

### 7.1 Make a code change

    # Edit src/index.html or any other source
    git add .
    git commit -m "Description of change"
    git push origin main

### 7.2 Watch CI build the image

Open: https://github.com/mholimncube/devops-app-template/actions

The `build-push.yaml` workflow runs automatically. It builds the image
and pushes three tags to GHCR:

- `sha-<short>` (immutable, tied to the commit)
- `main` (mutable, latest from main branch)
- `latest` (convenience alias)

Expected duration: ~30 seconds.

### 7.3 Deploy the new SHA to dev

    export GHCR_PAT=$(cat ~/.secrets/ghcr-pat)
    ./scripts/02-deploy.sh dev sha-<short>

Replace `<short>` with the first 7 characters of the commit hash shown
by `git log --oneline -1`.

---

## 8. Promotion Flow (dev -> uat -> prod)

Promotion never rebuilds. It retags the existing image in GHCR.

### 8.1 Trigger the promotion workflow

Open: https://github.com/mholimncube/devops-app-template/actions/workflows/promote.yaml

Click "Run workflow" and provide:

| Input | Example | Meaning |
|-------|---------|---------|
| source_tag | sha-fafc10f | Existing image tag to promote |
| target_tag | uat | New tag to create |
| environment | uat | Which environment gate to use |

### 8.2 Approve the deployment

The workflow pauses. GitHub sends a notification. Open the run page,
click "Review deployments", select the environment, and approve.

### 8.3 Deploy the promoted tag to the target namespace

    ./scripts/02-deploy.sh uat uat
    ./scripts/02-deploy.sh prod v1.0.0

---

## 9. Scripts Reference

### 9.1 scripts/00-setup-cluster.sh

Purpose: Apply namespaces and RBAC.
Idempotent: Yes.
Usage:   ./scripts/00-setup-cluster.sh

### 9.2 scripts/01-verify-cluster.sh

Purpose: Verify cluster matches expected state.
Checks:  Node ready, namespaces, SAs, roles, bindings, RBAC scoping.
Usage:   ./scripts/01-verify-cluster.sh
Exit:    0 on all-pass, 1 on any failure.

### 9.3 scripts/02-deploy.sh

Purpose: Deploy hello-app to a namespace with a specific tag.
Usage:   ./scripts/02-deploy.sh <namespace> <tag>
Args:
  namespace - one of dev, uat, prod
  tag       - image tag (sha-<short>, uat, v1.0.0, etc.)

Behaviour:
  1. Validates args and namespace
  2. Checks namespace exists
  3. Applies imagePullSecret (if GHCR_PAT set; otherwise skips)
  4. Substitutes TAG_PLACEHOLDER in k8s/deployment.yaml
  5. Applies deployment, service, ingress
  6. Waits for rollout
  7. Prints pod status

Env vars used:
  GHCR_PAT - GitHub PAT for pulling from GHCR

---

## 10. GitHub Workflows Reference

### 10.1 .github/workflows/build-push.yaml

Trigger: push to main, PR to main, manual dispatch.
Action:  Builds Dockerfile, pushes to GHCR with tags:
         sha-<short>, main, latest.
Auth:    Built-in GITHUB_TOKEN (no secret needed).

### 10.2 .github/workflows/promote.yaml

Trigger: manual dispatch only.
Inputs:
  source_tag  (string, required) - existing tag to promote
  target_tag  (string, required) - new tag to create
  environment (choice, required) - uat or prod
Action:  Pulls source image, retags, pushes. No rebuild.
Gate:    Environment approval (Required reviewers).

---

## 11. RBAC Model

| Namespace | Role | SA | Permissions |
|-----------|------|----|-------------|
| dev  | dev-admin     | github-actions | Full access (all verbs, all resources) |
| uat  | uat-admin     | github-actions | get/list/watch/create/update/patch on workloads; get/list on secrets |
| prod | prod-readonly | github-actions | get/list/watch on workloads only |

Verify at any time:

    kubectl auth can-i create deployments -n dev --as=system:serviceaccount:dev:github-actions
    # Expected: yes

    kubectl auth can-i create deployments -n prod --as=system:serviceaccount:prod:github-actions
    # Expected: no

---

## 12. Troubleshooting

### Pods stuck in ImagePullBackOff

Symptom: new pods fail to pull from ghcr.io.

Cause:   The imagePullSecret contains an expired or wrong PAT.

Fix:

    export GHCR_PAT=$(cat ~/.secrets/ghcr-pat)
    ./scripts/02-deploy.sh <namespace> <tag>
    kubectl rollout restart deployment hello-app -n <namespace>

Verify the token file is correct:

    head -c 4 ~/.secrets/ghcr-pat; echo
    # Expected: ghp_    (classic PAT)

### Workflow fails at "Invalid workflow file"

Symptom: GitHub says YAML syntax error on a specific line.

Cause:   Usually a non-ASCII character or a scalar value where a map
         was expected (e.g., `key: "value"` followed by indented children).

Fix:     Reproduce locally with:

    cat .github/workflows/<file>.yaml

Look for the offending line. Fix from WSL to keep LF endings.

### kubectl cannot reach cluster

Symptom: connection refused on 127.0.0.1:6443.

Cause:   Rancher Desktop's k3s is not running.

Fix:     Open Rancher Desktop and wait for Kubernetes status = Running.
         Verify:

    kubectl config current-context
    # Expected: default

    kubectl get nodes

### Scripts fail with "env: can't execute 'bash'"

Symptom: running a script errors on the shebang.

Cause:   Scripts written with `#!/usr/bin/env bash` but bash is not
         available in the minimal shell environment (e.g. Rancher).

Fix:     All scripts in this repo use `#!/bin/sh` and are POSIX.
         If you add new scripts, follow that convention.

### Scripts behave oddly after editing on Windows

Symptom: `command not found` on lines that look correct; unusual
         character errors.

Cause:   CRLF line endings introduced by Windows editors.

Fix:     Always create or edit scripts from WSL (LF endings), or after
         editing on Windows, run:

    sed -i 's/\r$//' scripts/<file>.sh

Verify:

    grep -c $'\r' scripts/<file>.sh
    # Expected: 0

---

## 13. Roadmap

This template is the base layer for a wider platform. The phases below
describe how the base expands into observability, GitOps, AI agents,
and non-Kubernetes targets.

### 13.1 Guiding Principle

The pipeline, observability, and AI agents should be infrastructure-agnostic.
The same patterns must work whether the target is a Kubernetes cluster,
a standalone VM, or bare metal. Only the deployment mechanism differs.

### 13.2 Phases

| Phase | Focus | Outcome |
|-------|-------|---------|
| 1 | Run real workloads | Something meaningful to monitor |
| 2 | Observability stack | Prometheus, Grafana, Loki, Alertmanager |
| 3 | GitOps | ArgoCD or Flux managing deployments from Git |
| 4 | AI agents | Alert enrichment, root cause, remediation |
| 5 | VM/WSL deployment path | Prove the patterns are portable |

### 13.3 Phase 1: Real Workloads

Add a two-container workload (API + database) to exercise the pipeline
beyond a static landing page. The workload should expose:

- Health endpoint (/healthz) for Kubernetes probes
- Metrics endpoint (/metrics) for Prometheus scraping
- Stateful data (persistent volume) to test storage
- Service-to-service communication via cluster DNS
- Config and secrets separated (ConfigMap vs Secret)

### 13.4 Phase 2: Observability

Deploy the standard Kubernetes observability stack:

| Component | Purpose | Distribution |
|-----------|---------|--------------|
| Prometheus | Metrics collection | kube-prometheus-stack |
| Grafana | Dashboards | kube-prometheus-stack |
| Alertmanager | Alert routing | kube-prometheus-stack |
| Loki | Log aggregation | loki-stack |
| Tempo | Distributed tracing | tempo |

Golden signals to capture: latency, traffic, errors, saturation.

Every app deployed through the golden path template should receive:
- A ServiceMonitor for metrics discovery
- A PrometheusRule for alert definitions
- A Grafana dashboard provisioned from a ConfigMap

### 13.5 Phase 3: GitOps

Move from imperative deploys (scripts running kubectl apply) to
declarative GitOps (a controller syncs cluster state from Git).

Recommended: ArgoCD. Rationale: rich web UI, native multi-tenancy,
integrates cleanly with a PR-driven promotion workflow.

Promotion pattern with GitOps:

    1. CI builds image, pushes sha-<short> tag to GHCR
    2. CI opens PR to update environments/dev/kustomization.yaml
    3. PR merged, ArgoCD auto-syncs dev
    4. Verify in dev
    5. Open PR to update environments/uat/kustomization.yaml
    6. Approve, ArgoCD syncs uat
    7. Same for prod

Every promotion becomes a pull request, fully auditable and reversible.

### 13.6 Phase 4: AI Agents

Once observability and GitOps are in place, AI agents become useful.

| Agent | Trigger | Action |
|-------|---------|--------|
| Alert Enricher | Alertmanager fires | Gather logs, metrics, events; post summary |
| Root Cause Analyzer | Alert plus enrichment | Query Prometheus, logs; suggest cause |
| Remediator | Known issue detected | Open PR with fix (scale, rollback) |
| Cost Optimizer | Scheduled | Rightsizing recommendations |

Principles:

- Human approval gate on all write actions
- Git as the action log (every change is a commit)
- Guardrails enforced by RBAC
- Learning loop: record outcomes, improve over time

### 13.7 Phase 5: VM/WSL Deployment Path

Replicate the pattern on non-Kubernetes targets to prove portability.

| Concept | Kubernetes | VM / WSL |
|---------|------------|----------|
| Deployment unit | Pod | systemd service |
| Config | ConfigMap / Secret | .env file |
| Networking | Service + Ingress | nginx reverse proxy |
| Metrics | ServiceMonitor | node_exporter textfile |
| Alerts | PrometheusRule | Prometheus config |
| GitOps | ArgoCD | Ansible pull or cron git pull |
| Agent action | Git PR, ArgoCD syncs | Git PR, Ansible applies |

The observability layer is identical across both. Only the deployment
mechanism differs.

### 13.8 The Golden Path

Every new app, on any target, should receive:

- CI pipeline (GitHub Actions)
- Container image (pushed to GHCR)
- Deployment descriptor (K8s manifests or systemd unit)
- Metrics configuration (ServiceMonitor or textfile collector)
- Alert rules (PrometheusRule or Prometheus config)
- Grafana dashboard (provisioned via ConfigMap)
- Log shipping (Loki / Promtail)
- Tracing (OpenTelemetry)

The pipeline and observability are constant. Only the deployment target varies.

### 13.9 Status

| Phase | Status |
|-------|--------|
| Base pipeline (this doc) | Complete |
| Phase 1: Real workloads | Not started |
| Phase 2: Observability | Not started |
| Phase 3: GitOps | Not started |
| Phase 4: AI agents | Not started |
| Phase 5: VM/WSL path | Not started |
