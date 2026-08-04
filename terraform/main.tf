# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------
# Deliberately no `credentials = ...` here. Locally, the provider picks up
# your `gcloud auth application-default login` credentials automatically.
# In GitHub Actions, google-github-actions/auth sets up Application Default
# Credentials (ADC) before Terraform runs — via Workload Identity Federation,
# no key file involved. Either way, "how we authenticate" stays out of this
# file. See docs/github-actions-auth.md.
provider "google" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# GKE cluster
# -----------------------------------------------------------------------------
# This resource represents the cluster you already created by hand with
# `gcloud container clusters create`. It isn't creating a new cluster right
# now — see import.tf, which tells Terraform "this resource already exists
# out there, adopt it into state instead of creating it."
resource "google_container_cluster" "kubia" {
  name     = var.cluster_name
  location = var.zone # a single zone, not a region => zonal cluster (see variables.tf note on zone)
  project  = var.project_id

  # GKE won't let you create a cluster with zero nodes, but we manage nodes
  # via the separate google_container_node_pool resource below (more
  # flexibility: independent scaling, upgrades, and machine types per pool,
  # and multiple pools later if needed). remove_default_node_pool, when
  # true, tells GKE "delete the node pool you auto-created alongside the
  # cluster" so we're not left managing a stray, untracked pool.
  #
  # This is gated behind a variable (default false) rather than hardcoded
  # true, on purpose, and it's not a stylistic choice — it's load-bearing.
  # This flag isn't a create-time-only setting the way it sounds: the
  # provider re-evaluates it on every apply, and if it's true while a pool
  # named "default-pool" exists on the cluster (imported or not), it
  # deletes that pool for real. On the actual kubia cluster, "default-pool"
  # *is* the real, already-running pool — tracked below as its own
  # resource, not something to remove. This exact combination (true,
  # against an existing default-pool) deleted the real node pool once
  # already; see docs/terraform-import.md for the full incident writeup.
  # Leave the variable at its default (false) for all normal operation.
  # It only becomes safe to set true via -var when applying against
  # genuinely empty state (no cluster exists yet), which is the only
  # scenario where "delete GKE's auto-created default pool" is actually
  # what you want.
  remove_default_node_pool = var.manage_default_node_pool_removal
  initial_node_count       = 1

  # VPC-native (alias IP) networking with auto-provisioned secondary ranges
  # for Pods and Services — this is what `gcloud container clusters create`
  # does by default with no extra networking flags, so an empty block here
  # reproduces that default rather than pinning it to the specific
  # auto-generated range names/hashes GCP assigned this one cluster (those
  # are unique per-cluster and would break re-creation elsewhere).
  ip_allocation_policy {}

  # GKE clusters default to deletion_protection = true as of recent provider
  # versions, which makes `terraform destroy` fail on purpose. That's a
  # sensible default for anything real, but this repo's roadmap explicitly
  # includes destroying and recreating this exact cluster to test the
  # from-scratch pipeline path. Leaving protection on would just mean
  # manually disabling it later anyway — being upfront about it here.
  deletion_protection = false

  # initial_node_count is a ForceNew field in the provider — change it and
  # Terraform wants to destroy + recreate the whole cluster. It's also only
  # meaningful once, at creation. The problem: on import, GKE's API doesn't
  # report a value for it the way the provider expects, so it lands in
  # state as 0. Config says 1. That mismatch alone is enough to trigger a
  # "must be replaced" plan — on a cluster that already exists and isn't
  # going anywhere. ignore_changes tells Terraform "don't compare this
  # field after the fact, only use it the moment something is actually
  # being created." Config still drives it on a genuine from-scratch apply
  # (no state yet = nothing to ignore); it just stops causing phantom
  # replacements against a cluster we imported.
  lifecycle {
    ignore_changes = [initial_node_count]
  }

  # Makes this cluster an OIDC identity provider that GCP trusts, and
  # establishes the workload pool. The pool name is not a free choice -
  # it is always PROJECT_ID.svc.id.goog.
  #
  # Cluster-level only. On its own this changes nothing for pods; the
  # node pool setting below is what actually routes credential requests
  # per-pod. Enabling one without the other is the most common way to end
  # up with Workload Identity that silently does not work.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

}

# -----------------------------------------------------------------------------
# Node pool
# -----------------------------------------------------------------------------
resource "google_container_node_pool" "default_pool" {
  name     = var.node_pool_name
  cluster  = google_container_cluster.kubia.name
  location = var.zone
  project  = var.project_id

  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD"

    # Minimum viable OAuth scopes for a node to do its job (pull images,
    # ship logs/metrics to Cloud Logging/Monitoring). The raw gcloud plan
    # included this same list — it's GKE's own sane default, not something
    # picked ad hoc, so kept as-is rather than hardcoded and forgotten.
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]

    # Replaces the per-NODE credential endpoint with a per-POD one.
    #
    # Without this, any pod can reach the node metadata server and obtain
    # the node service account credentials - which are broader than any
    # single workload should hold. This is a security improvement in its
    # own right, independent of ESO.
    #
    # THIS IS THE FIELD THAT ROLLS YOUR NODES.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }
}
