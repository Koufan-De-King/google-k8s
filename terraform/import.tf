# -----------------------------------------------------------------------------
# Import blocks — one-time adoption of the cluster you already created
# -----------------------------------------------------------------------------
# Full explanation in docs/terraform-import.md. Short version: these blocks
# tell Terraform "a real resource with this ID already exists — the next
# `terraform plan`/`apply` should adopt it into state instead of trying to
# create a new one." Nothing on GCP changes because of this file; it only
# changes what Terraform *believes* it's tracking.
#
# This is the modern (Terraform >= 1.5) declarative alternative to running
# `terraform import <address> <id>` by hand. It's checked into version
# control so the import is reproducible and reviewable, same as any other
# change here.
#
# These are safe to leave in place after the import completes — on every
# apply after the first, Terraform sees the resource is already in state
# and skips the import silently. No harm in deleting this file once you've
# confirmed the import worked, either; it's a one-time bootstrapping aid,
# not something the ongoing config depends on.

import {
  to = google_container_cluster.kubia
  id = "projects/${var.project_id}/locations/${var.zone}/clusters/${var.cluster_name}"
}

import {
  to = google_container_node_pool.default_pool
  id = "projects/${var.project_id}/locations/${var.zone}/clusters/${var.cluster_name}/nodePools/${var.node_pool_name}"
}
