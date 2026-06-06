"""Self-contained HTML frustum preview for ARKit camera trajectory."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np

from spatial_asset_compiler.reconstruction.arkit_to_nerfstudio import (
    arkit_c2w_to_nerfstudio,
    arkit_transform_to_matrix,
    camera_position,
)


def _frustum_corners(c2w: np.ndarray, scale: float = 0.05) -> list[list[float]]:
    """Simple camera frustum wireframe corners in world space."""
    # Camera looks down -Z in local frame (OpenGL-style after conversion)
    pts_local = np.array(
        [
            [0, 0, 0],
            [-scale, -scale * 0.75, -scale * 1.5],
            [scale, -scale * 0.75, -scale * 1.5],
            [scale, scale * 0.75, -scale * 1.5],
            [-scale, scale * 0.75, -scale * 1.5],
        ],
        dtype=np.float64,
    )
    ones = np.ones((pts_local.shape[0], 1))
    hom = np.hstack([pts_local, ones])
    world = (c2w @ hom.T).T[:, :3]
    return world.tolist()


def write_frustum_preview_html(
    accepted: list[dict[str, Any]],
    out_path: Path,
) -> Path:
    centers: list[list[float]] = []
    frustums: list[list[list[float]]] = []
    for rec in accepted:
        arkit = arkit_transform_to_matrix(rec["transform"])
        c2w = arkit_c2w_to_nerfstudio(arkit)
        centers.append(camera_position(c2w).tolist())
        frustums.append(_frustum_corners(c2w))

    payload = json.dumps({"centers": centers, "frustums": frustums})
    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>ARKit frustum preview</title>
<style>body{{margin:0;background:#111;color:#ccc;font:14px sans-serif}}
canvas{{display:block;width:100vw;height:90vh}}</style></head>
<body><p>Camera centers (green) + frustum wireframes. Orbit: drag. Scroll: zoom.</p>
<canvas id="c"></canvas>
<script>
const data = {payload};
const canvas = document.getElementById('c');
const ctx = canvas.getContext('2d');
let yaw=0.6, pitch=0.35, dist=1.5, cx=0, cy=0, cz=0;
function resize(){{ canvas.width=innerWidth; canvas.height=innerHeight*0.9; draw(); }}
function rot(x,y,z){{
  const cp=Math.cos(pitch), sp=Math.sin(pitch), cy=Math.cos(yaw), sy=Math.sin(yaw);
  let x1=x*cy+z*sy, z1=-x*sy+z*cy, y2=y*cp-z1*sp, z2=y*sp+z1*cp;
  return [x1-cx, y2-cy, z2-cz];
}}
function proj(p){{ const f=400/dist; return [canvas.width/2+p[0]*f, canvas.height/2-p[1]*f]; }}
function draw(){{
  ctx.fillStyle='#111'; ctx.fillRect(0,0,canvas.width,canvas.height);
  ctx.strokeStyle='#48f'; ctx.lineWidth=1;
  for (const fr of data.frustums){{
    const P=fr.map(p=>proj(rot(p[0],p[1],p[2])));
    const edges=[[0,1],[0,2],[0,3],[0,4],[1,2],[2,3],[3,4],[4,1]];
    for (const [a,b] of edges){{ ctx.beginPath(); ctx.moveTo(P[a][0],P[a][1]); ctx.lineTo(P[b][0],P[b][1]); ctx.stroke(); }}
  }}
  ctx.fillStyle='#4f4';
  for (const c of data.centers){{ const p=proj(rot(c[0],c[1],c[2])); ctx.beginPath(); ctx.arc(p[0],p[1],3,0,7); ctx.fill(); }}
}}
canvas.onmousedown=e=>{{ canvas._drag=e; }};
canvas.onmouseup=()=>{{ canvas._drag=null; }};
canvas.onmousemove=e=>{{ if(!canvas._drag)return; yaw+=(e.clientX-canvas._drag.clientX)*0.01; pitch+=(e.clientY-canvas._drag.clientY)*0.01; canvas._drag=e; draw(); }};
canvas.onwheel=e=>{{ dist*=1+e.deltaY*0.001; dist=Math.max(0.2,dist); draw(); }};
addEventListener('resize', resize); resize();
</script></body></html>"""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")
    return out_path
