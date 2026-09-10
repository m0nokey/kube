# kube-tools

`kube-tools` is a portable, security-focused Kubernetes administration toolbox. It provides the same CLI environment on any machine without installing Kubernetes tools on the host.

## Included tools

| Tool | Version | Notes |
| --- | --- | --- |
| kubectl | 1.37.0 | Kubernetes 1.37 line |
| kubeadm | 1.37.0 | Kubernetes 1.37 line |
| crictl | 1.37.0 | Kubernetes 1.37 line |
| etcdctl | 3.7.1 | Same etcd release as etcdutl |
| etcdutl | 3.7.1 | Same etcd release as etcdctl |
| clusterctl | 1.14.2 | Cluster API release line |
| Helm | 4.2.4 | Helm 4; see compatibility note below |
| Kustomize | 5.8.1 | |
| yq | 4.53.6 | |

The runtime also includes Alpine Linux 3.24, Bash, Git, jq, OpenSSL, Python 3, Vim, curl and terminal utilities. Published images support only `linux/amd64` and `linux/arm64` (both 64-bit).

Source-built Go tools use a separate Go `1.27.1` builder stage with pinned upstream release tags and commit SHAs. The build applies one audited set of current stable Go modules, including `go.etcd.io/etcd/client/pkg/v3 v3.7.1`, and runs `go mod tidy` before compilation. `clusterctl` is the official upstream release asset with SHA256 verification. The runtime image contains no Go compiler, source tree or build toolchain.

Helm 4 is intentional, but it is a major-version upgrade and is not a drop-in replacement for Helm 3. Most Helm 3 charts and releases are expected to work, while plugins, SDK/API integrations, post-renderers, flags and automation may require changes. Test Helm 4 before production use.

## Pull and run

```bash
docker pull ghcr.io/m0nokey/kube:latest

docker run --rm -it \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --tmpfs /tmp:rw,nosuid,nodev,size=256m \
  --tmpfs /home/kube/.cache:rw,nosuid,nodev,size=128m,uid=1000,gid=1000,mode=700 \
  --tmpfs /home/kube/.config:rw,nosuid,nodev,size=64m,uid=1000,gid=1000,mode=700 \
  -v "$HOME/.kube:/home/kube/.kube:ro" \
  -v "$PWD:/workspace:ro" \
  ghcr.io/m0nokey/kube:latest
```

Inside the container:

```bash
kubectl get nodes
kubectl version --client
kubeadm version
crictl --version
etcdctl version
etcdutl version
clusterctl version
helm version
helm list -A
kubectl apply -f /workspace/app.yaml
kustomize build /workspace/overlays/prod
yq --version
```

`kubectl`'s `Server Version` is returned by the connected cluster; it is not part of this image. Keep client/server minor-version skew within the Kubernetes support policy.

## `kube.sh` wrapper

The wrapper pulls the published image once at the start of each invocation and then runs Compose with `--pull never`, so exiting the shell does not trigger another pull or container. It allocates a TTY, forwards Ctrl+C/SIGINT, uses `init: true`, and removes the temporary container on exit. The tracked Compose configuration mounts the kubeconfig and workspace read-only.

```bash
cp config.example.yaml .kube/config
./kube.sh
./kube.sh --check
./kube.sh --ctx
./kube.sh --ns
./kube.sh --logs deploy/my-app
./kube.sh kubectl get pods -A
```

Use `./kube.sh --build` only for an explicit local Docker build. It does not push to GHCR. `.kube/` and `workspace/` are ignored by Git and excluded from the Docker build context; credentials are never copied into the image.

## Security and supply chain

- Runtime runs as unprivileged user `kube` (UID/GID 1000).
- Compose uses a read-only root filesystem, dropped capabilities and `no-new-privileges`.
- Compose limits memory to 512 MiB, CPU to one core and processes to 120; `/tmp`, cache and config use temporary filesystems.
- Builder-only packages, source trees and Go caches are absent from the final image.
- Upstream source tags are fetched over HTTPS and checked against pinned commit SHAs. Release assets use SHA256 verification where provided.
- Go build metadata is extracted in CI for every CLI binary.
- No secrets are stored in the Dockerfile, build arguments, image layers or repository. Keep `.kube/config` local.

For reproducible deployments, pin a verified manifest digest instead of a mutable tag:

```bash
ghcr.io/m0nokey/kube@sha256:<verified-digest>
```

## Trivy reporting and gate

Every trusted push and pull request builds an amd64 test image before publication. Trivy runs an informational scan for `UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL` and a blocking scan for `HIGH,CRITICAL` with `exit-code: 1`.

The full informational table is written to the **Actions → Summary** page. The full all-severity SARIF report is uploaded to **Security → Code scanning** (subject to GitHub fork permissions). Medium/Low findings remain visible for follow-up; any High or Critical finding fails the workflow and prevents GHCR publication. An SPDX JSON SBOM is uploaded as a workflow artifact.

Pull requests build, test and scan but never publish an image. Only trusted pushes/tags publish after the gate passes.

## Published tags and architectures

Pushes to `main` publish `latest` and `sha-<short-sha>`. A Git tag such as `v1.2.3` publishes `v1.2.3`, `1.2.3`, `1.2` and `1`. The manifest contains only:

- `linux/amd64`
- `linux/arm64`

Old image versions may be cleaned up by the publish workflow; pin a digest for long-lived deployments.

## Development

The image definition is in [`Dockerfile`](Dockerfile), the wrapper is [`kube.sh`](kube.sh), and CI is [`.github/workflows/container.yml`](.github/workflows/container.yml). The optional verification script is [`scripts/verify-tools.sh`](scripts/verify-tools.sh).
