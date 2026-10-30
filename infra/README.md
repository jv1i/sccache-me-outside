# Client infrastructure

OpenTofu configuration that manages:

- an Amazon Linux NativeLink CAS/execution farm with persistent EBS storage;
- the farm's SSM role, instance profile, and security group;
- an SSM document and association that keep NativeLink configured;
- an encrypted EC2 client with no inbound security-group rules;
- an SSM-only instance role;
- an SSM document and association that keep the pinned client environment
  configured;
- a security-group-to-security-group rule allowing only the client to reach
  NativeLink on TCP 50051;
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

Use the short `./rig` commands documented in the root README for setup
and daily lifecycle actions. Connections use SSM and require no SSH keys.
Resource creation and deletion are intentionally available only through
OpenTofu.

## State

Local state is gitignored and is acceptable while one person owns `apply`.
Before multiple people manage the same live resources, configure the encrypted
S3 backend shown in `backend.tf.example`.
