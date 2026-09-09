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
    go build -trimpath -ldflags "${version_ldflags}" -o /out/kubeadm ./cmd/kubeadm
)

fetch_release kubernetes-sigs/cri-tools /src/cri-tools "v${CRICTL_VERSION}" "${CRICTL_COMMIT}"
(
    cd /src/cri-tools
    GOFLAGS= go get golang.org/x/net@v0.58.0 golang.org/x/sys@v0.48.0 golang.org/x/text@v0.42.0
    GOFLAGS= go mod tidy
    export GOFLAGS=-mod=readonly
    go build -trimpath -ldflags "-s -w" -o /out/crictl ./cmd/crictl
)

fetch_release etcd-io/etcd /src/etcd "v${ETCD_VERSION}" "${ETCD_COMMIT}"
(
    cd /src/etcd
    GOFLAGS= go get golang.org/x/crypto@v0.57.0 golang.org/x/net@v0.58.0 golang.org/x/sys@v0.48.0 golang.org/x/text@v0.42.0
    GOFLAGS= go mod tidy
    export GOFLAGS=-mod=readonly
    go build -trimpath -ldflags "-s -w" -o /out/etcdctl ./etcdctl
    go build -trimpath -ldflags "-s -w" -o /out/etcdutl ./etcdutl
)

fetch_release kubernetes-sigs/cluster-api /src/cluster-api "v${CLUSTERCTL_VERSION}" "${CLUSTERCTL_COMMIT}"
(
    cd /src/cluster-api
    GOFLAGS= go get golang.org/x/crypto@v0.57.0 golang.org/x/net@v0.58.0 golang.org/x/sys@v0.48.0 golang.org/x/text@v0.42.0
    GOFLAGS= go mod tidy
    export GOFLAGS=-mod=readonly
    go build -trimpath -ldflags "-s -w" -o /out/clusterctl ./cmd/clusterctl
)

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
