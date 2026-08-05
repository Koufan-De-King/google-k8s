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
- [x] Destroy path built: a separate `Terraform Destroy` workflow, dispatch-only, main-only, with a typed confirmation and a GitHub Environment approval gate (see [destroy-recreate.md](destroy-recreate.md))
- [x] Recreate path unblocked: `import.tf` removed (it fails against empty state) and a `from_scratch` dispatch input added to pass `manage_default_node_pool_removal=true`
- [ ] Configure the `destroy` GitHub Environment with yourself as a required reviewer — until then the gate exists but enforces nothing
- [ ] Actually run the test: destroy `kubia`, rebuild it purely from this repo, and record every manual step it turns out to need

## Phase 2 — GitOps bootstrap
- [x] Decide ArgoCD vs Flux → **Argo CD** (see [argocd.md](argocd.md) for the reasoning)
- [x] Install the chosen controller into the cluster (this one step is the only manual/imperative install — everything after is declarative)
- [x] Point it at `gitops/` in this repo — root app-of-apps, `gitops/bootstrap/root.yaml`
- [x] Argo CD manages its own upgrades and config from `gitops/infra/argocd/` — 42 resources, `Synced`/`Healthy`
- [x] Drift correction verified on Argo CD itself: `kubectl scale` on `argocd-repo-server` 1→2 was reverted in ~2s (`Synced → OutOfSync → OperationCompleted → Synced`). Phase 3 repeats this on a real workload
- [ ] Retire the `argocd-initial-admin-secret` local admin once Keycloak is issuing logins — **more urgent now that the UI is on the public internet**, see Phase 4

## Phase 2.5 — Keycloak as OIDC provider
- [x] Prerequisite: a real hostname + TLS — done, this pulled Phase 4 forward
- [x] Decide how secrets reach the cluster → **External Secrets Operator + GCP Secret Manager**, authenticated by Workload Identity
- [x] Workload Identity enabled on the cluster and node pool (`terraform/main.tf`) — no long-lived credential anywhere in the chain
- [x] ESO deployed (`gitops/infra/external-secrets/`) with `ClusterSecretStore` and the first `ExternalSecret` (`gitops/infra/external-secrets-config/`)
- [x] `ARGOCD_CLIENT_SECRET` flowing from Secret Manager into the `argocd-oidc-secret` Kubernetes Secret, verified by hash
- [ ] Deploy Keycloak via `gitops/infra/keycloak/` — needs its own hostname, ingress and certificate, all of which the Phase 4 machinery now provides for the cost of one annotation
- [ ] Point Argo CD at Keycloak: `configs.cm.oidc.config`, `configs.rbac.policy.csv` (`global.domain` is already correct)
- [ ] Consider a reloader so rotating a secret actually restarts its consumers — ESO updates the Secret, but nothing restarts on its own
- [ ] **Back up Keycloak's database.** It is the first state in this repo that git cannot rebuild, and the PVC is now set to delete with the StatefulSet, so there is no accidental safety net. Options: a `pg_dump` CronJob to a GCS bucket, or GCE persistent-disk snapshots
- [ ] Express realms and clients as `KeycloakRealmImport` / `KeycloakOIDCClient` CRs — this is what keeps identity *configuration* reproducible even though runtime data (sessions, user-set passwords) is not

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
- [ ] Basic observability (metrics-server at minimum) — **note this will not currently schedule**, see below

## Phase 4.5 — The cluster is out of CPU
Adding Keycloak exposed a hard limit. Three e2-medium nodes give ~2820m allocatable, and GKE's own components take ~1560m of it before any of our workloads: kube-dns 540m, fluentbit 315m, kube-proxy 300m, gke-metadata-server 300m, kube-state-metrics 105m. Enabling Workload Identity is what added that last 300m — one `gke-metadata-server` pod per node.

The cluster now sits at roughly 99% CPU *requested*. Actual utilisation is far lower, but the scheduler works on requests, so the next component simply will not schedule.

- [x] Short-term: Keycloak's CPU request lowered from 250m to 150m so it fits
- [ ] The Keycloak operator requests 300m — more than Keycloak itself. Patch it down with a Kustomize overlay over the upstream base
- [ ] Decide the real fix:
  - **Add a 4th e2-medium node** — +50GB disk (200GB of the 250GB quota), most incremental
  - **Move to e2-standard-2** (2 vCPU per node) — replaces every node, roughly doubles CPU, costs more
  - **Keep trimming requests** — free, but every component then runs without a guaranteed share, and scheduling gets fragile
- [ ] Whichever is chosen, it is a `terraform/` change and therefore another node roll

## Phase 5 — Expand
- [ ] Add more workloads as they come up
- [ ] Consider Helm/Kustomize overlays for environment separation, if ever needed

## Non-goals (for now)
- Multi-cluster / multi-environment setups
- CI pipeline for building images (out of scope — this repo starts *after* an image exists)
