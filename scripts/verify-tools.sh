#!/bin/sh
set -eu

fail() {
    printf '::error title=Runtime verification::%s\n' "$1" >&2
    exit 1
}

check_command() {
    label="$1"
    shift
    "$@" || fail "${label} failed"
}

check_command alpine-release cat /etc/alpine-release
check_command helm-version helm version --short
check_command kubeadm-version kubeadm version -o short
check_command crictl-version crictl --version
check_command etcdctl-version etcdctl version
check_command etcdutl-version etcdutl version
check_command clusterctl-version clusterctl version -o short
check_command kubectl-version kubectl version --client
check_command kustomize-version kustomize version
check_command yq-version yq --version
check_command python-version python3 --version
check_command git-version git --version

test "$(whoami)" = kube
test "$(id -u)" = 1000
test "${HOME}" = /home/kube
test "${KUBECONFIG}" = /home/kube/.kube/config

for directory in /workspace /home/kube/.kube /home/kube/.cache; do
    test -d "${directory}" || fail "missing directory: ${directory}"
done

for binary in helm kubectl kubeadm crictl etcdctl etcdutl clusterctl kustomize yq; do
    path="$(command -v "${binary}")"
    test "${path}" = "/usr/local/bin/${binary}" || fail "wrong path for ${binary}: ${path}"
    mode="$(stat -c '%U:%G %a' "${path}")"
    test "${mode}" = "root:root 755" || fail "wrong ownership/mode for ${binary}: ${mode}"
done

for build_tool in go gcc g++ make; do
    if command -v "${build_tool}" >/dev/null 2>&1; then
        echo "Unexpected build tool in runtime image: ${build_tool}" >&2
        exit 1
    fi
done
