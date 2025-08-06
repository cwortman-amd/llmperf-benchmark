#!/bin/bash

PROJECT="llmperf"
MODEL=${MODEL:-"amd/Llama-3.1-70B-Instruct-FP8-KV"}
ITERATIONS=${ITERATIONS:-"3"}

export OPENAI_API_KEY=secret_abcdefg
export OPENAI_API_BASE="http://localhost:8000/v1/"

# Results and Logging Setup
RESULTS_DIR=${RESULTS_DIR:-"$PWD/results"}
LOG_DIR=${LOG_DIR:-"$RESULTS_DIR/$PROJECT"}
mkdir -p "$LOG_DIR"

DATETIME=$(date +'%Y%m%d-%H%M%S')
TEST_LOG=$LOG_DIR/test.${DATETIME}.log


{
  RUN_DIR=${RUN_DIR:-"$PWD/llmperf"}
  cd $RUN_DIR
  for ITERATION in $(seq 1 $ITERATIONS); do
    echo "Running benchmark for model: $MODEL, run number: $ITERATION"
    for CONCURRENCY in 1 2 4 8 16 32 64 128 256 ; do
      for INPUT in 1000; do
        for OUTPUT in 500; do
          LOG_DIR="$RESULTS_DIR/${PROJECT}-${MODEL//\//--}-c${CONCURRENCY}-i${INPUT}-o${OUTPUT}-r${ITERATION}"
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

} |& tee $TEST_LOG

echo "INFO: Test Log: $TEST_LOG"
cp $TEST_LOG $PWD/test.log
