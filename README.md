# kube-tools

`kube-tools` is a small security-hardened Kubernetes administration toolbox. It provides a consistent CLI environment without installing kubectl, Helm, Kustomize or yq on the host.

## Included versions

- kubectl 1.36.4
- kubeadm 1.36.4
- crictl 1.36.0 (Kubernetes 1.36 line)
- etcdctl 3.7.1
- etcdutl 3.7.1
- clusterctl 1.14.2
- Helm 4.2.4
- Kustomize 5.8.1
- yq 4.53.6
- Alpine Linux 3.24
- Bash, Git, jq, OpenSSL, Python 3, Vim, curl and terminal utilities

The image supports `linux/amd64` and `linux/arm64`. Kubernetes tools `kubectl`, `kubeadm` and `crictl` are kept on the 1.36 minor line; `etcdctl` and `etcdutl` use the same etcd 3.7.1 release. All Go CLI tools are built in a separate Go 1.27.1 builder stage from pinned upstream release tags and commit SHAs. The runtime image contains no Go compiler or build toolchain. Security module updates are applied during the reproducible build and the final binaries are scanned, rather than trusting an application version number alone.

Helm 4 is intentional, but it is not a drop-in replacement for Helm 3. Most Helm 3 charts and existing releases are expected to work, while CLI flags, plugins, SDK/API integrations and automation can break across this major-version boundary. Test Helm 4 before production use; choose a Helm 3 image when exact Helm 3 compatibility is required.

## Pull and run

```bash
docker pull ghcr.io/m0nokey/kube:latest

docker run --rm -it \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --tmpfs /tmp:rw,nosuid,nodev,size=256m \
  --tmpfs /home/kube/.cache:rw,nosuid,nodev,size=128m,uid=1000,gid=1000,mode=700 \
  -v "$HOME/.kube:/home/kube/.kube:ro" \
  -v "$PWD:/workspace:ro" \
  ghcr.io/m0nokey/kube:latest
```

Inside the container:

```bash
kubectl get nodes
kubeadm version
crictl --version
etcdctl version
etcdutl version
clusterctl version
helm list -A
kubectl apply -f /workspace/app.yaml
kustomize build /workspace/overlays/prod
yq --version
```

The image contains only the Kubernetes clients. `Server Version` reported by kubectl is the connected cluster's version, not part of this image. Keep the client/server minor-version skew within the Kubernetes support policy.

## `kube.sh` wrapper

The wrapper pulls the published GHCR image automatically; ordinary execution never builds locally. It allocates an interactive TTY, proxies Ctrl+C/SIGINT, and uses a short stop grace period. The mounted kubeconfig and workspace are read-only.

```bash
cp config.example.yaml .kube/config
./kube.sh
./kube.sh --check
./kube.sh --ctx
./kube.sh --ns
./kube.sh --logs deploy/my-app
./kube.sh kubectl get pods -A
```

Use `./kube.sh --build` only when an explicit local Docker build is wanted. `.kube/` and `workspace/` are ignored by Git and are never copied into the Docker build context.

## Security and supply chain

- Runtime runs as unprivileged user `kube` (UID/GID 1000).
- Compose uses a read-only root filesystem, read-only host mounts, dropped capabilities and `no-new-privileges`.
- Compose limits memory to 512 MiB, CPU to one core and processes to 120; `/tmp` and the cache use temporary filesystems.
- Builder-only packages, source trees and Go caches are absent from the final image.
- Upstream tags are fetched over HTTPS and checked against pinned commit SHAs.
- Go build metadata is extracted in CI for every CLI binary.
- GitHub Actions builds and functionally tests the image, creates an SPDX SBOM and runs Trivy. Any High or Critical finding fails the gate before publication. Trivy SARIF is uploaded when GitHub permissions allow it.

Do not put credentials in the repository or Dockerfile. Keep `.kube/config` local and use a digest when reproducibility is required:

```bash
ghcr.io/m0nokey/kube@sha256:<verified-digest>
```

## Published tags

Pushes to `main` publish `latest` and `sha-<short-sha>`. A Git tag such as `v1.2.3` publishes `v1.2.3`, `1.2.3`, `1.2` and `1`. Release tags are retained; routine `main` cleanup removes superseded tagged versions while preserving manifests required by the current multi-architecture tags. Pin a digest for long-lived deployments.

## Development

The workflow is defined in [`.github/workflows/container.yml`](.github/workflows/container.yml). Pull requests build, test and scan without publishing. Trusted pushes and tags publish only after the Critical/High Trivy gate passes.
