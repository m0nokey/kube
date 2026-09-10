#!/bin/sh
set -eu

case "${TARGETARCH}" in
    amd64|arm64) ;;
    *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac

export CGO_ENABLED=0
export GOARCH="${TARGETARCH}"
export GOOS=linux
export GOTOOLCHAIN=local
export GOFLAGS=-mod=readonly

fetch_release() {
    repository="$1"
    directory="$2"
    tag="$3"
    commit="$4"

    git init -q "${directory}"
    git -C "${directory}" remote add origin "https://github.com/${repository}.git"
    git -C "${directory}" fetch -q --depth 1 origin "refs/tags/${tag}:refs/tags/${tag}"
    git -C "${directory}" checkout -q --detach "${tag}"
    test "$(git -C "${directory}" rev-parse HEAD)" = "${commit}"
}

download_checked() {
    url="$1"
    expected="$2"
    output="$3"
    curl -fsSL --retry 5 --retry-delay 2 "${url}" -o "${output}"
    printf '%s  %s\n' "${expected}" "${output}" | sha256sum -c -
}

mkdir -p /src /out

# Helm: official release source, pinned tag/commit, patched modules.
fetch_release helm/helm /src/helm "v${HELM_VERSION}" "${HELM_COMMIT}"
(
    cd /src/helm
    GOFLAGS= go get golang.org/x/crypto@v0.57.0
    GOFLAGS= go get oras.land/oras-go/v2@v2.6.2
    export GOFLAGS=-mod=readonly
    make build BINDIR=/out VERSION="v${HELM_VERSION}" GIT_COMMIT="${HELM_COMMIT}" GIT_DIRTY=clean
)

# kubectl and kubeadm: same official Kubernetes release and minor.
fetch_release kubernetes/kubernetes /src/kubernetes "v${KUBECTL_VERSION}" "${KUBECTL_COMMIT}"
(
    cd /src/kubernetes
    version_ldflags="$(bash -c '
        export KUBE_ROOT=/src/kubernetes
        source hack/lib/version.sh
        kube::version::get_version_vars
        kube::version::ldflags
    ')"
    go mod edit -module kube-tools.local/kubernetes-build
    go mod edit "-require=k8s.io/kubernetes@v${KUBECTL_VERSION}"
    go mod edit "-replace=k8s.io/kubernetes=."
    GOFLAGS= go get golang.org/x/crypto@v0.57.0 golang.org/x/net@v0.59.0 golang.org/x/text@v0.42.0 golang.org/x/sys@v0.48.0 google.golang.org/grpc@v1.83.2
    export GOFLAGS=-mod=readonly
    go build -trimpath -ldflags "${version_ldflags}" -o /out/kubectl ./cmd/kubectl
    go build -trimpath -ldflags "${version_ldflags}" -o /out/kubeadm ./cmd/kubeadm
)

# crictl: official release source, pinned tag/commit and upstream dependency set.
fetch_release kubernetes-sigs/cri-tools /src/cri-tools "v${CRICTL_VERSION}" "${CRICTL_COMMIT}"
(
    cd /src/cri-tools
    GOFLAGS= go get golang.org/x/net@v0.59.0 golang.org/x/mod@v0.41.0 go.opentelemetry.io/otel/sdk@v1.46.0 google.golang.org/grpc@v1.83.2
    GOFLAGS=-mod=mod go mod tidy
    crictl_ldflags="-s -w -X sigs.k8s.io/cri-tools/pkg/version.Version=${CRICTL_VERSION}"
    GOFLAGS=-mod=readonly go build -trimpath -ldflags "${crictl_ldflags}" -o /out/crictl ./cmd/crictl
)

# etcdctl and etcdutl: official etcd release source, pinned tag/commit.
fetch_release etcd-io/etcd /src/etcd "v${ETCD_VERSION}" "${ETCD_COMMIT}"
(
    cd /src/etcd
    for module_dir in etcdctl etcdutl; do
        (
            cd "${module_dir}"
            GOFLAGS= go get golang.org/x/crypto@v0.57.0 golang.org/x/net@v0.59.0 golang.org/x/text@v0.42.0 golang.org/x/sys@v0.48.0 google.golang.org/grpc@v1.83.2
            GOFLAGS=-mod=mod go mod tidy
        )
    done
    etcd_ldflags="-s -w -X=go.etcd.io/etcd/api/v3/version.GitSHA=${ETCD_COMMIT}"
    (
        cd etcdctl
        GOFLAGS=-mod=readonly go build -trimpath -installsuffix=cgo -ldflags "${etcd_ldflags}" -o /out/etcdctl .
    )
    (
        cd etcdutl
        GOFLAGS=-mod=readonly go build -trimpath -installsuffix=cgo -ldflags "${etcd_ldflags}" -o /out/etcdutl .
    )
)

# clusterctl: official release asset with per-architecture SHA256 validation.
case "${TARGETARCH}" in
    amd64) CLUSTERCTL_SHA256=01122674fd3c47a33206ab1b8b81d437afbcf5dd25d126535564f24a2cdf676e ;;
    arm64) CLUSTERCTL_SHA256=83976008aa9ddb81dab01443c646aaa125e4993e17bf24e790e29779f712d79d ;;
esac
clusterctl_binary="/tmp/clusterctl-linux-${TARGETARCH}"
download_checked "https://github.com/kubernetes-sigs/cluster-api/releases/download/v${CLUSTERCTL_VERSION}/clusterctl-linux-${TARGETARCH}" "${CLUSTERCTL_SHA256}" "${clusterctl_binary}"
cp "${clusterctl_binary}" /out/clusterctl
rm -f "${clusterctl_binary}"

fetch_release kubernetes-sigs/kustomize /src/kustomize "kustomize/v${KUSTOMIZE_VERSION}" "${KUSTOMIZE_COMMIT}"
(
    cd /src/kustomize/kustomize
    GOFLAGS= go get golang.org/x/text@v0.42.0
    go build -trimpath -ldflags "-s -w -X sigs.k8s.io/kustomize/api/provenance.version=v${KUSTOMIZE_VERSION}" -o /out/kustomize .
)

fetch_release mikefarah/yq /src/yq "v${YQ_VERSION}" "${YQ_COMMIT}"
(
    cd /src/yq
    go build -trimpath -ldflags "-s -w -X github.com/mikefarah/yq/v4/cmd.yqVersion=v${YQ_VERSION}" -o /out/yq .
)

chmod 0755 /out/helm /out/kubectl /out/kubeadm /out/crictl /out/etcdctl /out/etcdutl /out/clusterctl /out/kustomize /out/yq
go version
for binary in /out/helm /out/kubectl /out/kubeadm /out/crictl /out/etcdctl /out/etcdutl /out/clusterctl /out/kustomize /out/yq; do
    go version -m "${binary}"
done
