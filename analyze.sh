#!/bin/bash

cd results

GROUP_LIST='
llmperf-vllm-rocm--vllm:rocm6.4.1_vllm_0.9.1_20250715-amd--Llama-3.1-70B-Instruct-FP8-KV*-pda
llmperf-vllm-rocm--vllm:rocm6.4.1_vllm_0.10.0_20250812-amd--Llama-3.1-70B-Instruct-FP8-KV*-pda
llmperf-vllm-rocm--vllm:rocm6.4.1_vllm_0.10.0_20250812-amd--Llama-3.1-70B-Instruct-FP8-KV*-aiter_pda
llmperf-vllm-rocm--vllm:rocm6.4.1_vllm_0.9.1_20250715-amd--Llama-3.1-8B-Instruct-FP8-KV*-pda_8b
dlmperf-vllm-rocm--vllm:rocm6.4.1_vllm_0.10.0_20250812-amd--Llama-3.1-8B-Instruct-FP8-KV*-pda_8b
'

while IFS= read -r GROUP; do
  [ -z "$GROUP" ] && continue  # skip empty lines
  echo "GROUP: ${GROUP}"
  echo "OUTPUT: ${GROUP//\*/-}"
  cat ${GROUP}/*summary.json | jq -c . > "${GROUP//\*/-}.jsonl"
  python3 json2csv.py "${GROUP//\*/-}.jsonl"
done <<< "$GROUP_LIST"