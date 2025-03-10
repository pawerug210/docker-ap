FROM alpine

MAINTAINER Jaka Hudoklin <offlinehacker@users.noreply.github.com>

RUN apk add --no-cache bash hostapd iptables dhcp-server-vanilla docker iproute2 iw && \
    mkdir -p /var/lib/dhcp && \
    mkdir -p /etc/dhcp && \
    touch /var/lib/dhcp/dhcpd.leases && \
    chmod 777 /var/lib/dhcp/dhcpd.leases

ADD wlanstart.sh /bin/wlanstart.sh
RUN chmod +x /bin/wlanstart.sh

ENTRYPOINT [ "/bin/wlanstart.sh" ]
