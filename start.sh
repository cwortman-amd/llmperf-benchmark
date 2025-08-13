#!/usr/bin/env bash
# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image) IMAGE=$2; shift 2 ;;
        --backend) BACKEND=$2; shift 2 ;;
        --model) MODEL=$2; shift 2 ;;
        --tp) TP=$2; shift 2 ;;
        --config) CONFIG=$2; shift 2 ;;
        --max-model-len) MAX_MODEL_LEN=$2; shift 2 ;;
        --profile) PROFILE=1; shift 1 ;;
        *) echo "ERROR: Unknown argument $1" ; exit 1 ;;
    esac
done

# Default environment variables with explanation
IMAGE="${IMAGE:-rocm/vllm:latest}"
BACKEND="${BACKEND:-vllm}"
MODEL="${MODEL:-amd/Llama-3.1-70B-Instruct-FP8-KV}"
TP="${TP:-8}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-2048}"
CONFIG="${CONFIG:-default}"

# Environment and launch command for serving the model
if [[ $BACKEND == "vllm" ]]; then
    [[ -z "$PROFIle" ]] &&
    [[ "$CONFIG" == "default" ]] && LAUNCH_ENV=""
    [[ "$CONFIG" == "pda" ]] && LAUNCH_ENV="VLLM_USE_V1=1 VLLM_V1_USE_PREFILL_DECODE_ATTENTION=1"
    [[ "$CONFIG" == "pda_8b" ]] && LAUNCH_ENV="VLLM_USE_V1=1 VLLM_V1_USE_PREFILL_DECODE_ATTENTION=1"
    [[ "$CONFIG" == "pda_fp8" ]] && LAUNCH_ENV="VLLM_USE_V1=1 VLLM_V1_USE_PREFILL_DECODE_ATTENTION=1"
    [[ "$CONFIG" == "pda_pto" ]] && LAUNCH_ENV="VLLM_USE_V1=1 VLLM_V1_USE_PREFILL_DECODE_ATTENTION=1 PYTORCH_TUNABLEOP_ENABLED=1"
    [[ "$CONFIG" == "aiter" ]] && LAUNCH_ENV="VLLM_USE_V1=1 VLLM_ROCM_USE_AITER=1"
    [[ "$CONFIG" == "noaiter" ]] && LAUNCH_ENV="VLLM_USE_V1=1 VLLM_V1_USE_PREFILL_DECODE_ATTENTION=1 VLLM_ROCM_USE_AITER=0 VLLM_ROCM_USE_AITER_MHA=0 VLLM_ROCM_USE_AITER_RMSNORM=0"
    [[ "$CONFIG" == "noaiter_nopda" ]] && LAUNCH_ENV="VLLM_USE_V1=1 VLLM_V1_USE_PREFILL_DECODE_ATTENTION=0 VLLM_ROCM_USE_AITER=0 VLLM_ROCM_USE_AITER_MHA=0 VLLM_ROCM_USE_AITER_RMSNORM=0"
    LAUNCH_CMD="$LAUNCH_ENV python3 -m vllm.entrypoints.openai.api_server \
        --model ${MODEL} \
        --disable-log-stats \
        --disable-log-requests \
        --tensor-parallel-size ${TP} \
        --max-model-len ${MAX_MODEL_LEN} \
        --gpu-memory-utilization 0.416 \
        "
    [[ "$CONFIG" == *fp8* ]] && LAUNCH_CMD+=" --kv-cache-dtype fp8 --quantization fp8 --dtype bfloat16 "
        #--max-num-batched-tokens 512 \
elif [[ $BACKEND == "sglang" ]]; then
    LAUNCH_CMD="$LAUNCH_ENV python3 -m sglang.launch_server \
        --model ${MODEL} \
        --port ${PORT:-8000} \
        --trust-remote-code \
        --log-level-http warning \
        --enable-torch-compile \
        "
        #--torch-compile-max-bs $MAX_BATCH_SIZE \
        #--chunked-prefill-size $MAX_BATCHED_TOKENS \
else
    echo "ERROR: Unknown backend $BACKEND"
    exit 1
fi

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
    bash -c ./launch.sh"

# Function to launch the Docker container
launch_container() {
    # Remove existing container, if any
    if docker inspect "${CONTAINER_NAME}" &>/dev/null; then
        echo "INFO: Removing existing container '${CONTAINER_NAME}'." >&2
        docker rm -f "${CONTAINER_NAME}"
    fi

    # Print info
    echo "INFO: Launching container '${CONTAINER_NAME}' using image '${IMAGE}' with model '${MODEL}' ..."
    echo "INFO: ${LAUNCH_CMD}"
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
        return 0
    else
        echo "ERROR: Failed to launch container ${CONTAINER_NAME}" >&2
        return 1
    fi
}

# Function to check if the container is active
active_container() {
    if docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "running"; then
        DOCKER_IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME")
        echo "INFO: Docker container '$CONTAINER_NAME' using image '$DOCKER_IMAGE' is active."
        return 0
    else
        echo "ERROR: Docker container '$CONTAINER_NAME' is not running."
        return 1
    fi
}

# Function to wait for server to become active
active_server() {
    local PORT=${1:-8000}
    local IP=${2:-localhost}
    local BASE_URL="http://$IP:$PORT"
    local MAX_ITERATIONS=10

    # Wait for server health status
    echo "INFO: Waiting for server to accept connections at $BASE_URL"
    for ((i=1; i<=MAX_ITERATIONS; i++)); do
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$BASE_URL/health")
        if [[ $? -eq 0 && "$RESPONSE" == "200" ]]; then
            SERVING_MODEL=$(curl -s "$BASE_URL/v1/models" | jq -r '.data[0].id')
            if [[ "$SERVING_MODEL" == "$MODEL" ]]; then
                echo "INFO: Server is active and serving model '$MODEL'"
                return 0
            else
                echo "ERROR: SERVING_MODEL=$SERVING_MODEL, MODEL=$MODEL"
            fi
        else
            echo "INFO: Attempt $i: $BACKEND server '$CONTAINER_NAME' on port $PORT not active"
            ((i < MAX_ITERATIONS)) && sleep 60
        fi
    done

    echo "ERROR: $BACKEND server '$CONTAINER_NAME' on port $PORT did not become active after $MAX_ITERATIONS attempts."
    echo "INFO: Container logs:"
    docker logs $CONTAINER_NAME
    return 1
}

# Launch the container
if ! launch_container; then
    exit 1
fi

# Check if container is active
if ! active_container; then
    exit 1
fi

# Check if server is active
if ! active_server; then
    exit 1
fi