#!/bin/sh
# Configura un bridge Linux intern al contenidor per actuar com a switch L2.
# Connecta totes les interfícies eth1+ al bridge br0.
set -e

ip link add name br0 type bridge 2>/dev/null || true
ip link set br0 up

for iface in $(ls /sys/class/net/ | grep -E '^eth[1-9]'); do
    ip link set "$iface" master br0
    ip link set "$iface" up
    echo "switch: $iface → br0"
done

echo "switch: br0 actiu amb $(bridge link 2>/dev/null | grep -c 'master br0' || echo '?') ports"
