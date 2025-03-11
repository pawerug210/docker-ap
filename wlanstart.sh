#!/bin/bash -e

# Check if running in privileged mode
if [ ! -w "/sys" ] ; then
    echo "[Error] Not running in privileged mode."
    exit 1
fi

# Default values
true ${INTERFACE:=wlan0}
true ${SUBNET:=192.168.254.0}
true ${AP_ADDR:=192.168.254.1}
true ${SSID:=docker-ap}
true ${CHANNEL:=11}
true ${WPA_PASSPHRASE:=passw0rd}
true ${HW_MODE:=g}
true ${DRIVER:=nl80211}
true ${HT_CAPAB:=[HT40-][SHORT-GI-20][SHORT-GI-40]}
true ${MODE:=host}

# Attach interface to container in guest mode
if [ "$MODE" == "guest"  ]; then
    echo "Attaching interface to container"

    CONTAINER_ID=$(cat /proc/self/cgroup | grep -o  -e "/docker/.*" | head -n 1| sed "s/\/docker\/\(.*\)/\\1/")
    CONTAINER_PID=$(docker inspect -f '{{.State.Pid}}' ${CONTAINER_ID})
    CONTAINER_IMAGE=$(docker inspect -f '{{.Config.Image}}' ${CONTAINER_ID})

    docker run -t --privileged --net=host --pid=host --rm --entrypoint /bin/sh ${CONTAINER_IMAGE} -c "
        PHY=\$(echo phy\$(iw dev ${INTERFACE} info | grep wiphy | tr ' ' '\n' | tail -n 1))
        iw phy \$PHY set netns ${CONTAINER_PID}
    "

    ip link set ${INTERFACE} name wlan0

    INTERFACE=wlan0
fi

if [ ! -f "/etc/hostapd.conf" ] ; then
    cat > "/etc/hostapd.conf" <<EOF
interface=${INTERFACE}
driver=${DRIVER}
ssid=${SSID}
hw_mode=${HW_MODE}
channel=${CHANNEL}
wpa=2
wpa_passphrase=${WPA_PASSPHRASE}
wpa_key_mgmt=WPA-PSK
# TKIP is no secure anymore
#wpa_pairwise=TKIP CCMP
wpa_pairwise=CCMP
rsn_pairwise=CCMP
wpa_ptk_rekey=600
ieee80211n=1
ht_capab=${HT_CAPAB}
wmm_enabled=1 
EOF

fi

# unblock wlan
rfkill unblock wlan

echo "Setting interface ${INTERFACE}"

# Setup interface and restart DHCP service 
ip link set ${INTERFACE} up
ip addr flush dev ${INTERFACE}
ip addr add ${AP_ADDR}/24 dev ${INTERFACE}

# NAT settings
echo "Setting up traffic redirection..."

# Clear existing rules
iptables -t nat -F
iptables -F FORWARD

# DNS redirection - force all DNS queries to be handled by our AP
iptables -t nat -A PREROUTING -i ${INTERFACE} -p udp --dport 53 -j DNAT --to ${AP_ADDR}
iptables -t nat -A PREROUTING -i ${INTERFACE} -p tcp --dport 53 -j DNAT --to ${AP_ADDR}

# HTTP/HTTPS redirection - capture all web traffic
iptables -t nat -A PREROUTING -i ${INTERFACE} -p tcp --dport 80 -j DNAT --to ${AP_ADDR}:8000
iptables -t nat -A PREROUTING -i ${INTERFACE} -p tcp --dport 443 -j DNAT --to ${AP_ADDR}:8000

# We need these rules for DNS and HTTP redirections to work properly
iptables -t nat -A POSTROUTING -j MASQUERADE
iptables -A FORWARD -i ${INTERFACE} -j ACCEPT

# Block all other outgoing traffic
iptables -A FORWARD -j DROP

echo "Configuring DHCP server .."

# Create required directories
mkdir -p /var/lib/misc
touch /var/lib/misc/udhcpd.leases

# Configure udhcpd
cat > "/etc/udhcpd.conf" <<EOF
interface ${INTERFACE}
start ${SUBNET::-1}100
end ${SUBNET::-1}200
option subnet 255.255.255.0
option router ${AP_ADDR}
lease_file /var/lib/misc/udhcpd.leases
EOF

echo "Starting DHCP server .."
udhcpd -f /etc/udhcpd.conf &

echo "Starting HostAP daemon ..."
/usr/sbin/hostapd /etc/hostapd.conf

