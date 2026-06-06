from spatial_asset_compiler.capture.schema import ARFramePose
from spatial_asset_compiler.config import PROFILES
from spatial_asset_compiler.ingest.arkit_pose_filter import filter_arkit_poses


def _pose(i: int, state: str = "normal", t_offset: float = 0.0) -> ARFramePose:
    m = [[1, 0, 0, i * 0.1], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    return ARFramePose(
        frame=f"frame_{i:05d}.jpg",
        timestamp_s=float(i) + t_offset,
        tracking_state=state,
        transform=m,
        intrinsics=[[800, 0, 0], [0, 800, 0], [0, 0, 1]],
        width=640,
        height=480,
    )


def test_rejects_bad_tracking():
    poses = [_pose(0), _pose(1, state="limited")]
    accepted, rejected, _ = filter_arkit_poses(poses, PROFILES["dev"])
    assert len(accepted) == 1
    assert rejected["tracking_not_normal"] == 1


def test_rejects_too_close_in_time():
    p0 = _pose(0, t_offset=0.0)
    p1 = ARFramePose(
        frame="frame_00001.jpg",
        timestamp_s=0.1,
        tracking_state="normal",
        transform=[[1, 0, 0, 0.1], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
        intrinsics=[[800, 0, 0], [0, 800, 0], [0, 0, 1]],
        width=640,
        height=480,
    )
    accepted, rejected, _ = filter_arkit_poses([p0, p1], PROFILES["dev"])
    assert len(accepted) == 1
    assert rejected["too_close_in_time"] == 1
