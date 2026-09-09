# syntax=docker/dockerfile:1.7
ARG GO_VERSION=1.27.1
ARG ALPINE_IMAGE=alpine:3.24
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS builder
ARG TARGETARCH
ARG HELM_VERSION=3.21.4
ARG HELM_COMMIT=813176c51bb5c181dbbd7901298ddcc104cd3417
ARG KUBECTL_VERSION=1.36.4
ARG KUBECTL_COMMIT=bb826b1d48562f110659e64e8ec444327433db95
ARG KUSTOMIZE_VERSION=5.8.1
ARG KUSTOMIZE_COMMIT=9790a1c3efd2fd35f1b768d495112834176581c1
ARG YQ_VERSION=4.53.6
ARG YQ_COMMIT=c14f446382944492701b16c1ddb48bb9dbe683e3
ENV CGO_ENABLED=0 GOOS=linux GOTOOLCHAIN=local
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN apk add --no-cache bash ca-certificates git make
RUN case "${TARGETARCH}" in amd64|arm64) ;; *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; esac; \
    export GOARCH="${TARGETARCH}" GOFLAGS="-mod=readonly"; mkdir -p /src /out; \
    git init -q /src/helm; git -C /src/helm remote add origin https://github.com/helm/helm.git; git -C /src/helm fetch -q --depth 1 origin "refs/tags/v${HELM_VERSION}"; git -C /src/helm checkout -q --detach FETCH_HEAD; test "$(git -C /src/helm rev-parse HEAD)" = "${HELM_COMMIT}"; make -C /src/helm build BINDIR=/out VERSION="v${HELM_VERSION}"; \
    git init -q /src/kubernetes; git -C /src/kubernetes remote add origin https://github.com/kubernetes/kubernetes.git; git -C /src/kubernetes fetch -q --depth 1 origin "refs/tags/v${KUBECTL_VERSION}"; git -C /src/kubernetes checkout -q --detach FETCH_HEAD; test "$(git -C /src/kubernetes rev-parse HEAD)" = "${KUBECTL_COMMIT}"; cd /src/kubernetes; export KUBE_ROOT=/src/kubernetes; . hack/lib/version.sh; kube::version::get_version_vars; go build -trimpath -ldflags "$(kube::version::ldflags)" -o /out/kubectl ./cmd/kubectl; \
    git init -q /src/kustomize; git -C /src/kustomize remote add origin https://github.com/kubernetes-sigs/kustomize.git; git -C /src/kustomize fetch -q --depth 1 origin "refs/tags/kustomize/v${KUSTOMIZE_VERSION}"; git -C /src/kustomize checkout -q --detach FETCH_HEAD; test "$(git -C /src/kustomize rev-parse HEAD)" = "${KUSTOMIZE_COMMIT}"; cd /src/kustomize/kustomize; go build -trimpath -ldflags "-s -w -X sigs.k8s.io/kustomize/api/provenance.version=v${KUSTOMIZE_VERSION}" -o /out/kustomize .; \
    git init -q /src/yq; git -C /src/yq remote add origin https://github.com/mikefarah/yq.git; git -C /src/yq fetch -q --depth 1 origin "refs/tags/v${YQ_VERSION}"; git -C /src/yq checkout -q --detach FETCH_HEAD; test "$(git -C /src/yq rev-parse HEAD)" = "${YQ_COMMIT}"; cd /src/yq; go build -trimpath -ldflags "-s -w -X github.com/mikefarah/yq/v4/cmd.yqVersion=v${YQ_VERSION}" -o /out/yq .; \
    chmod 0755 /out/helm /out/kubectl /out/kustomize /out/yq; go version; for binary in /out/helm /out/kubectl /out/kustomize /out/yq; do go version -m "${binary}"; done
FROM ${ALPINE_IMAGE} AS runtime
ENV HOME=/home/kube KUBECONFIG=/home/kube/.kube/config XDG_CACHE_HOME=/home/kube/.cache
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN apk add --no-cache bash ca-certificates vim curl git jq less ncurses openssl python3 tar \
    && addgroup -g 1000 -S kube \
    && adduser -S -D -u 1000 -G kube -h /home/kube -s /bin/bash kube \
    && install -d -m 0755 -o kube -g kube /workspace /home/kube/.kube /home/kube/.cache
COPY --from=builder --chmod=0755 /out/helm /usr/local/bin/helm
COPY --from=builder --chmod=0755 /out/kubectl /usr/local/bin/kubectl
COPY --from=builder --chmod=0755 /out/kustomize /usr/local/bin/kustomize
COPY --from=builder --chmod=0755 /out/yq /usr/local/bin/yq
WORKDIR /workspace
USER kube
ENTRYPOINT ["/bin/bash"]
