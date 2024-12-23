# Gitlab Local Test Environment

This is a repo to test Gitlab and runners.

## Prereqs
- Docker Desktop with Kubernetes enabled
- DNS name pointing to host machine running Docker

## Deploy
- Ensure the Kubernetes context is set to the docker-desktop cluster.
- Set `$env:GITLAB_HOSTNAME` environment variable (or you will be prompted during the execution of `deploy.ps1`) - e.g. `$env:GITLAB_HOSTNAME = "gitlab.example.com"`
- Run `deploy.ps1`