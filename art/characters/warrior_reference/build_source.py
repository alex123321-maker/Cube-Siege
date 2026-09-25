"""Author the reference-driven Blockbench candidate. No production asset is replaced.

Run with Python + Pillow. The resulting .bbmodel is the editable canonical source;
rerunning this authoring recipe backs up an existing source before regenerating it.
"""
from __future__ import annotations

import base64
import io
import json
import math
import random
import shutil
import uuid
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
NAME = "warrior_reference"
RNG = random.Random(819)
MATERIALS = {
    "steel": (113, 112, 119), "steel_light": (162, 158, 157),
    "steel_edge": (193, 185, 173), "steel_dark": (73, 73, 81),
    "leather": (87, 58, 41), "leather_light": (119, 78, 49),
    "hair": (70, 46, 32), "hair_light": (89, 57, 36),
    "cloth": (48, 71, 104), "cloth_light": (66, 90, 123),
    "cloth_dark": (31, 47, 68), "linen": (174, 159, 134),
    "skin": (191, 132, 91), "skin_light": (216, 161, 112),
    "gold": (153, 111, 57), "gold_light": (190, 147, 84),
    "padding": (42, 38, 37), "eye_white": (206, 203, 181),
    "eye_blue": (58, 91, 122), "eye_dark": (33, 47, 61),
    "mouth": (127, 76, 52), "wood": (92, 61, 40),
}
ATLAS_SIZE = 512
TILE = 32
atlas = Image.new("RGBA", (ATLAS_SIZE, ATLAS_SIZE), (50, 43, 38, 255))
draw = ImageDraw.Draw(atlas)
tiles = {}
for index, (name, color) in enumerate(MATERIALS.items()):
    for variant in range(4):
        tile_index = index * 4 + variant
        ox, oy = (tile_index % 16) * TILE, (tile_index // 16) * TILE
        tiles[name, variant] = (ox, oy)
        draw.rectangle((ox, oy, ox+31, oy+31), fill=(*color, 255))
        # Sparse, coherent pixel clusters; no per-pixel white noise.
        if name.startswith("eye") or name == "mouth":
            continue
        contrast = 5 if name.startswith("skin") else (19 if name.startswith("steel") else 14)
        for _ in range(64):
            x, y = RNG.randrange(1, 29), RNG.randrange(1, 29)
            w, h = RNG.choice((2, 3, 4, 6)), RNG.choice((2, 3, 5))
            delta = RNG.choice((-contrast, -contrast//2, contrast//2, contrast))
            patch = tuple(max(0, min(255, c+delta)) for c in color)
            draw.rectangle((ox+x, oy+y, ox+min(30,x+w), oy+min(30,y+h)), fill=(*patch, 255))
        if name in ("steel", "steel_light", "steel_edge", "gold", "leather_light"):
            bright = tuple(min(255, c+18) for c in color)
            for _ in range(7):
                x, y = RNG.randrange(1, 28), RNG.randrange(1, 30)
                draw.line((ox+x,oy+y,ox+x+RNG.randrange(1,4),oy+y), fill=(*bright,255))

elements = []
groups = {}


def uid(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "cube-siege/reference-warrior/"+name))


def group(name, origin, parent=None, rotation=None):
    value = {"name": name, "uuid": uid("bone/"+name), "origin": origin,
             "rotation": rotation or [0,0,0], "children": [], "export": True, "isOpen": True}
    groups[name] = value
    if parent:
        groups[parent]["children"].append(value)
    return value


def uv_rect(material, width, height):
    ox, oy = tiles[material, RNG.randrange(4)]
    w, h = min(29,max(2,round(width*2))), min(29,max(2,round(height*2)))
    return [ox+1, oy+1, ox+1+w, oy+1+h]


def cube(name, start, end, material, bone="body", rotation=None, origin=None):
    size = [end[i]-start[i] for i in range(3)]
    assert min(size) > 0, (name, size)
    dims = {"north": (size[0],size[1]), "south": (size[0],size[1]),
            "east": (size[2],size[1]), "west": (size[2],size[1]),
            "up": (size[0],size[2]), "down": (size[0],size[2])}
    e = {"name": name, "uuid": uid(name), "type": "cube", "from": start,
         "to": end, "origin": origin or [(start[i]+end[i])/2 for i in range(3)],
         "rotation": rotation or [0,0,0], "box_uv": False, "rescale": False,
         "autouv": 0, "color": 0, "export": True, "visibility": True,
         "faces": {face: {"uv": uv_rect(material,*d), "texture": 0} for face,d in dims.items()},
         "reference_material": material}
    elements.append(e)
    groups[bone]["children"].append(e["uuid"])
    return e


def mesh(name, vertices, faces, material, bone="body"):
    # Mesh vertices are local to origin (zero here); explicit face UVs survive Blockbench edits.
    vs = {f"v{i}": p for i,p in enumerate(vertices)}
    fs = {}
    for i, indices in enumerate(faces):
        points = [vertices[j] for j in indices]
        # Choose the two axes spanning this planar polygon for its UV projection.
        spread = [max(p[a] for p in points)-min(p[a] for p in points) for a in range(3)]
        axes = sorted(range(3), key=lambda a: spread[a], reverse=True)[:2]
        u0,v0,u1,v1 = uv_rect(material,spread[axes[0]],spread[axes[1]])
        lo = [min(p[a] for p in points) for a in axes]
        uv = {f"v{j}": [u0+(vertices[j][axes[0]]-lo[0])/max(.001,spread[axes[0]])*(u1-u0),
                         v1-(vertices[j][axes[1]]-lo[1])/max(.001,spread[axes[1]])*(v1-v0)] for j in indices}
        fs[f"f{i}"] = {"vertices": [f"v{j}" for j in indices], "uv": uv, "texture": 0}
    e = {"name": name, "uuid": uid(name), "type": "mesh", "origin": [0,0,0],
         "rotation": [0,0,0], "vertices": vs, "faces": fs, "export": True,
         "visibility": True, "color": 0, "reference_material": material}
    elements.append(e)
    groups[bone]["children"].append(e["uuid"])
    return e


def prism(name, outline, back, front, material, bone="body"):
    # Counterclockwise XY outline, extruded in Z.
    area = sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(outline,outline[1:]+outline[:1]))
    if area < 0:
        outline = list(reversed(outline))
    n = len(outline)
    vertices = [[x,y,back] for x,y in outline]+[[x,y,front] for x,y in outline]
    faces = [list(reversed(range(n))), list(range(n,2*n))]
    faces += [[i,(i+1)%n,(i+1)%n+n,i+n] for i in range(n)]
    return mesh(name,vertices,faces,material,bone)


def bar(name, a, b, width, depth, material, bone):
    length = math.hypot(b[0]-a[0],b[1]-a[1])
    center = [(a[i]+b[i])/2 for i in range(3)]
    angle = -math.degrees(math.atan2(b[0]-a[0],b[1]-a[1]))
    return cube(name,[center[0]-width/2,center[1]-length/2,center[2]-depth/2],
                [center[0]+width/2,center[1]+length/2,center[2]+depth/2],
                material,bone,[0,0,angle],center)


def chamfered_plate(name, cx, bottom, width, height, back, front, material, bone):
    """Cut-corner metal plate with an actual bevel ring, editable as a BB mesh."""
    cut=.4
    x0,x1=cx-width/2,cx+width/2
    y0,y1=bottom,bottom+height
    outline=[(x0+cut,y0),(x1-cut,y0),(x1,y0+cut),(x1,y1-cut),
             (x1-cut,y1),(x0+cut,y1),(x0,y1-cut),(x0,y0+cut)]
    vertices=[[x,y,back] for x,y in outline]
    vertices += [[x,y,front-.19] for x,y in outline]
    vertices += [[cx+(x-cx)*.87,(y0+y1)/2+(y-(y0+y1)/2)*.87,front] for x,y in outline]
    faces=[list(reversed(range(8))),list(range(16,24))]
    for i in range(8):
        j=(i+1)%8
        faces.extend([[i,j,j+8,i+8],[i+8,j+8,j+16,i+16]])
    return mesh(name,vertices,faces,material,bone)


def rivet(name,x,y,z,bone="body",material="steel_edge",size=.28):
    cube(name,[x-size/2,y-size/2,z],[x+size/2,y+size/2,z+.13],material,bone)


def emblem(name, cx, cy, z, scale, bone, back=False):
    # Angular fork / sword emblem from the supplied concept, made of crisp inlaid pixels.
    pattern = ["...##...", "...##...", "##.##.##", "##.##.##", ".######.",
               "..####..", "...##...", "...##...", "...##..."]
    for row, line in enumerate(pattern):
        for col, ch in enumerate(line):
            if ch == "#":
                x, y = cx+(col-4)*scale, cy+(4.5-row)*scale
                cube(f"{name}_{row}_{col}",[x,y,z-.07 if back else z],
                     [x+scale,y+scale,z if back else z+.07],"linen",bone)


group("root",[0,0,0])
group("body",[0,13.6,0],"root")
group("head",[0,27.0,0],"body")
group("arm_right",[-6.8,25,0],"body",[8,0,-9])
group("forearm_right",[-7.2,19.4,.1],"arm_right",[-17,0,-19])
group("arm_left",[6.8,25,0],"body")
group("forearm_left",[7.2,19.4,.1],"arm_left")
group("leg_right",[-2.65,13.6,0],"root")
group("shin_right",[-2.65,7.4,0],"leg_right")
group("leg_left",[2.65,13.6,0],"root")
group("shin_left",[2.65,7.4,0],"leg_left")
group("cape",[0,26.5,-3.15],"body")
group("sword",[-7.05,13.7,.6],"forearm_right",[0,8,0])
group("shield",[7.7,15.2,3.9],"forearm_left",[0,-13,-5])

# Stocky torso, segmented cuirass and shoulder harness.
cube("quilted_torso",[-4.3,14.4,-2.5],[4.3,26.3,2.35],"padding")
cube("blue_undercoat",[-4.7,12.6,-2.55],[4.7,18.5,2.5],"cloth_dark")
prism("cuirass_core",[(-4.15,18),(4.15,18),(4.5,23.8),(3.3,25.2),(-3.3,25.2),(-4.5,23.8)],-2.72,2.63,"steel_dark")
prism("cuirass_front",[(-3.7,19),(3.7,19),(4.05,23.7),(2.8,24.7),(-2.8,24.7),(-4.05,23.7)],2.6,2.98,"steel")
cube("cuirass_center_ridge",[-.32,18.8,2.99],[.32,24.4,3.17],"steel_light")
for s, tag in ((-1,"r"),(1,"l")):
    for row in range(2):
        cx = s*2.1
        cube(f"abdominal_lame_{tag}_{row}",[cx-1.78,17.2+row*1.45,2.67],[cx+1.78,18.5+row*1.45,3.1],"steel")
    cube(f"harness_{tag}",[s*3.45-.48,19,-2.9],[s*3.45+.48,26.45,3.23],"leather")
    for y in (20.0,23.0,25.3):
        rivet(f"harness_{tag}_{y}",s*3.45,y,3.24,size=.32)

# Wide belt, pouches, buckle and overlapping hip plates.
cube("belt",[-4.7,15.6,-2.9],[4.7,17.0,3.3],"leather")
cube("belt_upper_edge",[-4.75,16.8,-2.94],[4.75,17.07,3.37],"leather_light")
cube("belt_tail",[1.7,15.1,3.31],[4.3,16.35,3.58],"leather_light")
for x in (-3.8,-2.5,2.7,3.9):
    rivet(f"belt_stud_{x}",x,16.2,3.6,size=.21)
for name,a,b in [("top",[-.95,16.64,3.55],[1.0,17,3.98]),("bottom",[-.95,15.3,3.55],[1,15.65,3.98]),
                 ("left",[-.95,15.6,3.55],[-.58,16.7,3.98]),("right",[.64,15.6,3.55],[1,16.7,3.98])]:
    cube("buckle_"+name,a,b,"steel_light")
cube("buckle_tongue",[-.5,16.0,3.72],[.92,16.23,4.08],"steel_edge")
for s,tag in ((-1,"r"),(1,"l")):
    cube("hip_pouch_"+tag,[s*4.45-.78,13.7,-.2],[s*4.45+.78,16.7,1.7],"leather")
    cube("pouch_flap_"+tag,[s*4.45-.83,15.55,1.71],[s*4.45+.83,16.65,1.98],"leather_light")
    for i in range(2):
        x=s*(3.0+i*.55)
        cube(f"hip_plate_{tag}_{i}",[x-1.3,12.5+i*.9,1.8],[x+1.3,14.25+i*.9,2.6],"steel_dark",rotation=[0,0,s*13])

# Tabard with a stepped linen hem.
outline=[(-2.5,8.1),(0,7.55),(2.5,8.1),(2.7,15.55),(-2.7,15.55)]
prism("tabard_linen_border",outline,2.69,3.03,"linen")
prism("tabard_blue",[(-2.12,8.5),(0,8.05),(2.12,8.5),(2.27,15.57),(-2.27,15.57)],3.04,3.14,"cloth")
emblem("tabard_insignia",0,11.45,3.15,.38,"body")

# Diagonal leather baldric across the chest, with metal keepers.
bar("diagonal_baldric",[-3.7,24.1,3.5],[3.1,17.25,3.5],1.02,.28,"leather_light","body")
for i,t in enumerate((.15,.58,.77)):
    x,y=-3.7+6.8*t,24.1-6.85*t
    cube(f"baldric_keeper_{i}",[x-.68,y-.15,3.68],[x+.68,y+.15,3.87],"steel_light",rotation=[0,0,44])

# Hood/scarf rings and folded bib frame an exposed face.
cube("collar_base",[-3.4,25.3,-2.9],[3.4,27.6,2.82],"cloth_dark")
cube("scarf_back_fold",[-4.0,26.1,-3.5],[4.0,27.7,-2.35],"cloth")
for s,tag in ((-1,"r"),(1,"l")):
    cube("scarf_side_"+tag,[s*3.35-.8,25.55,-2.8],[s*3.35+.8,27.3,2.88],"cloth")
    bar("scarf_diagonal_"+tag,[s*3.4,26.5,3.18],[s*.55,25.1,3.18],1.05,.68,"cloth","body")
    bar("scarf_lip_"+tag,[s*3.45,26.8,3.52],[s*.55,25.4,3.52],.3,.18,"cloth_light","body")
cube("scarf_bottom_fold",[-1.65,24.7,2.97],[1.65,25.6,3.6],"cloth_dark")

# Broad, stepped cape and a compact hood on the back.
prism("cape_border",[(-3.5,10.0),(0,9.3),(3.5,10),(4.2,12),(3.6,26.5),(-3.6,26.5),(-4.2,12)],-3.93,-3.48,"linen","cape")
prism("cape_main",[(-3.12,10.45),(0,9.85),(3.12,10.45),(3.77,12.15),(3.25,26.55),(-3.25,26.55),(-3.77,12.15)],-4.04,-3.92,"cloth","cape")
for x in (-2.6,-1.25,1.25,2.6):
    cube(f"cape_vertical_fold_{x}",[x-.18,12.0,-4.17],[x+.18,24.9,-4.03],"cloth_light" if abs(x)>2 else "cloth_dark","cape")
emblem("cape_insignia",0,18.15,-4.2,.64,"cape",back=True)
prism("hood_back",[(-3.7,26.4),(3.7,26.4),(2.7,24.5),(0,23.2),(-2.7,24.5)],-4.4,-3.35,"cloth_dark","cape")
bar("hood_rim_left",[-3.5,26.5,-4.5],[0,24.15,-4.5],.46,.35,"cloth_light","cape")
bar("hood_rim_right",[0,24.15,-4.5],[3.5,26.5,-4.5],.46,.35,"cloth_light","cape")

# Exposed face with strong brows, blue eyes and a restrained mouth.
cube("neck",[-1.6,26.3,-1.25],[1.6,28.8,1.4],"skin","head")
cube("head_skin",[-3.9,27.3,-3.05],[3.9,34.7,3.4],"skin_light","head")
for s,tag in ((-1,"r"),(1,"l")):
    cube("ear_"+tag,[s*4.0-.5,29.4,-.55],[s*4.0+.5,31.45,1.0],"skin","head")
    cube("ear_inner_"+tag,[s*4.05-.28,29.9,1.01],[s*4.05+.28,30.95,1.12],"skin_light","head")
    cx=s*1.95
    cube("eye_socket_"+tag,[cx-1.02,29.85,3.42],[cx+1.02,31.65,3.47],"skin","head")
    cube("eye_white_"+tag,[cx-.85,30.13,3.48],[cx+.85,31.47,3.52],"eye_white","head")
    cube("eye_iris_"+tag,[cx-.44,30.14,3.53],[cx+.36,31.49,3.56],"eye_blue","head")
    cube("eye_pupil_"+tag,[cx-.16,30.34,3.57],[cx+.26,31.49,3.60],"eye_dark","head")
    cube("eye_glint_"+tag,[cx-.28,31.09,3.61],[cx-.02,31.4,3.64],"eye_white","head")
    cube("eyebrow_"+tag,[cx-1.15,31.52,3.47],[cx+1.05,32.15,3.74],"hair","head",[0,0,s*12])
cube("nose_plane",[-.43,29.48,3.43],[.43,30.7,3.62],"skin_light","head")
cube("nose_shadow",[-.35,29.38,3.63],[.44,29.57,3.67],"skin","head")
cube("mouth",[-.85,28.43,3.45],[.85,28.65,3.5],"mouth","head")

# Sculpted locks: offset cuboids around a solid cap, deliberately asymmetric fringe.
cube("hair_cap",[-4.25,33.35,-3.55],[4.25,35.55,3.56],"hair","head")
cube("hair_back_mass",[-4.15,28.6,-3.75],[4.15,34.6,-2.84],"hair","head")
for ix in range(5):
    for iz in range(4):
        x,z=-4.2+ix*1.69,-3.7+iz*1.85
        lift=RNG.choice((0,.22,.42,.6))
        cube(f"crown_lock_{ix}_{iz}",[x,34.9+lift,z],[x+1.78,35.75+lift,z+1.95],RNG.choice(("hair","hair_light")),"head")
for i,(x,w,bottom) in enumerate(((-4.1,1.6,31.8),(-2.8,1.7,32.7),(-1.3,1.9,32.0),(.3,1.65,33.1),(1.7,1.6,33.4),(3.0,1.2,32.4))):
    cube(f"fringe_{i}",[x,bottom,3.43],[x+w,35.03,4.0+(.13 if i%2 else 0)],"hair_light" if i in (1,3) else "hair","head")
for s,tag in ((-1,"r"),(1,"l")):
    for row in range(3):
        for col in range(3):
            z=-3.6+col*1.75
            y=29.4+row*1.8+RNG.choice((0,.35))
            if row==0 and col==2:
                continue
            cube(f"side_lock_{tag}_{row}_{col}",[s*4.12-.4,y,z],[s*4.12+.4,y+1.95,z+1.9],"hair_light" if (row+col)%4==0 else "hair","head")
for row in range(3):
    for col in range(5):
        x=-4.14+col*1.66
        y=28.45+row*1.9+RNG.choice((0,.25,.45))
        cube(f"rear_lock_{row}_{col}",[x,y,-4.05],[x+1.78,y+2.2,-3.42],"hair_light" if (row+col)%4==0 else "hair","head")

# Arms: quilted sleeves, strapped leather and overlapping iron plates.
for s,tag,upper,fore in ((-1,"r","arm_right","forearm_right"),(1,"l","arm_left","forearm_left")):
    cx=s*6.8
    cube("upper_sleeve_"+tag,[cx-1.65,19.2,-1.82],[cx+1.65,25.6,1.85],"padding",upper)
    cube("upper_leather_"+tag,[cx-1.83,20,-1.93],[cx+1.83,24.5,1.95],"leather",upper)
    cube("pauldron_underlay_"+tag,[cx-2.56,22.1,-2.47],[cx+2.56,26.0,2.55],"leather",upper)
    cube("pauldron_main_"+tag,[cx-2.22,23.9,-2.36],[cx+2.22,27.1,2.45],"steel",upper)
    cube("pauldron_crown_"+tag,[cx-1.5,26.4,-1.98],[cx+1.5,27.65,2.05],"steel_light",upper)
    cube("pauldron_outer_step_"+tag,[cx+s*1.95-.73,23.3,-2.52],[cx+s*1.95+.73,26.3,2.57],"steel_dark",upper)
    cube("pauldron_hem_"+tag,[cx-2.57,22.95,-2.61],[cx+2.57,23.57,2.7],"steel_edge",upper)
    chamfered_plate("pauldron_front_plate_"+tag,cx,23.6,3.8,3.05,2.46,2.84,"steel",upper)
    cube("pauldron_ridge_"+tag,[cx-.26,23.7,2.69],[cx+.26,26.6,2.96],"steel_light",upper)
    for x in (cx-1.6,cx+1.6):
        rivet(f"shoulder_stud_{tag}_{x}",x,23.94,2.7,upper,size=.34)
    for j,(dx,y,w) in enumerate(((-1.15,25.9,.54),(.95,24.2,.4),(-.9,24.0,.27))):
        cube(f"shoulder_edge_chip_{tag}_{j}",[cx+dx,y,2.86],[cx+dx+w,y+.18,2.89],"steel_light",upper)
    cube("elbow_"+tag,[cx-1.6,18.3,-1.78],[cx+1.6,20.25,1.9],"steel_dark",fore)
    cx=s*7.05
    cube("bracer_leather_"+tag,[cx-1.75,14.8,-1.73],[cx+1.75,19.4,1.96],"leather",fore)
    chamfered_plate("bracer_plate_"+tag,cx,15.9,3.28,3.85,1.96,2.44,"steel",fore)
    for j,y in enumerate((15.45,18.85)):
        cube(f"bracer_band_{tag}_{j}",[cx-1.92,y,-1.87],[cx+1.92,y+.58,2.61],"steel_light",fore)
        rivet(f"bracer_stud_{tag}_{j}",cx+1.43,y+.29,2.63,fore,size=.29)
    cube("glove_"+tag,[cx-1.55,12.2,-1.43],[cx+1.55,15.5,1.82],"leather",fore)
    cube("gauntlet_plate_"+tag,[cx-1.43,13.1,1.84],[cx+1.43,15.3,2.32],"steel_dark",fore)
    for finger in range(3):
        x=cx-1.4+finger*.93
        cube(f"finger_{tag}_{finger}",[x,12.1,1.7],[x+.79,13.35,2.14],"leather_light",fore)
    cube("thumb_"+tag,[cx-s*1.3-.55,13.0,1.05],[cx-s*1.3+.55,14.75,2.22],"leather_light",fore)

# Legs and planted square boots. Ground contact is exactly zero.
for s,tag,thigh,shin in ((-1,"r","leg_right","shin_right"),(1,"l","leg_left","shin_left")):
    cx=s*2.96
    cube("trouser_"+tag,[cx-1.78,7.2,-1.73],[cx+1.78,14.4,1.8],"padding",thigh)
    cube("thigh_leather_"+tag,[cx-1.89,8.9,-1.86],[cx+1.89,12.7,2.06],"leather",thigh)
    cube("thigh_strap_"+tag,[cx-1.97,10.35,-1.94],[cx+1.97,11.03,2.22],"leather_light",thigh)
    cube("knee_base_"+tag,[cx-2.06,6.7,-1.95],[cx+2.06,9.25,2.27],"steel_dark",thigh)
    chamfered_plate("knee_plate_"+tag,cx,6.85,3.6,2.46,2.28,2.7,"steel",thigh)
    cube("knee_top_lip_"+tag,[cx-1.85,8.94,2.71],[cx+1.85,9.35,2.89],"steel_light",thigh)
    for x in (cx-1.43,cx+1.43):
        rivet(f"knee_rivet_{tag}_{x}",x,7.35,2.73,thigh,size=.28)
    cube("boot_shaft_"+tag,[cx-1.86,1.0,-1.9],[cx+1.86,7.0,1.94],"leather",shin)
    cube("shin_panel_"+tag,[cx-1.23,2.3,1.95],[cx+1.23,6.5,2.12],"leather_light",shin)
    for j,y in enumerate((3.0,5.6)):
        cube(f"boot_strap_{tag}_{j}",[cx-1.98,y,-2.02],[cx+1.98,y+.66,2.31],"leather_light",shin)
        cube(f"boot_buckle_{tag}_{j}",[cx+s*.8-.48,y-.07,2.32],[cx+s*.8+.48,y+.72,2.51],"steel",shin)
        rivet(f"boot_buckle_pin_{tag}_{j}",cx+s*.8,y+.3,2.53,shin,size=.19)
    cube("boot_foot_"+tag,[cx-2.12,.45,-2.15],[cx+2.12,2.3,3.22],"leather",shin)
    cube("boot_toe_"+tag,[cx-1.95,.6,2.8],[cx+1.95,1.96,3.52],"leather_light",shin)
    cube("boot_sole_"+tag,[cx-2.21,0,-2.22],[cx+2.21,.47,3.63],"padding",shin)
    cube("sole_toe_edge_"+tag,[cx-2.2,.1,3.5],[cx+2.2,.49,3.68],"steel_dark",shin)

# Sword: genuine pointed, bevelled blade, brass guard and wrapped grip.
sx,sz=-7.05,.6
cube("sword_grip",[sx-.42,12.4,sz-.44],[sx+.42,15.8,sz+.44],"cloth_dark","sword")
for i in range(6):
    cube(f"grip_wrap_{i}",[sx-.47,12.6+i*.45,sz-.48],[sx+.47,12.77+i*.45,sz+.48],"cloth","sword")
cube("sword_pommel",[sx-.69,15.7,sz-.67],[sx+.69,16.55,sz+.67],"gold","sword")
cube("pommel_cap",[sx-.43,16.45,sz-.43],[sx+.43,16.72,sz+.43],"gold_light","sword")
cube("crossguard",[sx-2.15,11.92,sz-.68],[sx+2.15,12.65,sz+.68],"gold","sword")
for s in (-1,1):
    cube(f"guard_tip_{s}",[sx+s*1.8-.47,11.65,sz-.77],[sx+s*1.8+.47,12.92,sz+.77],"gold_light","sword",[0,0,s*13])
cube("blade_collar",[sx-.95,11.28,sz-.48],[sx+.95,12.04,sz+.48],"steel_dark","sword")
blade_outline=[(sx,1.0),(sx+1.02,3.0),(sx+1.02,11.62),(sx-1.02,11.62),(sx-1.02,3.0)]
prism("blade_silhouette",blade_outline,sz-.16,sz+.16,"steel_edge","sword")
mesh("blade_front_bevel",[[sx,1,sz+.16],[sx-1.02,3,sz+.16],[sx-1.02,11.62,sz+.16],
                          [sx,11.62,sz+.44],[sx,3,sz+.44],[sx+1.02,11.62,sz+.16],[sx+1.02,3,sz+.16]],
                         [[0,4,1],[1,4,3,2],[0,6,4],[4,6,5,3]],"steel_light","sword")
mesh("blade_back_bevel",[[sx,1,sz-.16],[sx-1.02,3,sz-.16],[sx-1.02,11.62,sz-.16],
                         [sx,11.62,sz-.44],[sx,3,sz-.44],[sx+1.02,11.62,sz-.16],[sx+1.02,3,sz-.16]],
                        [[0,1,4],[1,2,3,4],[0,4,6],[4,3,5,6]],"steel","sword")

# Kite shield: oak back, individual painted boards, perimeter iron frame and grip.
cx,cy=7.7,14.4
outline=[(cx,6.0),(cx+3.7,9.3),(cx+3.7,21.1),(cx,22.4),(cx-3.7,21.1),(cx-3.7,9.3)]
prism("shield_oak_core",outline,3.55,4.18,"wood","shield")
prism("shield_iron_rim",outline,4.19,4.58,"steel_light","shield")
inner=[(cx,6.85),(cx+3.08,9.65),(cx+3.08,20.62),(cx,21.68),(cx-3.08,20.62),(cx-3.08,9.65)]
prism("shield_rear_iron_rim",outline,3.27,3.54,"steel","shield")
prism("shield_rear_oak_inset",inner,3.13,3.26,"wood","shield")
prism("shield_painted_inset",inner,4.59,4.66,"cloth","shield")
for i in range(5):
    x=cx+(i-2)*1.18
    bottom=7.15+abs(x-cx)*.92
    top=21.5-abs(x-cx)*.35
    prism(f"shield_board_{i}",[(x-.56,bottom+.36),(x+.56,bottom+.36),(x+.56,top-.18),(x-.56,top-.18)],4.67,4.7,
          "wood" if i in (0,4) else ("cloth_light" if i==2 else "cloth"),"shield")
for i,(x,y) in enumerate([(cx,21.99),(cx-3.42,20.74),(cx+3.42,20.74),(cx-3.42,16.5),(cx+3.42,16.5),
                          (cx-3.42,11.8),(cx+3.42,11.8),(cx-2.05,8.3),(cx+2.05,8.3),(cx,6.5)]):
    rivet(f"shield_rivet_{i}",x,y,4.6,"shield",material="steel_edge",size=.37)
emblem("shield_insignia",cx,14.6,4.75,.69,"shield")
for i,y in enumerate((11.2,18.5)):
    cube(f"shield_rear_brace_{i}",[cx-3.1,y-.38,2.99],[cx+3.1,y+.38,3.14],"steel_dark","shield")
    for x in (cx-2.6,cx+2.6):
        cube(f"rear_bolt_{i}_{x}",[x-.19,y-.19,2.82],[x+.19,y+.19,3.0],"steel","shield")
for x in (cx-1.12,cx+1.12):
    cube(f"shield_handle_mount_{x}",[x-.24,13.45,2.05],[x+.24,15.0,3.55],"leather","shield")
cube("shield_handgrip",[cx-1.18,13.5,1.74],[cx+1.18,14.3,2.19],"leather_light","shield")

# Rest pose first; organised joints are ready for the next animation pass.
image_bytes=io.BytesIO()
atlas.save(image_bytes,format="PNG")
texture={"name":NAME+"_atlas.png","id":"0","uuid":uid("atlas"),"relative_path":NAME+"_atlas.png",
         "source":"data:image/png;base64,"+base64.b64encode(image_bytes.getvalue()).decode(),
         "mode":"bitmap","saved":True,"width":ATLAS_SIZE,"height":ATLAS_SIZE,
         "uv_width":ATLAS_SIZE,"uv_height":ATLAS_SIZE,"visible":True,"internal":True}
model={"meta":{"format_version":"4.5","model_format":"free","box_uv":False},
       "name":NAME,"model_identifier":NAME,"visible_box":[2,3,0],
       "resolution":{"width":ATLAS_SIZE,"height":ATLAS_SIZE},
       "elements":elements,"outliner":[groups["root"]],"textures":[texture],"animations":[],
       "reference_notes":{"front":"+Z","ground_y":0,"metres_per_unit":2/36.35,
                          "status":"Combat idle static pose candidate; animation not yet authored",
                          "pose":"Shoulder 9 deg outward; diagonal elbow bend about 25 deg; blade 9 deg forward and 8 deg axial roll, aligned with forearm.",
                          "reference":"D:/download/e1d86959-5d7a-46a4-94f2-325f00d9fc24.png"}}


def main():
    source=HERE/(NAME+".bbmodel")
    if source.exists():
        backups=HERE/"backups"
        backups.mkdir(exist_ok=True)
        shutil.copy2(source,backups/(NAME+"_"+datetime.now().strftime("%Y%m%d_%H%M%S")+".bbmodel"))
    source.write_text(json.dumps(model,ensure_ascii=False,indent=2),encoding="utf-8")
    atlas.save(HERE/(NAME+"_atlas.png"))
    print(json.dumps({"source":str(source),"elements":len(elements),"groups":len(groups),
                      "cubes":sum(e["type"]=="cube" for e in elements),
                      "meshes":sum(e["type"]=="mesh" for e in elements),"texture":[512,512]}))


if __name__=="__main__":
    main()
