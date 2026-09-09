#!/bin/sh
set -eu

cat /etc/alpine-release
helm version --short
helm3 version --short
kubectl version --client
kustomize version
yq --version
python3 --version
git --version

test "$(whoami)" = kube
test "$(id -u)" = 1000
test "${HOME}" = /home/kube
test "${KUBECONFIG}" = /home/kube/.kube/config

for directory in /workspace /home/kube/.kube /home/kube/.cache; do
    test -d "${directory}"
done

for binary in helm helm3 kubectl kustomize yq; do
    path="$(command -v "${binary}")"
    test "${path}" = "/usr/local/bin/${binary}"
    test "$(stat -c '%U:%G %a' "${path}")" = "root:root 755"
done

for build_tool in go gcc g++ make; do
    if command -v "${build_tool}" >/dev/null 2>&1; then
        echo "Unexpected build tool in runtime image: ${build_tool}" >&2
        exit 1
    fi
done
