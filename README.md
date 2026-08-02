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
| Cluster state | Argo CD | Often | Continuously reconciles everything *inside* the cluster — workloads, in-cluster infra like ingress and cert-manager — against what's declared in this repo |

Terraform hands off a bare cluster; Argo CD takes it from there. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the reasoning behind this split and the Argo-CD-vs-Flux decision.

## Repo layout

```
google-k8s/
├── terraform/          # GKE cluster + supporting GCP infra
├── .github/workflows/  # CI: terraform plan on PR + main, apply on manual dispatch
├── gitops/             # Desired cluster state, synced by Argo CD
│   ├── bootstrap/       # The root Application — the one thing applied by hand
│   ├── infra/           # In-cluster infra: Argo CD itself; later ingress, cert-manager
│   └── apps/            # Actual workloads
├── docs/               # Architecture notes, roadmap, decisions
└── README.md
```

A directory under `infra/` or `apps/` becomes a deployed component the moment it contains an `application.yaml` — the root app finds it and creates an Argo CD `Application` from it.

## Status

The GKE cluster (`kubia`) exists, is healthy, and is fully adopted into Terraform — CI reports no diff between the config and reality, so cluster changes now go through a PR rather than `gcloud`.

Argo CD is installed and manages itself from [gitops/infra/argocd/](gitops/infra/argocd/): upgrades and config changes happen by editing `values.yaml` and committing, not by running helm.

It is served at **https://argocd.koufan.dev** on a Let's Encrypt certificate that renews itself — behind ingress-nginx, pinned to a static IP reserved in Terraform, with certificates issued by cert-manager. Five Argo CD Applications currently reconcile the cluster: `root`, `argocd`, `ingress-nginx`, `cert-manager`, and `cert-manager-issuers`. No workloads are deployed yet.

Next up: Keycloak as an OIDC provider, replacing Argo CD's built-in admin account — which matters more now that the UI is reachable from the public internet.

Track progress in [docs/ROADMAP.md](docs/ROADMAP.md).

## Prerequisites

- A GCP project with billing enabled
- `gcloud`, `terraform`, `kubectl`, and `helm` installed locally
- `helm` is needed only for the one-time Argo CD bootstrap ([docs/argocd.md](docs/argocd.md)); after that Argo CD renders charts itself

## Applying infrastructure changes

Changes to `terraform/` go through GitHub Actions, not local `terraform apply` — see [docs/github-actions-auth.md](docs/github-actions-auth.md) for the one-time GCP setup this depends on (state bucket + auth).

The flow is:

1. Open a PR touching `terraform/`. CI runs `fmt`, `validate`, and `plan`. **Read the plan.** Nothing has touched GCP at this point.
2. Merge. `main` re-plans, but still applies nothing.
3. When you actually want the change to be real: Actions tab → **Terraform** → *Run workflow* → branch `main`. That run plans and then applies.

Applying is manual on purpose — see [the reasoning in ARCHITECTURE.md](docs/ARCHITECTURE.md#state--applying-changes). Short version: the infra layer has no self-correcting controller behind it, and this repo has already lost a live node pool to an apply nobody read first.

## License

MIT — see [LICENSE](LICENSE).
