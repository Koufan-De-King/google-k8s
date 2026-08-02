# Pin the Terraform CLI and provider versions. Without this, "it works on my
# machine" becomes a real risk: GitHub Actions might resolve a newer provider
# than what you tested locally, and a major-version bump in the google
# provider can silently change resource behavior.
terraform {
  required_version = ">= 1.7.0" # 1.7+ needed for import blocks with expressions (see import.tf)

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Remote state, stored in a GCS bucket instead of on disk.
  #
  # Why this matters: local state (the default) lives only on whichever
  # machine ran `terraform apply`. That's a non-starter the moment "applying"
  # happens from GitHub Actions runners, which are ephemeral and start fresh
  # every run — there's nowhere for local state to persist between runs.
  # A shared remote backend is what lets Terraform know what it already
  # created the next time it runs, from anywhere.
  #
  # This block is intentionally left empty ("partial configuration"). The
  # actual bucket name is supplied at `terraform init` time via
  # `-backend-config=backend.hcl` (local dev) or equivalent flags in CI.
  # That's what lets the same code work across environments/people without
  # a bucket name hardcoded into version control logic (the bucket name
  # itself isn't secret, but keeping it out of main.tf keeps this file
  # portable if you ever fork or reuse it elsewhere).
  #
  # See docs/github-actions-auth.md for how the bucket gets created and wired up.
  backend "gcs" {}
}
