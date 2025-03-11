FROM alpine

MAINTAINER Jaka Hudoklin <offlinehacker@users.noreply.github.com>

RUN apk add --no-cache bash hostapd iptables busybox-extras docker iproute2 iw dnsmasq && \
    mkdir -p /var/lib/misc

ADD wlanstart.sh /bin/wlanstart.sh
RUN chmod +x /bin/wlanstart.sh

ENTRYPOINT [ "/bin/wlanstart.sh" ]
