# Architecture

## The two-layer split

This repo separates concerns the same way most real GitOps setups do: **infrastructure** (the cluster itself) and **cluster state** (what runs inside it) are managed by different tools, because they change on different timescales and need different safety guarantees.

- **Terraform** provisions the GKE cluster, VPC, IAM, and node pools. This is infrastructure-as-code in the classic sense: you run `terraform plan`/`apply` yourself, changes are infrequent and deliberate, and the blast radius of a mistake is large (you can take down the whole cluster).
- **A GitOps controller** (ArgoCD or Flux — see below) runs *inside* the cluster and continuously pulls the desired state of workloads from this repo, applying it automatically. Changes here are frequent, low-risk individually, and don't require anyone to run a command — the controller notices drift and fixes it on its own.

A useful analogy: Terraform is like commissioning a building — pouring the foundation, wiring electrical, deciding room count. You don't redo that every day. The GitOps controller is like a thermostat with a very literal read of the blueprint: it's always checking "does the current state match the plan?" and nudging things back into line when it doesn't, without anyone flipping a switch.

## Why pull-based deployment (GitOps) instead of push-based CI/CD

Traditional CI/CD is push-based: a pipeline builds an image and then reaches *into* the cluster to deploy it (`kubectl apply`, `helm upgrade`, etc. run from outside). That means your CI system needs cluster credentials, and if someone manually changes something in the cluster, nothing notices or corrects it.

GitOps flips this: an agent *inside* the cluster (ArgoCD/Flux) watches this repo and pulls changes in. Benefits that matter for a learning project like this one:

- **No cluster credentials leave the cluster.** Nothing external needs prod-level access.
- **Git is the single source of truth.** `git log` on this repo *is* the deployment history.
- **Drift is self-correcting.** If you `kubectl edit` something by hand to debug, the controller will eventually revert it to match the repo — which is exactly the discipline this project is meant to enforce.

## ArgoCD vs Flux (open decision)

Both are CNCF GitOps controllers that do fundamentally the same job — reconcile cluster state against a Git repo. Neither is committed to yet; noting the tradeoff here so the decision (and reasoning) is recorded once made.

| | ArgoCD | Flux |
|---|---|---|
| UI | Built-in web UI showing live sync status, diffs, app health | Mostly CLI/GitOps-native; UI is a separate add-on (Weave GitOps or Flagger) |
| Mental model | "Applications" as first-class objects you can browse | Set of Kubernetes controllers (`kustomize-controller`, `helm-controller`) reconciling CRDs |
| Good for learning | Very visual — good for seeing sync state and drift at a glance | Forces you to understand the underlying controller/CRD mechanics more directly |
| Multi-tenancy / scale | Strong, used widely at scale in orgs | Also strong, slightly more composable/unix-y |

Given the learning goal of this repo, ArgoCD's UI is likely the easier on-ramp for *seeing* GitOps work, while Flux forces a deeper understanding of the controller pattern itself. Leaning ArgoCD first, revisit once the cluster is up — see [ROADMAP.md](ROADMAP.md).

## Directory-to-responsibility mapping

| Path | Owned by | Purpose |
|---|---|---|
| `terraform/` | You, manually | Cluster + GCP infra |
| `gitops/infra/` | GitOps controller | Cluster-wide infra: ingress controller, cert-manager, monitoring |
| `gitops/apps/` | GitOps controller | Actual workloads deployed on the cluster |
