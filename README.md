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
├── terraform/         # GKE cluster + supporting GCP infra
├── .github/workflows/ # CI: terraform plan on PR + main, apply on manual dispatch
├── gitops/            # Desired cluster state, synced by ArgoCD/Flux
│   ├── infra/          # In-cluster infra: ingress, cert-manager, etc.
│   └── apps/            # Actual workloads
├── docs/               # Architecture notes, roadmap, decisions
└── README.md
```

(`gitops/` is the target shape — doesn't exist yet. See status below.)

## Status

The GKE cluster (`kubia`) exists and is healthy — created manually to get moving, now being adopted into Terraform (see [docs/terraform-import.md](docs/terraform-import.md)) so all future changes go through CI instead of by hand. GitOps controller not yet chosen or installed; nothing is deployed on the cluster yet.

Track progress in [docs/ROADMAP.md](docs/ROADMAP.md).

## Prerequisites

- A GCP project with billing enabled
- `gcloud`, `terraform`, and `kubectl` installed locally
- (Once a GitOps controller is chosen) its CLI, e.g. `argocd` or `flux`

## Applying infrastructure changes

Changes to `terraform/` go through GitHub Actions, not local `terraform apply` — see [docs/github-actions-auth.md](docs/github-actions-auth.md) for the one-time GCP setup this depends on (state bucket + auth).

The flow is:

1. Open a PR touching `terraform/`. CI runs `fmt`, `validate`, and `plan`. **Read the plan.** Nothing has touched GCP at this point.
2. Merge. `main` re-plans, but still applies nothing.
3. When you actually want the change to be real: Actions tab → **Terraform** → *Run workflow* → branch `main`. That run plans and then applies.

Applying is manual on purpose — see [the reasoning in ARCHITECTURE.md](docs/ARCHITECTURE.md#state--applying-changes). Short version: the infra layer has no self-correcting controller behind it, and this repo has already lost a live node pool to an apply nobody read first.

## License

MIT — see [LICENSE](LICENSE).
