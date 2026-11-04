# TaskForge — AWS Deployment

## 1. Overview

TaskForge is deployed on an Amazon EC2 instance running Amazon Linux 2023.

Docker Compose orchestrates two services:
- FastAPI application.
- PostgreSQL 16 database.

The infrastructure is provisioned with Terraform.

## 2. Architecture

    Developer workstation
            |
            | AWS Systems Manager
            |
            v
    Amazon EC2 — Amazon Linux 2023
            |
            v
       Docker Compose
            |
       +----+----+
       |         |
       v         v
      API    PostgreSQL
       |         |
       +----+----+
            |
       Docker network

## 3. Infrastructure

| Component | Configuration |
|---|---|
| Cloud provider | AWS |
| Region | eu-north-1 |
| Compute | EC2 t3.small |
| Operating system | Amazon Linux 2023 |
| Container runtime | Docker |
| Orchestration | Docker Compose |
| Database | PostgreSQL 16 |
| Container registry | GitHub Container Registry |
| Remote administration | AWS Systems Manager |
| Infrastructure as Code | Terraform |

The EC2 security group does not expose inbound ports.

The API is bound to 127.0.0.1:8000 on the instance.
Remote access is provided through an SSM port-forwarding session.

## 4. Repository structure

    deploy/
    └── aws/
        ├── compose.yaml
        ├── .env.example
        └── README.md

## 5. Environment configuration

The deployment requires the following variables:

| Variable | Description |
|---|---|
| POSTGRES_DB | PostgreSQL database name |
| POSTGRES_USER | PostgreSQL username |
| POSTGRES_PASSWORD | PostgreSQL password |
| TASKFORGE_IMAGE | TaskForge container image |

A template is provided in .env.example.

The production .env file must be created directly on EC2.
It must never be committed to Git.

Recommended permissions:

    sudo chown root:root /opt/taskforge/.env
    sudo chmod 600 /opt/taskforge/.env

Generate a random password for a new database:

    openssl rand -hex 32

Do not replace the password of an initialized database
by simply editing the environment file. PostgreSQL
credentials must also be rotated inside PostgreSQL.

## 6. Deploying the application

The deployment directory on EC2 is:

    /opt/taskforge

The versioned compose.yaml must be copied into this directory.
The production .env file must already exist.

Validate the configuration:

    sudo docker compose -p taskforge \
      --env-file /opt/taskforge/.env \
      -f /opt/taskforge/compose.yaml config --quiet

Download the images:

    sudo docker compose -p taskforge \
      --env-file /opt/taskforge/.env \
      -f /opt/taskforge/compose.yaml pull

Start or update the services:

    sudo docker compose -p taskforge \
      --env-file /opt/taskforge/.env \
      -f /opt/taskforge/compose.yaml up -d

The explicit project name taskforge preserves the
existing Compose volume naming convention.

The database volume must not be removed during routine updates.

## 7. Health checks

Inspect the running services:

    sudo docker compose -p taskforge \
      --env-file /opt/taskforge/.env \
      -f /opt/taskforge/compose.yaml ps

Inspect application logs:

    sudo docker compose -p taskforge \
      --env-file /opt/taskforge/.env \
      -f /opt/taskforge/compose.yaml logs --tail=50

Test the API from EC2:

    curl -i http://127.0.0.1:8000/health

    curl -i http://127.0.0.1:8000/health/ready

Expected responses:

    {"status":"ok"}

    {"status":"ok","database":"connected"}

## 8. Remote access through AWS Systems Manager

No SSH access is required.

From Windows PowerShell:

    $env:AWS_PROFILE = "taskforge-terraform"

    $parametersFile = Join-Path $env:TEMP "taskforge-ssm-port-forward.json"

    '{"portNumber":["8000"],"localPortNumber":["18001"]}' |
        Set-Content -Path $parametersFile -Encoding ascii

    aws ssm start-session `
        --target "<EC2_INSTANCE_ID>" `
        --document-name "AWS-StartPortForwardingSession" `
        --parameters "file://$parametersFile" `
        --region "eu-north-1"

Keep the session open.

The API is then accessible locally:

- http://127.0.0.1:18001/health
- http://127.0.0.1:18001/health/ready
- http://127.0.0.1:18001/docs

## 9. Data persistence

PostgreSQL uses the named Docker volume:

    taskforge_postgres_data

The volume survives ordinary container recreation.

It does not replace a database backup strategy.
Automated backups and recovery procedures remain future improvements.

Never use docker compose down -v during routine deployments.
This removes the database volume.

## 10. Current deployment limitations

The current deployment is operational but manually managed.

Planned improvements:

- GitHub Actions deployment automation.
- AWS IAM federation using GitHub OIDC.
- Immutable image references.
- Automated post-deployment tests.
- Application rollback strategy.
- Database backup and recovery.
- Monitoring and observability.

The deployment does not expose a public HTTPS endpoint.
Remote application access is provided through AWS Systems Manager.
