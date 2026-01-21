# Prerequisites

## Hardware Requirements

### Management Cluster (Raspberry Pi 5)
- Raspberry Pi 5 (4GB+ RAM recommended)
- 64GB+ SD card or NVMe SSD
- Network connection (Ethernet recommended)
- Static IP address assigned via DHCP reservation
- **Hostname:** `controller.local`

### Apps Cluster (Office PC)
- AMD64 PC (8GB+ RAM, 100GB+ storage)
- Ubuntu 22.04 or 24.04 LTS
- Static IP address assigned via DHCP reservation
- **Hostname:** `server.local`

## Software Prerequisites

### On All Nodes

1. **Ubuntu 22.04/24.04 LTS** installed
2. **SSH access** configured
3. **sudo privileges** for installation user
4. **Hostnames configured:**
   ```bash
   # On Pi (mgmt cluster)
   sudo hostnamectl set-hostname controller.local

   # On PC (apps cluster)
   sudo hostnamectl set-hostname server.local
   ```

### On Your Workstation

```bash
# Git
git --version

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# kubeseal (for Sealed Secrets)
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.4/kubeseal-0.27.4-linux-amd64.tar.gz
tar -xvzf kubeseal-0.27.4-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Argo CD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
```

## Network Configuration

### DNS and IP Planning

| Host | Hostname | IP Address | Role | Notes |
|------|----------|------------|------|-------|
| Raspberry Pi 5 | controller.local | 192.168.1.10 | mgmt cluster | Pi 5 control plane |
| Office PC | server.local | 192.168.1.20 | apps cluster | Apps control plane |
| Worker 2 (optional) | worker2.local | 192.168.1.21 | apps worker | Additional node |
| Pi-hole | pihole.local | 192.168.1.53 | DNS server | LoadBalancer IP |

**Network:** `192.168.1.0/24`

**IMPORTANT:** Update these IPs to match your actual host IPs in `config.env` file.

### Update Configuration

```bash
cd homelab

# Edit config.env with your actual IPs
vim config.env

# Set:
# MGMT_IP="<your-pi-ip>"        # e.g., 192.168.1.10
# APPS_IP="<your-pc-ip>"        # e.g., 192.168.1.20
# GITHUB_USERNAME="<your-username>"
```

### /etc/hosts Configuration

Add these entries to `/etc/hosts` on your workstation:

```bash
# Homelab clusters (192.168.1.0/24 network)
192.168.1.10  controller.local controller argocd.mgmt.local grafana.mgmt.local pihole.mgmt.local
192.168.1.20  server.local server
192.168.1.53  pihole.local pihole
```

Update IPs to match your actual host addresses!

### Firewall Rules

Ensure these ports are open between nodes:

```bash
# On all nodes
sudo ufw allow 6443/tcp   # k3s API
sudo ufw allow 10250/tcp  # kubelet
sudo ufw allow 8472/udp   # Flannel VXLAN
sudo ufw allow 51820/udp  # WireGuard (k3s)
sudo ufw allow 51821/udp  # WireGuard (k3s)

# On mgmt cluster (Pi - controller.local)
sudo ufw allow 80/tcp     # Traefik HTTP
sudo ufw allow 443/tcp    # Traefik HTTPS
sudo ufw allow 53/tcp     # Pi-hole DNS
sudo ufw allow 53/udp     # Pi-hole DNS
```

## Git Repository Setup

```bash
# Fork or clone this repository
git clone https://github.com/YOUR_USERNAME/homelab.git
cd homelab

# Update config with your settings
vim config.env
# Set MGMT_IP, APPS_IP, GITHUB_USERNAME

# Source config (for use in scripts)
source config.env

# Update placeholders in files
find . -type f -name "*.yaml" -exec sed -i "s|YOUR_USERNAME|${GITHUB_USERNAME}|g" {} +

# NOTE: IP addresses are configured via config.env and scripts will use those values
# You don't need to manually update IPs in YAML files if using the bootstrap scripts

# Commit and push
git add .
git commit -m "Initial homelab configuration for controller.local and server.local"
git push origin main
```

## Pre-flight Checks

```bash
# On Pi (controller.local)
ssh ubuntu@controller.local
hostnamectl  # Should show: controller.local
ip addr      # Verify static IP
ping 8.8.8.8 # Verify internet connectivity
sudo systemctl status systemd-resolved  # Should be active
exit

# On PC (server.local)
ssh ubuntu@server.local
hostnamectl  # Should show: server.local
ip addr      # Verify static IP
ping 8.8.8.8 # Verify internet connectivity
sudo systemctl status systemd-resolved  # Should be active
exit

# From workstation - test connectivity
ping controller.local
ping server.local
ssh ubuntu@controller.local 'echo "Pi accessible"'
ssh ubuntu@server.local 'echo "PC accessible"'
```

---

**Next:** [Phase 1 - Bootstrap Management Cluster](runbooks/01-bootstrap-mgmt.sh)
