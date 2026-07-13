# Original credit: https://github.com/jpetazzo/dockvpn

# alpine:3.9 (EOL since ~2021, hasn't received security patches in years --
# confirmed 2026-07-13) is why the container was still running OpenVPN
# 2.4.6, several major versions and CVEs (e.g. CVE-2020-15078,
# CVE-2022-0547 -- both relevant to the deferred PAM auth this image uses)
# behind current. 3.24 is Alpine's newest supported branch (security
# support into mid-2028 as of this writing) and carries OpenVPN 2.7.x.
FROM alpine:3.24

LABEL maintainer="Kyle Manna <kyle@kylemanna.com>"

# Easy-RSA is intentionally NOT installed from the Alpine package repo
# (previously easy-rsa=3.0.5-r0). That version has no `renew` action at
# all -- confirmed the hard way in production on 2026-07-13 -- so pinning
# and verifying a specific upstream release is required, not optional.
# util-linux is required for a real `flock` binary: Alpine/BusyBox's
# built-in `flock` applet doesn't support `-w` (wait-with-timeout), which
# the PKI write-lock in ovpn_pki_lib depends on. py3-pip is separate from
# python3 on modern Alpine (no longer bundled); --break-system-packages is
# required because current pip refuses a bare system-wide install
# (PEP 668) otherwise -- there is no native Alpine package for
# influxdb-client (client-disconnect.py imports it directly), so pip is
# still required for that one dependency.
RUN apk add --update openvpn iptables bash openvpn-auth-pam google-authenticator python3 py3-pip \
        ca-certificates curl openssl tar util-linux && \
    pip3 install --no-cache-dir --break-system-packages influxdb-client && \
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/*

# pamtester (used only as an operator diagnostic per docs/otp.md, not by
# any runtime script) has never had a stable-branch build on Alpine --
# edge/testing is the only place it has ever existed, on 3.9 or 3.24 alike.
RUN apk add \
  --no-cache \
  --allow-untrusted \
  --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \
  pamtester

# AWS CLI v2, via Alpine's own community package -- a native musl/Python3
# build, not AWS's official installer (which is glibc-only and does not
# run on Alpine at all). This replaces the old Python 2 + `pip install
# awscli==1.16.169` block entirely: Python 2 has been unsupported since
# Jan 2020 and isn't packaged on modern Alpine in the first place, and
# nothing else in this image (grep confirmed) depends on the extra
# groff/less/make/jq/gettext-dev/wget/g++/zip/git tools that block used to
# pull in as a side effect -- those existed only to support the old pip
# install, not any script here.
RUN apk --no-cache add aws-cli && \
    rm -rf /var/cache/apk/*
# aws-cli v2 auto-invokes a pager for TTY-attached output; disable it so
# an interactive `docker exec ... raw ...` debugging session never hangs.
ENV AWS_PAGER=""

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
