# OpenVPN for Docker

[![Build Status](https://travis-ci.org/kylemanna/docker-openvpn.svg)](https://travis-ci.org/kylemanna/docker-openvpn)
[![Docker Stars](https://img.shields.io/docker/stars/kylemanna/openvpn.svg)](https://hub.docker.com/r/kylemanna/openvpn/)
[![Docker Pulls](https://img.shields.io/docker/pulls/kylemanna/openvpn.svg)](https://hub.docker.com/r/kylemanna/openvpn/)
[![ImageLayers](https://images.microbadger.com/badges/image/kylemanna/openvpn.svg)](https://microbadger.com/#/images/kylemanna/openvpn)
[![FOSSA Status](https://app.fossa.io/api/projects/git%2Bgithub.com%2Fkylemanna%2Fdocker-openvpn.svg?type=shield)](https://app.fossa.io/projects/git%2Bgithub.com%2Fkylemanna%2Fdocker-openvpn?ref=badge_shield)
[![Anchore Image Overview](https://anchore.io/service/badges/image/af41b351247fc340958e9c67aed342860da328339257f809c043c865679d981d)](https://anchore.io/image/dockerhub/kylemanna%2Fopenvpn%3Alatest)


OpenVPN server in a Docker container complete with an EasyRSA PKI CA.

Extensively tested on [Digital Ocean $5/mo node](http://bit.ly/1C7cKr3) and has
a corresponding [Digital Ocean Community Tutorial](http://bit.ly/1AGUZkq).

#### Upstream Links

* Docker Registry @ [kylemanna/openvpn](https://hub.docker.com/r/kylemanna/openvpn/)
* GitHub @ [kylemanna/docker-openvpn](https://github.com/kylemanna/docker-openvpn)

## Quick Start

* Pick a name for the `$OVPN_DATA` data volume container. It's recommended to
  use the `ovpn-data-` prefix to operate seamlessly with the reference systemd
  service.  Users are encourage to replace `example` with a descriptive name of
  their choosing.

      OVPN_DATA="ovpn-data-example"

* Initialize the `$OVPN_DATA` container that will hold the configuration files
  and certificates.  The container will prompt for a passphrase to protect the
  private key used by the newly generated certificate authority.

      docker volume create --name $OVPN_DATA
      docker run -v $OVPN_DATA:/etc/openvpn --log-driver=none --rm kylemanna/openvpn ovpn_genconfig -u udp://VPN.SERVERNAME.COM
      docker run -v $OVPN_DATA:/etc/openvpn --log-driver=none --rm -it kylemanna/openvpn ovpn_initpki

* Start OpenVPN server process

      docker run -v $OVPN_DATA:/etc/openvpn -d -p 1194:1194/udp --cap-add=NET_ADMIN kylemanna/openvpn

* Generate a client certificate without a passphrase

      docker run -v $OVPN_DATA:/etc/openvpn --log-driver=none --rm -it kylemanna/openvpn easyrsa build-client-full CLIENTNAME nopass

* Retrieve the client configuration with embedded certificates

      docker run -v $OVPN_DATA:/etc/openvpn --log-driver=none --rm kylemanna/openvpn ovpn_getclient CLIENTNAME > CLIENTNAME.ovpn

## Next Steps

### More Reading

Miscellaneous write-ups for advanced configurations are available in the
[docs](docs) folder.

### Systemd Init Scripts

A `systemd` init script is available to manage the OpenVPN container.  It will
start the container on system boot, restart the container if it exits
unexpectedly, and pull updates from Docker Hub to keep itself up to date.

Please refer to the [systemd documentation](docs/systemd.md) to learn more.

### Docker Compose

If you prefer to use `docker-compose` please refer to the [documentation](docs/docker-compose.md).

## Debugging Tips

* Create an environment variable with the name DEBUG and value of 1 to enable debug output (using "docker -e").

        docker run -v $OVPN_DATA:/etc/openvpn -p 1194:1194/udp --privileged -e DEBUG=1 kylemanna/openvpn

* Test using a client that has openvpn installed correctly

        $ openvpn --config CLIENTNAME.ovpn

* Run through a barrage of debugging checks on the client if things don't just work

        $ ping 8.8.8.8    # checks connectivity without touching name resolution
        $ dig google.com  # won't use the search directives in resolv.conf
        $ nslookup google.com # will use search

* Consider setting up a [systemd service](/docs/systemd.md) for automatic
  start-up at boot time and restart in the event the OpenVPN daemon or Docker
  crashes.

## How Does It Work?

Initialize the volume container using the `kylemanna/openvpn` image with the
included scripts to automatically generate:

- Diffie-Hellman parameters
- a private key
- a self-certificate matching the private key for the OpenVPN server
- an EasyRSA CA key and certificate
- a TLS auth key from HMAC security

The OpenVPN server is started with the default run cmd of `ovpn_run`

The configuration is located in `/etc/openvpn`, and the Dockerfile
declares that directory as a volume. It means that you can start another
container with the `-v` argument, and access the configuration.
The volume also holds the PKI keys and certs so that it could be backed up.

To generate a client certificate, `kylemanna/openvpn` uses EasyRSA via the
`easyrsa` command in the container's path.  The `EASYRSA_*` environmental
variables place the PKI CA under `/etc/openvpn/pki`.

Conveniently, `kylemanna/openvpn` comes with a script called `ovpn_getclient`,
which dumps an inline OpenVPN client configuration file.  This single file can
then be given to a client for access to the VPN.

To enable Two Factor Authentication for clients (a.k.a. OTP) see [this document](/docs/otp.md).

## Cloudstaff PKI Maintenance Scripts

Beyond the upstream `ovpn_genconfig` / `ovpn_initpki` / `ovpn_run` flow above, this fork adds
scripts for managing certificate lifecycle on a long-running server without ever recreating the
PKI. They're installed to `/usr/local/bin` (and `ovpn_pki_lib` to `/usr/local/lib`) by the
Dockerfile. All of them except `ovpn_pki_lib` are meant to be run against a live container, e.g.:

    docker exec <container> ovpn_cert_audit
    docker exec <container> ovpn_renew_server

- **`ovpn_pki_lib`** &mdash; not a command; a shared library every script below sources. Defines
  `log`/`warn`/`die`, the PKI write lock (`acquire_pki_lock`/`release_pki_lock`, via `flock` &mdash;
  requires the real `util-linux` `flock`, not BusyBox's, since BusyBox's doesn't support `-w`),
  certificate helpers (`cert_is_current`, `verify_cert_against_ca`, `verify_cert_key_match`,
  `cert_fingerprint`/`cert_serial`), and `backup_openvpn_state` (tars `pki/` + `clients/` into
  `/etc/openvpn/backups` before any write happens). It also works around Easy-RSA 3.1+'s
  "Missing vars file" hard-failure by creating an empty vars file if `EASYRSA_VARS_FILE` is
  exported but nothing exists there yet &mdash; this matters for any PKI that predates that
  variable, i.e. every pre-2026 production PKI.

- **`ovpn_cert_audit [--days N] [--active-users]`** &mdash; read-only. Lists every issued
  certificate's status (`VALID` / `EXPIRING_<N>D` / `EXPIRED` / `MISSING`) and expiry date.
  `--active-users` restricts the check to `$DOMAIN_NAME` plus the users currently listed in the
  `/${NAME:-openvpn}/USERS` SSM parameter, instead of every cert ever issued (including
  revoked/former users). Exits 2 if anything has expired &mdash; safe to wire into a monitoring
  check.

- **`ovpn_renew_server [--days N] [SERVER_NAME]`** &mdash; renews only the server certificate in
  place: backs up state, runs `easyrsa renew`, then verifies the CA fingerprint and private key
  are unchanged, the serial actually changed, and the new cert verifies against the CA with
  `sslserver` purpose &mdash; refuses (dies) if any check fails. Defaults to `$DOMAIN_NAME` and
  `$CERT_DAYS` (1095 days). **Requires a full container/task restart afterward** &mdash; OpenVPN
  only reads the server cert once at startup, and SIGHUP is unsafe after it drops privileges.
  Don't run `revoke-renewed` until the new cert is confirmed deployed and working.

- **`ovpn_renew_user [--days N] USER [USER ...]`** &mdash; same renew-and-verify pattern, for one
  or more client certificates. Does not touch OTP/MFA enrollment and does not regenerate `.ovpn`
  profiles &mdash; that's the deliberate next step, `ovpn_update_profile`. No restart needed: the
  server validates whatever cert a client presents at connect time, per-connection.

- **`ovpn_update_profile [--no-upload] USER [USER ...]`** &mdash; regenerates the inline `.ovpn`
  file for a user, verifies the regenerated profile actually embeds the currently-issued
  certificate (not a stale one), and uploads it to `s3://$S3_BUCKET/[$S3_PREFIX/]$USER.ovpn`
  unless `--no-upload` is passed or `S3_BUCKET` is unset. Verifies the uploaded object is
  non-empty via `head-object` before declaring success.

- **`ovpn_revokeclient CN [keep|remove]`** &mdash; revokes a client certificate and regenerates
  the CRL. `keep` (default) leaves the cert/key/request files on disk; `remove` deletes them
  after revocation.

All of these operate on one region/container at a time, by hand, on purpose &mdash; there's no
fleet-wide "renew everything" command in this repo. See `infra-cloudstaff-openvpn/scripts/` for
the tooling that drives these across the actual ECS fleet (deploying new images, running these
commands remotely via SSM, and auditing every region's cert status at once).

### Automatic client-cert renewal

`ovpn_run`'s background loop calls its user-sync routine every `$SYNCTIME` seconds (default
1800s / 30 min). As part of that cycle, if `AUTO_RENEW_CLIENT_CERTS=true` (the default) it
detects any active user whose client cert is within `$AUTO_RENEW_DAYS` of expiring and renews it
plus regenerates/re-uploads their profile automatically, using the same renew-and-verify logic as
`ovpn_renew_user`/`ovpn_update_profile` above. It doesn't touch OTP/MFA, and doesn't need a
restart, for the same reason manual client renewal doesn't.

## OpenVPN Details

We use `tun` mode, because it works on the widest range of devices.
`tap` mode, for instance, does not work on Android, except if the device
is rooted.

The topology used is `net30`, because it works on the widest range of OS.
`p2p`, for instance, does not work on Windows.

The UDP server uses`192.168.255.0/24` for dynamic clients by default.

The client profile specifies `redirect-gateway def1`, meaning that after
establishing the VPN connection, all traffic will go through the VPN.
This might cause problems if you use local DNS recursors which are not
directly reachable, since you will try to reach them through the VPN
and they might not answer to you. If that happens, use public DNS
resolvers like those of Google (8.8.4.4 and 8.8.8.8) or OpenDNS
(208.67.222.222 and 208.67.220.220).


## Security Discussion

The Docker container runs its own EasyRSA PKI Certificate Authority.  This was
chosen as a good way to compromise on security and convenience.  The container
runs under the assumption that the OpenVPN container is running on a secure
host, that is to say that an adversary does not have access to the PKI files
under `/etc/openvpn/pki`.  This is a fairly reasonable compromise because if an
adversary had access to these files, the adversary could manipulate the
function of the OpenVPN server itself (sniff packets, create a new PKI CA, MITM
packets, etc).

* The certificate authority key is kept in the container by default for
  simplicity.  It's highly recommended to secure the CA key with some
  passphrase to protect against a filesystem compromise.  A more secure system
  would put the EasyRSA PKI CA on an offline system (can use the same Docker
  image and the script [`ovpn_copy_server_files`](/docs/paranoid.md) to accomplish this).
* It would be impossible for an adversary to sign bad or forged certificates
  without first cracking the key's passphase should the adversary have root
  access to the filesystem.
* The EasyRSA `build-client-full` command will generate and leave keys on the
  server, again possible to compromise and steal the keys.  The keys generated
  need to be signed by the CA which the user hopefully configured with a passphrase
  as described above.
* Assuming the rest of the Docker container's filesystem is secure, TLS + PKI
  security should prevent any malicious host from using the VPN.


## Benefits of Running Inside a Docker Container

### The Entire Daemon and Dependencies are in the Docker Image

This means that it will function correctly (after Docker itself is setup) on
all distributions Linux distributions such as: Ubuntu, Arch, Debian, Fedora,
etc.  Furthermore, an old stable server can run a bleeding edge OpenVPN server
without having to install/muck with library dependencies (i.e. run latest
OpenVPN with latest OpenSSL on Ubuntu 12.04 LTS).

### It Doesn't Stomp All Over the Server's Filesystem

Everything for the Docker container is contained in two images: the ephemeral
run time image (kylemanna/openvpn) and the `$OVPN_DATA` data volume. To remove
it, remove the corresponding containers, `$OVPN_DATA` data volume and Docker
image and it's completely removed.  This also makes it easier to run multiple
servers since each lives in the bubble of the container (of course multiple IPs
or separate ports are needed to communicate with the world).

### Some (arguable) Security Benefits

At the simplest level compromising the container may prevent additional
compromise of the server.  There are many arguments surrounding this, but the
take away is that it certainly makes it more difficult to break out of the
container.  People are actively working on Linux containers to make this more
of a guarantee in the future.

## Differences from jpetazzo/dockvpn

* No longer uses serveconfig to distribute the configuration via https
* Proper PKI support integrated into image
* OpenVPN config files, PKI keys and certs are stored on a storage
  volume for re-use across containers
* Addition of tls-auth for HMAC security

## Originally Tested On

* Docker hosts:
  * server a [Digital Ocean](https://www.digitalocean.com/?refcode=d19f7fe88c94) Droplet with 512 MB RAM running Ubuntu 14.04
* Clients
  * Android App OpenVPN Connect 1.1.14 (built 56)
     * OpenVPN core 3.0 android armv7a thumb2 32-bit
  * OS X Mavericks with Tunnelblick 3.4beta26 (build 3828) using openvpn-2.3.4
  * ArchLinux OpenVPN pkg 2.3.4-1


## License
[![FOSSA Status](https://app.fossa.io/api/projects/git%2Bgithub.com%2Fkylemanna%2Fdocker-openvpn.svg?type=large)](https://app.fossa.io/projects/git%2Bgithub.com%2Fkylemanna%2Fdocker-openvpn?ref=badge_large)
