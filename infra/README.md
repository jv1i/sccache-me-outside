# Client infrastructure

OpenTofu configuration that manages:

- an Amazon Linux CAS/execution farm running Buildbarn or NativeLink, with
  persistent EBS storage;
- the farm's SSM role, instance profile, and security group;
- an SSM document and association that keep the farm's server configured;
- an encrypted EC2 client with no inbound security-group rules;
- loopback-only SSH for optional editor access through SSM;
- an SSM-only instance role;
- an SSM document and association that keep the pinned client environment
  configured;
- a security-group-to-security-group rule allowing only the client to reach
  the farm's server on TCP 50051;
- Nix with flakes enabled and the pinned development flake installed under
  `/opt/reapi-dev`.

## Apply

From the repository root, the normal setup path is:

```bash
aws login --profile farm
./rig setup
```

Copy `terraform.tfvars.example` to `terraform.tfvars` first only when the
defaults need customization.

If you customized either instance name, export it as `FARM_NAME` or
`CLIENT_NAME` before running `./rig`. After changing the farm
configuration or anything in `client/`, run `tofu -chdir=infra apply`. The SSM
associations apply updates immediately to running instances or after their
next start.

Use the short `./rig` commands documented in the root README for setup,
daily lifecycle actions, and optional editor access. All connections use SSM.
Resource creation and deletion are intentionally available only through
OpenTofu.

## REAPI server

`farm_server` picks the REAPI server on the farm:

- `buildbarn`, the default: Buildbarn as sccache's `make test-reapi-buildbarn`
  runs it: `bb_storage` as the frontend, `bb_scheduler`, and one worker whose
  actions run in Ubuntu 24.04 with `build-essential`.
- `nativelink`: NativeLink at `nativelink_tag`, with its `basic_cas` example
  configuration and a worker image that adds Ubuntu 24.04 with
  `build-essential`.

Both listen on `grpc://<farm-private-ip>:50051` and need no platform
properties, so the client and sccache's configuration are the same for both.
Neither checks authentication or uses TLS.

To switch, set `farm_server` and run `tofu -chdir=infra apply`. That runs the
farm's setup again through SSM on the same instance. It replaces one server's
containers with the other's and keeps both servers' data, so switching back
finds a warm cache. Buildbarn needs `farm_volume_gb` of at least 30: its CAS
file and worker cache take up to 10 GiB, next to NativeLink's 10 GiB. A larger
`farm_volume_gb` grows the filesystem only when the farm next starts, so run
`./rig farm stop` and `./rig farm start` before switching.

## Tests

```bash
tofu -chdir=infra init -backend=false
tofu -chdir=infra test
```

The tests in `tests/` plan and apply against a mocked AWS provider, so they
need no AWS credentials and create nothing.

## State

Local state is gitignored and is acceptable while one person owns `apply`.
Before multiple people manage the same live resources, configure the encrypted
S3 backend shown in `backend.tf.example`.
