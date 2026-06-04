#!/usr/bin/env bash
set -u

echo "=============================="
echo "SYSTEM"
echo "=============================="
date
echo "User: $(whoami)"
echo "Host: $(hostname)"
echo "PWD: $(pwd)"
echo

echo "=============================="
echo "OS / KERNEL"
echo "=============================="
uname -a
echo
if [ -f /etc/os-release ]; then
  cat /etc/os-release
fi
echo

echo "=============================="
echo "CPU / RAM"
echo "=============================="
lscpu | sed -n '1,25p' 2>/dev/null || true
echo
free -h 2>/dev/null || true
echo

echo "=============================="
echo "DISK"
echo "=============================="
df -h . 2>/dev/null || true
echo

echo "=============================="
echo "GPU / NVIDIA"
echo "=============================="
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi
  echo
  echo "--- NVIDIA query ---"
  nvidia-smi --query-gpu=name,driver_version,cuda_version,memory.total,compute_cap --format=csv,noheader 2>/dev/null || true
else
  echo "nvidia-smi not found"
fi
echo

echo "=============================="
echo "CUDA TOOLKIT"
echo "=============================="
if command -v nvcc >/dev/null 2>&1; then
  nvcc --version
else
  echo "nvcc not found"
fi
echo
echo "CUDA_HOME=${CUDA_HOME:-}"
echo "PATH=$PATH"
echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}"
echo

echo "=============================="
echo "PYTHON / PIP"
echo "=============================="
which python || true
python --version 2>/dev/null || true
which python3 || true
python3 --version 2>/dev/null || true
which pip || true
pip --version 2>/dev/null || true
which pip3 || true
pip3 --version 2>/dev/null || true
echo

echo "=============================="
echo "CONDA / VENV"
echo "=============================="
echo "VIRTUAL_ENV=${VIRTUAL_ENV:-}"
echo "CONDA_PREFIX=${CONDA_PREFIX:-}"
if command -v conda >/dev/null 2>&1; then
  conda --version
  conda info --envs 2>/dev/null || true
else
  echo "conda not found"
fi
echo

echo "=============================="
echo "PYTORCH CHECK"
echo "=============================="
python3 - <<'PY' 2>/dev/null || echo "PyTorch check failed or torch not installed"
import sys
print("python:", sys.version)
try:
    import torch
    print("torch:", torch.__version__)
    print("torch cuda:", torch.version.cuda)
    print("cuda available:", torch.cuda.is_available())
    print("device count:", torch.cuda.device_count())
    if torch.cuda.is_available():
        for i in range(torch.cuda.device_count()):
            print(f"device {i}:", torch.cuda.get_device_name(i))
            print(f"capability {i}:", torch.cuda.get_device_capability(i))
except Exception as e:
    print("torch error:", repr(e))
PY
echo

echo "=============================="
echo "KEY TOOLS"
echo "=============================="
for cmd in git ffmpeg colmap cmake ninja gcc g++ node npm pnpm yarn cargo rustc; do
  echo "--- $cmd ---"
  if command -v "$cmd" >/dev/null 2>&1; then
    which "$cmd"
    "$cmd" --version 2>&1 | head -n 3
  else
    echo "not found"
  fi
done
echo

echo "=============================="
echo "DONE"
echo "=============================="
