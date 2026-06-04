#!/usr/bin/env bash
# Clone or sync third_party repos to pinned refs in versions.lock.json.
# Does not install Python packages — run setup_env.sh after this.
# Requires: --yes  or  SAC_ALLOW_THIRD_PARTY_SYNC=1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

_sac_approved=0
for _arg in "$@"; do
  [[ "$_arg" == "--yes" ]] && _sac_approved=1
done
if [[ "$_sac_approved" != 1 && -z "${SAC_ALLOW_THIRD_PARTY_SYNC:-}" ]]; then
  cat <<'EOF'
Refusing to sync third_party (git fetch/checkout can move repos and discard local changes).

Approve explicitly:
  bash scripts/setup_third_party.sh --yes
  SAC_ALLOW_THIRD_PARTY_SYNC=1 bash scripts/setup_third_party.sh
EOF
  exit 1
fi
TP="$ROOT/third_party"
LOCK="$TP/versions.lock.json"
LOG="$TP/setup.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

lock_field() {
  python3 -c "import json,sys; c=json.load(open(sys.argv[1])); r=c[sys.argv[2]]; print(r[sys.argv[3]])" "$@"
}

lock_recursive() {
  python3 -c "import json,sys; c=json.load(open(sys.argv[1])); r=c[sys.argv[2]]; print('true' if r.get('recursive') else 'false')" "$@"
}

sync_repo() {
  local name="$1" url="$2" ref="$3" recursive="${4:-false}"
  local dest="$TP/$name"

  if [[ ! -d "$dest/.git" ]]; then
    log "clone $name (ref=$ref recursive=$recursive)"
    if [[ "$recursive" == "true" ]]; then
      git clone --recursive "$url" "$dest" >>"$LOG" 2>&1
    else
      git clone "$url" "$dest" >>"$LOG" 2>&1
    fi
  else
    log "fetch $name"
    git -C "$dest" fetch --tags --force >>"$LOG" 2>&1
  fi

  log "checkout $name -> $ref"
  if ! git -C "$dest" checkout "$ref" >>"$LOG" 2>&1; then
    git -C "$dest" checkout "tags/$ref" >>"$LOG" 2>&1
  fi

  if [[ "$name" == "gsplat" ]]; then
    log "gsplat: enforce v1.4.0 + submodules"
    git -C "$dest" checkout v1.4.0 >>"$LOG" 2>&1
    git -C "$dest" submodule update --init --recursive >>"$LOG" 2>&1
  elif [[ "$recursive" == "true" ]]; then
    git -C "$dest" submodule update --init --recursive >>"$LOG" 2>&1
  fi

  local head
  head="$(git -C "$dest" rev-parse HEAD)"
  log "$name HEAD=$head"
  echo "$name $ref $head" >>"$LOG"
}

mkdir -p "$TP/checkpoints"
: > "$LOG"
log "setup_third_party.sh start ROOT=$ROOT"

REPOS=(nerfstudio gsplat sam2 SegAnyGAussians gaussian-grouping SuGaR)
for name in "${REPOS[@]}"; do
  url="$(lock_field "$LOCK" "$name" repo)"
  ref="$(lock_field "$LOCK" "$name" tag)"
  recursive="$(lock_recursive "$LOCK" "$name")"
  sync_repo "$name" "$url" "$ref" "$recursive"
done

log "setup_third_party.sh done"
log "Next: bash scripts/setup_env.sh --yes"
