# docker-openvpn

## Special variables:

### `USERS`

List of users comma separated (no spaces).

Will create keys for the users passed, export the config and store at `/etc/openvpn/clients/<name>.ovpn`

### `REVOKE_USERS`

List of users to revoke comma separated (no spaces).

Will revoke the users passed and rename the configuration to `/etc/openvpn/clients/<name>-REVOKED.ovpn`.

### `S3_BUCKET`

Passing a bucket name, all contents of `/etc/openvpn/clients/*` will be pushed to this bucket, making it easier to access user configuration.

### `ROUTE_PUSH`

A list of routes separated by comma to push to clients.

Example:
`ROUTE_PUSH="10.30.0.0 255.255.0.0,10.40.0.0 255.255.0.0"`

## Testing Locally

Build the container:

```
docker build -t kylemanna/openvpn:latest .
```

Testing:

```
mkdir -p storage
docker run -v $(PWD)/storage:/etc/openvpn --env-file=.env.assume -e "MFA=true" -e "AWS_DEFAULT_REGION=ap-southeast-2" -e "NAME=openvpn-mgmt" -e "DOMAIN_NAME=vpn3.server.address" -e "ROUTE_PUSH=10.100.0.0 255.255.0.0,10.200.0.0 255.255.0.0" -p 1194:1194/udp --cap-add=NET_ADMIN kylemanna/openvpn
```