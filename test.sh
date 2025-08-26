#!/bin/bash

PROJECT="llmperf"
DEVICE=${DEVICE:-"rocm"}
[[ -f .env ]] && . .env

VENV=".${PROJECT}-${DEVICE}-venv"
if [[ ! $VIRTUAL_ENV =~ $VENV ]]; then
  . $VENV/bin/activate
fi

# --- Test case definitions ---
declare -A testcase
testcase[default]="MODEL: amd/Llama-3.1-70B-Instruct-FP8-KV; BACKEND: vllm; IMAGE: rocm/vllm:latest; TP: 8; CONCURRENCY: 1 2 4 8 16 32 64 128 256"
testcase[default_8b]="MODEL: amd/Llama-3.1-B-Instruct-FP8-KV; BACKEND: vllm; IMAGE: rocm/vllm:rocm6.4.1_vllm_0.10.0_20250812; TP: 8"
testcase[aiter]="MODEL: amd/Llama-3.1-70B-Instruct-FP8-KV; BACKEND: vllm; IMAGE: rocm/vllm:rocm6.4.1_vllm_0.10.0_20250812; TP: 8"
testcase[aiter_pda]="MODEL: amd/Llama-3.1-70B-Instruct-FP8-KV; BACKEND: vllm; IMAGE: rocm/vllm:rocm6.4.1_vllm_0.10.0_20250812; TP: 8"
testcase[noaiter_pda]="MODEL: amd/Llama-3.1-70B-Instruct-FP8-KV; BACKEND: vllm; IMAGE: rocm/vllm:rocm6.4.1_vllm_0.10.0_20250812 TP: 8"
testcase[noaiter_nopda]="MODEL: amd/Llama-3.1-70B-Instruct-FP8-KV; BACKEND: vllm; IMAGE: rocm/vllm:rocm6.4.1_vllm_0.10.0_20250812; TP: 8"
testcase[pda]="MODEL: amd/Llama-3.1-70B-Instruct-FP8-KV; BACKEND: vllm; IMAGE: rocm/vllm:rocm6.4.1_vllm_0.10.0_20250812; TP: 8"
testcase[pda_fp8]="MODEL: amd/Llama-3.1-70B-Instruct-FP8-KV; BACKEND: vllm; IMAGE: rocm/vllm:rocm6.4.1_vllm_0.10.0_20250812; TP: 8"
testcase[pda_pto]="MODEL: amd/Llama-3.1-70B-Instruct-FP8-KV; BACKEND: vllm; IMAGE: rocm/vllm:rocm6.4.1_vllm_0.10.0_20250812; TP: 8"
testcase[sglang]="MODEL: amd/Llama-3.1-70B-Instruct-FP8-KV; BACKEND: sglang; IMAGE: lmsysorg/sglang:v0.4.10.post2-rocm630-mi30x; TP: 8"
testcase[pda_8b]="MODEL: amd/Llama-3.1-8B-Instruct-FP8-KV; BACKEND: vllm; IMAGE: rocm/vllm:rocm6.4.1_vllm_0.10.0_20250812; TP: 8"

TESTCASES=("${!testcase[@]}")  # Dynamically generate TESTCASES list

export OPENAI_API_KEY=secret_abcdefg
export OPENAI_API_BASE="http://localhost:8000/v1/"

RUN_DIR=${RUN_DIR:-"$PWD/llmperf"}

# Results and Logging Setup
RESULTS_DIR=${RESULTS_DIR:-"$PWD/results"}
LOG_DIR=${LOG_DIR:-"$RESULTS_DIR/$PROJECT"}
mkdir -p "$LOG_DIR"

DATETIME=$(date +'%Y%m%d-%H%M%S')
TEST_LOG=$LOG_DIR/test.${DATETIME}.log

# Run tests
run_tests() {
  local t=$1
  IFS=';' read -ra pairs <<< "${testcase[$t]}"
  declare -A params
  for pair in "${pairs[@]}"; do
    IFS=':' read -r key value <<< "$pair"
    key="${key# }"  # Remove leading space
    echo "params[$key]=$value"
    params[$key]=$value
  done

  BACKEND_LIST=${params[BACKEND]:-"vllm"}
  IMAGE_LIST=${params[IMAGE]:-"rocm/vllm:latest"}
  MODEL_LIST=${params[MODEL]:-"amd/Llama-3.1-70B-Instruct-FP8-KV"}
  TP_LIST=${params[TP]:-"8"}
  #CONCURRENCY_LIST=${params[CONCURRENCY]:-"64"}
  CONCURRENCY_LIST=${params[CONCURRENCY]:-"1 2 4 8 16 32 64 128 256"}

  ITERATIONS=${ITERATIONS:-"3"}
  CONFIG=${TESTCASE}

  for BACKEND in $BACKEND_LIST; do
    for IMAGE in $IMAGE_LIST; do
      for MODEL in $MODEL_LIST; do
        for TP in $TP_LIST; do
          echo "INFO: Starting backend: $BACKEND with model: $MODEL and tensor parallelism: $TP using image: $IMAGE and config: $CONFIG"
          START_CMD="./start.sh --backend $BACKEND --model $MODEL --image $IMAGE --tp $TP --config $CONFIG"
          echo "INFO: $START_CMD"
          eval "$START_CMD"
          for CONCURRENCY in $CONCURRENCY_LIST ; do
            for INPUT in 1000; do
              for OUTPUT in 500; do
                for ITERATION in $(seq 1 $ITERATIONS); do
                  echo "INFO: Running benchmark for model: $MODEL, run number: $ITERATION"
                  LOG_DIR="$RESULTS_DIR/${PROJECT}-${BACKEND}-${IMAGE//\//--}-${MODEL//\//--}-c${CONCURRENCY}-i${INPUT}-o${OUTPUT}-r${ITERATION}-${TESTCASE}"
                  cd $RUN_DIR
                  RUN_CMD="python token_benchmark_ray.py \
                    --model $MODEL \
                    --mean-input-tokens $INPUT \
                    --stddev-input-tokens 150 \
                    --mean-output-tokens $OUTPUT \
                    --stddev-output-tokens 10 \
                    --max-num-completed-requests $((10*CONCURRENCY+50)) \
                    --timeout 600 \
                    --num-concurrent-requests $CONCURRENCY \
                    --results-dir $LOG_DIR \
                    --llm-api "openai" \
                    --additional-sampling-params '{}'
                  "
                  echo "INFO:$RUN_CMD"
                  eval "$RUN_CMD"
                done
              done
            done
          done
        done
      done
    done
  done

}

# Main execution loop to handle arguments and run tests
{
  TESTCASE="default" # Default test case

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--testcase) TESTCASE="$2"; shift 2 ;;
      -a|--all) TESTCASE="all"; shift ;;
      *) echo "ERROR: Unknown option '$1'. Valid options are -t|--testcase <name> or -a|--all."; exit 1 ;;
    esac
  done

  if [[ "$TESTCASE" == "all" ]]; then
    echo "INFO: Running all test cases."
    for t in "${TESTCASES[@]}"; do
      echo "INFO: Testcase '$t'"
      for i in $(seq 1 $ITERATIONS); do
        echo "INFO: Iteration $i of $ITERATIONS for testcase '$t'"
        run_tests "$t"
      done
    done
  elif [[ " ${TESTCASES[*]} " =~ " $TESTCASE " ]]; then
    echo "INFO: Running specified test case '$TESTCASE'."
    run_tests "$TESTCASE"
  else
    echo "ERROR: Unknown test case '$TESTCASE'. Valid options are ${TESTCASES[*]} or 'all'."
    exit 1
  fi
  for BACKEND in vllm sglang; do
    docker rm -f $(docker ps -aq --filter "name=$BACKEND") 2>/dev/null || true
  done

} |& tee $TEST_LOG

echo "INFO: Test Log: $TEST_LOG"
cp $TEST_LOG $PWD/test.log
