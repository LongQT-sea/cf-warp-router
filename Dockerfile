# CF WARP client cli container Dockerfile
# Copyright (C) 2026 Tieu Long <long025733@gmail.com>
#
# Build:
# docker build -t warp .
#
# docker run --detach -it --name warp --hostname warp \
#    -p 2222:22 \
#    --dns 1.1.1.1 \
#    --dns 2620:fe::fe \
#    --restart unless-stopped \
#    --cgroupns=private \
#    --security-opt seccomp=profile.json \
#    --security-opt apparmor=unconfined \
#    --cap-add=SYS_ADMIN \
#    --cap-add=NET_ADMIN \
#    --env PASSWORD=123 \
#    warp

FROM debian:13-slim

# Set build time variables
ARG DEBIAN_FRONTEND=noninteractive

# Set environment variables
ENV TERM="xterm-256color"

COPY warp-gui-stub /tmp/stub/DEBIAN/control
RUN <<EOF
set -e
apt-get update
apt-get install -y --no-install-recommends \
    systemd-sysv \
    bash-completion \
    dbus \
    iproute2 \
    iputils-ping \
    isc-dhcp-client \
    ifupdown2 \
    dnsmasq \
    locales \
    procps \
    cron \
    nano \
    less \
    busybox \
    openssh-server \
    ca-certificates \
    curl \
    gpg

locale-gen en_US.UTF-8
ln -s /usr/bin/busybox /usr/local/bin/wget
ln -s /usr/bin/busybox /usr/local/bin/nslookup
ln -s /usr/bin/busybox /usr/local/bin/traceroute
ln -s /usr/bin/busybox /usr/local/bin/nc
ln -s /usr/bin/busybox /usr/local/bin/brctl

# Stub package to skip ~600MB of unused GUI dependencies
dpkg-deb --build /tmp/stub /tmp/warp-gui-stub.deb
dpkg -i /tmp/warp-gui-stub.deb

# Install CF WARP
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg |
gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ trixie main" |
tee /etc/apt/sources.list.d/cloudflare-client.list

apt-get update
apt-get install -y --no-install-recommends cloudflare-warp

# Cleanup
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
rm /etc/machine-id
rm /var/lib/dbus/machine-id
find /var/log -type f -delete
EOF

# Register WARP automatically on first boot
COPY <<'EOF' /etc/systemd/system/firstboot-warp-register.service
[Unit]
After=warp-svc.service multi-user.target
ConditionFirstBoot=yes

[Service]
Type=oneshot
ExecStart=sh -c 'sleep 4 && warp-cli --accept-tos registration new'
ExecStart=sh -c 'warp-cli --accept-tos mode tunnel_only && warp-cli --accept-tos connect'

[Install]
WantedBy=multi-user.target
EOF

RUN <<EOF
systemctl enable firstboot-warp-register

sed -i '/^flush ruleset$/d' /etc/nftables.conf
echo 'include "/etc/nftables.d/*.nft"' >> /etc/nftables.conf
mkdir -p /etc/iproute2/rt_tables.d

# To avoid memory leak on warp-svc daemon
echo '0 4 * * 0 root systemctl restart warp-svc' >> /etc/cron.d/warp-svc
EOF

COPY nftables_rules.nft /etc/nftables.d/50-router.nft
COPY network_interfaces /etc/network/interfaces
COPY dnsmasq.conf /etc/dnsmasq.d/dhcp.conf

# Install AdGuard Home
RUN curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
COPY AdGuardHome.yaml /opt/AdGuardHome/AdGuardHome.yaml

# Mask unneeded services in container
RUN <<EOF
systemctl mask \
    systemd-udevd.service \
    systemd-modules-load.service \
    systemd-networkd-wait-online.service \
    proc-sys-fs-binfmt_misc.automount \
    sys-kernel-config.mount \
    sys-kernel-debug.mount \
    sys-kernel-tracing.mount
EOF

# Config journald (store in RAM only)
COPY <<EOF /etc/systemd/journald.conf.d/container.conf
[Journal]
Storage=volatile
ForwardToSyslog=no
RuntimeMaxUse=500M
EOF

# OpenSSH allow root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

COPY <<'EOF' /entrypoint.sh
#!/bin/sh
mount -o remount,rw /sys/fs/cgroup
mount -o remount,rw /proc/sys

mkdir -p /dev/net
mknod /dev/net/tun c 10 200

# Set root password and edit hosts file on first boot
if [ -n "$PASSWORD" ] && [ ! -f /etc/machine-id ]; then
    echo "root:$PASSWORD" | chpasswd
    echo "10.11.11.1 $HOSTNAME" >> /etc/hosts
    echo "fd11:1111:: $HOSTNAME" >> /etc/hosts
fi

exec "$@"
EOF
RUN chmod +x /entrypoint.sh

# Run with custom entrypoint script
ENTRYPOINT ["/entrypoint.sh"]

# Default command to systemd init
CMD ["/sbin/init"]

# Set working dir
WORKDIR "/root"

# Expose SSH
EXPOSE 22/tcp

# Shutdown gracefully
STOPSIGNAL SIGRTMIN+3

# Labels & Annotations
LABEL org.opencontainers.image.os="linux"
LABEL org.opencontainers.image.author="Tieu Long <long025733@gmail.com>"
LABEL org.opencontainers.image.description="CloudFlare WARP"

LABEL io.containers.type="system"
LABEL io.container.runtime.init="true"
