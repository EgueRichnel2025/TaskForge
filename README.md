# TaskForge

**An End-to-End DevOps Platform**

TaskForge is an engineering project focused on building, testing, securing, distributing, deploying, and monitoring an application through reproducible DevOps practices.

The project starts with a task management API built with FastAPI and progressively evolves toward a secure, observable, and resilient platform.

> **Current status:** Phase 1 — CI/CD and Containerization implemented and validated. The API, PostgreSQL integration, automated tests, Docker image build, Trivy security scan, GitHub Actions workflow, and GHCR image publishing are operational.

## Project Objectives

TaskForge demonstrates practical DevOps engineering skills through five progressive phases:

- Automated testing and CI/CD.
- Secure containerization and image distribution.
- Cloud infrastructure provisioned as code.
- Kubernetes deployment and orchestration.
- Monitoring, resilience, and high availability.

## Project Roadmap

### Phase 1 — CI/CD and Containerization

**Status: Implemented and validated.**

- [x] Build a Python API with FastAPI.
- [x] Implement health endpoints.
- [x] Connect the API to PostgreSQL using SQLAlchemy and Psycopg.
- [x] Add automated tests with pytest.
- [x] Enforce code quality with Ruff.
- [x] Containerize the API with Docker.
- [x] Orchestrate the API and PostgreSQL with Docker Compose.
- [x] Configure container health checks.
- [x] Automate quality checks and tests with GitHub Actions.
- [x] Scan the Docker image with Trivy.
- [x] Publish the validated image to GitHub Container Registry (GHCR).
- [x] Verify that the published image can be pulled from GHCR.

### Phase 2 — Infrastructure as Code

**Status: Planned.**

- [ ] Provision AWS infrastructure using Terraform.
- [ ] Configure networking, compute resources, and access permissions.
- [ ] Manage Terraform state securely.
- [ ] Automate infrastructure formatting, validation, and planning.
- [ ] Review cloud costs and document resource cleanup procedures.

### Phase 3 — Kubernetes Deployment

**Status: Planned.**

- [ ] Deploy the application to a local Kubernetes cluster.
- [ ] Configure Deployments, Services, and application configuration.
- [ ] Configure health probes and resource limits.
- [ ] Implement horizontal scaling.
- [ ] Explore declarative deployment workflows.

### Phase 4 — Observability

**Status: Planned.**

- [ ] Collect metrics with Prometheus.
- [ ] Build Grafana dashboards.
- [ ] Configure actionable alerts.
- [ ] Monitor traffic, errors, latency, and resource utilization.
- [ ] Document incidents and troubleshooting procedures.

### Phase 5 — Resilience and High Availability

**Status: Planned.**

- [ ] Build a multi-node local Kubernetes environment.
- [ ] Explore PostgreSQL replication and automated failover.
- [ ] Configure backups and test data restoration.
- [ ] Apply network policies and TLS.
- [ ] Implement progressive delivery and automated rollback.
- [ ] Run controlled failure scenarios and measure recovery.

## Architecture

The current architecture consists of two services managed by Docker Compose.

```text
                  Developer
                      |
                      v
                GitHub repository
                      |
                      v
                GitHub Actions
                      |
             +--------+--------+
             |                 |
             v                 v
       Ruff and pytest    Docker build
                               |
                               v
                         Trivy scan
                               |
                     Scan successful
                               |
                               v
                            GHCR
                               |
                               v
                     Published Docker image


        Local application architecture

             HTTP client
                  |
                  | localhost:8001
                  v
          +-------------------+
          |   TaskForge API   |
          |      FastAPI      |
          +-------------------+
                   |
                   | Docker network: db:5432
                   v
          +-------------------+
          |    PostgreSQL     |
          +-------------------+
                   |
                   v
            Persistent volume
```

### Application Endpoints

| Endpoint | Purpose |
|---|---|
| `GET /health` | Checks whether the API responds. |
| `GET /health/ready` | Checks whether the API can access PostgreSQL. |
| `/docs` | Provides the interactive FastAPI documentation. |

With the current Docker Compose configuration, the API is exposed on port `8001` and PostgreSQL on port `5433` on the host.

Inside the Docker network, the API connects to PostgreSQL through the service name `db` on port `5432`.

## Prerequisites

- Git
- Python 3.12 for local development and tests
- Docker Desktop with the Docker Engine running
- A GitHub account to access the repository and published package

## Local Setup

### 1. Clone the repository

```bash
git clone https://github.com/EgueRichnel2025/TaskForge.git
cd TaskForge
```

### 2. Configure environment variables

Create a local environment file from the example:

```bash
cp .env.example .env
```

Edit `.env` and replace the example password with your own development password.

Keep `POSTGRES_PASSWORD` and the password in `DATABASE_URL` consistent. The example `DATABASE_URL` uses `127.0.0.1:5433` for connections from the host machine.

Do not commit `.env` or put real credentials in `.env.example`.

If you change the password after PostgreSQL has initialized its persistent volume, updating `.env` alone does not change the existing PostgreSQL role password.

### 3. Create the Python environment

In Git Bash on Windows:

```bash
python -m venv .venv
source .venv/Scripts/activate
python -m pip install -r requirements-dev.txt
```

### 4. Start the application

Make sure Docker Desktop is running, then execute:

```bash
docker compose up -d --build
```

Check the status of the services:

```bash
docker compose ps
```

Both `taskforge-api` and `taskforge-postgres` should eventually report a healthy status.

### 5. Test the endpoints

Check the API health:

```bash
curl -i http://localhost:8001/health
```

Expected response body:

```json
{"status":"ok"}
```

Check database readiness:

```bash
curl -i http://localhost:8001/health/ready
```

Expected response body:

```json
{"status":"ok","database":"connected"}
```

Both endpoints should return HTTP `200` when the services are healthy.

### 6. Stop the services

```bash
docker compose down
```

This command preserves the PostgreSQL volume.

**Warning:** `docker compose down -v` also removes the declared volume and deletes the database data stored in it. Use it only when you intentionally want to remove that data.

## Development and Testing

Activate the virtual environment before running development commands:

```bash
source .venv/Scripts/activate
```

Run Ruff:

```bash
python -m ruff check app tests
```

Run the test suite:

```bash
python -m pytest -v
```

The current tests verify the API health endpoint and its ability to reach PostgreSQL.

The database must be accessible and the local environment variables must be configured for the integration tests to pass.

## Continuous Integration and Security

The workflow is defined in `.github/workflows/ci.yml`.

It runs on pushes to `main` and pull requests targeting `main`.

The workflow performs these steps:

1. Set up Python and install dependencies.
2. Run Ruff and pytest using a temporary PostgreSQL service.
3. Build the Docker image.
4. Scan the image with Trivy.
5. Publish the image to GHCR only after the preceding checks succeed and the event is a push to `main`.

The Trivy configuration fails the workflow when it detects HIGH or CRITICAL vulnerabilities for which fixes are available, according to the configured scan options.

Pull requests are checked but do not publish container images.

## Published Docker Image

The TaskForge API image is published to GitHub Container Registry:

```text
ghcr.io/eguerichnel2025/taskforge
```

Pull the latest published image:

```bash
docker pull ghcr.io/eguerichnel2025/taskforge:latest
```

Inspect the downloaded image:

```bash
docker image inspect ghcr.io/eguerichnel2025/taskforge:latest
```

The workflow publishes two tags:

- `latest` for the most recently published image.
- The full Git commit SHA for a traceable version of the image.

The commit-specific tag helps identify which source revision produced a particular image.

The Docker Compose configuration in this repository builds the API locally from the Dockerfile. Pulling the GHCR image separately verifies that the published artifact is retrievable.

## Engineering Principles

- Build incrementally and verify each change.
- Keep commits small, descriptive, and meaningful.
- Automate repeatable checks wherever possible.
- Never commit passwords, access keys, or other secrets.
- Document real failures, their root causes, and their solutions.
- Measure reliability and performance instead of making unsupported claims.
- Keep deployment and recovery procedures reproducible.
- Review cloud costs before provisioning paid resources.

## Security Notice

This repository must never contain AWS credentials, database passwords, unencrypted secrets, or Terraform state files.

Local environment files such as `.env` are excluded from version control and the Docker build context. Environment-specific credentials must be supplied outside the application image.

Cloud resources will be created only after reviewing their potential costs and the appropriate cleanup procedure.
