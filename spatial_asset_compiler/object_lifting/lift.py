"""Orchestrate object lifting: SAGA → Gaussian Grouping → vote emergency."""

from __future__ import annotations

import time

from spatial_asset_compiler.config import PipelineState
from spatial_asset_compiler.object_lifting.gaussian_grouping_runner import run_gaussian_grouping
from spatial_asset_compiler.object_lifting.projection import run_vote_fallback
from spatial_asset_compiler.object_lifting.saga_runner import run_saga


def run_object_lifting(state: PipelineState) -> dict:
    start = time.perf_counter()
    meta: dict | None = None

    meta = run_saga(state)
    if meta and meta.get("object_count", 0) > 0:
        state.benchmarks["object_lifting_method"] = meta.get("lifting_method", "saga")
        state.benchmarks["object_lifting_degraded"] = False
    else:
        meta = run_gaussian_grouping(state)
        if meta and meta.get("object_count", 0) > 0:
            method = meta.get("lifting_method", "gaussian_grouping")
            state.benchmarks["object_lifting_method"] = method
            state.benchmarks["object_lifting_degraded"] = "pseudo" in method
        elif state.profile.allow_vote_fallback:
            meta = run_vote_fallback(state)
            state.benchmarks["object_lifting_method"] = "vote_fallback"
            state.benchmarks["object_lifting_degraded"] = True
            state.warnings.append("object_lifting: degraded to vote_fallback")
        else:
            state.failures.append("object_lifting: SAGA and Gaussian Grouping failed")
            raise RuntimeError(
                "Object lifting failed. Install saga-lift / gaussian-grouping envs. "
                "See exports/.../object_lifting/*.log"
            )

    duration = time.perf_counter() - start
    state.benchmarks.setdefault("object_lifting", {})
    state.benchmarks["object_lifting"].update(
        {
            "lifting_time_s": duration,
            "object_count": meta.get("object_count", 0) if meta else 0,
            "method": state.benchmarks.get("object_lifting_method"),
        }
    )
    return meta or {}
