#!/bin/bash
export PROJECT="llmperf"

if [[ -z $DEVICE ]] ; then
  if [[ -n $(rocm-smi --showuniqueid | grep "ID:") ]] ; then
    # AMD devices - rocm
    export DEVICE="rocm"
  else
    echo "Error: No ROCm device found."
    exit 1
  fi
fi

# Ensure no environment is active
[ -n "$VIRTUAL_ENV" ] && deactivate
while [ -n "$CONDA_DEFAULT_ENV" ]; do conda deactivate ; done

echo "========================================"
echo "Setup: ${PROJECT}-${DEVICE}"
echo "========================================"
echo "Setup Python Virtual Environment"
VENV=".${PROJECT}-${DEVICE}-venv"
python3 -m venv $VENV
source $VENV/bin/activate

export WORKSPACE=${WORKSPACE:-"$HOME/workspace"}
export WORKDIR="$PWD"

mkdir -p results
ln -s $PWD/json2csv.py results/json2csv.py

echo "========================================"
echo "Project Setup"

git clone https://github.com/ray-project/llmperf.git
cd llmperf
sed -i 's/3.11/3.19/g' pyproject.toml
pip install ray pandas
pip install -e .
cd ..

pip install huggingface_hub hf_transfer

echo "========================================"
pip check
