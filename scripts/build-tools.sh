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

mkdir -p /src /out

fetch_release helm/helm /src/helm "v${HELM_VERSION}" "${HELM_COMMIT}"
(
    cd /src/helm
    GOFLAGS= go get golang.org/x/crypto@v0.57.0
    GOFLAGS= go get oras.land/oras-go/v2@v2.6.2
    export GOFLAGS=-mod=readonly
    make build BINDIR=/out VERSION="v${HELM_VERSION}" GIT_COMMIT="${HELM_COMMIT}" GIT_DIRTY=clean
)

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
    GOFLAGS= go get golang.org/x/crypto@v0.57.0
    export GOFLAGS=-mod=readonly
    go build -trimpath -ldflags "${version_ldflags}" -o /out/kubectl ./cmd/kubectl
)

case "${TARGETARCH}" in
    amd64)
        ETCD_SHA256=e8cd3fa8064c98137c5dbd78b76f969417ace84efb83c481041d7a52ffdd8fb9
        CLUSTERCTL_SHA256=01122674fd3c47a33206ab1b8b81d437afbcf5dd25d126535564f24a2cdf676e
        ;;
    arm64)
        ETCD_SHA256=d7e25e08f694b6ed7792fc7b7a891fe2c3f3d3dccfe2f3bfdb1547b0eb75b6da
        CLUSTERCTL_SHA256=83976008aa9ddb81dab01443c646aaa125e4993e17bf24e790e29779f712d79d
        ;;
esac

download_checked() {
    url="$1"
    expected="$2"
    output="$3"
    curl -fsSL --retry 5 --retry-delay 2 "${url}" -o "${output}"
    printf '%s  %s\n' "${expected}" "${output}" | sha256sum -c -
}

kubeadm_binary="/tmp/kubeadm"
kubeadm_url="https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubeadm"
kubeadm_sha_url="${kubeadm_url}.sha256"
curl -fsSL --retry 5 --retry-delay 2 "${kubeadm_url}" -o "${kubeadm_binary}"
kubeadm_sha256="$(curl -fsSL --retry 5 --retry-delay 2 "${kubeadm_sha_url}" | tr -d '[:space:]')"
printf '%s  %s\n' "${kubeadm_sha256}" "${kubeadm_binary}" | sha256sum -c -
cp "${kubeadm_binary}" /out/kubeadm
rm -f "${kubeadm_binary}"

fetch_release kubernetes-sigs/cri-tools /src/cri-tools "v${CRICTL_VERSION}" "88d8ad9d40f82726fda53c2d271e6172b4c619c9"
(
    cd /src/cri-tools
    sed -i '/github.com\/docker\/docker\/api\/types\/time/d' cmd/crictl/logs.go
    sed -i 's/timetypes\.GetTimestamp/getTimestamp/g; s/timetypes\.ParseTimestamps/parseTimestamps/g' cmd/crictl/logs.go
    cp /usr/local/share/crictl-time.go cmd/crictl/time_compat.go
    gofmt -w cmd/crictl/time_compat.go
    GOFLAGS= go mod edit -droprequire github.com/docker/docker
    GOFLAGS= go get golang.org/x/net@v0.59.0 golang.org/x/mod@v0.41.0 go.opentelemetry.io/otel/sdk@v1.46.0
    GOFLAGS=-mod=mod go mod tidy
    GOFLAGS=-mod=readonly go build -trimpath -ldflags "-s -w" -o /out/crictl ./cmd/crictl
)

etcd_archive="/tmp/etcd-v${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz"
download_checked "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz" "${ETCD_SHA256}" "${etcd_archive}"
tar -xzf "${etcd_archive}" -C /tmp
cp "/tmp/etcd-v${ETCD_VERSION}-linux-${TARGETARCH}/etcdctl" /out/etcdctl
cp "/tmp/etcd-v${ETCD_VERSION}-linux-${TARGETARCH}/etcdutl" /out/etcdutl
rm -rf "/tmp/etcd-v${ETCD_VERSION}-linux-${TARGETARCH}" "${etcd_archive}"

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

chmod 0755 /out/helm /out/kubectl /out/kustomize /out/yq
go version
for binary in /out/helm /out/kubectl /out/kustomize /out/yq; do
    go version -m "${binary}"
done
