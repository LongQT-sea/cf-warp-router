# CF WARP ROUTER
CloudFlare WARP router for Proxmox VE, enjoy a premium internet route for your VMs and containers.

**[Quick Start](#quick-start)**

## Why
Does your ISP give you a terrible international route? Does `apt/dnf upgrade` or `git clone` crawl at KB/s? Do GitHub Actions artifacts or SourceForge downloads take hours? This router sends your outbound traffic over Cloudflare's network instead, which usually turns those KB/s into MB/s.

## Features

- **Ad blocking** – work out of the box with AdGuard Home plus DNS over HTTPS upstreams preconfigured.
- **Kill switch** — if the tunnel drops, client traffic stops. No silent fallback to the plain ISP route.
- **Easy configure** — clients just tag onto VLAN `1111`; no per-device configuration.

## Quick Start

### Proxmox VE
> [!TIP]
> All the steps below can be done using the Proxmox VE web GUI, though not recommended.

> [!IMPORTANT]
> Your $BRIDGE (default is `vmbr0`) must have `VLAN aware` enabled, e.g.:<br>
> ![Enable VLAN aware on the bridge](./assets/pve_bridge_vlan_aware.png)

Obtaining OCI Images:
```sh
skopeo copy docker://docker.io/long025733/cf-warp-router:latest  oci-archive:/var/lib/vz/template/cache/cf-warp-router_latest.tar
```

Create the container:
```sh
# Configure the container
BRIDGE=             # Default: vmbr0
VLAN_ID=            # Leave empty if unsure
STORAGE=            # Default: local-lvm
VMID=               # Default: 1111
ROOT_PASSWORD=''    # Default: 123456
NAME=''             # Default: warp-router
DISK_SIZE_GB=       # Default: 4
CPU_CORE=           # Default: 2
RAM_MB=             # Default: 512

# Create the container
pct create "${VMID:=1111}" local:vztmpl/cf-warp-router_latest.tar \
  --arch amd64 --ostype debian \
  --hostname "${NAME:-warp-router}" \
  --password "${ROOT_PASSWORD:-123456}" \
  --cores "${CPU_CORE:-2}" --memory "${RAM_MB:-512}" \
  --rootfs "${STORAGE:-local-lvm}:${DISK_SIZE_GB:-4}" \
  --unprivileged 1 \
  --features nesting=1 \
  --dev0 /dev/net/tun \
  --net0 name=eth0,bridge="${BRIDGE:=vmbr0}",firewall=0,host-managed=0,"${VLAN_ID:+tag=$VLAN_ID,}"ip=dhcp,ip6=dhcp,type=veth \
  --net1 name=eth1,bridge="$BRIDGE",firewall=0,host-managed=0,type=veth \
  -onboot 1

# Finally, boot it
pct start $VMID
```

To connect VM or container to this CF WARP router:
- Make sure its NIC is in the same **VLAN-aware bridge** (default `vmbr0`).
- Edit the NIC and set **VLAN Tag** to `1111`.

![Set VLAN for VM/CT](./assets/pve_set_network_vlan.png)

> [!WARNING]
> Don't leave a second NIC on the guest. It will pick up a lease from your ISP router and traffic will prefer that path, bypassing the tunnel and the kill switch.

> [!NOTE]
> This `1111` is the client VLAN and is unrelated to `$VLAN_ID` above, which tags the router's own uplink.

---

## Docker Compose - TODO

Test run:
```sh
docker run --detach -it --name warp-router --hostname warp-router \
    -p 2222:22 \
    --dns 1.1.1.1 \
    --dns 2620:fe::fe \
    --restart unless-stopped \
    --cgroupns=private \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    --cap-add=SYS_ADMIN \
    --cap-add=NET_ADMIN \
    --env PASSWORD=123 \
    long025733/cf-warp-router
```

compose.yml
```yaml
services:
  warp-router:
    image: long025733/cf-warp-router
    container_name: warp-router
    hostname: warp-router
    restart: unless-stopped
    stdin_open: true
    tty: true
    cgroup: private
    cap_add:
      - SYS_ADMIN
      - NET_ADMIN
    security_opt:
      - seccomp=unconfined
      - apparmor=unconfined
    ports:
      - "2222:22"
    networks:
      - egress
      - warp-lan
    environment:
      - PASSWORD=123

  debian_13:
    image: debian13-systemd
    container_name: debian_13
    hostname: debian_13
    restart: unless-stopped
    stdin_open: true
    tty: true
    cap_add:
      - SYS_ADMIN
      - NET_ADMIN
    security_opt:
      - seccomp=unconfined
      - apparmor=unconfined
    ports:
      - "2223:22"
    networks:
      - warp-lan
    environment:
      - PASSWORD=123

networks:
  egress:
    driver: bridge
  warp-lan:
    driver: bridge
    internal: true
```

## Legal stuff
Not affiliated with or endorsed by Cloudflare, Inc. Cloudflare and WARP are registered trademarks of their respective owners.
