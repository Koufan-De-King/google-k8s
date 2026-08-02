# Roadmap

Tracks the bootstrap sequence for this repo. Update as phases complete — this file is the honest current status, not an aspirational plan.

## Phase 0 — Repo scaffolding
- [x] Initialize repo, README, LICENSE
- [x] Write architecture docs

## Phase 1 — Infrastructure (Terraform)
- [ ] `terraform/` module provisioning a GKE cluster (start small: single zone, minimal node pool)
- [ ] Remote state backend (GCS bucket) instead of local state
- [ ] `terraform apply` produces a working, empty cluster

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
