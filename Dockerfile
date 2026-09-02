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

ARG DEBIAN_FRONTEND=noninteractive

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
    ifupdown2 \
    nftables \
    isc-dhcp-client \
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

curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg |
gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ trixie main" |
tee /etc/apt/sources.list.d/cloudflare-client.list

apt-get update
apt-get install -y --no-install-recommends cloudflare-warp

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
EOF

# Cap warp-svc memory usage to 350MB
COPY <<'EOF' /etc/systemd/system/warp-svc.service.d/override.conf
[Service]
MemoryMax=400M
MemorySwapMax=400M
EOF

COPY nftables_rules.nft /etc/nftables.d/50-router.nft
COPY network_interfaces /etc/network/interfaces
COPY dnsmasq.conf /etc/dnsmasq.d/dhcp.conf

RUN curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
COPY AdGuardHome.yaml /opt/AdGuardHome/AdGuardHome.yaml

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

COPY <<EOF /etc/systemd/journald.conf.d/container.conf
[Journal]
Storage=volatile
ForwardToSyslog=no
RuntimeMaxUse=500M
EOF

RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

CMD ["/sbin/init"]

WORKDIR "/root"

EXPOSE 22/tcp

STOPSIGNAL SIGRTMIN+3

LABEL org.opencontainers.image.os="linux"
LABEL org.opencontainers.image.author="Tieu Long <long025733@gmail.com>"
LABEL org.opencontainers.image.description="Cloudflare WARP"
LABEL io.containers.type="system"
LABEL io.container.runtime.init="true"
