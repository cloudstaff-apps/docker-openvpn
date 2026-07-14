# Original credit: https://github.com/jpetazzo/dockvpn

# REVERTED 2026-07-14: back to the exact base (alpine:3.9, its packaged
# OpenVPN 2.4.6) that was proven working before tonight's rebuild. Every
# attempt to move OpenVPN forward tonight -- the packaged 2.7.5, then a
# source-built 2.5.10 with dyn-tls-crypt/cc-exit/tls-ekm stripped out --
# still broke real traffic on the affected client network. A verb-4 server
# log during that last test showed zero data-channel activity ever reaching
# the OpenVPN process after the initial handshake, which points at something
# in the network path itself, not the OpenVPN version or its config -- so
# the version swap was abandoned rather than pursued further tonight.
#
# This keeps that known-good base and carries forward only what this
# session's script/PKI work actually depends on: a working Easy-RSA
# (3.0.5-r0, previously pinned here, has no `renew` action at all -- see
# the version history above this comment) and the six ovpn_* maintenance
# scripts plus the locking/renewal support they need.
#
# Be clear about the tradeoff, not just the revert: alpine:3.9 has been EOL
# since ~2021 and OpenVPN 2.4.6 is years behind on patches (CVE-2020-15078,
# CVE-2022-0547 both apply). That EOL exposure is being deliberately
# reintroduced to get back to a connectivity baseline that's proven to work
# for real users tonight -- not a free fix, a real tradeoff made under time
# pressure, and worth revisiting once the actual network-path cause is
# found.
FROM alpine:3.9

LABEL maintainer="Kyle Manna <kyle@kylemanna.com>"

# util-linux added (wasn't in the original 3.9 image): the current
# ovpn_pki_lib's write-lock uses `flock -w` (wait-with-timeout), which
# Alpine/BusyBox's built-in `flock` applet doesn't support -- confirmed
# necessary for the maintenance scripts added below, not part of the
# original working image.
RUN apk add --update openvpn iptables bash openvpn-auth-pam google-authenticator python3 util-linux openssl && \
    pip3 install influxdb-client && \
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/*

# pamtester (used only as an operator diagnostic per docs/otp.md, not by
# any runtime script) has never had a stable-branch build on Alpine --
# edge/testing is the only place it has ever existed, on 3.9 or otherwise.
RUN apk add \
  --no-cache \
  --allow-untrusted \
  --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \
  pamtester

ENV AWSCLI_VERSION=1.16.169
RUN apk --no-cache update && \
    apk --no-cache add python py-pip py-setuptools ca-certificates groff less bash make jq gettext-dev curl wget g++ zip git && \
    pip --no-cache-dir install awscli==$AWSCLI_VERSION && \
    update-ca-certificates && \
    rm -rf /var/cache/apk/*

# Easy-RSA is intentionally NOT installed from the Alpine package repo
# (previously easy-rsa=3.0.5-r0). That version has no `renew` action at
# all -- confirmed the hard way in production this session -- so pinning
# and verifying a specific upstream release is required, not optional.
ARG EASYRSA_VERSION=3.2.6
ARG EASYRSA_SHA256=c2572990ce91112eef8d1b8e4a3b58790da95b68501785c621f69121dfbd22d7

RUN curl -fsSL \
        -o /tmp/easyrsa.tgz \
        "https://github.com/OpenVPN/easy-rsa/releases/download/v${EASYRSA_VERSION}/EasyRSA-${EASYRSA_VERSION}.tgz" && \
    echo "${EASYRSA_SHA256}  /tmp/easyrsa.tgz" | sha256sum -c - && \
    mkdir -p /opt/easy-rsa && \
    tar -xzf /tmp/easyrsa.tgz --strip-components=1 -C /opt/easy-rsa && \
    ln -sfn /opt/easy-rsa/easyrsa /usr/local/bin/easyrsa && \
    rm -f /tmp/easyrsa.tgz && \
    easyrsa version

# Needed by scripts
ENV OPENVPN /etc/openvpn
ENV EASYRSA /opt/easy-rsa
ENV EASYRSA_PKI $OPENVPN/pki
ENV EASYRSA_VARS_FILE $OPENVPN/vars

# Prevents refused client connection because of an expired CRL
ENV EASYRSA_CRL_DAYS 3650

# Certificate lifecycle management (see cert-lifecycle-overlay/ for the
# staging validation this was built and tested against).
ENV CERT_DAYS=1095 \
    CERT_WARN_DAYS=30 \
    PKI_LOCK_TIMEOUT=30 \
    PKI_WRITER=true \
    S3_ALLOW_DELETE=false \
    AUTO_RENEW_CLIENT_CERTS=true \
    AUTO_RENEW_DAYS=1095

VOLUME ["/etc/openvpn"]

# Internally uses port 1194/udp, remap using `docker run -p 443:1194/tcp`
EXPOSE 1194/udp
EXPOSE 8080/tcp

CMD ["ovpn_run"]

ADD ./bin /usr/local/bin
ADD ./bin/ovpn_pki_lib /usr/local/lib/ovpn_pki_lib
RUN chmod a+x /usr/local/bin/* && \
    chmod 0644 /usr/local/lib/ovpn_pki_lib && \
    rm -f /usr/local/bin/ovpn_pki_lib && \
    bash -n /usr/local/lib/ovpn_pki_lib && \
    bash -n /usr/local/bin/ovpn_run && \
    bash -n /usr/local/bin/ovpn_genconfig && \
    bash -n /usr/local/bin/ovpn_initpki && \
    bash -n /usr/local/bin/ovpn_cert_audit && \
    bash -n /usr/local/bin/ovpn_renew_server && \
    bash -n /usr/local/bin/ovpn_renew_user && \
    bash -n /usr/local/bin/ovpn_update_profile && \
    bash -n /usr/local/bin/ovpn_revokeclient

# Add support for OTP authentication using a PAM module
ADD ./otp/openvpn /etc/pam.d/
