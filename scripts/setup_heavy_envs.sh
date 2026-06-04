#!/usr/bin/env bash
# Isolated heavy-stage conda envs (legacy torch stacks for SAGA, Gaussian Grouping, SuGaR).
# Creates/modifies ONLY: saga-lift, gaussian-grouping, sugar-mesh
# Does not activate spatial-asset-clean; uses conda run per command.
# Requires: --yes  or  SAC_ALLOW_HEAVY_ENV_SETUP=1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

_sac_approved=0
for _arg in "$@"; do
  [[ "$_arg" == "--yes" ]] && _sac_approved=1
done
if [[ "$_sac_approved" != 1 && -z "${SAC_ALLOW_HEAVY_ENV_SETUP:-}" ]]; then
  cat <<'EOF'
Refusing to build heavy-stage conda envs (saga-lift, gaussian-grouping, sugar-mesh).

Approve explicitly:
  bash scripts/setup_heavy_envs.sh --yes
  SAC_ALLOW_HEAVY_ENV_SETUP=1 bash scripts/setup_heavy_envs.sh
EOF
  exit 1
fi
TP="$ROOT/third_party"
STATUS_DIR="$ROOT/logs/setup"
STATUS_FILE="$STATUS_DIR/heavy_envs_status.json"
LOG="$STATUS_DIR/heavy_envs.log"

export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-7.5}"
export MAX_JOBS="${MAX_JOBS:-4}"

mkdir -p "$STATUS_DIR"
# Fresh logs each run (avoid stale errors from prior attempts).
: > "$LOG"
for _sac_heavy_log in saga-lift gaussian-grouping sugar-mesh; do
  : > "$STATUS_DIR/${_sac_heavy_log}.log"
done
unset _sac_heavy_log

if ! command -v conda &>/dev/null; then
  echo "ERROR: conda not found" | tee -a "$LOG"
  exit 1
fi

source "$(conda info --base)/etc/profile.d/conda.sh"

# Remember caller's active env (do not leave them in a heavy env)
_PREV_CONDA_ENV="${CONDA_DEFAULT_ENV:-}"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log_section() {
  local env="$1"
  local msg="$2"
  local section_log="$STATUS_DIR/${env}.log"
  echo "" | tee -a "$LOG" "$section_log"
  echo "========== $env: $msg ==========" | tee -a "$LOG" "$section_log"
}

log_cmd() {
  # log_cmd <env> <command...>
  local env="$1"
  shift
  local section_log="$STATUS_DIR/${env}.log"
  echo ">>> $*" | tee -a "$LOG" "$section_log"
  conda run -n "$env" --no-capture-output "$@" >>"$section_log" 2>&1
  local rc=$?
  echo "<<< exit $rc" | tee -a "$LOG" "$section_log"
  return $rc
}

prepare_repo_submodules() {
  # Rewrite SSH submodule URLs to HTTPS before sync/update (avoids hang on git@github.com).
  local repo="$1"
  local env="$2"
  local section_log="$STATUS_DIR/${env}.log"
  log "git submodule prep in $(basename "$repo")"
  git -C "$repo" config --local --unset-all url.https://github.com/.insteadOf || true
  git -C "$repo" config --local --add url.https://github.com/.insteadOf git@github.com:
  git -C "$repo" config --local --add url.https://github.com/.insteadOf ssh://git@github.com/
  git -C "$repo" submodule sync --recursive >>"$section_log" 2>&1
}

env_exists() {
  conda env list | grep -qE "^${1}[[:space:]]"
}

# Fresh status file at the start of each run (no stale per-env notes).
reset_heavy_envs_status_file() {
  python3 - "$STATUS_FILE" <<'PY'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
data = {
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "environments": {},
}
json.dump(data, open(path, "w"), indent=2)
PY
}

init_status_file() {
  python3 - "$STATUS_FILE" <<'PY'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    data = {}
if "environments" not in data:
    data["environments"] = {}
data["updated_at"] = datetime.now(timezone.utc).isoformat()
json.dump(data, open(path, "w"), indent=2)
PY
}

update_env_status() {
  # update_env_status <env_name> <json_patch_file>
  python3 - "$STATUS_FILE" "$1" "$2" <<'PY'
import json, sys
from datetime import datetime, timezone
path, env, patch_path = sys.argv[1:4]
data = json.load(open(path))
envs = data.setdefault("environments", {})
base = {
    "status": "failed",
    "env_created": False,
    "torch_installed": False,
    "torch_version": None,
    "torch_cuda_version": None,
    "nvcc_version": None,
    "cuda_toolkit_mismatch_risky": False,
    "repo_present": False,
    "submodules_present": False,
    "diff_gaussian_rasterization_installed": False,
    "simple_knn_installed": False,
    "minimal_repo_check": False,
    "cuda_extension_build_status": "not_attempted",
    "install_py_succeeded": None,
    "notes": [],
    "log_file": f"logs/setup/{env}.log",
}
# Merge: base + current-run env (reset at run start) + patch. Patches without "notes" keep existing notes.
existing = envs.get(env, {})
cur = {**base, **existing}
patch = json.load(open(patch_path))
if "notes" in patch:
    cur["notes"] = patch["notes"]
    patch = {k: v for k, v in patch.items() if k != "notes"}
cur.update(patch)
cur["checked_at"] = datetime.now(timezone.utc).isoformat()
envs[env] = cur
data["environments"] = envs
data["updated_at"] = cur["checked_at"]
json.dump(data, open(path, "w"), indent=2)
PY
}

write_patch() {
  # write_patch <path> "<json string>"  OR  write_patch <path> <<EOF ... EOF
  local path="$1"
  if [[ $# -ge 2 ]]; then
    printf "%s\n" "$2" > "$path"
  else
    cat > "$path"
  fi
}

json_array() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"
}

collect_cuda_info() {
  local env="$1"
  local patch="$STATUS_DIR/_patch_${env}_cuda.json"
  local torch_cuda nvcc_line risky torch_ver
  torch_ver="$(conda run -n "$env" --no-capture-output python -c "import torch; print(torch.__version__)" 2>/dev/null || echo "unknown")"
  torch_cuda="$(conda run -n "$env" --no-capture-output python -c "import torch; print(getattr(torch.version,'cuda',None) or 'none')" 2>/dev/null || echo "unknown")"
  local nvcc_path
  nvcc_path="$(conda run -n "$env" --no-capture-output bash -lc 'export PATH="$CONDA_PREFIX/bin:$PATH"; command -v nvcc 2>/dev/null || true' 2>/dev/null || true)"
  nvcc_line="$(conda run -n "$env" --no-capture-output bash -lc 'export PATH="$CONDA_PREFIX/bin:$PATH"; nvcc --version 2>/dev/null | grep release | head -1' 2>/dev/null || true)"
  if [[ -z "$nvcc_line" ]]; then
    nvcc_line="$(nvcc --version 2>/dev/null | grep release | head -1 || echo "nvcc not found (host fallback)")"
  fi
  local cuda_home
  cuda_home="$(conda info --base)/envs/${env}"
  risky="$(conda run -n "$env" --no-capture-output python -c "
import torch, subprocess, re, os
tv = getattr(torch.version, 'cuda', None) or ''
nvcc = ''
try:
    nvcc = subprocess.check_output(['nvcc','--version'], text=True, stderr=subprocess.STDOUT, env={**os.environ, 'PATH': os.environ.get('CONDA_PREFIX','') + '/bin:' + os.environ.get('PATH','')})
except Exception:
    pass
m = re.search(r'release ([0-9]+)', nvcc)
maj = int(m.group(1)) if m else -1
r = bool(tv.startswith('11.') and maj >= 12)
print('true' if r else 'false')
" 2>/dev/null || echo "false")"
  write_patch "$patch" <<EOF
{
  "torch_version": $(python3 -c "import json; print(json.dumps('$torch_ver'))"),
  "torch_cuda_version": $(python3 -c "import json; print(json.dumps('$torch_cuda'))"),
  "nvcc_version": $(python3 -c "import json; print(json.dumps('$nvcc_line'))"),
  "nvcc_path": $(python3 -c "import json; print(json.dumps('$nvcc_path'))"),
  "cuda_home": $(python3 -c "import json; print(json.dumps('$cuda_home'))"),
  "cuda_toolkit_mismatch_risky": $risky
}
EOF
  echo "$patch"
}

check_extension_imports() {
  local env="$1"
  conda run -n "$env" --no-capture-output python -c "
try:
    import diff_gaussian_rasterization  # noqa: F401
    import simple_knn  # noqa: F401
    print('extensions_ok')
except Exception as e:
    print('extensions_fail', e)
    raise SystemExit(1)
" >>"$STATUS_DIR/${env}.log" 2>&1
}

# gaussian-grouping submodule may lack simple_knn/ in git; setuptools needs the package dir for _C.so.
ensure_simple_knn_package_dir() {
  local simple_knn_repo="$1"
  mkdir -p "$simple_knn_repo/simple_knn"
  touch "$simple_knn_repo/simple_knn/__init__.py"
  touch "$simple_knn_repo/simple_knn/.gitkeep"
  log "ensured simple_knn/ package dir in $simple_knn_repo"
}

check_gg_runtime_imports() {
  local env="$1"
  conda run -n "$env" --no-capture-output bash -lc '
TORCH_LIB=$(python -c "import torch, pathlib; print(pathlib.Path(torch.__file__).parent / \"lib\")")
export LD_LIBRARY_PATH="$TORCH_LIB:$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}"
python -c "
import torch
from diff_gaussian_rasterization import GaussianRasterizationSettings, GaussianRasterizer
from simple_knn._C import distCUDA2
print(\"gg_runtime_ok\", torch.__version__, torch.version.cuda)
"
' >>"$STATUS_DIR/${env}.log" 2>&1
}

log_cuda_diagnostics() {
  local env="$1"
  conda run -n "$env" --no-capture-output python -c \
    "import torch; print('torch', torch.__version__, 'torch.version.cuda', torch.version.cuda)" \
    | tee -a "$LOG" "$STATUS_DIR/${env}.log"
  {
    echo "host nvcc: $(nvcc --version 2>/dev/null | grep release | head -1 || echo missing)"
    echo "host CUDA_HOME=${CUDA_HOME:-<unset>}"
    conda run -n "$env" --no-capture-output bash -lc \
      'echo env CONDA_PREFIX=$CONDA_PREFIX CUDA_HOME=${CUDA_HOME:-<unset>}; which nvcc 2>/dev/null || true; nvcc --version 2>/dev/null | grep release | head -1 || echo env nvcc missing'
  } | tee -a "$LOG" "$STATUS_DIR/${env}.log"
}

install_legacy_pip_tooling() {
  local env="$1"
  log_cmd "$env" python -m pip install "pip<24" "setuptools==59.5.0" "wheel<0.45"
}

install_torch_cu113_stack() {
  local env="$1"
  log_cmd "$env" python -m pip install \
    torch==1.12.1+cu113 torchvision==0.13.1+cu113 \
    --extra-index-url https://download.pytorch.org/whl/cu113
}

verify_torch_cu113() {
  local env="$1"
  local patch="$2"
  local section_log="$STATUS_DIR/${env}.log"
  if conda run -n "$env" --no-capture-output python -c "
import torch
v = torch.__version__
c = getattr(torch.version, 'cuda', None) or ''
assert '1.12.1+cu113' in v, f'torch version {v!r}'
assert str(c).startswith('11.3'), f'torch.version.cuda {c!r}'
print(v, c)
" >>"$section_log" 2>&1; then
    return 0
  fi
  write_patch "$patch" '{"torch_installed": false, "status": "incomplete", "notes": ["torch must be 1.12.1+cu113 with torch.version.cuda 11.3 after install"]}'
  update_env_status "$env" "$patch"
  return 1
}

install_saga_python_deps() {
  local env="$1"
  log_cmd "$env" python -m pip install \
    "numpy>=1.21,<2" \
    plyfile \
    "opencv-python-headless==4.10.0.84" \
    scipy tqdm
  log_cmd "$env" python -m pip uninstall -y opencv-python || true
}

install_gg_python_deps() {
  local env="$1"
  log_cmd "$env" python -m pip install \
    "numpy>=1.21,<2" \
    plyfile \
    "opencv-python-headless==4.10.0.84" \
    scipy tqdm scikit-learn
  log_cmd "$env" python -m pip uninstall -y opencv-python || true
  log_cmd "$env" python -m pip install --no-deps lpips
}

git_submodule_update_safe() {
  local repo="$1"
  local env="$2"
  prepare_repo_submodules "$repo" "$env"
  log "git submodule update --init --recursive in $(basename "$repo")"
  if ! git -C "$repo" submodule update --init --recursive >>"$STATUS_DIR/${env}.log" 2>&1; then
    log "WARNING: submodule update failed for $(basename "$repo") (continuing)"
    return 1
  fi
  return 0
}

# Isolated CUDA 11.8 compiler/toolkit inside the heavy conda env (not system /usr/local/cuda-12.x).
install_cuda11_toolchain_in_env() {
  local env="$1"
  local section_log="$STATUS_DIR/${env}.log"
  log "$env: installing env-local CUDA 11.8 (nvidia CCCL/nvcc/libs) + gcc/g++ 11 (conda-forge)"
  {
    echo ">>> conda install -n $env -c nvidia cuda-cccl=11.8 cuda-nvcc=11.8 cuda-cudart-dev=11.8 cuda-libraries-dev=11.8"
    conda install -n "$env" -y -c nvidia cuda-cccl=11.8 cuda-nvcc=11.8 cuda-cudart-dev=11.8 cuda-libraries-dev=11.8
    echo ">>> conda install -n $env -c conda-forge gcc_linux-64=11 gxx_linux-64=11"
    conda install -n "$env" -y -c conda-forge gcc_linux-64=11 gxx_linux-64=11
    echo ">>> conda install -n $env -c conda-forge linux sysroot/devel headers"
    conda install -n "$env" -y -c conda-forge \
      sysroot_linux-64 \
      kernel-headers_linux-64 \
      libgcc-devel_linux-64 \
      libstdcxx-devel_linux-64
  } >>"$section_log" 2>&1
}

# CUB / Thrust / libcu++ headers (cuda-cccl may install under include/ or targets/.../include/cccl/).
verify_cuda_cccl_headers() {
  local env="$1"
  SAC_SKIP_REASON=""
  local section_log="$STATUS_DIR/${env}.log"
  local out
  out="$(conda run -n "$env" --no-capture-output bash -lc '
P="$CONDA_PREFIX"
DIRS=(
  "$P/include"
  "$P/targets/x86_64-linux/include"
  "$P/targets/x86_64-linux/include/cccl"
)
for rel in cub/cub.cuh thrust/complex.h cuda/std/type_traits; do
  found=""
  for d in "${DIRS[@]}"; do
    if [[ -f "$d/$rel" ]]; then
      echo "ok:$d/$rel"
      found=1
      break
    fi
  done
  if [[ -z "$found" ]]; then
    echo "missing:$rel (checked: ${DIRS[*]})"
  fi
done
' 2>/dev/null || true)"
  {
    echo "=== CUDA CCCL header check ($env) ==="
    echo "$out"
  } >>"$section_log" 2>&1

  if echo "$out" | grep -q '^missing:'; then
    SAC_SKIP_REASON="CUDA CCCL/CUB/Thrust headers missing in $env (need cuda-cccl=11.8): $(echo "$out" | grep '^missing:' | tr '\n' ' ')"
    log "$env: SKIP extension build — ${SAC_SKIP_REASON}"
    return 1
  fi
  log "$env: CUDA header check OK (cub.cuh, thrust/complex.h, cuda/std/type_traits)"
  return 0
}

# Sets SAC_CUDA_HOME_FOR_BUILD; return 0 only if which nvcc is inside the conda env and CUDA major < 12.
verify_env_local_nvcc() {
  local env="$1"
  SAC_SKIP_REASON=""
  local env_prefix nvcc_path nvcc_line nvcc_major=""
  env_prefix="$(conda info --base)/envs/${env}"
  SAC_CUDA_HOME_FOR_BUILD="$env_prefix"

  nvcc_path="$(conda run -n "$env" --no-capture-output bash -lc 'export PATH="$CONDA_PREFIX/bin:$PATH"; command -v nvcc 2>/dev/null || true')"
  nvcc_line="$(conda run -n "$env" --no-capture-output bash -lc 'export PATH="$CONDA_PREFIX/bin:$PATH"; nvcc --version 2>/dev/null | grep release | head -1' 2>/dev/null || true)"

  log "$env: which nvcc => ${nvcc_path:-<missing>}"
  log "$env: nvcc release => ${nvcc_line:-<missing>}"

  if [[ -z "$nvcc_path" ]]; then
    SAC_SKIP_REASON="nvcc not on PATH in $env after CUDA 11.8 toolchain install"
    return 1
  fi

  if [[ "$nvcc_path" != "${env_prefix}"* ]]; then
    local sys_hint=""
    if [[ "$nvcc_path" == *"cuda-12"* ]]; then
      sys_hint=" (system CUDA 12.x wins PATH — need env-local nvcc first)"
    fi
    SAC_SKIP_REASON="which nvcc is outside $env: ${nvcc_path}${sys_hint}"
    return 1
  fi

  if [[ "$nvcc_line" =~ release[[:space:]]+([0-9]+)\. ]]; then
    nvcc_major="${BASH_REMATCH[1]}"
  fi
  if [[ -z "$nvcc_major" || "$nvcc_major" -ge 12 ]]; then
    local host_nvcc
    host_nvcc="$(command -v nvcc 2>/dev/null || echo missing)"
    SAC_SKIP_REASON="env nvcc reports CUDA ${nvcc_major:-unknown} at ${nvcc_path}; host nvcc=${host_nvcc}; need CUDA 11.x inside env"
    return 1
  fi

  log "$env: using env-local CUDA 11.x toolchain CUDA_HOME=$SAC_CUDA_HOME_FOR_BUILD"
  return 0
}

# Expect torch.version.cuda prefix (e.g. 11.3 for cu113 legacy envs).
prepare_legacy_cuda_build_env() {
  local env="$1"
  local expect_torch_cuda_prefix="$2"
  SAC_SKIP_REASON=""
  local torch_cuda
  torch_cuda="$(conda run -n "$env" --no-capture-output python -c "import torch; print(getattr(torch.version,'cuda',None) or '')" 2>/dev/null || echo "")"
  if [[ ! "$torch_cuda" =~ ^${expect_torch_cuda_prefix} ]]; then
    SAC_SKIP_REASON="unexpected torch.version.cuda=${torch_cuda} (expected ${expect_torch_cuda_prefix}*)"
    return 1
  fi
  install_cuda11_toolchain_in_env "$env" || true
  if ! verify_env_local_nvcc "$env"; then
    return 1
  fi
  verify_cuda_cccl_headers "$env"
}

# Shared conda CUDA build env: CCCL via CPATH/CXXFLAGS only — do not override C_INCLUDE_PATH/CPLUS_INCLUDE_PATH.
_cuda_build_env_bash_snippet() {
  cat <<'SNIP'
export CUDA_HOME="$CONDA_PREFIX"
export CUDA_PATH="$CONDA_PREFIX"
export PATH="$CONDA_PREFIX/bin:$PATH"
unset C_INCLUDE_PATH
unset CPLUS_INCLUDE_PATH
export CC="$CONDA_PREFIX/bin/x86_64-conda-linux-gnu-cc"
export CXX="$CONDA_PREFIX/bin/x86_64-conda-linux-gnu-c++"
export CUDAHOSTCXX="$CONDA_PREFIX/bin/x86_64-conda-linux-gnu-c++"
SAC_CCCL_DIRS=(
  "$CONDA_PREFIX/include"
  "$CONDA_PREFIX/targets/x86_64-linux/include"
  "$CONDA_PREFIX/targets/x86_64-linux/include/cccl"
)
SAC_CCCL_CPATH=""
SAC_CCCL_CFLAGS=""
SAC_CCCL_NVCC=""
for _d in "${SAC_CCCL_DIRS[@]}"; do
  [[ -d "$_d" ]] || continue
  SAC_CCCL_CPATH="${SAC_CCCL_CPATH:+$SAC_CCCL_CPATH:}$_d"
  SAC_CCCL_CFLAGS="${SAC_CCCL_CFLAGS} -I$_d"
  SAC_CCCL_NVCC="${SAC_CCCL_NVCC} -I$_d"
done
unset _d
export CPATH="${SAC_CCCL_CPATH}${CPATH:+:$CPATH}"
export CFLAGS="${CFLAGS:-}${SAC_CCCL_CFLAGS}"
export CXXFLAGS="${CXXFLAGS:-}${SAC_CCCL_CFLAGS}"
export NVCC_FLAGS="${NVCC_FLAGS:-}${SAC_CCCL_NVCC}"
export LIBRARY_PATH="$CONDA_PREFIX/targets/x86_64-linux/lib:$CONDA_PREFIX/lib:${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="$CONDA_PREFIX/targets/x86_64-linux/lib:$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}"
SNIP
}

_log_cuda_build_env_diagnostics() {
  cat <<'SNIP'
echo "=== cuda build env diagnostics ==="
echo "CC=$CC"
echo "CXX=$CXX"
echo "CUDAHOSTCXX=$CUDAHOSTCXX"
echo "CPATH=${CPATH:-<unset>}"
echo "C_INCLUDE_PATH=${C_INCLUDE_PATH:-<unset>}"
echo "CPLUS_INCLUDE_PATH=${CPLUS_INCLUDE_PATH:-<unset>}"
echo "CONDA_BUILD_SYSROOT=${CONDA_BUILD_SYSROOT:-<unset>}"
echo "CUDA_HOME=$CUDA_HOME pwd=$(pwd) which nvcc=$(command -v nvcc 2>/dev/null || echo missing)"
nvcc --version 2>/dev/null | grep release | head -1 || true
echo "--- $CXX -E -x c++ -v /dev/null (include search) ---"
"$CXX" -E -x c++ -v /dev/null 2>&1 | sed -n '/#include <...> search starts here:/,/End of search list./p' || true
for h in cub/cub.cuh thrust/complex.h cuda/std/type_traits; do
  found=""
  for d in "${SAC_CCCL_DIRS[@]}"; do
    f="$d/$h"
    if [[ -f "$f" ]]; then echo "header ok: $f"; found=1; break; fi
  done
  [[ -n "$found" ]] || echo "header MISSING: $h"
done
SNIP
}

verify_compiler_sysroot_sanity() {
  local env="$1"
  SAC_SKIP_REASON=""
  local section_log="$STATUS_DIR/${env}.log"
  local probe_rc=0
  {
    echo "=== compiler/sysroot sanity ($env) ==="
    conda run -n "$env" --no-capture-output bash -lc "
$(_cuda_build_env_bash_snippet)
export TORCH_CUDA_ARCH_LIST=\"${TORCH_CUDA_ARCH_LIST}\"
export MAX_JOBS=\"${MAX_JOBS}\"
echo '--- find stdlib.h ---'
find \"\$CONDA_PREFIX\" -name stdlib.h 2>/dev/null | head -5
echo '--- find math.h ---'
find \"\$CONDA_PREFIX\" -name math.h 2>/dev/null | head -5
$(_log_cuda_build_env_diagnostics)
_probe=\$(mktemp -t sac-probe.XXXXXX.cpp)
cat > \"\$_probe\" <<'PROBE'
#include <cstdlib>
#include <cmath>
int main(){ return 0; }
PROBE
echo '--- compile probe ---'
\"\$CXX\" -o \"\${_probe}.out\" \"\$_probe\"
_probe_rc=\$?
rm -f \"\$_probe\" \"\${_probe}.out\"
exit \$_probe_rc
"
  } >>"$section_log" 2>&1 || probe_rc=$?

  if [[ $probe_rc -ne 0 ]]; then
    SAC_SKIP_REASON="conda compiler/sysroot cannot resolve stdlib.h/math.h (C++ probe compile failed; see ${env}.log)"
    log "$env: SKIP extension build — ${SAC_SKIP_REASON}"
    return 1
  fi
  log "$env: compiler/sysroot sanity OK (stdlib.h/math.h probe compile succeeded)"
  return 0
}

log_cmd_with_cuda_env() {
  # log_cmd_with_cuda_env <env> [workdir] <command...>
  local env="$1"
  shift
  local workdir=""
  if [[ $# -ge 1 && -d "$1" ]]; then
    workdir="$1"
    shift
  fi
  local section_log="$STATUS_DIR/${env}.log"
  local cmd_quoted cd_prefix=""
  cmd_quoted="$(printf '%q ' "$@")"
  if [[ -n "$workdir" ]]; then
    cd_prefix="cd $(printf '%q' "$workdir") && "
  fi
  echo ">>> [cuda build env]${workdir:+ cwd=$workdir} $*" | tee -a "$LOG" "$section_log"
  conda run -n "$env" --no-capture-output bash -lc "
$(_cuda_build_env_bash_snippet)
export TORCH_CUDA_ARCH_LIST=\"${TORCH_CUDA_ARCH_LIST}\"
export MAX_JOBS=\"${MAX_JOBS}\"
$(_log_cuda_build_env_diagnostics)
${cd_prefix}${cmd_quoted}
" >>"$section_log" 2>&1
  local rc=$?
  echo "<<< exit $rc" | tee -a "$LOG" "$section_log"
  return $rc
}

log_cmd_cuda_build() {
  log_cmd_with_cuda_env "$@"
}

install_libxcrypt_in_env() {
  local env="$1"
  local section_log="$STATUS_DIR/${env}.log"
  log "$env: installing libxcrypt for crypt.h (conda-forge)"
  {
    echo ">>> conda install -n $env -c conda-forge libxcrypt libxcrypt-devel"
    if ! conda install -n "$env" -y -c conda-forge libxcrypt libxcrypt-devel; then
      echo ">>> fallback: libxcrypt only (libxcrypt-devel unavailable)"
      conda install -n "$env" -y -c conda-forge libxcrypt || true
    fi
    echo ">>> find crypt.h in env"
    conda run -n "$env" --no-capture-output bash -lc 'find "$CONDA_PREFIX" -name crypt.h 2>/dev/null | head -20'
  } >>"$section_log" 2>&1
}

verify_crypt_header() {
  local env="$1"
  SAC_SKIP_REASON=""
  local section_log="$STATUS_DIR/${env}.log"
  local out
  out="$(conda run -n "$env" --no-capture-output bash -lc '
P="$CONDA_PREFIX"
DIRS=(
  "$P/include"
  "$P/x86_64-conda-linux-gnu/sysroot/usr/include"
)
found=""
for d in "${DIRS[@]}"; do
  if [[ -f "$d/crypt.h" ]]; then
    echo "ok:$d/crypt.h"
    found=1
    break
  fi
done
if [[ -z "$found" ]]; then
  echo "missing:crypt.h"
  find "$P" -name crypt.h 2>/dev/null | head -10 | while read -r f; do echo "find:$f"; done
fi
' 2>/dev/null || true)"
  {
    echo "=== crypt.h check ($env) ==="
    echo "$out"
  } >>"$section_log" 2>&1

  if echo "$out" | grep -q '^missing:'; then
    SAC_SKIP_REASON="missing crypt.h / libxcrypt-devel in $env: $(echo "$out" | grep -E '^(missing:|find:)' | tr '\n' ' ')"
    log "$env: SKIP extension build — ${SAC_SKIP_REASON}"
    return 1
  fi
  log "$env: crypt.h check OK"
  return 0
}

# Sets globals: SAC_EXT_DIFF_OK SAC_EXT_KNN_OK SAC_EXT_BUILD SAC_EXT_EXTRA_NOTES (array)
build_legacy_cuda_extensions() {
  local env="$1"
  local repo="$2"
  SAC_EXT_DIFF_OK=false
  SAC_EXT_KNN_OK=false
  SAC_EXT_BUILD="not_attempted"
  SAC_EXT_EXTRA_NOTES=()

  local dgr="$repo/submodules/diff-gaussian-rasterization"
  local sk="$repo/submodules/simple-knn"

  log_cuda_diagnostics "$env"

  if ! prepare_legacy_cuda_build_env "$env" "11.3"; then
    log "SKIP extension build for $env: ${SAC_SKIP_REASON}"
    if [[ "${SAC_SKIP_REASON}" == *"headers missing"* || "${SAC_SKIP_REASON}" == *"CCCL"* ]]; then
      SAC_EXT_BUILD="skipped_cuda_cccl_headers_missing"
    else
      SAC_EXT_BUILD="skipped_cuda_toolchain_mismatch"
    fi
    SAC_EXT_EXTRA_NOTES+=("${SAC_SKIP_REASON}")
    return 0
  fi

  if [[ "$env" == "gaussian-grouping" ]]; then
    install_libxcrypt_in_env "$env" || true
    if ! verify_crypt_header "$env"; then
      SAC_EXT_BUILD="skipped_missing_crypt_h"
      SAC_EXT_EXTRA_NOTES+=("${SAC_SKIP_REASON}")
      return 0
    fi
  fi

  if ! verify_compiler_sysroot_sanity "$env"; then
    SAC_EXT_BUILD="skipped_compiler_sysroot"
    SAC_EXT_EXTRA_NOTES+=("${SAC_SKIP_REASON}")
    return 0
  fi

  if [[ ! -d "$dgr" || ! -d "$sk" ]]; then
    SAC_EXT_BUILD="failed"
    SAC_EXT_EXTRA_NOTES+=("diff-gaussian-rasterization or simple-knn submodule directory missing")
    return 0
  fi

  if log_cmd_cuda_build "$env" python -m pip install --no-build-isolation -e "$dgr"; then
    SAC_EXT_DIFF_OK=true
  else
    SAC_EXT_BUILD="failed"
    SAC_EXT_EXTRA_NOTES+=("diff-gaussian-rasterization pip build failed")
  fi

  if [[ "$env" == "gaussian-grouping" ]]; then
    ensure_simple_knn_package_dir "$sk"
  fi

  if log_cmd_cuda_build "$env" python -m pip install --no-build-isolation -e "$sk"; then
    SAC_EXT_KNN_OK=true
  else
    SAC_EXT_BUILD="failed"
    SAC_EXT_EXTRA_NOTES+=("simple-knn pip build failed")
  fi

  if [[ "$SAC_EXT_DIFF_OK" == true && "$SAC_EXT_KNN_OK" == true ]]; then
    if [[ "$env" == "gaussian-grouping" ]]; then
      if check_gg_runtime_imports "$env"; then
        SAC_EXT_BUILD="succeeded"
      else
        SAC_EXT_BUILD="failed"
        SAC_EXT_EXTRA_NOTES+=("gaussian-grouping runtime import failed (torch + diff_gaussian_rasterization + simple_knn._C; see gaussian-grouping.log)")
      fi
    elif check_extension_imports "$env"; then
      SAC_EXT_BUILD="succeeded"
    else
      SAC_EXT_BUILD="failed"
      SAC_EXT_EXTRA_NOTES+=("extensions built but import check failed")
    fi
  elif [[ "$SAC_EXT_BUILD" != "failed" ]]; then
    SAC_EXT_BUILD="failed"
  fi
  return 0
}

setup_saga_lift() {
  local env="saga-lift"
  local repo="$TP/SegAnyGAussians"
  local patch="$STATUS_DIR/_patch_${env}.json"
  log_section "$env" "start"

  if ! env_exists "$env"; then
    log "creating conda env $env"
    conda create -n "$env" python=3.10 -y >>"$STATUS_DIR/${env}.log" 2>&1
  fi
  write_patch "$patch" '{"env_created": true}'
  update_env_status "$env" "$patch"

  install_legacy_pip_tooling "$env" || true

  if ! install_torch_cu113_stack "$env"; then
    write_patch "$patch" '{"torch_installed": false, "status": "failed", "notes": ["torch pip install failed"]}'
    update_env_status "$env" "$patch"
    return 0
  fi
  if ! verify_torch_cu113 "$env" "$patch"; then
    return 0
  fi

  install_saga_python_deps "$env" || true
  if ! verify_torch_cu113 "$env" "$patch"; then
    return 0
  fi

  merge_cuda_patch "$env"

  local torch_ver
  torch_ver="$(conda run -n "$env" --no-capture-output python -c "import torch; print(torch.__version__)" 2>/dev/null || echo "unknown")"

  if [[ ! -d "$repo" ]]; then
    write_patch "$patch" '{"repo_present": false, "status": "incomplete", "notes": ["SegAnyGAussians missing — run setup_third_party.sh"]}'
    update_env_status "$env" "$patch"
    return 0
  fi

  git_submodule_update_safe "$repo" "$env" || true

  local dgr="$repo/submodules/diff-gaussian-rasterization"
  local sk="$repo/submodules/simple-knn"
  build_legacy_cuda_extensions "$env" "$repo"

  local ext_build="$SAC_EXT_BUILD"
  local diff_ok="$SAC_EXT_DIFF_OK"
  local knn_ok="$SAC_EXT_KNN_OK"
  local -a status_notes=("ready requires train_scene.py, train_contrastive_feature.py or prompt_segmenting.ipynb, and importable diff_gaussian_rasterization + simple_knn")
  if [[ ${#SAC_EXT_EXTRA_NOTES[@]} -gt 0 ]]; then
    status_notes+=("${SAC_EXT_EXTRA_NOTES[@]}")
  fi

  local minimal=false
  if [[ -f "$repo/train_scene.py" ]] && { [[ -f "$repo/train_contrastive_feature.py" ]] || [[ -f "$repo/prompt_segmenting.ipynb" ]]; }; then
    minimal=true
  fi

  local final="incomplete"
  if [[ "$diff_ok" == true && "$knn_ok" == true && "$minimal" == true && "$ext_build" == "succeeded" ]]; then
    final="ready"
    status_notes=("extensions built and importable; minimal repo layout OK")
  elif ! conda run -n "$env" --no-capture-output python -c "import torch" &>/dev/null; then
    final="failed"
  fi

  write_patch "$patch" <<EOF
{
  "status": "$final",
  "env_created": true,
  "torch_installed": true,
  "torch_version": "$(echo "$torch_ver" | sed 's/"/\\"/g')",
  "repo_present": true,
  "submodules_present": $( [[ -d "$dgr" && -d "$sk" ]] && echo true || echo false ),
  "diff_gaussian_rasterization_installed": $diff_ok,
  "simple_knn_installed": $knn_ok,
  "minimal_repo_check": $minimal,
  "cuda_extension_build_status": "$ext_build",
  "notes": $(json_array "${status_notes[@]}")
}
EOF
  update_env_status "$env" "$patch"
  merge_cuda_patch "$env"
  return 0
}

merge_cuda_patch() {
  local env="$1"
  local cuda_patch
  cuda_patch="$(collect_cuda_info "$env")"
  update_env_status "$env" "$cuda_patch"
}

setup_gaussian_grouping() {
  local env="gaussian-grouping"
  local repo="$TP/gaussian-grouping"
  local patch="$STATUS_DIR/_patch_${env}.json"
  log_section "$env" "start"

  if ! env_exists "$env"; then
    log "creating conda env $env"
    conda create -n "$env" python=3.8 -y >>"$STATUS_DIR/${env}.log" 2>&1
  fi
  write_patch "$patch" '{"env_created": true}'
  update_env_status "$env" "$patch"

  install_legacy_pip_tooling "$env" || true

  if ! install_torch_cu113_stack "$env"; then
    write_patch "$patch" '{"torch_installed": false, "status": "failed", "notes": ["torch pip install failed"]}'
    update_env_status "$env" "$patch"
    return 0
  fi
  if ! verify_torch_cu113 "$env" "$patch"; then
    return 0
  fi

  install_gg_python_deps "$env" || true
  if ! verify_torch_cu113 "$env" "$patch"; then
    return 0
  fi

  merge_cuda_patch "$env"

  local torch_ver
  torch_ver="$(conda run -n "$env" --no-capture-output python -c "import torch; print(torch.__version__)" 2>/dev/null || echo "unknown")"

  if [[ ! -d "$repo" ]]; then
    write_patch "$patch" '{"repo_present": false, "status": "incomplete", "notes": ["gaussian-grouping missing — run setup_third_party.sh"]}'
    update_env_status "$env" "$patch"
    return 0
  fi

  git_submodule_update_safe "$repo" "$env" || true

  local dgr="$repo/submodules/diff-gaussian-rasterization"
  local sk="$repo/submodules/simple-knn"
  build_legacy_cuda_extensions "$env" "$repo"

  local ext_build="$SAC_EXT_BUILD"
  local diff_ok="$SAC_EXT_DIFF_OK"
  local knn_ok="$SAC_EXT_KNN_OK"
  local -a status_notes=("ready requires convert.py, script/train.sh, and importable diff_gaussian_rasterization + simple_knn")
  if [[ ${#SAC_EXT_EXTRA_NOTES[@]} -gt 0 ]]; then
    status_notes+=("${SAC_EXT_EXTRA_NOTES[@]}")
  fi

  local minimal=false
  if [[ -f "$repo/convert.py" ]] && [[ -f "$repo/script/train.sh" ]]; then
    minimal=true
  fi

  local runtime_ok=false
  local final="incomplete"
  if [[ "$diff_ok" == true && "$knn_ok" == true && "$minimal" == true && "$ext_build" == "succeeded" ]]; then
    if check_gg_runtime_imports "$env"; then
      runtime_ok=true
      final="ready"
      status_notes=("extensions built; runtime import OK (torch, diff_gaussian_rasterization, simple_knn._C); minimal repo layout OK")
    else
      SAC_EXT_BUILD="failed"
      ext_build="failed"
      status_notes+=("runtime import check failed after build (import torch before simple_knn; LD_LIBRARY_PATH must include torch/lib)")
    fi
  elif ! conda run -n "$env" --no-capture-output python -c "import torch" &>/dev/null; then
    final="failed"
  fi

  write_patch "$patch" <<EOF
{
  "status": "$final",
  "env_created": true,
  "torch_installed": true,
  "torch_version": "$(echo "$torch_ver" | sed 's/"/\\"/g')",
  "repo_present": true,
  "submodules_present": $( [[ -d "$dgr" && -d "$sk" ]] && echo true || echo false ),
  "diff_gaussian_rasterization_installed": $diff_ok,
  "simple_knn_installed": $( [[ "$runtime_ok" == true || "$knn_ok" == true ]] && echo true || echo false ),
  "minimal_repo_check": $minimal,
  "cuda_extension_build_status": "$ext_build",
  "notes": $(json_array "${status_notes[@]}")
}
EOF
  update_env_status "$env" "$patch"
  merge_cuda_patch "$env"
  return 0
}

install_torch_cu118_stack() {
  local env="$1"
  log_cmd "$env" python -m pip install \
    torch==2.0.1+cu118 torchvision==0.15.2+cu118 \
    --extra-index-url https://download.pytorch.org/whl/cu118
}

verify_torch_cu118() {
  local env="$1"
  local patch="$2"
  local section_log="$STATUS_DIR/${env}.log"
  if conda run -n "$env" --no-capture-output python -c "
import torch
v = torch.__version__
c = getattr(torch.version, 'cuda', None) or ''
assert '2.0.1+cu118' in v, f'torch version {v!r}'
assert str(c).startswith('11.8'), f'torch.version.cuda {c!r}'
print(v, c)
" >>"$section_log" 2>&1; then
    return 0
  fi
  write_patch "$patch" '{"torch_installed": false, "status": "incomplete", "notes": ["torch must be 2.0.1+cu118 with torch.version.cuda 11.8 before SuGaR install.py"]}'
  update_env_status "$env" "$patch"
  return 1
}

verify_sugar_install_prereqs() {
  local repo="$1"
  SAC_SKIP_REASON=""
  local -a missing=()
  [[ -f "$repo/environment.yml" ]] || missing+=("environment.yml")
  [[ -d "$repo/gaussian_splatting/submodules/diff-gaussian-rasterization" ]] \
    || missing+=("gaussian_splatting/submodules/diff-gaussian-rasterization")
  if [[ ${#missing[@]} -gt 0 ]]; then
    SAC_SKIP_REASON="SuGaR install prereqs missing under $(basename "$repo") (git submodule update --init --recursive): ${missing[*]}"
    return 1
  fi
  return 0
}

setup_sugar_mesh() {
  local env="sugar-mesh"
  local repo="$TP/SuGaR"
  local patch="$STATUS_DIR/_patch_${env}.json"
  log_section "$env" "start"

  if ! env_exists "$env"; then
    log "creating conda env $env"
    conda create -n "$env" python=3.9 -y >>"$STATUS_DIR/${env}.log" 2>&1
  fi
  write_patch "$patch" '{"env_created": true}'
  update_env_status "$env" "$patch"

  local install_py_ok=false torch_ok=false minimal=false
  local final="incomplete"
  local -a notes=()

  if [[ ! -d "$repo" ]]; then
    write_patch "$patch" "$(python3 -c "import json; print(json.dumps({'repo_present': False, 'status': 'incomplete', 'notes': ['SuGaR repo missing']}))")"
    update_env_status "$env" "$patch"
    return 0
  fi

  install_legacy_pip_tooling "$env" || true
  install_cuda11_toolchain_in_env "$env" || true

  if ! install_torch_cu118_stack "$env"; then
    write_patch "$patch" '{"torch_installed": false, "status": "failed", "notes": ["torch 2.0.1+cu118 pip install failed"]}'
    update_env_status "$env" "$patch"
    return 0
  fi
  if ! verify_torch_cu118 "$env" "$patch"; then
    return 0
  fi
  torch_ok=true

  log_cuda_diagnostics "$env"
  merge_cuda_patch "$env"

  git_submodule_update_safe "$repo" "$env" || true

  if [[ ! -f "$repo/install.py" ]]; then
    notes+=("install.py not found")
  elif ! verify_sugar_install_prereqs "$repo"; then
    notes+=("${SAC_SKIP_REASON}")
  else
    log "$env: running SuGaR install.py with cwd=$repo"
    if log_cmd_with_cuda_env "$env" "$repo" python install.py; then
      install_py_ok=true
    else
      notes+=("install.py exited non-zero (see sugar-mesh.log; cwd must be SuGaR repo root)")
    fi
  fi

  if conda run -n "$env" --no-capture-output python -c "import torch; print(torch.__version__)" >>"$STATUS_DIR/${env}.log" 2>&1; then
    if ! verify_torch_cu118 "$env" "$patch"; then
      torch_ok=false
      notes+=("torch import/version check failed after install.py")
    fi
  else
    torch_ok=false
    notes+=("torch import failed after install.py")
  fi

  if [[ -f "$repo/extract_mesh.py" ]] && { [[ -d "$repo/gaussian_splatting" ]] || [[ -d "$repo/sugar_extractors" ]]; }; then
    minimal=true
  else
    notes+=("SuGaR layout check failed: need extract_mesh.py and gaussian_splatting/ or sugar_extractors/")
  fi

  local torch_ver="unknown"
  if [[ "$torch_ok" == true ]]; then
    torch_ver="$(conda run -n "$env" --no-capture-output python -c "import torch; print(torch.__version__)" 2>/dev/null)"
  fi

  if [[ "$install_py_ok" == true && "$torch_ok" == true && "$minimal" == true ]]; then
    final="ready"
    notes=("SuGaR install.py succeeded; torch 2.0.1+cu118 import OK; layout checks passed")
  elif [[ "$torch_ok" == false ]]; then
    final="failed"
  else
    final="incomplete"
    notes+=("ready requires install.py success, torch 2.0.1+cu118 import, and SuGaR layout paths")
  fi

  write_patch "$patch" <<EOF
{
  "status": "$final",
  "env_created": true,
  "torch_installed": $torch_ok,
  "torch_version": "$(echo "$torch_ver" | sed 's/"/\\"/g')",
  "repo_present": true,
  "submodules_present": true,
  "install_py_succeeded": $install_py_ok,
  "minimal_repo_check": $minimal,
  "cuda_extension_build_status": "n/a",
  "notes": $(json_array "${notes[@]}")
}
EOF
  update_env_status "$env" "$patch"
  merge_cuda_patch "$env"
  return 0
}

# --- main ---
log "setup_heavy_envs.sh start"
log "TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST MAX_JOBS=$MAX_JOBS"
reset_heavy_envs_status_file

# Continue through all heavy envs even if SAGA/GG extensions fail (set -e would abort on git/pip otherwise).
set +e
setup_saga_lift
setup_gaussian_grouping
setup_sugar_mesh
set -e

init_status_file

log "heavy env status: $STATUS_FILE"
log "per-env logs: $STATUS_DIR/saga-lift.log $STATUS_DIR/gaussian-grouping.log $STATUS_DIR/sugar-mesh.log"
log "Verify: bash scripts/verify_deps.sh --full"

# Restore caller conda env if it was active
if [[ -n "$_PREV_CONDA_ENV" ]]; then
  conda activate "$_PREV_CONDA_ENV" 2>/dev/null || true
else
  conda deactivate 2>/dev/null || true
fi
