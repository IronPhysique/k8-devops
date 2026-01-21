# Prerequisites

## Hardware Requirements

### Management Cluster (Raspberry Pi 5)
- Raspberry Pi 5 (4GB+ RAM)
- 64GB+ SD card or NVMe SSD
- Network connection (Ethernet recommended)
- Static IP via DHCP reservation
- **Hostname:** `controller.local`

### Apps Cluster (Office PC)
- AMD64 PC (8GB+ RAM, 100GB+ storage)
- Ubuntu 22.04 or 24.04 LTS
- Static IP via DHCP reservation
- **Hostname:** `server.local`

## Software Prerequisites

### On All Nodes

1. Ubuntu 22.04/24.04 LTS installed
2. SSH access configured
3. sudo privileges for installation user
4. Hostnames configured:
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

# ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
```

## Network Configuration

### Example IP Planning

| Host | Hostname | IP Address | Role |
|------|----------|------------|------|
| Raspberry Pi 5 | controller.local | 192.168.1.10 | mgmt cluster |
| Office PC | server.local | 192.168.1.20 | apps cluster |
| Pi-hole | pihole.local | Via mgmt cluster IP | DNS server |

**Update these IPs to match your network!**

### /etc/hosts Configuration

Add to `/etc/hosts` on your workstation:

```bash
# Homelab clusters
192.168.1.10  controller.local controller argocd.local grafana.local pihole.local
192.168.1.20  server.local server
```

### Firewall Rules

```bash
# On all nodes
sudo ufw allow 6443/tcp   # k3s API
sudo ufw allow 10250/tcp  # kubelet
sudo ufw allow 8472/udp   # Flannel VXLAN

# On mgmt cluster (Pi)
sudo ufw allow 80/tcp     # HTTP
sudo ufw allow 443/tcp    # HTTPS
sudo ufw allow 53/tcp     # DNS
sudo ufw allow 53/udp     # DNS
```

## Git Repository Setup

```bash
# Fork or clone repository
git clone https://github.com/YOUR_USERNAME/homelab.git
cd homelab

# Update GitHub username in files
find . -type f -name "*.yaml" -exec sed -i "s|YOUR_USERNAME|your-github-username|g" {} +

# Commit
git add .
git commit -m "Initial homelab configuration"
git push origin main
```

## Pre-flight Checks

```bash
# On Pi (controller.local)
ssh ubuntu@controller.local
hostnamectl  # Should show: controller.local
ip addr      # Verify static IP
ping 8.8.8.8 # Verify internet
exit

# On PC (server.local)
ssh ubuntu@server.local
hostnamectl  # Should show: server.local
ip addr      # Verify static IP
ping 8.8.8.8 # Verify internet
exit

# From workstation - test connectivity
ping controller.local
ping server.local
ssh ubuntu@controller.local 'echo "Pi accessible"'
ssh ubuntu@server.local 'echo "PC accessible"'
```

---

**Next:** [Quick Start Guide](quickstart.md) or run `./bootstrap/01-bootstrap-mgmt.sh`
