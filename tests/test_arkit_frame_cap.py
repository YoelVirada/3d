from spatial_asset_compiler.capture.schema import ARFramePose
from spatial_asset_compiler.config import ProfileConfig
from spatial_asset_compiler.ingest.arkit_pose_filter import filter_arkit_poses, uniform_subsample


def _pose(i: int) -> ARFramePose:
    m = [[1, 0, 0, i * 0.5], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    return ARFramePose(
        frame=f"f{i}.jpg",
        timestamp_s=float(i),
        tracking_state="normal",
        transform=m,
        intrinsics=[[800, 0, 0], [0, 800, 0], [0, 0, 1]],
        width=640,
        height=480,
    )


def test_uniform_subsample():
    items = list(range(10))
    out = uniform_subsample(items, 5)
    assert len(out) == 5


def test_profile_cap():
    profile = ProfileConfig(name="dev", ar_max_frames=3)
    poses = [_pose(i) for i in range(10)]
    accepted, _, capped = filter_arkit_poses(poses, profile)
    assert len(accepted) == 3
    assert capped is True
