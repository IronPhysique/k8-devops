# Network Setup

## IPs (Update in config.env)

```
Network:         192.168.1.0/24
controller.local 192.168.1.10 (Pi 5)
server.local     192.168.1.20 (PC)
pihole.local     192.168.1.53 (LoadBalancer)
```

## /etc/hosts

Add to your workstation:

```
192.168.1.10  controller.local argocd.mgmt.local grafana.mgmt.local
192.168.1.20  server.local
192.168.1.53  pihole.local
```

## Router Setup

1. **Static DHCP**: Reserve .10 for Pi, .20 for PC
2. **DNS** (after Pi-hole): Set to 192.168.1.53

## Required Ports

Between nodes:
- 6443/tcp (k8s API)
- 10250/tcp (kubelet)
- 8472/udp (Flannel)

From LAN to mgmt cluster:
- 80/443 (Traefik)
- 53 (Pi-hole)

## Verify

```bash
ping 192.168.1.10
ssh ubuntu@controller.local
```
