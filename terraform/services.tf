# The Secret Manager API is not enabled on this project. Every gcloud
# secrets command and every ESO read fails until it is.
#
# disable_on_destroy = false is deliberate: destroying this project's
# Terraform resources should not switch off a project-wide API that other
# things may rely on. Enabling an API is close to irreversible in practice
# and should not be undone as a side effect.
resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}
