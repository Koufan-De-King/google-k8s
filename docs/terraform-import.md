# Importing existing infrastructure into Terraform

You already ran `gcloud container clusters create` by hand. The cluster is real and running. `terraform/main.tf` now describes that same cluster in code — but Terraform doesn't know that yet. As far as its state is concerned, this cluster doesn't exist. That gap between "what's really out there" and "what Terraform thinks exists" is exactly what `import` closes.

## The mental model

Think of Terraform state as a filing cabinet, not a construction crew. The crew (the GCP API) builds things. The cabinet just tracks "here's what I'm responsible for and its current details." `terraform apply` normally does both at once — build something, then file the paperwork.

Import skips the building step and does only the filing: "this real thing, at this address, already exists — put it in the cabinet without touching it." Nothing on GCP changes because of an import. It's a purely local, purely bookkeeping operation.

This matters because of what happens if you *skip* it. If you write `main.tf` describing a cluster that already exists and just run `terraform apply` with no import, Terraform assumes the cluster doesn't exist (empty cabinet) and tries to create it — which fails with an "already exists" error from the GCP API, or worse, silently creates a second thing with a conflicting name. Import is what lets code and reality start from the same page.

## How it's done here

`terraform/import.tf` contains two `import` blocks — one for the cluster, one for the node pool:

```hcl
import {
  to = google_container_cluster.kubia
  id = "projects/${var.project_id}/locations/${var.zone}/clusters/${var.cluster_name}"
}
```

`to` is the address in *your* config this should be filed under. `id` is how the GCP provider identifies the real resource — the format (`projects/.../locations/.../clusters/...`) is specific to each resource type and documented per-resource in the Google provider docs.

This is the modern, declarative form (Terraform ≥ 1.5), checked into the repo like everything else, rather than a one-off `terraform import <address> <id>` command typed into a terminal and forgotten. Anyone reading this repo can see exactly what was imported and why.

## Step by step, for the real kubia cluster

1. **One-time setup first** — GCS state bucket created, `backend.hcl` and `terraform.tfvars` filled in locally. See [github-actions-auth.md](github-actions-auth.md) for the bucket bootstrap; `terraform/*.example` files show what to copy.

2. **Local auth, if you haven't already:**
   ```
   gcloud auth application-default login
   ```
   This is easy to trip over: `gcloud auth login` (which you already did, to create the cluster) authenticates the `gcloud` CLI itself. It does **not** set up Application Default Credentials (ADC) — a separate credential file that Terraform's Google provider and the GCS backend both read directly, bypassing `gcloud` entirely. Without this, `terraform init` fails immediately trying to reach the state bucket, with an error like `credentials: could not find default credentials`. This command opens a browser login and writes that ADC file (`~/.config/gcloud/application_default_credentials.json`) for you. One-time, per machine, not per repo.

3. **Init:**
   ```
   cd terraform
   terraform init -backend-config=backend.hcl
   ```

4. **Plan:**
   ```
   terraform plan -var-file=terraform.tfvars
   ```
   With the import blocks present, the plan output will call out the two resources as *to be imported* rather than created. Read this plan carefully — this is the step that matters most.

   - If it says something like `2 to import, 0 to add, 0 to change` — great, the config matches reality exactly.
   - If it also proposes *changes* to the imported resources (anything other than 0 to change), stop and look closely at what's being changed. Some of that is expected and harmless (a handful of fields were deliberately left out of `main.tf` — see the comments in `main.tf` — and the provider will just fill in GCP's own defaults for those on import, no drift). But if the plan proposes something destructive — anything that says a resource **must be replaced** — do not apply. That would tear down and recreate your real cluster. Go fix `main.tf` to match the live value instead, and re-plan.
   - One specific version of this you will likely hit: `google_container_cluster.kubia must be replaced`, with `initial_node_count = 0 -> 1 # forces replacement`. This isn't a real conflict — GKE's API doesn't return a usable value for `initial_node_count` on an existing cluster, so it imports as `0` and immediately disagrees with the `1` in config. `main.tf` already works around this with a `lifecycle { ignore_changes = [initial_node_count] }` block on the cluster resource, which tells Terraform to stop comparing that field after creation. If you still see this, make sure your `terraform/main.tf` is up to date and re-run `terraform plan`.
   - A second one that looks harmless but isn't: a diff showing `remove_default_node_pool` newly appearing (e.g. `+ remove_default_node_pool = true`) under an otherwise ordinary "update in-place" plan. Unlike most attributes, this one isn't just bookkeeping — see the incident below. `main.tf` now gates it behind `var.manage_default_node_pool_removal`, defaulted to `false`, so this shouldn't reappear. If a plan ever proposes flipping it to `true` against this cluster, stop and don't apply.

## Incident: `remove_default_node_pool` deleted the real node pool

Worth recording plainly, since it's exactly the kind of mistake this repo exists to make visible rather than hide.

The first version of `main.tf` set `remove_default_node_pool = true` unconditionally, with a comment claiming it "only matters at creation time." That's wrong. The provider re-evaluates it on every apply, and when it's `true` and a pool literally named `default-pool` exists on the cluster, it deletes that pool — no exceptions for "but this pool already existed before Terraform showed up." On the real `kubia` cluster, `default-pool` *was* the actual, already-running 3-node pool (also tracked separately as `google_container_node_pool.default_pool`, per the import above). The first `apply` after import did exactly what it was told: it deleted it. Cluster came back with zero node pools.

No data was lost — nothing was deployed on the cluster yet — but it's a clean example of why "must be replaced" and "this field looks unrelated to me" both deserve a second look in a plan, not just a skim.

**The fix:** `remove_default_node_pool` is now driven by `var.manage_default_node_pool_removal`, defaulted to `false`. `main.tf` has the full explanation inline. Short version: `false` means "leave whatever default pool exists alone," which is correct for this already-imported cluster from now on. It only ever needs to become `true` for the future from-scratch recreate test in the roadmap, where there's no existing pool to accidentally delete.

**Recovery, if you're reading this because it just happened to you too:**
1. Pull the updated `main.tf`/`variables.tf` (the `manage_default_node_pool_removal` gate above).
2. `terraform plan -var-file=terraform.tfvars` — expect `google_container_node_pool.default_pool` to show as needing to be **created** (the real one is gone, so this is a genuine, safe create, not a replace of something live), and the cluster to show `remove_default_node_pool: true -> false` as a plain in-place update.
3. If that's all it shows, `terraform apply`. GKE takes a few minutes to spin up the new pool; `Nodes` in the console should repopulate once it's done.

5. **Apply** (only once the plan looks right):
   ```
   terraform apply -var-file=terraform.tfvars
   ```
   This performs the import (files the paperwork) and applies any genuinely-intended changes, if any.

6. **Verify:**
   ```
   terraform state list
   terraform plan -var-file=terraform.tfvars
   ```
   The first command should list both resources. The second should now say **no changes** — Terraform's cabinet and GCP's reality agree.

7. **Clean up:** `import.tf` has now been deleted, and this turned out to be less optional than the original note suggested.

   The claim that leaving it in place is "also fine" holds only for as long as the cluster exists. Against **empty** state — which is exactly what the destroy-and-recreate test produces — an `import` block pointing at an object that no longer exists fails the plan outright:

   ```
   Error: Cannot import non-existent remote object
   ```

   So the file that made adoption possible is the same file that blocks rebuilding from nothing. It was removed in the commit that added the destroy workflow. If a future import is ever needed — state lost, or a second cluster adopted — the blocks are recoverable from git history, and the reasoning above is the point of keeping this document.

## After this

From this point on, `kubia` is Terraform-managed. Any further change to the cluster — resizing the node pool, bumping the machine type — should go through `main.tf` and a PR, not `gcloud` or the console. That's the whole premise of this repo (see [ARCHITECTURE.md](ARCHITECTURE.md)): if it's not in Git, it's not really there.

When you later destroy this cluster to test the from-scratch pipeline path (per the roadmap), you won't need import at all — a clean `terraform apply` with no prior state will just create it directly from `main.tf`.
