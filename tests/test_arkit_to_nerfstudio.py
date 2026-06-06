import numpy as np

from spatial_asset_compiler.reconstruction.arkit_to_nerfstudio import arkit_c2w_to_nerfstudio


def test_identity_remap():
    t = np.eye(4)
    c2w = arkit_c2w_to_nerfstudio(t)
    expected = np.array(
        [
            [0, 0, 1, 0],
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 0, 1],
        ],
        dtype=np.float64,
    )
    np.testing.assert_allclose(c2w, expected, atol=1e-9)


def test_translation_preserved_in_remapped_axes():
    t = np.eye(4)
    t[0, 3] = 1.5
    c2w = arkit_c2w_to_nerfstudio(t)
    assert abs(c2w[1, 3] - 1.5) < 1e-9
