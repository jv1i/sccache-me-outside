#!/bin/bash
# Configures Buildbarn at first boot and on later OpenTofu changes, in place of
# NativeLink. OpenTofu delivers updates through an SSM association.
# Logs: /var/log/cloud-init-output.log
#
# The images and configuration follow sccache's test-reapi-buildbarn: one
# bb_storage that keeps the CAS and the action cache and forwards Execute to
# bb_scheduler, and one worker that hardlinks inputs and needs no privileges.
set -euxo pipefail

dnf install -y docker
systemctl enable --now docker

STORAGE_IMAGE="ghcr.io/buildbarn/bb-storage:20260906T092937Z-ae61334"
SCHEDULER_IMAGE="ghcr.io/buildbarn/bb-scheduler:20261008T101024Z-582d07f"
WORKER_IMAGE="ghcr.io/buildbarn/bb-worker:20261008T101024Z-582d07f"
RUNNER_INSTALLER_IMAGE="ghcr.io/buildbarn/bb-runner-installer:20261008T101024Z-582d07f"
RUNNER_IMAGE="buildbarn-runner:24.04"

# bb_storage doesn't create its directories. The worker hardlinks between its
# build and cache directories, so both live in /var/lib/buildbarn/worker.
mkdir -p /opt/buildbarn \
  /var/lib/buildbarn/storage/cas/persistent_state /var/lib/buildbarn/storage/ac/persistent_state \
  /var/lib/buildbarn/worker/build /var/lib/buildbarn/worker/cache /var/lib/buildbarn/runner
chmod 0755 /opt/buildbarn

cat > /opt/buildbarn/storage.jsonnet <<'JSONNET'
// The action cache needs a single new block, since its entries are replaced. A
// blob must fit in one block, and the files are sparse. Without the persistent
// state, bb_storage empties both stores whenever it starts.
local blobstore(dir, keysBytes, blocksBytes, newBlocks) = {
  'local': {
    keyLocationMapOnBlockDevice: {
      file: { path: dir + '/key_location_map', sizeBytes: keysBytes },
    },
    keyLocationMapMaximumGetAttempts: 16,
    keyLocationMapMaximumPutAttempts: 64,
    oldBlocks: 2,
    currentBlocks: 6,
    newBlocks: newBlocks,
    blocksOnBlockDevice: {
      source: { file: { path: dir + '/blocks', sizeBytes: blocksBytes } },
      spareBlocks: 3,
    },
    persistent: {
      stateDirectoryPath: dir + '/persistent_state',
      minimumEpochInterval: '300s',
    },
  },
};

{
  grpcServers: [{
    listenAddresses: [':8980'],
    authenticationPolicy: { allow: {} },
  }],
  schedulers: {
    '': { endpoint: { address: 'bb-scheduler:8982' } },
  },
  maximumMessageSizeBytes: 2 * 1024 * 1024,
  contentAddressableStorage: {
    // 14 blocks of about 585 MiB, so that librustc_driver fits in one. The farm's
    // volume also keeps NativeLink's data, up to 10 GiB.
    backend: blobstore('/storage/cas', 64 * 1024 * 1024, 8 * 1024 * 1024 * 1024, 3),
    getAuthorizer: { allow: {} },
    putAuthorizer: { allow: {} },
    findMissingAuthorizer: { allow: {} },
  },
  actionCache: {
    backend: blobstore('/storage/ac', 1024 * 1024, 20 * 1024 * 1024, 1),
    getAuthorizer: { allow: {} },
    putAuthorizer: { allow: {} },
  },
  executeAuthorizer: { allow: {} },
}
JSONNET

cat > /opt/buildbarn/scheduler.jsonnet <<'JSONNET'
{
  clientGrpcServers: [{
    listenAddresses: [':8982'],
    authenticationPolicy: { allow: {} },
  }],
  workerGrpcServers: [{
    listenAddresses: [':8983'],
    authenticationPolicy: { allow: {} },
  }],
  buildQueueStateGrpcServers: [{
    listenAddresses: [':8984'],
    authenticationPolicy: { allow: {} },
  }],
  contentAddressableStorage: { grpc: { client: { address: 'bb-storage:8980' } } },
  maximumMessageSizeBytes: 2 * 1024 * 1024,
  executeAuthorizer: { allow: {} },
  modifyDrainsAuthorizer: { allow: {} },
  killOperationsAuthorizer: { allow: {} },
  synchronizeAuthorizer: { allow: {} },
  actionRouter: {
    simple: {
      platformKeyExtractor: { action: {} },
      invocationKeyExtractors: [
        { correlatedInvocationsId: {} },
        { toolInvocationId: {} },
      ],
      initialSizeClassAnalyzer: {
        defaultExecutionTimeout: '1800s',
        maximumExecutionTimeout: '7200s',
      },
    },
  },
  platformQueueWithNoWorkersTimeout: '900s',
  // Otherwise an execution that comes before the worker's first
  // synchronization fails instead of waiting in the queue.
  predeclaredPlatformQueues: [{
    instanceNamePrefix: '',
    platform: {},
    sizeClasses: [0],
  }],
}
JSONNET

# The worker has an empty platform, as NativeLink's basic_cas does, so sccache
# needs no platform properties for either server.
cat > /opt/buildbarn/worker.jsonnet <<'JSONNET'
local storage = { grpc: { client: { address: 'bb-storage:8980' } } };

{
  blobstore: {
    contentAddressableStorage: storage,
    actionCache: storage,
  },
  portalUrl: 'http://localhost/browser',
  maximumMessageSizeBytes: 2 * 1024 * 1024,
  scheduler: { address: 'bb-scheduler:8983' },
  buildDirectories: [{
    native: {
      buildDirectoryPath: '/worker/build',
      cacheDirectoryPath: '/worker/cache',
      maximumCacheFileCount: 10000,
      maximumCacheSizeBytes: 2 * 1024 * 1024 * 1024,
      cacheReplacementPolicy: 'LEAST_RECENTLY_USED',
    },
    runners: [{
      endpoint: { address: 'unix:///worker/runner' },
      concurrency: __CPU_COUNT__,
      instanceNamePrefix: '',
      platform: {},
      workerId: { hostname: 'bb-worker' },
    }],
  }],
  inputDownloadConcurrency: 10,
  outputUploadConcurrency: 11,
  directoryCache: {
    maximumCount: 1000,
    maximumSizeBytes: 1000 * 1024,
    cacheReplacementPolicy: 'LEAST_RECENTLY_USED',
  },
}
JSONNET
sed -i "s/__CPU_COUNT__/$(nproc)/" /opt/buildbarn/worker.jsonnet
grep -q "concurrency: $(nproc)," /opt/buildbarn/worker.jsonnet

cat > /opt/buildbarn/runner.jsonnet <<'JSONNET'
{
  buildDirectoryPath: '/worker/build',
  grpcServers: [{
    listenPaths: ['/worker/runner'],
    authenticationPolicy: { allow: {} },
  }],
}
JSONNET

docker pull "$STORAGE_IMAGE"
docker pull "$SCHEDULER_IMAGE"
docker pull "$WORKER_IMAGE"
docker pull "$RUNNER_INSTALLER_IMAGE"

# Actions run in this image, so uploaded Linux compilers have a shell, glibc,
# binutils and a linker available, as in the NativeLink worker image.
docker build --progress=plain -t "$RUNNER_IMAGE" - <<'DOCKERFILE'
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash build-essential ca-certificates coreutils libc6 \
 && rm -rf /var/lib/apt/lists/*
DOCKERFILE

# Copies bb_runner into /var/lib/buildbarn/runner and exits.
docker run --rm -v /var/lib/buildbarn/runner:/bb "$RUNNER_INSTALLER_IMAGE"
test -x /var/lib/buildbarn/runner/bb_runner

# Only one server can listen on port 50051. NativeLink's data stays on disk, so
# switching back finds its cache. Stop Buildbarn first: rm -f kills bb_storage
# before it saves its state.
docker stop -t 60 bb-storage bb-scheduler bb-worker bb-runner 2>/dev/null || true
docker rm -f nativelink bb-storage bb-scheduler bb-worker bb-runner 2>/dev/null || true
docker network inspect buildbarn >/dev/null 2>&1 || docker network create buildbarn

# The EC2 security group controls access, as for NativeLink: it permits port
# 50051 only from the client. bb_storage is the REAPI frontend.
docker run -d --name bb-storage --network buildbarn --restart unless-stopped \
  --stop-timeout 60 \
  --log-opt max-size=10m --log-opt max-file=3 \
  -v /opt/buildbarn:/config:ro \
  -v /var/lib/buildbarn/storage:/storage \
  -p 0.0.0.0:50051:8980 \
  "$STORAGE_IMAGE" /config/storage.jsonnet

docker run -d --name bb-scheduler --network buildbarn --restart unless-stopped \
  --log-opt max-size=10m --log-opt max-file=3 \
  -v /opt/buildbarn:/config:ro \
  "$SCHEDULER_IMAGE" /config/scheduler.jsonnet

# Actions get no network, and --init reaps the processes they leave behind. The
# wait below needs the new runner's socket.
rm -f /var/lib/buildbarn/worker/runner
docker run -d --name bb-runner --network none --restart unless-stopped --init \
  --log-opt max-size=10m --log-opt max-file=3 \
  -v /opt/buildbarn:/config:ro \
  -v /var/lib/buildbarn/runner:/bb:ro \
  -v /var/lib/buildbarn/worker:/worker \
  --entrypoint /bb/bb_runner \
  "$RUNNER_IMAGE" /config/runner.jsonnet

# bb_worker exits while the runner's socket is missing.
for _ in $(seq 60); do
  test -S /var/lib/buildbarn/worker/runner && break
  sleep 1
done
test -S /var/lib/buildbarn/worker/runner

docker run -d --name bb-worker --network buildbarn --restart unless-stopped \
  --log-opt max-size=10m --log-opt max-file=3 \
  -v /opt/buildbarn:/config:ro \
  -v /var/lib/buildbarn/worker:/worker \
  "$WORKER_IMAGE" /config/worker.jsonnet

sleep 5
for name in bb-storage bb-scheduler bb-runner bb-worker; do
  docker ps --filter "name=^/$name$" --filter status=running --format '{{.Names}}' | grep -qx "$name"
done
