# Destroying and rebuilding the cluster

The roadmap's most meaningful test: destroy `kubia` entirely, rebuild it from this repo alone, and see whether the claim on the front page — *if the cluster disappeared tomorrow, `terraform apply` plus a GitOps sync should bring it back* — is actually true.

This document is the procedure and, more usefully, the list of things that do **not** come back on their own.

## What each side owns

| | Destroyed | Survives |
|---|---|---|
| **Terraform-managed** | GKE cluster `kubia`, its node pool, the static IP `ingress-nginx-ip` | — |
| **In-cluster** | Everything: Argo CD, ingress-nginx, cert-manager, every issued certificate | — |
| **Not Terraform-managed** | — | GCS state bucket, `terraform-ci` service account and its IAM, the WIF pool and provider, this repository, the DNS record at Spaceship |

That asymmetry is deliberate. The pipeline that rebuilds the cluster is not itself destroyed by running the destroy — which is the only reason this test is safe to run at all.

## Destroying

Actions → **Terraform Destroy** → Run workflow. Two inputs:

- `mode` — `plan` shows what would be destroyed and changes nothing. Run this first, always.
- `confirm` — must be typed as `kubia` when `mode=destroy`. A dropdown alone is one misclick.

The workflow additionally refuses to run from any branch but `main`, and references a GitHub Environment named `destroy`.

> **Configure that environment.** Settings → Environments → `destroy` → add yourself as a required reviewer. Until you do, the environment exists but enforces nothing. With it, every destroy pauses for an explicit approval on a different screen than the one that launched it.

## Rebuilding

Three things are needed, and only the first is automatic.

### 1. Terraform, with `from_scratch` ticked

Actions → **Terraform** → Run workflow → tick **from_scratch**.

That input sets `manage_default_node_pool_removal=true` for this run only. Without it the apply fails: GKE always creates a node pool named `default-pool` alongside a new cluster, and `google_container_node_pool.default_pool` in `main.tf` wants that same name.

The variable is `false` everywhere else on purpose. Against the *existing* cluster, `true` tells the provider to delete the real running node pool — which is precisely what happened once before (see [terraform-import.md](terraform-import.md)). The correct value depends on the state of the world rather than on the code, which is why it is a dispatch-time choice and not a committed default.

### 2. Update DNS — the step that will catch you out

`terraform destroy` releases the static IP. The rebuild allocates a **new** one, and the A record at Spaceship still points at the old address.

```sh
# The new address:
gcloud compute addresses list --project=project-b3b52501-db4a-4fd7-9e7

# Update the A record at Spaceship, then confirm:
dig +short argocd.koufan.dev @8.8.8.8
```

Until that record is correct, nothing resolves, cert-manager's HTTP-01 challenges fail, and each failure counts against the Let's Encrypt production rate limit of five per hostname per hour. Fix DNS *before* Argo CD comes up and starts requesting certificates.

You must also update `loadBalancerIP` in `gitops/infra/ingress-nginx/values.yaml` to the new address and commit it, or the ingress Service will sit at `pending` forever asking for an address that no longer exists.

### 3. Re-bootstrap Argo CD

Nothing in-cluster survives, including the controller that reconciles everything else. The bootstrap is the same one-time procedure as the first time — `helm template | kubectl apply`, then apply the root Application. See [argocd.md](argocd.md).

Once the root app is running, every other component returns on its own: ingress-nginx, cert-manager, the issuers, and Argo CD's own self-management. That part genuinely is automatic, and it is the part worth watching.

## What this test actually proves

If the rebuild works, the repo can reconstruct the cluster. If it needs undocumented manual steps, those steps are gaps in this repo — and finding them is the entire purpose of running it. Add anything you discover here rather than to your memory.

Known manual steps today, all listed above: ticking `from_scratch`, updating the A record and the ingress-nginx values with the new IP, and the Argo CD bootstrap. The first is inherent to the collision between GKE's default pool and ours. The second could be removed by managing DNS in Terraform via Cloud DNS, which would mean moving nameservers off Spaceship. The third is inherent to GitOps — something has to install the thing that installs everything else.
