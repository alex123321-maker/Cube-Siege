"""Derive a GLB and review renders from the canonical .bbmodel using Blender.

blender --background --python export_and_render.py -- [--quick]
The Blender scene is a derived review file, never the canonical source.
"""
from __future__ import annotations

import base64
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Vector

HERE=Path(__file__).resolve().parent
SOURCE=HERE/"warrior_reference.bbmodel"
data=json.loads(SOURCE.read_text(encoding="utf-8"))
SCALE=data["reference_notes"]["metres_per_unit"]
QUICK="--quick" in sys.argv
VIEWS=["three_quarter"] if QUICK else ["front","side","back","three_quarter","gameplay","rear_three_quarter"]
if "--views" in sys.argv:
    VIEWS=sys.argv[sys.argv.index("--views")+1].split(",")
    if VIEWS==["none"]:
        VIEWS=[]
OUT=HERE/"review"
OUT.mkdir(exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.unit_settings.system="METRIC"
scene.unit_settings.scale_length=1.0
export=bpy.data.collections.new("EXPORT")
scene.collection.children.link(export)
review=bpy.data.collections.new("REVIEW")
scene.collection.children.link(review)


def convert(p):
    return Vector((p[0]*SCALE,-p[2]*SCALE,p[1]*SCALE))


def bb_rotation(deg):
    return Euler(tuple(math.radians(x) for x in deg),"ZYX").to_matrix().to_4x4()


axis=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
elements={e["uuid"]:e for e in data["elements"]}
nodes={}
owner={}
rest={}


def load_group(g,parent=None,parent_origin=None):
    node=bpy.data.objects.new(g["name"],None)
    export.objects.link(node)
    node.empty_display_size=.06
    nodes[g["name"]]=node
    node.parent=parent
    origin=Vector(g.get("origin",[0,0,0]))
    node.location=convert(origin-(parent_origin or Vector((0,0,0))))
    node.rotation_euler=(axis@bb_rotation(g.get("rotation",[0,0,0]))@axis.inverted()).to_euler()
    rest[g["name"]]=node.rotation_euler.copy()
    for child in g["children"]:
        if isinstance(child,str):
            owner[child]=(node,origin)
        else:
            load_group(child,node,origin)


for group in data["outliner"]:
    load_group(group)

texture_path=HERE/"warrior_reference_atlas.png"
texture_path.write_bytes(base64.b64decode(data["textures"][0]["source"].split(",",1)[1]))
image=bpy.data.images.load(str(texture_path),check_existing=True)
image.pack()
materials={}


def material(name):
    if name in materials:
        return materials[name]
    mat=bpy.data.materials.new(name)
    mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get("Principled BSDF")
    metal=.35 if name.startswith("steel") else (.45 if name.startswith("gold") else 0)
    bsdf.inputs["Metallic"].default_value=metal
    bsdf.inputs["Roughness"].default_value=.65 if metal else .88
    tex=mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image=image
    tex.interpolation="Closest"
    tex.extension="EXTEND"
    mat.node_tree.links.new(tex.outputs["Color"],bsdf.inputs["Base Color"])
    mat.diffuse_color=(.5,.5,.5,1)
    materials[name]=mat
    return mat


# Merge geometry per joint while preserving every face UV and material assignment.
buckets={}
for e in data["elements"]:
    if not e.get("export",True):
        continue
    node,bone_origin=owner[e["uuid"]]
    bucket=buckets.setdefault(node.name,{"vertices":[],"faces":[],"uv":[],"mats":[]})
    origin=Vector(e.get("origin",[0,0,0]))
    rot=bb_rotation(e.get("rotation",[0,0,0])).to_3x3()
    if e["type"]=="cube":
        x,y,z=e["from"]
        X,Y,Z=e["to"]
        verts=[(x,y,z),(X,y,z),(X,Y,z),(x,Y,z),(x,y,Z),(X,y,Z),(X,Y,Z),(x,Y,Z)]
        face_defs={"north":[1,0,3,2],"south":[4,5,6,7],"east":[5,1,2,6],
                   "west":[0,4,7,3],"up":[7,6,2,3],"down":[0,1,5,4]}
        faces=[]
        uvs=[]
        for name,indices in face_defs.items():
            info=e["faces"][name]
            if info.get("texture") is None:
                continue
            u0,v0,u1,v1=info["uv"]
            faces.append(indices)
            uvs.append([(u0,v1),(u1,v1),(u1,v0),(u0,v0)])
    else:
        keys=list(e["vertices"])
        lookup={k:i for i,k in enumerate(keys)}
        verts=[Vector(e["vertices"][k])+origin for k in keys]
        faces=[[lookup[k] for k in f["vertices"]] for f in e["faces"].values()]
        uvs=[[f["uv"][k] for k in f["vertices"]] for f in e["faces"].values()]
    start=len(bucket["vertices"])
    for p in verts:
        p=origin+rot@(Vector(p)-origin)-bone_origin
        bucket["vertices"].append(convert(p))
    bucket["faces"].extend([[start+i for i in f] for f in faces])
    bucket["uv"].extend(uvs)
    bucket["mats"].extend([e["reference_material"]]*len(faces))

triangle_count=0
for name,bucket in buckets.items():
    m=bpy.data.meshes.new(name+"_geometry")
    m.from_pydata(bucket["vertices"],[],bucket["faces"])
    m.update()
    obj=bpy.data.objects.new(name+"_mesh",m)
    export.objects.link(obj)
    obj.parent=nodes[name]
    unique=list(dict.fromkeys(bucket["mats"]))
    for mat_name in unique:
        m.materials.append(material(mat_name))
    uv=m.uv_layers.new(name="UVMap")
    for poly,coords,mat_name in zip(m.polygons,bucket["uv"],bucket["mats"]):
        poly.material_index=unique.index(mat_name)
        poly.use_smooth=False
        triangle_count+=len(poly.vertices)-2
        for li,coord in zip(poly.loop_indices,coords):
            uv.data[li].uv=(coord[0]/512,1-coord[1]/512)

bpy.context.view_layer.update()


def pose_metrics(model):
    """Measure the authored joint chain, not the orientation of a camera render."""
    owned={}
    joints={}
    def visit(g,parent=Matrix.Identity(4),parent_origin=Vector((0,0,0))):
        pivot=Vector(g.get("origin",[0,0,0]))
        transform=parent@Matrix.Translation(pivot-parent_origin)@bb_rotation(g.get("rotation",[0,0,0]))
        joints[g["name"]]=transform
        for child in g["children"]:
            if isinstance(child,str):
                owned[child]=(transform,pivot)
            else:
                visit(child,transform,pivot)
    for g in model["outliner"]:
        visit(g)
    named={e["name"]:e for e in model["elements"]}
    def world(e,point):
        transform,pivot=owned[e["uuid"]]
        origin=Vector(e.get("origin",[0,0,0]))
        if e["type"]=="mesh":
            point=Vector(point)+origin
        p=origin+bb_rotation(e.get("rotation",[0,0,0])).to_3x3()@(Vector(point)-origin)
        return convert(transform@(p-pivot))
    blade=named["blade_silhouette"]
    verts=list(blade["vertices"].values())
    tip_y=min(p[1] for p in verts)
    tip_points=[p for p in verts if abs(p[1]-tip_y)<.001]
    tip=world(blade,sum((Vector(p) for p in tip_points),Vector())/len(tip_points))
    top_y=max(p[1] for p in verts)
    top=[p for p in verts if abs(p[1]-top_y)<.001]
    base=world(blade,sum((Vector(p) for p in top),Vector())/len(top))
    direction=(tip-base).normalized()
    grip=named["sword_grip"]
    grip_center=world(grip,(Vector(grip["from"])+Vector(grip["to"]))/2)
    forearm_direction=convert(joints["forearm_right"].to_3x3()@Vector((0,-1,0))).normalized()
    upperarm_direction=convert(joints["arm_right"].to_3x3()@Vector((0,-1,0))).normalized()
    relative_sword=joints["forearm_right"].to_3x3().inverted()@joints["sword"].to_3x3()
    boot=named["boot_sole_r"]
    boot_outer=world(boot,boot["from"])
    return {"blade_outward_deg":math.degrees(math.atan2(-direction.x,-direction.z)),
            "blade_back_deg":math.degrees(math.atan2(direction.y,math.hypot(direction.x,direction.z))),
            "blade_forward_deg":-math.degrees(math.atan2(direction.y,math.hypot(direction.x,direction.z))),
            "elbow_bend_deg":math.degrees(upperarm_direction.angle(forearm_direction)),
            "sword_axial_roll_deg":math.degrees(math.atan2(relative_sword[0][2],relative_sword[0][0])),
            "blade_forearm_angle_deg":math.degrees(direction.angle(forearm_direction)),
            "grip_height_m":grip_center.z,"grip_forward_m":-grip_center.y,"tip_blender_m":list(tip),
            "tip_to_boot_lateral_gap_m":boot_outer.x-tip.x}


pose=pose_metrics(data)
if "--compare-source" in sys.argv:
    previous=json.loads(Path(sys.argv[sys.argv.index("--compare-source")+1]).read_text(encoding="utf-8"))
    old_pose=pose_metrics(previous)
    pose["tip_shift_outward_m"]=old_pose["tip_blender_m"][0]-pose["tip_blender_m"][0]
    pose["tip_shift_forward_m"]=old_pose["tip_blender_m"][1]-pose["tip_blender_m"][1]
    pose["grip_shift_forward_m"]=pose["grip_forward_m"]-old_pose["grip_forward_m"]
    pose["previous"]=old_pose
points=[obj.matrix_world@Vector(c) for obj in export.objects if obj.type=="MESH" for c in obj.bound_box]
minimum=Vector(tuple(min(p[i] for p in points) for i in range(3)))
maximum=Vector(tuple(max(p[i] for p in points) for i in range(3)))
assert abs(minimum.z)<.001, minimum
assert 1.95<maximum.z<2.05, maximum

# Runtime export includes only actual asset nodes, never lights or floor.
bpy.ops.object.select_all(action="DESELECT")
for obj in export.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active=nodes["root"]
bpy.ops.export_scene.gltf(filepath=str(HERE/"warrior_reference.glb"),export_format="GLB",
                          use_selection=True,export_yup=True,export_animations=False,
                          export_materials="EXPORT",export_cameras=False,export_lights=False)

# Soft neutral studio lighting, matching the reference's light grey sheet.
scene.render.engine="CYCLES"
scene.cycles.samples=24 if QUICK else 48
scene.cycles.use_denoising=True
scene.cycles.max_bounces=6
try:
    prefs=bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type="OPTIX"
    prefs.get_devices()
    gpu=False
    for device in prefs.devices:
        device.use=device.type!="CPU"
        gpu=gpu or device.use
    if gpu:
        scene.cycles.device="GPU"
except Exception:
    pass
scene.render.resolution_x=800 if QUICK else 1000
scene.render.resolution_y=900 if QUICK else 1120
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.view_settings.view_transform="AgX"
scene.view_settings.look="AgX - Medium High Contrast"
world=bpy.data.worlds.new("Neutral studio")
scene.world=world
world.use_nodes=True
world.node_tree.nodes["Background"].inputs[0].default_value=(.68,.7,.74,1)
world.node_tree.nodes["Background"].inputs[1].default_value=.45


def area(name,loc,power,size,color):
    lamp=bpy.data.lights.new(name,"AREA")
    lamp.energy=power
    lamp.shape="DISK"
    lamp.size=size
    lamp.color=color
    obj=bpy.data.objects.new(name,lamp)
    review.objects.link(obj)
    obj.location=loc
    obj.rotation_euler=(Vector((0,0,1))-obj.location).to_track_quat("-Z","Y").to_euler()


area("large warm key",(-3.0,-4.5,6),420,4,(1,.93,.86))
area("soft fill",(4,-1.0,3.2),170,3,(.83,.90,1))
area("rim",(1,3.3,4.8),360,3,(1,.97,.92))
bpy.ops.mesh.primitive_plane_add(size=2000,location=(0,0,-.007))
floor=bpy.context.object
floor.name="Studio floor"
for col in list(floor.users_collection):
    col.objects.unlink(floor)
review.objects.link(floor)
mat=bpy.data.materials.new("warm grey ground")
mat.use_nodes=True
bsdf=mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value=(.56,.54,.51,1)
bsdf.inputs["Roughness"].default_value=.94
floor.data.materials.append(mat)
camera_data=bpy.data.cameras.new("Review camera")
camera=bpy.data.objects.new("Review camera",camera_data)
review.objects.link(camera)
scene.camera=camera
camera_data.type="ORTHO"
camera_data.ortho_scale=2.65
camera_data.clip_end=500.0
target=Vector((-.06,0,1.02))
locations={"front":(0,-8,2.0),"side":(-8,0,2.0),"back":(0,8,2.0),
           "three_quarter":(-5.8,-8,3.1),"gameplay":(-5,-7,7.2),"rear_three_quarter":(5.8,8,3.1)}
for name in VIEWS:
    camera.location=locations[name]
    camera.rotation_euler=(target-camera.location).to_track_quat("-Z","Y").to_euler()
    camera_data.ortho_scale=2.65 if name!="gameplay" else 2.8
    scene.render.filepath=str(OUT/(name+".png"))
    bpy.ops.render.render(write_still=True)
camera.location=locations["three_quarter"]
camera.rotation_euler=(target-camera.location).to_track_quat("-Z","Y").to_euler()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/"warrior_reference_review.blend"))
report={"source":str(SOURCE),"elements":len(elements),"joints":len(nodes),"triangles":triangle_count,
        "materials":len(materials),"height_m":maximum.z,"ground_m":minimum.z,
        "bounds_blender":{"min":list(minimum),"max":list(maximum)},
        "renders":[view for view in locations if (OUT/(view+".png")).exists()],"updated_views":VIEWS,
        "texture_filter":"Nearest","animations":[],"status":"combat-idle static pose candidate","pose":pose}
(OUT/"report.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
print("REFERENCE_WARRIOR_REPORT="+json.dumps(report))
