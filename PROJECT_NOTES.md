# Submission notes

This repository is intentionally self-contained for assessment review.

Before pushing:
1. Run `docker compose up -d`.
2. Verify seed row counts.
3. Run `./scripts/backup.sh`.
4. Run `./scripts/restore.sh <backup-file>`.
5. Run Terraform fmt/init/validate/plan for both environments.
6. Review the Terraform plan artifacts produced by GitHub Actions.
7. Do not commit real AWS credentials or production database passwords.
