#!/bin/bash
# Configures NativeLink at first boot and on later OpenTofu changes. OpenTofu
# renders the placeholders and delivers updates through an SSM association.
# Logs: /var/log/cloud-init-output.log
set -euxo pipefail

dnf install -y docker
systemctl enable --now docker

mkdir -p /opt/nativelink /var/lib/nativelink
chmod 0755 /opt/nativelink /var/lib/nativelink

curl -fsSL -o /opt/nativelink/config.json5 \
  "https://raw.githubusercontent.com/TraceMachina/nativelink/__TAG__/nativelink-config/examples/basic_cas.json5"

# The NativeLink image is intentionally minimal and has no nproc binary. Resolve
# the host CPU count now and write a static value into the worker configuration.
HOST_CPU_COUNT="$(nproc)"
sed -i '/^[[:space:]]*cpu_count: {$/,/^[[:space:]]*},$/c\
          cpu_count: {\
            values: ["__CPU_COUNT__"],\
          },' /opt/nativelink/config.json5
sed -i "s/__CPU_COUNT__/$HOST_CPU_COUNT/" /opt/nativelink/config.json5
grep -q "values: \[\"$HOST_CPU_COUNT\"\]" /opt/nativelink/config.json5

BASE_IMAGE="ghcr.io/tracemachina/nativelink:__TAG__"
WORKER_IMAGE="nativelink-worker:__TAG__"
docker pull "$BASE_IMAGE"
BASE_ENTRYPOINT="$(docker image inspect --format '{{index .Config.Entrypoint 0}}' "$BASE_IMAGE")"
case "$BASE_ENTRYPOINT" in
  /nix/store/*) ;;
  *) echo "Unexpected NativeLink entrypoint: $BASE_ENTRYPOINT" >&2; exit 1 ;;
esac

# Add a normal Linux userspace to NativeLink's minimal image so uploaded Linux
# compilers have a shell, glibc, binutils and a linker available.
docker build --progress=plain --build-arg NATIVELINK_IMAGE="$BASE_IMAGE" -t "$WORKER_IMAGE" - <<'DOCKERFILE'
ARG NATIVELINK_IMAGE
FROM ${NATIVELINK_IMAGE} AS nativelink
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash build-essential ca-certificates coreutils libc6 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=nativelink /nix/store /nix/store
DOCKERFILE

# The EC2 security group controls access. By default NativeLink binds on all host
# interfaces so same-VPC clients can connect; the security group has no public
# ingress and permits port 50051 only from explicitly referenced client groups.
# CAS and work directories live on EBS and survive container recreation.
# Only one server can listen on port 50051, so remove Buildbarn's containers
# too; their data stays on disk. Stop them first: rm -f kills bb_storage before
# it saves its state.
docker stop -t 60 bb-storage bb-scheduler bb-worker bb-runner 2>/dev/null || true
docker rm -f nativelink bb-storage bb-scheduler bb-worker bb-runner 2>/dev/null || true
docker run -d --name nativelink --restart unless-stopped \
  --entrypoint "$BASE_ENTRYPOINT" \
  --log-opt max-size=10m --log-opt max-file=3 \
  -v /opt/nativelink/config.json5:/config:ro \
  -v /var/lib/nativelink:/tmp/nativelink \
  -p 0.0.0.0:50051:50051 \
  "$WORKER_IMAGE" config

docker ps --filter name=^/nativelink$ --filter status=running --format '{{.Names}}' | grep -qx nativelink
