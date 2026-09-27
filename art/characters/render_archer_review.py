"""Render the actual saved Blender model in a neutral studio, without repainting."""
import math
from pathlib import Path
import bpy
from mathutils import Vector

root=Path(__file__).resolve().parents[2]
out=root/'art/work/hero-polish/archer-reference-studio'
out.mkdir(parents=True,exist_ok=True)
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=32
scene.cycles.use_denoising=True
scene.render.resolution_x=1000
scene.render.resolution_y=1000
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
scene.world=bpy.data.worlds.new('Warm neutral studio')
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.15,.135,.115,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
for obj in bpy.data.collections['EXPORT'].objects:
    if obj.animation_data:
        for track in obj.animation_data.nla_tracks:
            track.mute=track.name!='idle-loop'
scene.frame_set(15)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015))
floor=bpy.context.object
floor.name='Review floor (not exported)'
mat=bpy.data.materials.new('Studio taupe')
mat.use_nodes=True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.13,.115,.095,1)
mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.9
floor.data.materials.append(mat)
def point(obj,target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
for name,location,power,size,color in [('Key',(-3,4,6),650,4,(1,.88,.70)),('Fill',(4,2,3),400,3,(.77,.85,1)),('Rim',(0,-3,5),750,3,(1,.91,.76))]:
    light=bpy.data.lights.new(name,'AREA'); light.energy=power; light.shape='DISK'; light.size=size; light.color=color
    obj=bpy.data.objects.new(name,light); scene.collection.objects.link(obj); obj.location=location; point(obj,(0,0,1.1))
data=bpy.data.cameras.new('Review camera'); data.type='ORTHO'; data.ortho_scale=2.75
camera=bpy.data.objects.new('Review camera',data); scene.collection.objects.link(camera); scene.camera=camera
for name,location,target,size in [('three_quarter',(3.5,6,3.0),(0,0,1.1),2.8),('front',(0,7,1.7),(0,0,1.1),2.65),('back',(-3,-6,2.8),(0,0,1.1),2.8),('face',(2,6,2.8),(0,0,1.78),1.13),('gameplay',(4.5,6,7),(0,0,1.0),3.15)]:
    camera.location=location; point(camera,target); data.ortho_scale=size
    scene.render.filepath=str(out/(name+'.png')); bpy.ops.render.render(write_still=True)
print('BLENDER_REVIEW_OUTPUT',out)
