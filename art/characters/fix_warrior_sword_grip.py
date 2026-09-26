"""Revise the existing Blender warrior's sword fist and low guard, preserving clip clocks.

Run once against the repository source before this revision; the .blend remains canonical.
"""
from pathlib import Path
from math import radians
import bpy
from mathutils import Matrix, Vector

scene = bpy.context.scene
if scene.get('sword_grip_revision') == 1:
    raise RuntimeError('Sword grip revision is already applied')
sword = bpy.data.objects['sword']
arm = bpy.data.objects['right_arm']
collection = bpy.data.collections['EXPORT']
template = bpy.data.objects['R_Gauntlet']

def block(name, parent, center, size, material):
    obj = template.copy()
    obj.data = template.data.copy()
    obj.name = name
    collection.objects.link(obj)
    # Keep the authored UVs, but build each finger from the same centred box.
    old_size = Vector((.27, .32, .18))
    for v in obj.data.vertices:
        for i in range(3):
            v.co[i] *= size[i] / old_size[i]
    obj.data.materials.clear()
    obj.data.materials.append(bpy.data.materials[material])
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.location = center
    obj.rotation_euler = (0, 0, 0)
    obj.scale = (1, 1, 1)
    return obj

# The old straight blade extended the forearm like a spike. Pitch the hilt into
# a low forward guard; the same constant change applies to every authored clip.
for track in sword.animation_data.nla_tracks:
    for strip in track.strips:
        for layer in strip.action.layers:
            for action_strip in layer.strips:
                for bag in action_strip.channelbags:
                    for curve in bag.fcurves:
                        if curve.data_path == 'location' and curve.array_index in (1, 2):
                            offset = -.09 if curve.array_index == 1 else -.095
                            for key in curve.keyframe_points:
                                key.co.y += offset
                                key.handle_left.y += offset
                                key.handle_right.y += offset
                            curve.update()
                        if curve.data_path == 'rotation_euler' and curve.array_index == 0:
                            for key in curve.keyframe_points:
                                key.co.y -= radians(60)
                                key.handle_left.y -= radians(60)
                                key.handle_right.y -= radians(60)
                            curve.update()
sword.rotation_euler.x = -radians(60)
sword.location.y -= .09
sword.location.z -= .095

# A small wrist joint stays with the forearm. The closed fist and thumb share
# the hilt's transform so their orientation cannot lag behind it in an attack.
block('R_WristJoint', arm, (0, -.07, -.645), (.17, .19, .23), 'Warrior_cloth')
palm = block('SwordPalm', sword, (-.083, .008, 0), (.09, .19, .15), 'Warrior_leather')
for i, z in enumerate([-.06, -.02, .02, .06]):
    block(f'R_GripFinger{i}_Knuckle', sword, (0, -.089, z), (.17, .052, .033), 'Warrior_dark_steel')
    block(f'R_GripFinger{i}_Curl', sword, (.075, -.028, z), (.045, .102, .033), 'Warrior_leather')
    block(f'R_GripFinger{i}_Tip', sword, (.043, .026, z), (.065, .042, .033), 'Warrior_leather')
block('R_GripThumbBase', sword, (-.075, .071, -.046), (.067, .072, .058), 'Warrior_leather')
thumb = block('R_GripThumbTip', sword, (-.009, .073, -.047), (.104, .047, .049), 'Warrior_leather')
thumb.rotation_euler.y = radians(-12)
block('R_KnucklePlate', sword, (-.134, -.005, 0), (.025, .158, .125), 'Warrior_brass')
bpy.data.objects.remove(bpy.data.objects['R_Knuckle'], do_unlink=True)
bpy.data.objects.remove(template, do_unlink=True)
palm.name = 'R_Gauntlet'
socket = bpy.data.objects.new('SwordPalmSocket', None)
collection.objects.link(socket)
socket.parent = palm
socket.location = (.083, -.008, 0)
scene['sword_grip_revision'] = 1
scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
print('WARRIOR_SWORD_GRIP_REVISION=1')
