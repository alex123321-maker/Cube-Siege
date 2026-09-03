"""
render_animation.py
Renders Blockbench skeletal animations into:
1. A multi-pose storyboard / contact sheet (PNG)
2. A smooth animated GIF
Allows AI and developer to visually verify keyframes, dynamics, and timing.
"""

import sys
import os
import json
import io
import numpy as np
from PIL import Image
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

PALETTE = [
    "#4a90e2", "#50e3c2", "#b8e986", "#f8e71c", "#f5a623",
    "#d0021b", "#9013fe", "#4a4a4a", "#9b9b9b", "#ffffff"
]

def euler_to_matrix(rx_deg, ry_deg, rz_deg):
    rx, ry, rz = np.radians([rx_deg, ry_deg, rz_deg])
    cx, sx = np.cos(rx), np.sin(rx)
    Rx = np.array([[1, 0, 0, 0], [0, cx, -sx, 0], [0, sx, cx, 0], [0, 0, 0, 1]])
    cy, sy = np.cos(ry), np.sin(ry)
    Ry = np.array([[cy, 0, sy, 0], [0, 1, 0, 0], [-sy, 0, cy, 0], [0, 0, 0, 1]])
    cz, sz = np.cos(rz), np.sin(rz)
    Rz = np.array([[cz, -sz, 0, 0], [sz, cz, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
    return Rz @ Ry @ Rx

def translation_matrix(tx, ty, tz):
    T = np.eye(4)
    T[0, 3] = tx
    T[1, 3] = ty
    T[2, 3] = tz
    return T

def interpolate_channel(keyframes, t, default_val=[0.0, 0.0, 0.0]):
    if not keyframes:
        return default_val
    times = [float(k["time"]) for k in keyframes]
    if t <= times[0]:
        dp = keyframes[0]["data_points"][0]
        return [float(dp.get("x", 0)), float(dp.get("y", 0)), float(dp.get("z", 0))]
    if t >= times[-1]:
        dp = keyframes[-1]["data_points"][0]
        return [float(dp.get("x", 0)), float(dp.get("y", 0)), float(dp.get("z", 0))]
        
    for i in range(len(times) - 1):
        t0, t1 = times[i], times[i+1]
        if t0 <= t <= t1:
            dp0 = keyframes[i]["data_points"][0]
            dp1 = keyframes[i+1]["data_points"][0]
            v0 = np.array([float(dp0.get("x", 0)), float(dp0.get("y", 0)), float(dp0.get("z", 0))])
            v1 = np.array([float(dp1.get("x", 0)), float(dp1.get("y", 0)), float(dp1.get("z", 0))])
            factor = (t - t0) / (t1 - t0) if t1 > t0 else 0
            return list(v0 + factor * (v1 - v0))
    return default_val

def build_bone_tree(node, parent_bone_uuid=None, element_map={}, bone_map={}):
    """
    Traverses outliner to map elements to bones and record parent-child relations.
    """
    if isinstance(node, str):
        # Child is an element UUID
        element_map[node] = parent_bone_uuid
        return

    b_uuid = node.get("uuid")
    b_name = node.get("name", "")
    b_origin = node.get("origin", [0, 0, 0])
    
    bone_map[b_uuid] = {
        "uuid": b_uuid,
        "name": b_name,
        "origin": b_origin,
        "parent": parent_bone_uuid,
        "children": []
    }
    if parent_bone_uuid and parent_bone_uuid in bone_map:
        bone_map[parent_bone_uuid]["children"].append(b_uuid)
        
    for child in node.get("children", []):
        build_bone_tree(child, b_uuid, element_map, bone_map)

def get_bone_world_matrix(b_uuid, bone_map, anim_data, t, memo={}):
    if b_uuid in memo:
        return memo[b_uuid]
    if not b_uuid or b_uuid not in bone_map:
        return np.eye(4)
        
    bone = bone_map[b_uuid]
    p_uuid = bone["parent"]
    p_matrix = get_bone_world_matrix(p_uuid, bone_map, anim_data, t, memo)
    
    origin = bone["origin"]
    animator = anim_data.get(b_uuid, {})
    
    # Keyframes
    rot_kfs = [k for k in animator.get("rotation", []) if k.get("channel") == "rotation"]
    pos_kfs = [k for k in animator.get("position", []) if k.get("channel") == "position"]
    
    cur_rot = interpolate_channel(rot_kfs, t, [0, 0, 0])
    cur_pos = interpolate_channel(pos_kfs, t, [0, 0, 0])
    
    # Local transform around origin
    T_to_orig = translation_matrix(origin[0], origin[1], origin[2])
    T_from_orig = translation_matrix(-origin[0], -origin[1], -origin[2])
    T_anim = translation_matrix(cur_pos[0], cur_pos[1], cur_pos[2])
    R_anim = euler_to_matrix(cur_rot[0], cur_rot[1], cur_rot[2])
    
    # M_local = T_to_orig * T_anim * R_anim * T_from_orig
    M_local = T_to_orig @ T_anim @ R_anim @ T_from_orig
    M_world = p_matrix @ M_local
    
    memo[b_uuid] = M_world
    return M_world

def bb_to_plot(p):
    return [p[0], p[2], p[1]]

def get_polygons_at_time(data, anim_name, t, element_map, bone_map):
    # Find animation
    anim = next((a for a in data.get("animations", []) if a.get("name") == anim_name), None)
    anim_data = anim.get("animators", {}) if anim else {}
    
    elements = data.get("elements", [])
    polygons = []
    colors = []
    all_coords = []
    
    memo = {}
    light_dir = np.array([0.4, -0.6, 0.7])
    light_dir = light_dir / np.linalg.norm(light_dir)
    
    for idx, elem in enumerate(elements):
        elem_uuid = elem.get("uuid")
        bone_uuid = element_map.get(elem_uuid)
        M_world = get_bone_world_matrix(bone_uuid, bone_map, anim_data, t, memo)
        
        p_from = elem.get("from", [0, 0, 0])
        p_to = elem.get("to", [1, 1, 1])
        x1, y1, z1 = p_from
        x2, y2, z2 = p_to
        
        corners = [
            [x1, y1, z1], [x2, y1, z1], [x2, y2, z1], [x1, y2, z1],
            [x1, y1, z2], [x2, y1, z2], [x2, y2, z2], [x1, y2, z2]
        ]
        
        # Transform corners by M_world
        transformed_corners = []
        for c in corners:
            v4 = np.array([c[0], c[1], c[2], 1.0])
            vt = M_world @ v4
            transformed_corners.append(bb_to_plot(vt[:3]))
            all_coords.append(bb_to_plot(vt[:3]))
            
        c0, c1, c2, c3, c4, c5, c6, c7 = transformed_corners
        
        faces_def = [
            ([c0, c1, c2, c3], [0, -1, 0]), # North
            ([c5, c4, c7, c6], [0, 1, 0]),  # South
            ([c1, c5, c6, c2], [1, 0, 0]),  # East
            ([c4, c0, c3, c7], [-1, 0, 0]), # West
            ([c3, c2, c6, c7], [0, 0, 1]),  # Up
            ([c4, c5, c1, c0], [0, 0, -1])  # Down
        ]
        
        col_idx = elem.get("color", idx % len(PALETTE))
        base_hex = PALETTE[col_idx % len(PALETTE)]
        
        for face_pts, norm_initial in faces_def:
            # Estimate normal from first 3 vertices
            vA = np.array(face_pts[0])
            vB = np.array(face_pts[1])
            vC = np.array(face_pts[2])
            norm = np.cross(vB - vA, vC - vA)
            norm_len = np.linalg.norm(norm)
            if norm_len > 1e-6:
                norm = norm / norm_len
            else:
                norm = np.array(norm_initial)
                
            intensity = 0.4 + 0.6 * max(0.0, float(np.dot(norm, light_dir)))
            r = int(int(base_hex[1:3], 16) * intensity)
            g = int(int(base_hex[3:5], 16) * intensity)
            b = int(int(base_hex[5:7], 16) * intensity)
            col = (min(r, 255)/255.0, min(g, 255)/255.0, min(b, 255)/255.0, 1.0)
            
            polygons.append(face_pts)
            colors.append(col)
            
    return polygons, colors, all_coords

def render_storyboard(bbmodel_path, anim_name, output_png):
    with open(bbmodel_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    element_map = {}
    bone_map = {}
    for node in data.get("outliner", []):
        build_bone_tree(node, None, element_map, bone_map)
        
    anim = next((a for a in data.get("animations", []) if a.get("name") == anim_name), None)
    if not anim:
        print(f"Animation '{anim_name}' not found.")
        return
        
    length = float(anim.get("length", 1.0))
    # 4 sample timestamps
    timestamps = [0.0, length * 0.25, length * 0.55, length * 0.85]
    step_labels = ["Pose 1 (Start)", "Pose 2 (Phase A)", "Pose 3 (Apex/Phase B)", "Pose 4 (Follow-through)"]
    
    fig = plt.figure(figsize=(16, 5), facecolor='#181818')
    fig.suptitle(f"Animation Storyboard: '{anim_name}' ({length}s)", color='#ffffff', fontsize=14, fontweight='bold')
    
    # Calculate global bounds across all 4 frames
    all_bounds = []
    frames_data = []
    for t in timestamps:
        poly, col, coords = get_polygons_at_time(data, anim_name, t, element_map, bone_map)
        frames_data.append((poly, col))
        all_bounds.extend(coords)
        
    bounds_arr = np.array(all_bounds)
    min_x, min_y, min_z = bounds_arr.min(axis=0)
    max_x, max_y, max_z = bounds_arr.max(axis=0)
    cx, cy, cz = (min_x + max_x)/2.0, (min_y + max_y)/2.0, (min_z + max_z)/2.0
    radius = max(max_x - min_x, max_y - min_y, max_z - min_z, 1.0) * 0.6
    
    for i, (poly, col) in enumerate(frames_data):
        ax = fig.add_subplot(1, 4, i + 1, projection='3d')
        ax.set_facecolor('#222222')
        ax.view_init(elev=25, azim=-45) # Game Camera
        
        poly_col = Poly3DCollection(poly, facecolors=col, edgecolors='#111111', linewidths=0.5)
        ax.add_collection3d(poly_col)
        
        ax.set_xlim([cx - radius, cx + radius])
        ax.set_ylim([cy - radius, cy + radius])
        ax.set_zlim([cz - radius, cz + radius])
        
        ax.set_xticks([])
        ax.set_yticks([])
        ax.set_zticks([])
        ax.set_title(f"{step_labels[i]}\nt={timestamps[i]:.2f}s", color='#dddddd', fontsize=11)
        
        ax.xaxis.pane.fill = False
        ax.yaxis.pane.fill = False
        ax.zaxis.pane.fill = False
        ax.xaxis.pane.set_edgecolor('#333333')
        ax.yaxis.pane.set_edgecolor('#333333')
        ax.zaxis.pane.set_edgecolor('#333333')
        ax.grid(False)
        
    plt.tight_layout()
    os.makedirs(os.path.dirname(os.path.abspath(output_png)), exist_ok=True)
    plt.savefig(output_png, dpi=130, facecolor=fig.get_facecolor(), edgecolor='none')
    plt.close(fig)
    print(f"Storyboard saved: {output_png}")

def render_gif(bbmodel_path, anim_name, output_gif, fps=15):
    with open(bbmodel_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    element_map = {}
    bone_map = {}
    for node in data.get("outliner", []):
        build_bone_tree(node, None, element_map, bone_map)
        
    anim = next((a for a in data.get("animations", []) if a.get("name") == anim_name), None)
    if not anim:
        return
        
    length = float(anim.get("length", 1.0))
    frame_count = max(4, int(length * fps))
    times = np.linspace(0, length, frame_count, endpoint=False)
    
    # Calculate global bounds
    all_bounds = []
    frames_cache = []
    for t in times:
        poly, col, coords = get_polygons_at_time(data, anim_name, t, element_map, bone_map)
        frames_cache.append((poly, col))
        all_bounds.extend(coords)
        
    bounds_arr = np.array(all_bounds)
    min_x, min_y, min_z = bounds_arr.min(axis=0)
    max_x, max_y, max_z = bounds_arr.max(axis=0)
    cx, cy, cz = (min_x + max_x)/2.0, (min_y + max_y)/2.0, (min_z + max_z)/2.0
    radius = max(max_x - min_x, max_y - min_y, max_z - min_z, 1.0) * 0.6
    
    images = []
    for idx, (poly, col) in enumerate(frames_cache):
        fig = plt.figure(figsize=(5, 5), facecolor='#181818')
        ax = fig.add_subplot(111, projection='3d')
        ax.set_facecolor('#222222')
        ax.view_init(elev=25, azim=-45) # Game Camera
        
        poly_col = Poly3DCollection(poly, facecolors=col, edgecolors='#111111', linewidths=0.5)
        ax.add_collection3d(poly_col)
        
        ax.set_xlim([cx - radius, cx + radius])
        ax.set_ylim([cy - radius, cy + radius])
        ax.set_zlim([cz - radius, cz + radius])
        
        ax.set_xticks([])
        ax.set_yticks([])
        ax.set_zticks([])
        ax.set_title(f"{anim_name} - {times[idx]:.2f}s", color='#ffffff', fontsize=10)
        
        ax.xaxis.pane.fill = False
        ax.yaxis.pane.fill = False
        ax.zaxis.pane.fill = False
        ax.xaxis.pane.set_edgecolor('#333333')
        ax.yaxis.pane.set_edgecolor('#333333')
        ax.zaxis.pane.set_edgecolor('#333333')
        ax.grid(False)
        
        plt.tight_layout()
        buf = io.BytesIO()
        plt.savefig(buf, format='png', dpi=90, facecolor=fig.get_facecolor())
        plt.close(fig)
        buf.seek(0)
        images.append(Image.open(buf).convert("RGB"))
        
    if images:
        os.makedirs(os.path.dirname(os.path.abspath(output_gif)), exist_ok=True)
        images[0].save(
            output_gif,
            save_all=True,
            append_images=images[1:],
            duration=int(1000 / fps),
            loop=0
        )
        print(f"Animated GIF saved: {output_gif}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python render_animation.py <bbmodel_path> <anim_name>")
        sys.exit(1)
        
    path = sys.argv[1]
    name = sys.argv[2]
    out_png = f"d:/Repository/game/assets/models/previews/hero_warrior_{name}_storyboard.png"
    out_gif = f"d:/Repository/game/assets/models/previews/hero_warrior_{name}.gif"
    
    render_storyboard(path, name, out_png)
    render_gif(path, name, out_gif)
