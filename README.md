# google-k8s

A personal GitOps homelab: one GKE cluster, managed entirely from this repo, built to learn Kubernetes and GitOps by running it for real rather than just reading about it.

## Goal

Everything that runs on the cluster — from the cluster itself down to individual app deployments — should be describable by, and recoverable from, the contents of this repo. No manual `kubectl apply`, no console clicking. If the cluster disappeared tomorrow, `terraform apply` + a GitOps sync should bring it back exactly as it was.

Secondary goal: use this as a hands-on way to build real intuition for GitOps, Kubernetes internals, and GCP — not just to have a working cluster.

## Architecture at a glance

The repo is split into two layers that change at very different speeds:

| Layer | Tool | Changes | Responsibility |
|---|---|---|---|
| Infrastructure | Terraform | Rarely | Provisions the GKE cluster itself and any surrounding GCP resources (networking, IAM, node pools) |
| Cluster state | ArgoCD or Flux (TBD) | Often | Continuously reconciles everything *inside* the cluster — workloads, in-cluster infra like ingress and cert-manager — against what's declared in this repo |

Terraform hands off a bare cluster; the GitOps controller takes it from there. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the reasoning behind this split and the ArgoCD-vs-Flux tradeoff (not yet decided).

## Repo layout

```
google-k8s/
├── terraform/        # GKE cluster + supporting GCP infra
├── gitops/           # Desired cluster state, synced by ArgoCD/Flux
│   ├── infra/         # In-cluster infra: ingress, cert-manager, etc.
│   └── apps/           # Actual workloads
├── docs/              # Architecture notes, roadmap, decisions
└── README.md
```

(This layout is the target shape — most of it doesn't exist yet. See status below.)

## Status

Early bootstrap stage. Nothing is deployed yet. Current focus is standing up the Terraform-managed cluster and picking a GitOps controller.

Track progress in [docs/ROADMAP.md](docs/ROADMAP.md).

## Prerequisites

- A GCP project with billing enabled
- `gcloud`, `terraform`, and `kubectl` installed locally
- (Once a GitOps controller is chosen) its CLI, e.g. `argocd` or `flux`

## License

MIT — see [LICENSE](LICENSE).
