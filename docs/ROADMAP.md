# Roadmap

Tracks the bootstrap sequence for this repo. Update as phases complete — this file is the honest current status, not an aspirational plan.

## Phase 0 — Repo scaffolding
- [x] Initialize repo, README, LICENSE
- [x] Write architecture docs

## Phase 1 — Infrastructure (Terraform)
- [x] Cluster created manually (`gcloud container clusters create kubia`, zonal, 3x e2-medium, 50GB disks — kept under the free-tier 250GB disk quota) — 2026-08-02
- [x] `terraform/` module written describing that same cluster (see [ARCHITECTURE.md](ARCHITECTURE.md#state--applying-changes))
- [x] CI wired up: GitHub Actions plans on PR and on `main`; applies only on manual dispatch (see [github-actions-auth.md](github-actions-auth.md))
- [ ] Remote state backend (GCS bucket) created and wired up
- [ ] Existing `kubia` cluster imported into Terraform state (see [terraform-import.md](terraform-import.md)) — one-time, adopts the cluster you already created without recreating it
- [ ] `terraform plan` shows no diff after import (config matches reality exactly)
- [ ] Test the from-scratch path: destroy `kubia`, let the GitHub Actions pipeline recreate it purely from `terraform/` — proves the repo can rebuild this cluster from nothing

## Phase 2 — GitOps bootstrap
- [ ] Decide ArgoCD vs Flux (see [ARCHITECTURE.md](ARCHITECTURE.md))
- [ ] Install the chosen controller into the cluster (this one step is the only manual/imperative install — everything after is declarative)
- [ ] Point it at `gitops/` in this repo

## Phase 3 — First real workload
- [ ] Deploy one trivial app (e.g. a static site or hello-world container) through `gitops/apps/`
- [ ] Confirm drift correction works: manually change something with `kubectl`, watch the controller revert it

## Phase 4 — In-cluster infra
- [ ] Ingress controller
- [ ] cert-manager for TLS
- [ ] Basic observability (metrics-server at minimum)

## Phase 5 — Expand
- [ ] Add more workloads as they come up
- [ ] Consider Helm/Kustomize overlays for environment separation, if ever needed

## Non-goals (for now)
- Multi-cluster / multi-environment setups
- CI pipeline for building images (out of scope — this repo starts *after* an image exists)
