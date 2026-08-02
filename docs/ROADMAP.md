# Roadmap

Tracks the bootstrap sequence for this repo. Update as phases complete — this file is the honest current status, not an aspirational plan.

## Phase 0 — Repo scaffolding
- [x] Initialize repo, README, LICENSE
- [x] Write architecture docs

## Phase 1 — Infrastructure (Terraform)
- [x] Cluster created manually (`gcloud container clusters create kubia`, zonal, 3x e2-medium, 50GB disks — kept under the free-tier 250GB disk quota) — 2026-08-02
- [x] `terraform/` module written describing that same cluster (see [ARCHITECTURE.md](ARCHITECTURE.md#state--applying-changes))
- [x] CI wired up: GitHub Actions plans on PR and on `main`; applies only on manual dispatch (see [github-actions-auth.md](github-actions-auth.md))
- [x] Remote state backend (GCS bucket) created and wired up — versioning + uniform bucket-level access on
- [x] Existing `kubia` cluster imported into Terraform state (see [terraform-import.md](terraform-import.md)) — one-time, adopts the cluster you already created without recreating it
- [x] `terraform plan` shows no diff after import — CI reports `No changes. Your infrastructure matches the configuration.`
- [ ] Test the from-scratch path: destroy `kubia`, let the GitHub Actions pipeline recreate it purely from `terraform/` — proves the repo can rebuild this cluster from nothing

## Phase 2 — GitOps bootstrap
- [x] Decide ArgoCD vs Flux → **Argo CD** (see [argocd.md](argocd.md) for the reasoning)
- [x] Install the chosen controller into the cluster (this one step is the only manual/imperative install — everything after is declarative)
- [x] Point it at `gitops/` in this repo — root app-of-apps, `gitops/bootstrap/root.yaml`
- [x] Argo CD manages its own upgrades and config from `gitops/infra/argocd/` — 42 resources, `Synced`/`Healthy`
- [x] Drift correction verified on Argo CD itself: `kubectl scale` on `argocd-repo-server` 1→2 was reverted in ~2s (`Synced → OutOfSync → OperationCompleted → Synced`). Phase 3 repeats this on a real workload
- [ ] Retire the `argocd-initial-admin-secret` local admin once Keycloak is issuing logins — **more urgent now that the UI is on the public internet**, see Phase 4

## Phase 2.5 — Keycloak as OIDC provider
- [ ] Deploy Keycloak via `gitops/infra/keycloak/`
- [ ] Decide how secrets reach the cluster (sealed-secrets / external-secrets / by hand) — blocks the Argo CD client secret
- [ ] Point Argo CD at Keycloak: `configs.cm.oidc.config`, `configs.rbac.policy.csv` (`global.domain` is already correct)
- [x] Prerequisite: a real hostname + TLS — done, this pulled Phase 4 forward

## Phase 3 — First real workload
- [ ] Deploy one trivial app (e.g. a static site or hello-world container) through `gitops/apps/`
- [ ] Confirm drift correction works: manually change something with `kubectl`, watch the controller revert it

## Phase 4 — In-cluster infra
Pulled forward ahead of Phase 3, because Keycloak needs a real hostname and TLS before it can do anything.

- [x] Static external IP reserved in Terraform (`terraform/network.tf`) — `34.140.41.168`, so DNS can point somewhere that outlives any Kubernetes object
- [x] Ingress controller — ingress-nginx via `gitops/infra/ingress-nginx/`, pinned to that IP
- [x] DNS — `argocd.koufan.dev` A record at Spaceship (registrar-managed; koufan.dev is not in Cloud DNS)
- [x] cert-manager for TLS — `gitops/infra/cert-manager/`, with Let's Encrypt issuers in `gitops/infra/cert-manager-issuers/`
- [x] Argo CD served at https://argocd.koufan.dev on a real Let's Encrypt certificate, auto-renewing
- [ ] **Decide how to protect the publicly-reachable Argo CD UI** — it is now on the open internet with a static admin password. Options: leave it until Keycloak lands, restrict by source IP at the ingress, or put it behind auth sooner
- [ ] Basic observability (metrics-server at minimum)

## Phase 5 — Expand
- [ ] Add more workloads as they come up
- [ ] Consider Helm/Kustomize overlays for environment separation, if ever needed

## Non-goals (for now)
- Multi-cluster / multi-environment setups
- CI pipeline for building images (out of scope — this repo starts *after* an image exists)
