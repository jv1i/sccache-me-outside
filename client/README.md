# Pinned client environment

OpenTofu installs `flake.nix` and `flake.lock` under `/opt/reapi-dev` on the
Ubuntu client. The client does not clone this infrastructure repository and
does not run an SSH server.

Connect from the local repository with:

```bash
./rig up
./rig shell
```

This opens the pinned environment, which exports
`REAPI_ENDPOINT=grpc://<farm-private-ip>:50051` and contains the Rust,
protobuf, NativeLink debugging, and benchmarking tools defined by the lock.
Clone or sync only the project being developed. Use
`./rig client system-shell` for machine-level debugging.

Run `./rig check` locally to verify both machines and their connection.
