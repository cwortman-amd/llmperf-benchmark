#!/bin/bash

PROJECT="llmperf"
DEVICE=${DEVICE:-"rocm"}
[[ -f .env ]] && . .env

VENV=".${PROJECT}-${DEVICE}-venv"
if [[ ! $VIRTUAL_ENV =~ $VENV ]]; then
  . $VENV/bin/activate
fi

MODEL=${MODEL:-"amd/Llama-3.1-70B-Instruct-FP8-KV"}
BACKEND=${BACKEND:-"vllm"}
IMAGE=${IMAGE:-"rocm/vllm:latest"}
ITERATIONS=${ITERATIONS:-"3"}

declare -A testcase
testcase[noaiter_new]="MODEL: $MODEL; BACKEND: $BACKEND; IMAGE: $IMAGE; ITERATIONS: $ITERATIONS"

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
  echo "INFO: Starting backend: $BACKEND with model: $MODEL"
  ./start.sh --backend $BACKEND --model $MODEL --image $IMAGE --tp 8 --max-model-len 2048
  cd $RUN_DIR
  for ITERATION in $(seq 1 $ITERATIONS); do
    echo "Running benchmark for model: $MODEL, run number: $ITERATION"
    #for CONCURRENCY in 1 2 4 8 16 32 64 128 256 ; do
    for CONCURRENCY in 8 16 32 ; do
      for INPUT in 1000; do
        for OUTPUT in 500; do
          LOG_DIR="$RESULTS_DIR/${PROJECT}-${BACKEND}-${MODEL//\//--}-c${CONCURRENCY}-i${INPUT}-o${OUTPUT}-r${ITERATION}-${TESTCASE}"
          python token_benchmark_ray.py \
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
        done
      done
    done
  done

}

# Main execution loop to handle arguments and run tests
{
  RUN_TESTCASE="default" # Default test case

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--testcase) RUN_TESTCASE="$2"; shift 2 ;;
      -a|--all) RUN_TESTCASE="all"; shift ;;
      *) echo "ERROR: Unknown option '$1'. Valid options are -t|--testcase <name> or -a|--all."; exit 1 ;;
    esac
  done

  if [[ "$RUN_TESTCASE" == "all" ]]; then
    echo "INFO: Running all test cases."
    for t in "${TESTCASES[@]}"; do
      echo "INFO: Testcase '$t'"
      for i in $(seq 1 $ITERATIONS); do
        echo "INFO: Iteration $i of $ITERATIONS for testcase '$t'"
        run_tests "$t"
      done
    done
  elif [[ " ${TESTCASES[*]} " =~ " $RUN_TESTCASE " ]]; then
    echo "INFO: Running specified test case '$RUN_TESTCASE'."
    run_tests "$RUN_TESTCASE"
  else
    echo "ERROR: Unknown test case '$RUN_TESTCASE'. Valid options are ${TESTCASES[*]} or 'all'."
    exit 1
  fi
  docker rm -f $(docker ps -aq --filter "name=$BACKEND") || true

} |& tee $TEST_LOG

echo "INFO: Test Log: $TEST_LOG"
cp $TEST_LOG $PWD/test.log
