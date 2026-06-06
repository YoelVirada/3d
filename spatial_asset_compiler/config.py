"""Pipeline configuration and hardware profiles for RTX 2080 Ti (11GB)."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

ProfileName = Literal["dev", "production", "mesh-full"]

REPO_ROOT = Path(__file__).resolve().parent.parent
THIRD_PARTY = REPO_ROOT / "third_party"
DATA_CAPTURES = REPO_ROOT / "data" / "captures"
DEFAULT_EXPORTS = REPO_ROOT / "exports"
LOGS_ROOT = REPO_ROOT / "logs"

ASSET_VERSION = "0.1.0"


@dataclass
class ProfileConfig:
    name: ProfileName
    frame_stride: int = 2
    splat_max_iterations: int = 7000
    sam2_model: str = "sam2.1_hiera_small"
    sam2_keyframe_stride: int = 8
    saga_feature_iterations: int = 5000
    mesh_top_n: int = 5
    allow_vote_fallback: bool = True
    run_sugar_scene_mesh: bool = False
    ar_max_frames: int = 80
    ar_min_time_delta_s: float = 0.25
    ar_min_translation_m: float = 0.02
    ar_max_translation_jump_m: float = 0.5
    ar_max_rotation_jump_deg: float = 25.0


PROFILES: dict[str, ProfileConfig] = {
    "dev": ProfileConfig(
        name="dev",
        frame_stride=3,
        splat_max_iterations=3000,
        sam2_keyframe_stride=12,
        saga_feature_iterations=2000,
        allow_vote_fallback=True,
        ar_max_frames=80,
        ar_min_time_delta_s=0.25,
        ar_min_translation_m=0.02,
    ),
    "production": ProfileConfig(
        name="production",
        frame_stride=2,
        splat_max_iterations=30000,
        sam2_keyframe_stride=6,
        saga_feature_iterations=30000,
        allow_vote_fallback=False,
        ar_max_frames=200,
        ar_min_time_delta_s=0.20,
        ar_min_translation_m=0.015,
    ),
    "mesh-full": ProfileConfig(
        name="mesh-full",
        frame_stride=2,
        splat_max_iterations=30000,
        saga_feature_iterations=30000,
        allow_vote_fallback=False,
        run_sugar_scene_mesh=True,
        ar_max_frames=200,
        ar_min_time_delta_s=0.20,
        ar_min_translation_m=0.015,
    ),
}


@dataclass
class PipelinePaths:
    scene_id: str
    capture_dir: Path
    output_dir: Path

    @property
    def frames_dir(self) -> Path:
        return self.output_dir / "frames"

    @property
    def reconstruction_dir(self) -> Path:
        return self.output_dir / "reconstruction"

    @property
    def splats_dir(self) -> Path:
        return self.output_dir / "splats"

    @property
    def masks_dir(self) -> Path:
        return self.output_dir / "masks"

    @property
    def object_groups_dir(self) -> Path:
        return self.output_dir / "object_groups"

    @property
    def meshes_dir(self) -> Path:
        return self.output_dir / "meshes"

    @property
    def object_lifting_dir(self) -> Path:
        return self.output_dir / "object_lifting"

    @property
    def logs_dir(self) -> Path:
        return self.output_dir / "logs"

    @property
    def viewer_dir(self) -> Path:
        return self.output_dir / "viewer"

    @property
    def mobile_benchmarks_dir(self) -> Path:
        return self.output_dir / "mobile_benchmarks"

    @property
    def runtime_dir(self) -> Path:
        return self.output_dir / "runtime"

    @property
    def scene_ply(self) -> Path:
        return self.output_dir / "scene.ply"

    @property
    def manifest_path(self) -> Path:
        return self.output_dir / "manifest.json"

    @property
    def objects_path(self) -> Path:
        return self.output_dir / "objects.json"

    @property
    def benchmarks_path(self) -> Path:
        return self.output_dir / "benchmarks.json"


@dataclass
class PipelineState:
    paths: PipelinePaths
    profile: ProfileConfig
    warnings: list[str] = field(default_factory=list)
    failures: list[str] = field(default_factory=list)
    benchmarks: dict = field(default_factory=dict)
