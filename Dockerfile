# syntax=docker/dockerfile:1.7

ARG GO_VERSION=1.27.1
ARG ALPINE_IMAGE=alpine:3.24

FROM --platform=${BUILDPLATFORM} golang:${GO_VERSION}-alpine AS builder

ARG TARGETARCH
ARG HELM_VERSION=4.2.4
ARG HELM_COMMIT=3900f434fd3ef2b84065dc04508df48f288dba00
ARG KUBECTL_VERSION=1.37.0
ARG KUBECTL_COMMIT=f54c212e3a2f75d674b717a9b29052b20b60aefc
ARG CRICTL_VERSION=1.37.0
ARG CRICTL_COMMIT=13496db06e3f6636a0855977dd86344698dfc501
ARG ETCD_VERSION=3.7.1
ARG ETCD_COMMIT=5e7fd0de9a57db03ecc11794dc40403a734c07bb
ARG CLUSTERCTL_VERSION=1.14.2
ARG KUSTOMIZE_VERSION=5.8.1
ARG KUSTOMIZE_COMMIT=9790a1c3efd2fd35f1b768d495112834176581c1
ARG YQ_VERSION=4.53.6
ARG YQ_COMMIT=c14f446382944492701b16c1ddb48bb9dbe683e3

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache bash ca-certificates curl git make
COPY --chmod=0755 scripts/build-tools.sh /usr/local/bin/build-tools
RUN build-tools

FROM ${ALPINE_IMAGE} AS runtime

ENV HOME=/home/kube \
    KUBECONFIG=/home/kube/.kube/config \
    XDG_CACHE_HOME=/home/kube/.cache \
    XDG_CONFIG_HOME=/home/kube/.config

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache \
        bash \
        ca-certificates \
        vim \
        curl \
        git \
        jq \
        less \
        ncurses \
        openssl \
        python3 \
        tar \
    && addgroup -g 1000 -S kube \
    && adduser -S -D -u 1000 -G kube -h /home/kube -s /bin/bash kube \
    && install -d -m 0755 -o kube -g kube /workspace /home/kube/.kube /home/kube/.cache /home/kube/.config

COPY --from=builder --chown=0:0 --chmod=0755 /out/helm /usr/local/bin/helm
COPY --from=builder --chown=0:0 --chmod=0755 /out/kubectl /usr/local/bin/kubectl
COPY --from=builder --chown=0:0 --chmod=0755 /out/kubeadm /usr/local/bin/kubeadm
COPY --from=builder --chown=0:0 --chmod=0755 /out/crictl /usr/local/bin/crictl
COPY --from=builder --chown=0:0 --chmod=0755 /out/etcdctl /usr/local/bin/etcdctl
COPY --from=builder --chown=0:0 --chmod=0755 /out/etcdutl /usr/local/bin/etcdutl
COPY --from=builder --chown=0:0 --chmod=0755 /out/clusterctl /usr/local/bin/clusterctl
COPY --from=builder --chown=0:0 --chmod=0755 /out/kustomize /usr/local/bin/kustomize
COPY --from=builder --chown=0:0 --chmod=0755 /out/yq /usr/local/bin/yq

WORKDIR /workspace
USER kube

STOPSIGNAL SIGINT

ENTRYPOINT ["/bin/bash"]
