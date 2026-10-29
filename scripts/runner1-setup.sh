#!/bin/bash
# One-time bootstrap for the runner1 VM, run by hand inside the VM (formerly
# the runner1-setup ConfigMap). It formats /dev/vda, so never re-run it on a
# working VM. Not deployed by Argo; nothing in the cluster references it.
# usage: RUNNER_TOKEN=glrt-... ./runner1-setup.sh
set -e
: "${RUNNER_TOKEN:?set RUNNER_TOKEN to the runner authentication token}"

echo "=== Starting runner1 setup script ==="

# Format the scratch disk (which is already mounted as /)
echo "=== Formatting scratch disk ==="
mkfs.ext4 -F /dev/vda

# Mount the Ubuntu containerDisk image
echo "=== Mounting Ubuntu image ==="
mkdir -p /old-root
mount /dev/vdb /old-root

# Copy all contents from Ubuntu image to scratch disk
echo "=== Copying Ubuntu contents to scratch disk ==="
rsync -aAXv /old-root/ /

# Update fstab to mount scratch disk as root
echo "=== Updating fstab ==="
echo "/dev/vda / ext4 defaults 0 1" > /etc/fstab

# Create directories for Docker and builds
echo "=== Creating directories ==="
mkdir -p /docker
mkdir -p /builds

# Install Docker
echo "=== Installing Docker ==="
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

echo "=== Installing Docker GPG key ==="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "=== Adding Docker repository ==="
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list

echo "=== Installing Docker ==="
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

echo "=== Configuring Docker ==="
echo '{"data-root": "/docker"}' > /etc/docker/daemon.json
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

echo "=== Installing GitLab Runner ==="
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | bash
apt-get install -y gitlab-runner

echo "=== Registering GitLab Runner ==="
gitlab-runner register --url https://gitlab.nrp-nautilus.io --token "$RUNNER_TOKEN" --executor docker --docker-image docker:dind --name runner1 --non-interactive --docker-privileged --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" --docker-volumes "/builds:/builds"

echo "=== Starting GitLab Runner ==="
systemctl enable gitlab-runner
systemctl start gitlab-runner

echo "=== Final verification ==="
df -h
docker --version
systemctl status gitlab-runner --no-pager

echo "=== Runner1 setup completed successfully ==="

