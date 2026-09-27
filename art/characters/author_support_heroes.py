"""Blender authoring recipe for the Archer and Engineer candidates.

The saved, editable .blend is the artistic source. This is an explicit authoring
operation, never a build step. Coordinates below use the existing Godot rig frame
(metres, +Y up, -Z forward), converted to Blender on entry. Existing hook names
and clip durations are retained; continuous poses are baked on the rigid joints.
"""
from __future__ import annotations
import argparse
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector, Matrix, Quaternion

C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
ROOT = Path(__file__).resolve().parents[2]
FPS = 100  # Exact .06/.08/.12/.15/.28 gameplay contact times.
nodes = {}
rest = {}
mats = {}
kind = ""


def vec(v):
    return C @ Vector(v)


def empty(name, pos, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.data.collections['EXPORT'].objects.link(obj)
    obj.parent = nodes.get(parent)
    obj.location = vec(pos)
    obj.rotation_mode = 'QUATERNION'
    obj.empty_display_size = .06
    nodes[name] = obj
    rest[name] = obj.location.copy()
    return obj


def rot(name, degrees):
    # Same intrinsic YXZ convention as Godot Basis.from_euler.
    x, y, z = map(math.radians, degrees)
    q = Quaternion((0, 1, 0), y) @ Quaternion((1, 0, 0), x) @ Quaternion((0, 0, 1), z)
    nodes[name].rotation_quaternion = (C @ q.to_matrix() @ C.inverted()).to_quaternion()


def mesh(name, vertices, faces, parent, cell, material='soft', bevel=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata([vec(v) for v in vertices], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.data.collections['EXPORT'].objects.link(obj)
    obj.parent = nodes[parent]
    data.materials.append(mats[material])
    uv = data.uv_layers.new(name='UVMap')
    col, row = cell % 4, cell // 4
    lo_u, lo_v = col / 4 + .006, 1 - (row + 1) / 4 + .006
    width = .238
    for poly in data.polygons:
        normal = poly.normal
        axes = (0, 2) if abs(normal.y) > .5 else ((1, 2) if abs(normal.x) > .5 else (0, 1))
        coords = [data.vertices[data.loops[i].vertex_index].co for i in poly.loop_indices]
        lows = [min(v[a] for v in coords) for a in axes]
        spans = [max(v[a] for v in coords) - low for a, low in zip(axes, lows)]
        for i, v in zip(poly.loop_indices, coords):
            uv.data[i].uv = (lo_u + width * (v[axes[0]] - lows[0]) / max(spans[0], .0001),
                             lo_v + width * (v[axes[1]] - lows[1]) / max(spans[1], .0001))
    if bevel:
        mod = obj.modifiers.new('One planar edge bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
    return obj


def box(name, center, size, parent, cell, material='soft', bevel=.006):
    x, y, z = center
    a, b, c = [v / 2 for v in size]
    vs = [(x-a,y-b,z-c),(x+a,y-b,z-c),(x+a,y+b,z-c),(x-a,y+b,z-c),
          (x-a,y-b,z+c),(x+a,y-b,z+c),(x+a,y+b,z+c),(x-a,y+b,z+c)]
    return mesh(name, vs, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)], parent,cell,material,bevel)


def prism(name, outline, front, back, parent, cell, material='soft', bevel=.006):
    n = len(outline)
    vs = [(x,y,front) for x,y in outline] + [(x,y,back) for x,y in outline]
    faces = [tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,vs,faces,parent,cell,material,bevel)


def beam(name, start, end, width, depth, parent, cell, material='soft'):
    a, b = Vector(start), Vector(end)
    direction = (b-a).normalized()
    axis = Vector((0,0,1)) if abs(direction.z) < .9 else Vector((0,1,0))
    u = direction.cross(axis).normalized()*width/2
    v = direction.cross(u.normalized())*depth/2
    vs = [p+s*u+t*v for p in (a,b) for s,t in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    return mesh(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],parent,cell,material,.003)


def material_setup(image):
    for name, metallic, rough in [('soft',0,.91),('leather',0,.7),('wood',0,.76),('iron',.65,.46),('copper',.72,.4),('glass',.15,.26)]:
        mat = bpy.data.materials.new(kind+'_'+name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Metallic'].default_value = metallic
        bsdf.inputs['Roughness'].default_value = rough
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = image
        tex.interpolation = 'Closest'
        mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
        mats[name] = mat


def rig():
    archer = kind == 'archer'
    hip, shoulder, neck = (.76, .61, .72) if archer else (.72, .60, .74)
    empty('root',(0,0,0))
    empty('torso',(0,hip,0),'root')
    empty('head',(0,neck,0),'torso')
    for side, sign in [('right',-1),('left',1)]:
        empty(side+'_arm',(sign*(.32 if archer else .40),shoulder,0),'torso')
        empty(side+'_elbow',(0,-.29,0),side+'_arm')
        empty(side+'_leg',(sign*(.145 if archer else .20),hip,0),'root')
        empty(side+'_knee',(0,-hip/2,0),side+'_leg')
    if archer:
        empty('bow',(0,-.57,0),'left_arm')
        empty('arrow_hand',(0,-.57,0),'right_arm')
        empty('quiver',(-.22,.34,.27),'torso')
        empty('cloak',(0,.51,.19),'torso')
        empty('bow_string_upper',(0,0,0),'bow')
        empty('bow_string_lower',(0,0,0),'bow')
    else:
        empty('wrench',(0,-.59,0),'right_arm')
        empty('gadget',(0,-.59,0),'left_arm')
        empty('powerpack',(.035,.31,.28),'torso')


def legs():
    archer = kind == 'archer'
    hip = .76 if archer else .72
    for side in ['right','left']:
        upper, lower = side+'_leg',side+'_knee'
        width = .205 if archer else .27
        box(side+'_trouser',(0,-hip/4,0),(width,hip/2,.24),upper,13 if archer else 1)
        box(side+'_shin',(0,-hip/4,0),(width*.9,hip/2-.06,.235),lower,4,'leather')
        box(side+'_boot',(0,-hip/2+.095,-.065),(width+.045,.19,.36),lower,4,'leather',.015)
        box(side+'_sole',(0,-hip/2+.025,-.065),(width+.055,.05,.37),lower,9 if archer else 11,'soft')
        box(side+'_boot_cuff',(0,-.06,0),(width+.035,.11,.27),lower,5,'leather')
        if not archer:
            box(side+'_knee_pad',(0,.025,-.14),(.23,.16,.05),lower,0,'leather')


def arms():
    archer = kind == 'archer'
    for side in ['right','left']:
        upper, lower = side+'_arm',side+'_elbow'
        width = .185 if archer else .24
        box(side+'_sleeve',(0,-.13,0),(width,.27,width),upper,2)
        box(side+'_forearm',(0,-.12,0),(width*.83,.25,width*.88),lower,8 if archer else 3,'soft' if archer else 'leather')
        box(side+'_bracer',(0,-.14,-.015),(width+.025,.17,width+.03),lower,5 if archer else 3,'leather')
        box(side+'_hand',(0,-.285,0),(width*.88,.12,width*.95),lower,8 if archer else 3,'soft' if archer else 'leather')


def archer_geometry():
    prism('fitted_tunic',[(-.21,0),(.21,0),(.265,.52),(.20,.65),(-.20,.65),(-.265,.52)],-.145,.15,'torso',2)
    box('waist_belt',(0,.075,0),(.46,.09,.33),'torso',5,'leather')
    box('belt_clasp',(.055,.075,-.183),(.10,.09,.025),'torso',12,'copper')
    prism('tunic_split_left',[(-.245,.05),(-.015,.05),(-.03,-.19),(-.19,-.25),(-.27,-.14)],-.16,.13,'torso',1)
    prism('tunic_split_right',[(.01,.05),(.235,.05),(.27,-.12),(.10,-.20),(.035,-.15)],-.16,.13,'torso',2)
    beam('diagonal_quiver_strap',(-.20,.60,-.177),(.20,.08,-.185),.085,.026,'torso',5,'leather')
    box('belt_pouch',(.27,.02,-.025),(.16,.21,.17),'torso',3,'leather')
    # Deliberately asymmetric, broad cloak panels leave legs and bow readable.
    prism('cloak_body',[(-.26,.035),(.26,.035),(.33,-.63),(.14,-.73),(-.01,-.64),(-.26,-.79),(-.32,-.48)],.04,.10,'cloak',15)
    prism('left_shoulder_cowl',[(.13,.55),(.41,.50),(.38,.37),(.20,.35)],-.18,.16,'torso',0)
    prism('right_shoulder_cowl',[(-.40,.53),(-.18,.57),(-.15,.39),(-.35,.34)],-.19,.14,'torso',1)
    box('face',(0,.205,-.012),(.36,.39,.33),'head',8,'soft',.018)
    # Open hood, never a solid cube obscuring the face.
    prism('hood_crown',[(-.27,.37),(-.23,.52),(.12,.55),(.25,.43),(.27,.35)],-.22,.22,'head',0)
    box('hood_back',(0,.24,.18),(.50,.36,.13),'head',1)
    prism('hood_left',[(-.28,.40),(-.19,.40),(-.17,.04),(-.28,-.03)],-.23,.20,'head',0)
    prism('hood_right',[(.18,.41),(.27,.41),(.28,.06),(.19,.015)],-.23,.19,'head',0)
    box('hood_brow',(0,.395,-.21),(.41,.065,.07),'head',0)
    box('nose',(0,.19,-.194),(.055,.085,.055),'head',8)
    for x in [-.087,.087]:
        box('eye_'+str(x),(x,.265,-.183),(.046,.043,.012),'head',9,bevel=0)
        box('brow_'+str(x),(x,.31,-.185),(.077,.027,.018),'head',9,bevel=0)
    beam('hood_feather_stem',(-.245,.31,.12),(-.34,.69,.13),.025,.018,'head',7,'wood')
    prism('hood_feather',[(-.34,.67),(-.39,.54),(-.30,.43),(-.275,.50)],.12,.135,'head',10,bevel=0)
    box('quiver_case',(0,0,0),(.22,.61,.19),'quiver',14,'leather',.014)
    box('quiver_rim',(0,.29,0),(.25,.065,.215),'quiver',5,'leather')
    for i in range(3):
        x = (i-1)*.062
        top = .53 + (i%2)*.065
        beam('arrow_shaft_'+str(i),(x,.15,0),(x,top,0),.015,.015,'quiver',7,'wood')
        prism('fletch_'+str(i),[(x-.036,top-.10),(x-.029,top+.025),(x+.03,top+.025),(x+.037,top-.08)],-.014,.015,'quiver',10,bevel=0)
    # Angular recurve with open negative space between limb and string.
    for sign in [-1,1]:
        points = [(0,0,-.055),(0,sign*.24,-.13),(0,sign*.43,-.12),(0,sign*.59,-.015),(0,sign*.67,-.055)]
        for i in range(4):
            beam('recurve_'+str(sign)+'_'+str(i),points[i],points[i+1],.064-i*.009,.064-i*.009,'bow',6,'wood')
    box('bow_grip',(0,0,-.035),(.085,.18,.08),'bow',5,'leather')
    # Unit-length strings are animated from their endpoints, not stretched meshes across hands.
    beam('string_top',(0,0,0),(0,1,0),.010,.010,'bow_string_upper',10)
    beam('string_bottom',(0,0,0),(0,1,0),.010,.010,'bow_string_lower',10)
    beam('nocked_arrow',(0,0,.035),(0,0,-.67),.014,.014,'arrow_hand',7,'wood')
    prism('arrowhead',[(-.035,0),(.035,0),(0,.095)],-.005,.005,'arrow_hand',11,'iron')


def engineer_geometry():
    prism('work_jacket',[(-.28,0),(.28,0),(.33,.54),(.23,.68),(-.23,.68),(-.33,.54)],-.18,.19,'torso',2)
    prism('apron_bib',[(-.24,.49),(.24,.49),(.27,.035),(.23,-.15),(-.22,-.15),(-.27,.035)],-.208,-.18,'torso',0,'leather')
    for sign in [-1,1]:
        beam('apron_suspenders_'+str(sign),(sign*.20,.62,-.19),(sign*.18,.34,-.23),.065,.027,'torso',5,'leather')
    box('belt',(0,.055,0),(.61,.085,.43),'torso',5,'leather')
    box('belt_buckle',(.06,.065,-.245),(.12,.095,.035),'torso',13,'copper')
    box('apron_pocket',(-.08,.24,-.238),(.21,.15,.042),'torso',15,'leather')
    box('side_tool_pouch',(.33,.015,.03),(.19,.26,.21),'torso',15,'leather')
    beam('belt_small_tool',(-.31,.13,-.12),(-.34,-.14,-.12),.045,.045,'torso',7,'iron')
    box('belt_tool_head',(-.31,.16,-.12),(.14,.085,.08),'torso',7,'iron')
    box('head_face',(0,.23,0),(.42,.43,.37),'head',8,bevel=.02)
    prism('hair_cap',[(-.245,.32),(-.235,.49),(-.08,.51),(-.05,.55),(.21,.50),(.245,.33)],-.19,.215,'head',9)
    box('hair_back',(0,.25,.20),(.43,.33,.07),'head',9)
    for sign in [-1,1]:
        box('sideburn_'+str(sign),(sign*.20,.14,-.135),(.055,.19,.075),'head',9)
        box('goggle_frame_'+str(sign),(sign*.105,.31,-.225),(.196,.15,.085),'head',12,'copper',.014)
        box('goggle_lens_'+str(sign),(sign*.105,.31,-.276),(.143,.099,.019),'head',10,'glass',.008)
    box('goggle_bridge',(0,.32,-.234),(.047,.04,.04),'head',11,'iron')
    box('goggle_headstrap',(0,.31,.025),(.485,.07,.405),'head',3,'leather',.002)
    box('nose',(0,.195,-.215),(.085,.12,.075),'head',8)
    prism('beard',[(-.17,.12),(-.07,.12),(-.07,.08),(.07,.08),(.07,.12),(.17,.12),(.145,-.005),(-.10,-.025)],-.204,-.15,'head',9)
    # Separate painted iron pack, copper pressure vessel and protected exhaust.
    box('pack_main',(0,0,.055),(.56,.62,.30),'powerpack',6,'iron',.018)
    box('pack_service_panel',(0,-.02,.226),(.43,.38,.046),'powerpack',14,'iron')
    box('pack_top_rail',(0,.30,.09),(.61,.07,.38),'powerpack',11,'iron')
    box('pack_lower_rail',(0,-.30,.09),(.61,.07,.38),'powerpack',11,'iron')
    box('copper_pressure_tank',(-.36,.00,.11),(.18,.49,.22),'powerpack',12,'copper',.018)
    for y in [-.17,.17]:
        box('tank_band_'+str(y),(-.36,y,.11),(.205,.048,.245),'powerpack',11,'iron')
    beam('exhaust_stack',(.22,.26,.11),(.22,.53,.11),.095,.095,'powerpack',11,'iron')
    box('exhaust_cap',(.22,.535,.11),(.145,.055,.145),'powerpack',7,'iron')
    box('pack_indicator',(.13,.125,.259),(.064,.07,.024),'powerpack',10,'glass')
    beam('pack_hose1',(-.34,-.21,.17),(-.35,-.35,.14),.042,.042,'powerpack',3,'leather')
    beam('pack_hose2',(-.35,-.35,.14),(-.11,-.37,.12),.042,.042,'powerpack',3,'leather')
    # Wrench-hammer: thick striking face and an unmistakable open jaw.
    box('tool_handle',(0,.18,0),(.085,.72,.08),'wrench',3,'leather')
    box('tool_shaft',(0,.43,0),(.095,.24,.09),'wrench',7,'iron')
    box('hammer_head',(-.035,.60,0),(.34,.21,.18),'wrench',7,'iron',.012)
    box('hammer_face',(-.235,.60,0),(.075,.25,.235),'wrench',11,'iron',.009)
    prism('open_wrench_upper',[(.09,.64),(.25,.64),(.30,.73),(.24,.78),(.10,.74)],-.08,.08,'wrench',7,'iron')
    prism('open_wrench_lower',[(.09,.56),(.24,.55),(.30,.47),(.23,.42),(.09,.47)],-.08,.08,'wrench',7,'iron')
    box('tool_collar',(0,.40,0),(.12,.055,.115),'wrench',12,'copper')
    box('detonator',(0,-.005,-.05),(.125,.17,.075),'gadget',11,'iron')
    box('detonator_switch',(0,.09,-.05),(.04,.04,.04),'gadget',12,'copper')


def solve_arm(side, hand, pole, hook=None, hook_rotation=(0,0,0)):
    """Offline two-link solve: rigid lengths, authored elbow plane, no runtime IK."""
    shoulder = C.inverted() @ rest[side+'_arm']
    target = Vector(hand)
    d = target - shoulder
    length = min(d.length,.569)
    direction = d.normalized()
    bend = Vector(pole) - direction * Vector(pole).dot(direction)
    bend.normalize()
    elbow = shoulder + direction*length/2 + bend*math.sqrt(max(0,.29**2-(length/2)**2))
    q1 = Vector((0,-1,0)).rotation_difference((elbow-shoulder).normalized())
    q2 = Vector((0,-1,0)).rotation_difference((target-elbow).normalized())
    nodes[side+'_arm'].rotation_quaternion = (C @ q1.to_matrix() @ C.inverted()).to_quaternion()
    nodes[side+'_elbow'].rotation_quaternion = (C @ (q1.inverted()@q2).to_matrix() @ C.inverted()).to_quaternion()
    if hook:
        nodes[hook].location = vec(q1.inverted() @ (target-shoulder))
        rot(hook,hook_rotation)
        desired = nodes[hook].rotation_quaternion.copy()
        nodes[hook].rotation_quaternion = nodes[side+'_arm'].rotation_quaternion.inverted() @ desired


def string_pose(draw):
    for name, tip in [('bow_string_upper',(0,.67,-.055)),('bow_string_lower',(0,-.67,-.055))]:
        a, b = Vector(tip), Vector((0,0,.11+draw))
        nodes[name].location = vec(a)
        q = Vector((0,1,0)).rotation_difference((b-a).normalized())
        nodes[name].rotation_quaternion = (C@q.to_matrix()@C.inverted()).to_quaternion()
        # The string primitive runs on Blender Z (Godot Y).
        nodes[name].scale = (1,1,(b-a).length)


def lerp_keys(t,keys):
    for (ta,a),(tb,b) in zip(keys,keys[1:]):
        if t <= tb:
            f = max(0,min(1,(t-ta)/(tb-ta)))
            f = f*f*(3-2*f)
            if isinstance(a,(tuple,list)):
                return tuple(x+(y-x)*f for x,y in zip(a,b))
            return a+(b-a)*f
    return keys[-1][1]


def pose(clip,t,length):
    for name,obj in nodes.items():
        obj.location = rest[name].copy()
        obj.rotation_quaternion = Quaternion()
        obj.scale = (1,1,1)
    breath = math.sin(t/1.2*math.tau)
    rot('torso',(1+breath*.65,0,0))
    rot('head',(-1-breath*.4,0,0))
    if clip == 'walk':
        phase = t/.8*math.tau
        for side,offset in [('right',0),('left',math.pi)]:
            rot(side+'_leg',(math.cos(phase+offset)*30,0,0))
            rot(side+'_knee',(-max(0,math.sin(phase+offset))*38,0,0))
        nodes['torso'].location += vec((0,abs(math.sin(phase))*.025,0))
        rot('torso',(4,math.sin(phase)*3,0))
    if kind == 'archer':
        bow = (.46,.27,-.24)
        draw_hand = (-.29,.20,-.22)
        draw = 0
        if clip in ('attack','special'):
            contact = .08 if clip == 'attack' else .28
            ready = (.45,.31,-.23)
            aimed = (.25,.61,-.53)
            bow = lerp_keys(t,[(0,ready),(contact*.60,aimed),(contact+.035,aimed),(length,ready)])
            draw = lerp_keys(t,[(0,0),(contact*.75,.29),(contact,.29),(contact+.025,0),(length,0)])
            draw_hand = (bow[0]-.035,bow[1],bow[2]+.11+draw)
            rot('head',(-2,-12,0))
        elif clip == 'utility':
            draw_hand = lerp_keys(t,[(0,draw_hand),(.08,(-.32,.20,.15)),(.14,(-.20,.44,-.50)),(length,draw_hand)])
        elif clip == 'ultimate':
            bow = lerp_keys(t,[(0,bow),(.25,(.70,.85,-.12)),(.50,(.70,.85,-.12)),(length,bow)])
            draw_hand = lerp_keys(t,[(0,draw_hand),(.25,(-.69,.83,-.12)),(.50,(-.69,.83,-.12)),(length,draw_hand)])
            rot('head',(-14,0,0))
        solve_arm('left',bow,(1,0,0),'bow')
        solve_arm('right',draw_hand,(-1,0,.5),'arrow_hand')
        string_pose(draw)
        # Park the cosmetic arrow inside its quiver outside shooting clips.
        if clip not in ('attack','special'):
            nodes['arrow_hand'].scale = (.001,.001,.001)
        elif t > (.08 if clip=='attack' else .28)+.02:
            nodes['arrow_hand'].scale = (.001,.001,.001)
        rot('cloak',(-3 + (math.sin(t/.8*math.tau)*3 if clip=='walk' else breath),0,-2))
    else:
        hand=(-.53,.15,-.18)
        left=(.45,.12,-.16)
        tool=(0,0,-15)
        if clip=='attack':
            hand=lerp_keys(t,[(0,hand),(.06,(-.50,.91,-.08)),(.12,(-.34,.18,-.45)),(.23,(-.36,.10,-.38)),(length,hand)])
            tool=lerp_keys(t,[(0,tool),(.06,(30,0,-10)),(.12,(-112,0,-15)),(.23,(-95,0,-10)),(length,tool)])
            rot('torso',(lerp_keys(t,[(0,2),(.06,-6),(.12,13),(.23,8),(length,2)]),0,0))
        elif clip in ('special','utility'):
            contact=.15 if clip=='special' else .18
            left=lerp_keys(t,[(0,left),(contact*.4,(.45,.23,.12)),(contact,(.35,.13,-.42)),(length,left)])
            rot('torso',(lerp_keys(t,[(0,2),(contact,19),(length,2)]),0,0))
        elif clip=='ultimate':
            left=lerp_keys(t,[(0,left),(.20,(.27,.78,-.15)),(.55,(.27,.78,-.15)),(length,left)])
            hand=lerp_keys(t,[(0,hand),(.25,(-.53,.39,-.26)),(.55,(-.53,.39,-.26)),(length,hand)])
        solve_arm('right',hand,(-1,0,.1),'wrench',tool)
        solve_arm('left',left,(1,0,.1),'gadget')


def animations():
    source=json.loads((ROOT/'assets/models/sources'/('hero_'+kind+'.bbmodel')).read_text())
    scene=bpy.context.scene
    scene.render.fps=FPS
    scene['gltf_animation_mode']='NLA_TRACKS'
    for clip in source['animations']:
        name=clip['name']
        length=clip['length']
        export_name=name+'-loop' if clip['loop']=='loop' else name
        for obj in nodes.values():
            obj.animation_data_create()
            obj.animation_data.action=bpy.data.actions.new(obj.name+'_'+name)
        for frame in range(round(length*FPS)+1):
            scene.frame_set(frame)
            pose(name,frame/FPS,length)
            for obj in nodes.values():
                obj.keyframe_insert('location',frame=frame)
                obj.keyframe_insert('rotation_quaternion',frame=frame)
                obj.keyframe_insert('scale',frame=frame)
        for obj in nodes.values():
            action=obj.animation_data.action
            track=obj.animation_data.nla_tracks.new()
            track.name=export_name
            strip=track.strips.new(export_name,0,action)
            strip.action_frame_start=0
            strip.action_frame_end=length*FPS
            track.mute=True
            obj.animation_data.action=None
    scene.frame_set(0)
    # Store an actual neutral rig pose, not an action sample, for additive binding.
    for name,obj in nodes.items():
        obj.location=rest[name].copy()
        obj.rotation_quaternion=Quaternion()
        obj.scale=(1,1,1)


def main():
    global kind
    parser=argparse.ArgumentParser()
    parser.add_argument('--class',dest='kind',choices=['engineer'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    kind=args.kind
    bpy.ops.wm.read_factory_settings(use_empty=True)
    collection=bpy.data.collections.new('EXPORT')
    bpy.context.scene.collection.children.link(collection)
    source=ROOT/'art/textures/characters'/f'{kind}_material_atlas_source.png'
    image=bpy.data.images.load(str(source))
    image.name=kind+'_material_atlas'
    image.scale(1024,1024)
    runtime=ROOT/'assets/models/textures'/kind/f'hero_{kind}_material_atlas.png'
    runtime.parent.mkdir(parents=True,exist_ok=True)
    image.filepath_raw=str(runtime)
    image.file_format='PNG'
    image.save()
    image.pack()
    material_setup(image)
    rig()
    legs()
    arms()
    (archer_geometry if kind=='archer' else engineer_geometry)()
    animations()
    scene=bpy.context.scene
    scene.unit_settings.system='METRIC'
    scene['asset_front']='Blender +Y -> Godot -Z, matches existing Archer/Engineer controller frame'
    scene['source_contract']='Cube-Siege issues #9/#10; preserve rigid ownership and gameplay timings'
    dest=ROOT/'art/characters'/kind/f'hero_{kind}.blend'
    dest.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(dest),compress=True)
    print('AUTHORED',dest)


if __name__=='__main__':
    main()
