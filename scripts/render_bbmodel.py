"""
render_bbmodel.py
Renders a Blockbench .bbmodel file into a multi-angle turnaround image (Front, Side, Top, Isometric 3D)
so that the AI assistant can visually inspect models and eliminate blind modeling.
"""

import sys
import os
import json
import base64
import io
import numpy as np
from PIL import Image
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

# Default palette if no texture
PALETTE = [
    "#4a90e2", "#50e3c2", "#b8e986", "#f8e71c", "#f5a623",
    "#d0021b", "#9013fe", "#4a4a4a", "#9b9b9b", "#ffffff"
]

def rotate_point(p, origin, angles_deg):
    if not any(angles_deg):
        return p
    rx, ry, rz = np.radians(angles_deg)
    pt = np.array(p, dtype=float) - np.array(origin, dtype=float)
    
    # Blockbench rotation order: X, then Y, then Z
    cx, sx = np.cos(rx), np.sin(rx)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    cy, sy = np.cos(ry), np.sin(ry)
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    cz, sz = np.cos(rz), np.sin(rz)
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    
    R = Rz @ Ry @ Rx
    pt = R @ pt
    return pt + np.array(origin, dtype=float)

def bb_to_plot(p):
    """
    Blockbench coordinate system:
      X = Right (+X), Left (-X)
      Y = Up (+Y), Down (-Y)
      Z = South/Front (+Z), North/Back (-Z)
    Matplotlib 3D coordinate system:
      X_plot = X_bb (Right/Left)
      Y_plot = Z_bb (Front/Back depth)
      Z_plot = Y_bb (Up/Down height)
    """
    return [p[0], p[2], p[1]]

def get_face_color(elem, face_name, textures_img, res_w, res_h, default_color):
    face_info = elem.get("faces", {}).get(face_name, {})
    tex_idx = face_info.get("texture")
    uv = face_info.get("uv")
    
    if tex_idx is not None and tex_idx in textures_img and uv and len(uv) == 4:
        img = textures_img[tex_idx]
        u1, v1, u2, v2 = uv
        px1 = int(np.clip(min(u1, u2) / res_w * img.width, 0, img.width - 1))
        px2 = int(np.clip(max(u1, u2) / res_w * img.width, 1, img.width))
        py1 = int(np.clip(min(v1, v2) / res_h * img.height, 0, img.height - 1))
        py2 = int(np.clip(max(v1, v2) / res_h * img.height, 1, img.height))
        
        if px2 > px1 and py2 > py1:
            patch = img.crop((px1, py1, px2, py2))
            arr = np.array(patch)
            if arr.ndim == 3 and arr.shape[2] >= 3:
                r = int(np.mean(arr[:, :, 0]))
                g = int(np.mean(arr[:, :, 1]))
                b = int(np.mean(arr[:, :, 2]))
                return f"#{r:02x}{g:02x}{b:02x}"
                
    return default_color

def render_bbmodel(bbmodel_path, output_png_path=None):
    with open(bbmodel_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    model_name = data.get("name", os.path.splitext(os.path.basename(bbmodel_path))[0])
    if output_png_path is None:
        output_png_path = os.path.splitext(bbmodel_path)[0] + "_preview.png"
        
    res = data.get("resolution", {"width": 64, "height": 64})
    res_w = res.get("width", 64)
    res_h = res.get("height", 64)
    
    textures_img = {}
    for i, tex in enumerate(data.get("textures", [])):
        src = tex.get("source", "")
        if src.startswith("data:image"):
            b64_data = src.split(",", 1)[1]
            img_bytes = base64.b64decode(b64_data)
            textures_img[i] = Image.open(io.BytesIO(img_bytes)).convert("RGBA")
            textures_img[tex.get("id")] = textures_img[i]
            
    elements = data.get("elements", [])
    polygons = []
    colors = []
    
    # Light direction in plot space (coming from top-front-right)
    light_dir = np.array([0.4, -0.6, 0.7])
    light_dir = light_dir / np.linalg.norm(light_dir)
    
    all_plot_coords = []
    
    for idx, elem in enumerate(elements):
        p_from = elem.get("from", [0, 0, 0])
        p_to = elem.get("to", [1, 1, 1])
        origin = elem.get("origin", [0, 0, 0])
        rot = elem.get("rotation", [0, 0, 0])
        
        x1, y1, z1 = p_from
        x2, y2, z2 = p_to
        
        corners = [
            [x1, y1, z1], [x2, y1, z1], [x2, y2, z1], [x1, y2, z1],
            [x1, y1, z2], [x2, y1, z2], [x2, y2, z2], [x1, y2, z2]
        ]
        
        rot_corners = [rotate_point(c, origin, rot) for c in corners]
        plot_corners = [bb_to_plot(c) for c in rot_corners]
        all_plot_coords.extend(plot_corners)
        
        c0, c1, c2, c3, c4, c5, c6, c7 = plot_corners
        
        faces_def = [
            ([c0, c1, c2, c3], [0, -1, 0], "north"),
            ([c5, c4, c7, c6], [0, 1, 0], "south"),
            ([c1, c5, c6, c2], [1, 0, 0], "east"),
            ([c4, c0, c3, c7], [-1, 0, 0], "west"),
            ([c3, c2, c6, c7], [0, 0, 1], "up"),
            ([c4, c5, c1, c0], [0, 0, -1], "down")
        ]
        
        def_col = PALETTE[idx % len(PALETTE)]
        
        for face_pts, norm_initial_bb, face_name in faces_def:
            norm_rot_bb = rotate_point(norm_initial_bb, [0, 0, 0], rot)
            norm_plot = np.array(bb_to_plot(norm_rot_bb), dtype=float)
            norm_plot = norm_plot / (np.linalg.norm(norm_plot) + 1e-6)
            
            base_col = get_face_color(elem, face_name, textures_img, res_w, res_h, def_col)
            
            intensity = 0.4 + 0.6 * max(0.0, float(np.dot(norm_plot, light_dir)))
            if base_col.startswith("#"):
                r = int(int(base_col[1:3], 16) * intensity)
                g = int(int(base_col[3:5], 16) * intensity)
                b = int(int(base_col[5:7], 16) * intensity)
                col = (min(r, 255)/255.0, min(g, 255)/255.0, min(b, 255)/255.0, 1.0)
            else:
                col = (0.7 * intensity, 0.7 * intensity, 0.7 * intensity, 1.0)
                
            polygons.append(face_pts)
            colors.append(col)

    if not all_plot_coords:
        print("No elements in model.")
        return

    coords_arr = np.array(all_plot_coords)
    min_x, min_y, min_z = coords_arr.min(axis=0)
    max_x, max_y, max_z = coords_arr.max(axis=0)
    
    cx = (min_x + max_x) / 2.0
    cy = (min_y + max_y) / 2.0
    cz = (min_z + max_z) / 2.0
    
    # Scale bounds tightly
    max_span = max(max_x - min_x, max_y - min_y, max_z - min_z, 1.0)
    radius = max_span * 0.55
    
    fig = plt.figure(figsize=(12, 12), facecolor='#181818')
    fig.suptitle(f"Model Turnaround: {model_name}", color='#ffffff', fontsize=16, fontweight='bold', y=0.98)
    
    # Views in plot space (where Z is UP, Y is Front/Back, X is Right/Left):
    # Front View: looking at face (facing -Y)
    # Side View: looking at right profile (facing +X)
    # Top View: looking down (+Z)
    # Isometric: 30 deg elevation, 45 deg azimuth
    views = [
        (221, "Front View (Facing Forward)", 0, -90),
        (222, "Side View (Right Profile)", 0, 0),
        (223, "Top View (Bird's Eye)", 90, -90),
        (224, "Isometric 3D (Game Camera)", 25, -45)
    ]
    
    for subplot_id, title, elev, azim in views:
        ax = fig.add_subplot(subplot_id, projection='3d')
        ax.set_facecolor('#222222')
        ax.view_init(elev=elev, azim=azim)
        
        poly_col = Poly3DCollection(polygons, facecolors=colors, edgecolors='#151515', linewidths=0.6)
        ax.add_collection3d(poly_col)
        
        ax.set_xlim([cx - radius, cx + radius])
        ax.set_ylim([cy - radius, cy + radius])
        ax.set_zlim([cz - radius, cz + radius])
        
        ax.set_xticks([])
        ax.set_yticks([])
        ax.set_zticks([])
        ax.set_title(title, color='#e0e0e0', fontsize=12, pad=10)
        
        ax.xaxis.pane.fill = False
        ax.yaxis.pane.fill = False
        ax.zaxis.pane.fill = False
        ax.xaxis.pane.set_edgecolor('#333333')
        ax.yaxis.pane.set_edgecolor('#333333')
        ax.zaxis.pane.set_edgecolor('#333333')
        ax.grid(False)

    plt.tight_layout()
    os.makedirs(os.path.dirname(os.path.abspath(output_png_path)), exist_ok=True)
    plt.savefig(output_png_path, dpi=140, facecolor=fig.get_facecolor(), edgecolor='none')
    plt.close(fig)
    print(f"Render saved: {output_png_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python render_bbmodel.py <path_to_bbmodel> [output_png]")
        sys.exit(1)
    bb_path = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else None
    render_bbmodel(bb_path, out_path)
