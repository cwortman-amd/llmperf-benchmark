#!/usr/bin/env bash

set -euo pipefail

# Default environment variables with explanation
IMAGE="${IMAGE:-rocm/vllm:latest}"
BACKEND="${BACKEND:-vllm}"
MODEL="${MODEL:-amd/Llama-3.1-70B-Instruct-FP8-KV}"
TP="${TP:-8}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-2048}"

# Environment and launch command for serving the model
# Uncomment and adjust LAUNCH_ENV if needed
# LAUNCH_ENV="VLLM_V1_USE_PREFILL_DECODE_ATTENTION=1 VLLM_ROCM_USE_AITER=1 VLLM_ROCM_USE_AITER_RMSNORM=0"
LAUNCH_ENV="VLLM_ROCM_USE_AITER=0 VLLM_ROCM_USE_AITER_MHA=0 VLLM_ROCM_USE_AITER_RMSNORM=0"
LAUNCH_CMD="$LAUNCH_ENV python3 -m vllm.entrypoints.openai.api_server \
    --max-model-len ${MAX_MODEL_LEN} \
    --disable-log-stats \
    --disable-log-requests \
    --tensor-parallel-size ${TP} \
    --model=${MODEL}"

# Generate launch script
echo "${LAUNCH_CMD}" > launch.sh
chmod +x ./launch.sh

# Docker device and rendering arguments
RENDERD="--device=/dev/dri"
CONTAINER_NAME="${USER:-$(whoami)}_${BACKEND}"
DOCKER_HF_HOME="/root/.cache/huggingface"

# Docker environment variables
DOCKER_ENV=(
    "--env" "HF_HOME=${DOCKER_HF_HOME}"
    "--env" "HUGGINGFACE_HUB_CACHE=${DOCKER_HF_HOME}/hub"
    "--env" "BACKEND=${BACKEND}"
    "--env" "MODEL=${MODEL}"
    "--env" "TP=${TP}"
    "--env" "MAX_MODEL_LEN=${MAX_MODEL_LEN}"
)

# Docker run mode
if [[ "${DEBUG:-0}" == "1" ]]; then
    DOCKER_RUN="docker run --rm -it"
else
    DOCKER_RUN="docker run --rm -d"
fi

# Compose Docker run command
DOCKER_CMD="${DOCKER_RUN} \
    --device=/dev/kfd \
    ${RENDERD} \
    --group-add video \
    --network=host \
    --ipc=host \
    --security-opt seccomp=unconfined \
    --cap-add=SYS_PTRACE \
    --name ${CONTAINER_NAME} \
    --label user=${USER:-$(whoami)} \
    -v ${HF_HOME:-$HOME/.cache/huggingface}:${DOCKER_HF_HOME} \
    -v ${PWD}:/workdir \
    -w /workdir \
    ${DOCKER_ENV[*]} \
    ${IMAGE} \
    ./launch.sh"

# Remove existing container, if any
if docker inspect "${CONTAINER_NAME}" &>/dev/null; then
    echo "INFO: Removing existing container '${CONTAINER_NAME}'." >&2
    docker rm -f "${CONTAINER_NAME}"
fi

# Print info
echo "INFO: Launching container '${CONTAINER_NAME}' using image '${IMAGE}' with model '${MODEL}' ..."
echo "INFO: Running - ${LAUNCH_CMD}"
echo "${DOCKER_CMD}"

# Run the Docker container
if [[ "${DEBUG:-0}" == "1" ]]; then
    echo "INFO: Run in foreground for interactive debugging" >&2
    eval "${DOCKER_CMD}"
else
    echo "INFO: Run in background for detached mode" >&2
    eval "${DOCKER_CMD}" &
fi

sleep 2  # Give container a moment to start

# Report success/failure by checking if container is running
if docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}" | grep -q "${CONTAINER_NAME}"; then
    echo "INFO: Container ${CONTAINER_NAME} launched successfully" >&2
else
    echo "ERROR: Failed to launch container ${CONTAINER_NAME}" >&2
    exit 1
fi
