# sccache remote development rig

OpenTofu-managed Buildbarn or NativeLink farm and Linux development client on
AWS. Access uses AWS Systems Manager.

## When setting up infra from scratch

```bash
brew install awscli opentofu                  # AWS CLI and infrastructure tool
brew install --cask session-manager-plugin   # interactive shells and tunnels
aws login --profile farm                     # sign in to the AWS account
./rig setup                                  # create the farm and client
```

## Using the rig

```bash
./rig up                    # start farm and client
./rig down                  # stop both; keep their data
./rig status                # show both
./rig check                 # check both and their connection
./rig shell                 # client development shell
./rig tunnel                # farm at grpc://127.0.0.1:50051
./rig editor setup          # configure Zed/Cursor Remote SSH

./rig farm start            # farm only: start/stop/status/shell/tunnel/check
./rig client check          # client only: start/stop/status/shell/check
./rig client system-shell   # client OS shell for debugging
```

Idle machines stop on their own, by default the farm after about an hour and
the client after about three. `./rig up` starts them again; see
[infra/README.md](infra/README.md#automatic-stops).

## Configuration and access

The defaults work without a variables file. To customize instance names,
types, volumes, the farm's REAPI server, or the NativeLink version before setup:

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
$EDITOR infra/terraform.tfvars
```

After changing infrastructure or the pinned client environment, the owner can
run `tofu -chdir=infra apply`. To give another person operational access
without OpenTofu access, follow [ACCESS.md](ACCESS.md).

Local OpenTofu state is gitignored. Keep one clone as the infrastructure owner.
`tofu -chdir=infra destroy` permanently deletes the instances, EBS data, and
farm cache.
