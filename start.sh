#!/bin/bash


BACKEND=${BACKEND:-"vllm"}
MODEL=${MODEL:-"amd/Llama-3.1-70B-Instruct-FP8-KV"}
TP=${TP:-"1"}
MAX_MODEL_LEN=${MAX_MODEL_LEN:-2048}

LAUNCH_ENV="VLLM_USE_V1=1 VLLM_V1_USE_PREFILL_DECODE_ATTENTION=1 VLLM_V1_USE_PREFILL_DECODE_ATTENTION=1 VLLM_ROCM_USE_AITER=1 VLLM_ROCM_USE_AITER_RMSNORM=0"
LAUNCH_CMD="$LAUNCH_ENV python3 -m vllm.entrypoints.openai.api_server --max-model-len $MAX_MODEL_LEN --disable-log-stats --disable-log-requests --tensor-parallel-size $TP --model=$MODEL"

RENDERD="--device=/dev/dri "
CONTAINER_NAME="${USER}_${BACKEND}_${container_idx}"
DOCKER_HF_HOME=/root/.cache/huggingface

DOCKER_ENV="\
    --env HF_HOME=$DOCKER_HF_HOME \
    --env HUGGINGFACE_HUB_CACHE=${DOCKER_HF_HOME}/hub \
    --env ENGINES=$ENGINES \
    --env BACKEND=$BACKEND \
    --env MODEL=$MODEL \
    --env TP=$TP \
    "

[[ $DEBUG == 0 ]] && DOCKER_RUN="docker run --rm -d" || DOCKER_RUN="docker run --rm -it"

DOCKER_CMD="$DOCKER_RUN \
    --device=/dev/kfd \
    $RENDERD \
    --group-add video \
    --network=host \
    --ipc=host \
    --security-opt seccomp=unconfined \
    --cap-add=SYS_PTRACE \
    --name $CONTAINER_NAME \
    --label user=$USER \
    -v $HF_HOME:$DOCKER_HF_HOME \
    -v $PWD:/workdir \
    -w /workdir \
    $DOCKER_ENV \
    $IMAGE \
    ./launch.sh"

# Remove existing container if necessary
if docker inspect "$CONTAINER_NAME" &>/dev/null; then
    echo "INFO: Removing existing container '$CONTAINER_NAME'."
    docker rm -f "$CONTAINER_NAME"
fi

echo "INFO: Launching container '$CONTAINER_NAME' using image '$IMAGE' with model '$MODEL' on ports $CONTAINER_BASE_PORT-$((CONTAINER_BASE_PORT + ENGINES - 1)) ..."
echo "$DOCKER_CMD"
eval "$DOCKER_CMD" &

if [ $? -eq 0 ]; then
    echo "INFO: Container $CONTAINER_NAME launched successfully"
else
    echo "ERROR: Failed to launch container $CONTAINER_NAME"
    exit 1
fi