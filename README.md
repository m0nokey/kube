# kube-tools

Production-oriented Kubernetes CLI toolbox based on Alpine Linux 3.24. The final container runs as the unprivileged user `kube` (UID/GID 1000) and contains no compiler or build toolchain.

## Included tools

- Helm 3.21.4
- kubectl 1.36.4
- Kustomize 5.8.1
- yq 4.53.6
- bash, curl, git, jq, openssl, Python 3, tar, vim and terminal utilities

The four Go CLIs are built from pinned upstream release tags and pinned commit SHAs with Go 1.27.1 in a separate builder stage. The runtime stage contains only the resulting binaries and Alpine 3.24 packages.

## Pull and run

```bash
docker pull ghcr.io/m0nokey/kube:latest

docker run --rm -it \
  -v ~/.kube:/home/kube/.kube:ro \
  ghcr.io/m0nokey/kube:latest
```

To mount a manifests directory as well:

```bash
docker run --rm -it \
  -v ~/.kube:/home/kube/.kube:ro \
  -v "$PWD:/workspace" \
  ghcr.io/m0nokey/kube:latest
```

The local wrapper remains available:

```bash
cp config.example.yaml .kube/config
./kube.sh --build
./kube.sh
```

The real kubeconfig under `.kube/` is ignored by both Git and the Docker build context.

## Verify versions

```bash
docker run --rm --entrypoint /bin/sh ghcr.io/m0nokey/kube:latest -c '
  helm version --short
  kubectl version --client
  kustomize version
  yq --version
  python3 --version
  git --version
'
```

Supported platforms are `linux/amd64` and `linux/arm64`.

## CI, security and supply chain

[The container workflow](.github/workflows/container.yml) runs for pull requests, pushes to `main`, version tags and manual dispatches. Pull requests build, test, extract Go build metadata, generate an SPDX JSON SBOM and scan the locally built image with Trivy. Critical or High findings fail the security gate.

Trusted branch and tag events publish only after that gate passes. The published OCI manifest contains both supported architectures, provenance and an SBOM attestation. Trivy SARIF is uploaded to GitHub code scanning when event permissions allow it; an SPDX JSON SBOM is also retained as a workflow artifact.

Source tags are fetched over HTTPS and verified against immutable commit SHAs. Go modules are resolved in `-mod=readonly` mode and validated against each project's `go.sum`. No downloaded release binary is trusted without verification because all four tools are compiled from verified source instead.

## Published tags

Pushes to `main` publish:

- `latest`
- `sha-<short-sha>`

A Git tag such as `v1.2.3` additionally publishes:

- `v1.2.3`
- `1.2.3`
- `1.2`
- `1`

Images are published as `ghcr.io/m0nokey/kube:<tag>`.
