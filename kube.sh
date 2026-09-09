#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

KUBE_IMAGE_NAME="${KUBE_IMAGE_NAME:-ghcr.io/m0nokey/kube:latest}"
KUBE_RUNNER_DIR="${KUBE_RUNNER_DIR:-$SCRIPT_DIR}"
KUBE_WORKSPACE_DIR="${KUBE_WORKSPACE_DIR:-${KUBE_RUNNER_DIR}/workspace}"
KUBE_CONFIG_DIR="${KUBE_CONFIG_DIR:-${KUBE_RUNNER_DIR}/.kube}"
KUBE_CONFIG_FILE="${KUBE_CONFIG_FILE:-${KUBE_CONFIG_DIR}/config}"
KUBE_CONFIG_EXAMPLE="${KUBE_CONFIG_EXAMPLE:-${KUBE_RUNNER_DIR}/config.example.yaml}"
COMPOSE_FILE_PATH="${COMPOSE_FILE_PATH:-${KUBE_RUNNER_DIR}/compose.yml}"
COMPOSE_SERVICE_NAME="${COMPOSE_SERVICE_NAME:-kube}"
DOCKER_BIN="${DOCKER_BIN:-docker}"

export KUBE_IMAGE_NAME
export KUBE_RUNNER_DIR
export KUBE_WORKSPACE_DIR
export KUBE_CONFIG_DIR

docker_cmd() {
    env \
        -u DOCKER_CLI_OTEL_EXPORTER_OTLP_ENDPOINT \
        -u DOCKER_CLI_OTEL_EXPORTER_OTLP_HEADERS \
        -u DOCKER_CLI_OTEL_EXPORTER_OTLP_PROTOCOL \
        -u OTEL_EXPORTER_OTLP_ENDPOINT \
        -u OTEL_EXPORTER_OTLP_TRACES_ENDPOINT \
        -u OTEL_EXPORTER_OTLP_HEADERS \
        -u OTEL_TRACES_EXPORTER \
        -u OTEL_SERVICE_NAME \
        -u BUILDKIT_TRACE \
        "$DOCKER_BIN" "$@"
}

compose_cmd() {
    docker_cmd compose -f "$COMPOSE_FILE_PATH" "$@"
}

ensure_layout() {
    mkdir -p "$KUBE_WORKSPACE_DIR" "$KUBE_CONFIG_DIR"
    chmod 700 "$KUBE_CONFIG_DIR"

    if [[ ! -f "$KUBE_CONFIG_FILE" ]]; then
        printf 'Kubeconfig not found: %s\n' "$KUBE_CONFIG_FILE" >&2
        printf 'Copy %s to %s and fill NAME, NAMESPACE, CA, and TOKEN.\n' "$KUBE_CONFIG_EXAMPLE" "$KUBE_CONFIG_FILE" >&2
        printf 'Put manifests/YAML into %s; it is mounted read-only at /workspace.\n' "$KUBE_WORKSPACE_DIR" >&2
        exit 0
    fi

    chmod 600 "$KUBE_CONFIG_FILE"
}

show_help() {
    cat <<'EOF'
Usage:
  ./kube.sh                 Open shell with kubectl tools
  ./kube.sh --build         Build image
  ./kube.sh --check         kubectl cluster-info
  ./kube.sh --ctx           Show current context
  ./kube.sh --ns            Show namespace resources
  ./kube.sh --logs ARGS     Run kubectl logs -f ARGS
  ./kube.sh --help

Examples:
  ./kube.sh --logs pod/my-pod
  ./kube.sh --logs deploy/my-app --all-containers
  ./kube.sh kubectl apply -f app.yaml

Files:
  .kube/config              Mounted read-only as KUBECONFIG
  workspace/                Mounted read-only as /workspace for manifests/YAML
EOF
}

run_tool() {
    compose_cmd pull "$COMPOSE_SERVICE_NAME"
    if [[ $# -eq 0 ]]; then
        compose_cmd run --no-build --rm --service-ports "$COMPOSE_SERVICE_NAME"
        return
    fi

    if [[ "$1" == "-c" && $# -eq 2 ]]; then
        compose_cmd run --no-build --rm --service-ports "$COMPOSE_SERVICE_NAME" "$@"
        return
    fi

    compose_cmd run --no-build --rm --service-ports "$COMPOSE_SERVICE_NAME" -c 'exec "$@"' -- "$@"
}

main() {
    ensure_layout

    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --build)
            docker_cmd build \
                --tag "$KUBE_IMAGE_NAME" \
                --file "$KUBE_RUNNER_DIR/Dockerfile" \
                "$KUBE_RUNNER_DIR"
            ;;
        --check)
            run_tool kubectl cluster-info
            ;;
        --ctx)
            run_tool kubectl config current-context
            run_tool kubectl config view --minify
            ;;
        --ns)
            run_tool kubectl get all
            ;;
        --logs)
            shift
            if [[ $# -eq 0 ]]; then
                printf 'Usage: ./kube.sh --logs ARGS\n' >&2
                exit 1
            fi
            run_tool kubectl logs -f "$@"
            ;;
        "")
            run_tool
            ;;
        *)
            run_tool "$@"
            ;;
    esac
}

main "$@"
