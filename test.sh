#!/bin/bash

if [ -z "$OPENAI_API_KEY" ]; then
  echo "Error: Please set the OPENAI_API_KEY environment variable."
  exit 1
fi
export OPENAI_API_BASE="http://localhost:8000/v1/"

MODEL=${MODEL:-"amd/Llama-3.1-70B-Instruct-FP8-KV"}
ITERATIONS=${ITERATIONS:-3}

for ITERATION in $(seq 1 ITERATIONS); do
  echo "Running benchmark for model: $MODEL, run number: $RUN_NO"
  for CONCURRENCY in 1 2 4 8 16 32 64 128 256 ; do
    for INPUT in 1000; do
      for OUTPUT in 500; do
        RESULTS_DIR="results/${MODEL//\//--}-c${CONCURRENCY}-i${INPUT}-o${OUTPUT}-r${ITERATION}"
        python token_benchmark_ray.py \
          --model $MODEL \
          --mean-input-tokens $INPUT \
          --stddev-input-tokens 150 \
          --mean-output-tokens $OUTPUT \
          --stddev-output-tokens 10 \
          --max-num-completed-requests $((10*CONCURRENCY+50)) \
          --timeout 600 \
          --num-concurrent-requests $CONCURRENCY \
          --results-dir $RESULTS_DIR \
          --llm-api "openai" \
          --additional-sampling-params '{}'
      done
    done
  done
done
