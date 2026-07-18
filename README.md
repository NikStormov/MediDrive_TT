This repository contains a production-oriented implementation for the assessment. The infrastructure was validated with `terraform validate` and selected `gcloud` bootstrap commands, but it was not fully applied to a live GCP environment as part of the submission.

## Environment bootstrap (local validation)

To validate the Terraform configuration and CI/CD authentication flow, I bootstrapped a GCP project using `gcloud`. The following services were enabled:

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  sqladmin.googleapis.com \
  servicenetworking.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  artifactregistry.googleapis.com \
  binaryauthorization.googleapis.com \
  storage.googleapis.com
```

```bash
    gcloud container clusters update <cluster_name> --enable-secret-manager --location=<location>
```

I also configured **Workload Identity Federation** for GitHub Actions and created a dedicated service account used by the CI/CD pipeline.

For local validation I temporarily used broader project-level permissions to simplify the bootstrap process. In a production setup, the CI/CD service account should use least-privilege IAM roles scoped only to the required Terraform, GKE, Artifact Registry, and Secret Manager operations.
For reproducibility, the exact `gcloud` bootstrap commands used during local validation are documented in [`docs/bootstrap-gcp.md`](docs/bootstrap-gcp.md).
