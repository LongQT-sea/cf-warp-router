#!/bin/sh
mount -o remount,rw /sys/fs/cgroup
mount -o remount,rw /proc/sys

mkdir -p /dev/net
mknod /dev/net/tun c 10 200

# Set root password and edit hosts file on first boot
[ ! -f /etc/machine-id ] && {
    [ -n "$PASSWORD" ] && echo "root:$PASSWORD" | chpasswd
    echo "10.11.11.1 $HOSTNAME" >> /etc/hosts
    echo "fdfd:1111:: $HOSTNAME" >> /etc/hosts
}

exec "$@"
