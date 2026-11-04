#!/bin/bash
set -euxo pipefail

dnf install -y docker

systemctl enable --now docker
systemctl enable --now amazon-ssm-agent

usermod -aG docker ec2-user

docker --version

systemctl is-active docker
systemctl is-active amazon-ssm-agent
