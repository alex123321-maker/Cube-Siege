"""Explicit Blender authoring session for the user-supplied elf Archer target.

Source of direction: art/references/issue-9/archer_approved_target.png.
Saved .blend owns the editable candidate; this recipe is not run during export.
"""
import math
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_support_heroes as m

box, prism, beam, empty = m.box, m.prism, m.beam, m.empty


def rings(name, levels, parent, cell, material='soft', corner=.025):
    vertices=[]
    for y,w,f,b in levels:
        c=min(corner,w*.4,(b-f)*.2)
        vertices += [(x,y,z) for x,z in [(-w+c,f),(w-c,f),(w,f+c),(w,b-c),(w-c,b),(-w+c,b),(-w,b-c),(-w,f+c)]]
    faces=[tuple(reversed(range(8)))]
    for row in range(len(levels)-1):
        for i in range(8):
            a=row*8+i; b=row*8+(i+1)%8
            faces.append((a,b,b+8,a+8))
    faces.append(tuple(range(len(vertices)-8,len(vertices))))
    return m.mesh(name,vertices,faces,parent,cell,material,.002)


def solid(name, color):
    mat=bpy.data.materials.new(name)
    mat.use_nodes=True
    mat.diffuse_color=(*color,1)
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value=(*color,1)
    bsdf.inputs['Roughness'].default_value=.8
    m.mats[name]=mat


def patch(name, outline, z, parent, mat):
    return prism(name,outline,z,z+.004,parent,8,mat,bevel=0)


def diamond(name, center, size, parent, cell, material='copper'):
    x,y,z=center
    w,h,d=size
    return m.mesh(name,[(x-w,y,z),(x,y+h,z),(x+w,y,z),(x,y-h,z),(x,y,z-d)],
                  [(0,1,4),(1,2,4),(2,3,4),(3,0,4),(3,2,1,0)],parent,cell,material,.001)


def head():
    rings('angular_face',[(.015,.155,-.17,.14),(.08,.21,-.204,.17),(.36,.228,-.204,.19),(.49,.22,-.18,.17)],'head',8,corner=.027)
    box('neck',(0,-.028,0),(.15,.115,.15),'head',8,bevel=.003)
    # Eyes are layered planar geometry. Their clear whites/iris/pupil survive iso zoom.
    for side in [-1,1]:
        x=side*.109
        # Mirrored angular almond shapes; no black rectangular lower/side frame.
        eye_shape=[(-.069,.302),(-.054,.324),(.067,.348),(.078,.309),(.057,.226),(-.044,.223),(-.066,.242)]
        patch('eye_white_'+str(side),[(x+side*u,v) for u,v in eye_shape],-.208,'head','eye_white')
        patch('sclera_lid_shadow_'+str(side),[(x+side*u,v) for u,v in [(-.065,.300),(-.054,.324),(.067,.348),(.072,.315),(.042,.316),(-.045,.293)]],-.210,'head','sclera_shadow')
        iris_x=x-side*.004
        patch('iris_rim_'+str(side),[(iris_x+u,v) for u,v in [(-.034,.321),(.034,.321),(.044,.303),(.039,.241),(.022,.221),(-.022,.221),(-.039,.241),(-.044,.303)]],-.212,'head','iris_dark')
        patch('emerald_iris_'+str(side),[(iris_x+u,v) for u,v in [(-.027,.316),(.027,.316),(.033,.299),(.03,.244),(.018,.23),(-.018,.23),(-.03,.244),(-.033,.299)]],-.214,'head','iris')
        patch('jade_lower_iris_'+str(side),[(iris_x+u,v) for u,v in [(-.032,.268),(.032,.268),(.03,.244),(.018,.23),(-.018,.23),(-.03,.244)]],-.216,'head','iris_light')
        patch('iris_lower_gold_'+str(side),[(iris_x+u,v) for u,v in [(-.021,.243),(.021,.243),(.016,.232),(-.016,.232)]],-.217,'head','iris_gold')
        patch('pupil_'+str(side),[(iris_x+u,v) for u,v in [(-.018,.323),(.018,.323),(.019,.269),(.012,.251),(-.012,.251),(-.019,.269)]],-.218,'head','eye_dark')
        # One primary reflection and a small secondary reflection, shared light direction.
        box('eye_catchlight_'+str(side),(iris_x-.016,.307,-.222),(.026,.032,.002),'head',0,'eye_white',bevel=0)
        box('eye_low_light_'+str(side),(iris_x+.023,.252,-.220),(.011,.012,.002),'head',0,'eye_white',bevel=0)
        patch('upper_lash_'+str(side),[(x+side*u,v) for u,v in [(-.073,.303),(-.060,.329),(.070,.352),(.088,.347),(.092,.326),(.062,.330),(-.055,.306)]],-.224,'head','eye_dark')
        patch('outer_lash_'+str(side),[(x+side*u,v) for u,v in [(.065,.335),(.101,.356),(.095,.324),(.074,.308)]],-.225,'head','eye_dark')
        patch('lower_lid_'+str(side),[(x+side*u,v) for u,v in [(-.042,.220),(.056,.224),(.056,.217),(-.042,.214)]],-.211,'head','lid_skin')
        beam('eyebrow_'+str(side),(x-side*.055,.377,-.211),(x+side*.062,.398,-.206),.021,.006,'head',13)
        # Tapered pointed ears with a recessed warm inner triangle.
        vs=[(side*.21,.29,.005),(side*.40,.385,.035),(side*.275,.205,.045),
            (side*.21,.29,.07),(side*.40,.385,.065),(side*.275,.205,.10)]
        m.mesh('pointed_ear_'+str(side),vs,[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],'head',8,bevel=.002)
        m.mesh('ear_inner_'+str(side),[(side*.25,.286,-.002),(side*.365,.36,.028),(side*.28,.245,.03)],[(0,2,1)],'head',8,'ear_inner')
    box('small_nose',(0,.188,-.218),(.043,.046,.026),'head',8,bevel=.002)
    box('mouth',(0,.104,-.21),(.070,.012,.003),'head',8,'lip',bevel=0)
    # Layered hair masses: a stepped crown, diagonal fringe, long side locks, ponytail.
    rings('hair_under_cap',[(.42,.242,-.13,.21),(.51,.266,-.21,.23),(.60,.215,-.17,.205),(.655,.11,-.11,.15)],'head',9,corner=.04)
    prism('swept_fringe_left',[(-.245,.56),(-.08,.635),(.055,.595),(-.015,.50),(-.095,.46),(-.17,.39),(-.215,.41)],-.253,-.20,'head',9,bevel=.002)
    prism('swept_fringe_right',[(.075,.595),(.21,.565),(.245,.495),(.18,.415),(.115,.46)],-.262,-.202,'head',9,bevel=.002)
    for i,(x,y,w,h,z) in enumerate([(-.205,.49,.12,.18,-.245),(-.12,.57,.13,.14,-.24),(-.02,.603,.14,.105,-.205),(.10,.58,.15,.105,-.222),(.20,.535,.12,.12,-.25),(.247,.465,.07,.13,-.231)]):
        box('fringe_step_%02d'%i,(x,y,z),(w,h,.095),'head',9,bevel=.003)
    prism('left_face_lock',[(-.274,.49),(-.19,.46),(-.195,.14),(-.185,-.015),(-.25,-.005),(-.292,.30)],-.244,-.145,'head',9,bevel=.003)
    prism('right_face_lock',[(.215,.47),(.288,.43),(.27,.18),(.224,.12),(.211,.31)],-.234,-.136,'head',9,bevel=.003)
    for i,(x,y,z,s) in enumerate([(-.23,.54,-.05,.12),(-.14,.625,-.05,.13),(0,.65,.025,.14),(.12,.61,.09,.14),(.20,.53,.14,.12),(-.20,.45,.205,.12)]):
        box('crown_lock_%02d'%i,(x,y,z),(s,.12,.18),'head',9,bevel=.003)
    box('ponytail_tie',(-.04,.48,.265),(.19,.10,.12),'head',0,bevel=.003)
    for i,(x,y,z,w,h) in enumerate([(-.035,.40,.325,.22,.22),(-.045,.24,.365,.24,.19),(-.01,.08,.39,.21,.18),(.035,-.06,.405,.19,.16),(.08,-.18,.40,.15,.14),(.10,-.265,.365,.11,.11)]):
        box('ponytail_lock_%02d'%i,(x,y,z),(w,h,.15),'head',9 if i%3 else 13,bevel=.003)
        if i<5:
            box('ponytail_side_strand_%02d'%i,(x-.09,y+.02,z-.035),(.08,h*.87,.13),'head',9,bevel=.002)


def body():
    # Ring topology gives a fitted waist, chest planes and hips instead of a box torso.
    rings('fitted_leather_cuirass',[(0,.205,-.128,.13),(.17,.165,-.128,.12),(.33,.18,-.158,.13),(.47,.225,-.183,.15),(.57,.205,-.14,.145),(.62,.15,-.11,.11)],'torso',2,'leather')
    prism('chest_center_panel',[(-.045,.16),(.045,.16),(.07,.47),(0,.54),(-.07,.47)],-.191,-.17,'torso',3,'leather')
    for side in [-1,1]:
        beam('chest_gold_seam_'+str(side),(0,.44,-.198),(side*.15,.53,-.162),.042,.022,'torso',10,'copper')
        box('leather_chest_side_'+str(side),(side*.185,.375,-.12),(.07,.13,.14),'torso',3,'leather')
    rings('layered_belt',[(.075,.215,-.16,.15),(.16,.208,-.16,.15)],'torso',5,'leather',corner=.03)
    for x in [-.16,-.10,.11,.17]:
        box('belt_rivet_'+str(x),(x,.115,-.166),(.014,.02,.013),'torso',10,'copper',bevel=.001)
    diamond('belt_gold_frame',(.005,.118,-.19),(.083,.082,.027),'torso',10)
    diamond('belt_green_gem',(.005,.12,-.224),(.047,.048,.014),'torso',0,'gem')
    beam('slung_leather_belt',(-.20,.04,-.16),(.22,.13,-.162),.052,.024,'torso',5,'leather')
    for side in [-1,1]:
        outline=[(side*.075,.04),(side*.20,.09),(side*.29,-.18),(side*.14,-.245),(side*.07,-.11)]
        prism('hip_leather_panel_'+str(side),outline,-.148,.11,'torso',3,'leather')
        beam('hip_gold_hem_'+str(side),(side*.145,-.226,-.15),(side*.275,-.17,-.15),.025,.026,'torso',10,'copper')
    prism('tabard_ivory_border',[(-.096,.043),(.096,.043),(.089,-.264),(0,-.344),(-.089,-.264)],-.178,-.155,'torso',7)
    prism('tabard_leaf_emblem',[(-.075,.037),(.075,.037),(.068,-.25),(0,-.312),(-.068,-.25)],-.185,-.18,'torso',14)
    # Folded scarf wraps the shoulders as a substantial continuous silhouette.
    rings('scarf_collar',[(.555,.245,-.18,.18),(.605,.278,-.195,.19),(.66,.24,-.14,.145)],'torso',0,corner=.037)
    beam('scarf_front_fold',(-.24,.608,-.189),(.245,.67,-.152),.087,.068,'torso',1)
    # A split, flared cape attached below the scarf. Fold geometry is broad, not noisy.
    prism('cape_left',[(-.22,.025),(.015,.025),(.045,-.51),(-.08,-.71),(-.27,-.79),(-.32,-.57)],.045,.09,'cloak',0)
    prism('cape_right',[(.01,.025),(.23,.025),(.32,-.60),(.27,-.77),(.11,-.65),(.07,-.73)],.052,.095,'cloak',14)
    beam('cape_ridge',(-.055,-.03,.043),(-.10,-.62,.084),.025,.025,'cloak',1)
    beam('quiver_diagonal_strap',(-.21,.53,.225),(.18,.07,.207),.075,.032,'torso',5,'leather')
    box('belt_side_pouch',(.27,.055,.07),(.12,.18,.145),'torso',5,'leather')


def limbs():
    for side,sign in [('right',-1),('left',1)]:
        arm,knee,leg,elbow=[side+s for s in ['_arm','_knee','_leg','_elbow']]
        rings(side+'_upper_arm',[(.015,.09,-.09,.09),(-.25,.071,-.068,.068),(-.29,.069,-.065,.065)],arm,8)
        # Three planar shoulder surfaces and narrow gold edging.
        prism(side+'_pauldron',[(-.115,.02),(-.09,.13),(.075,.13),(.12,.015),(.10,-.12),(-.11,-.10)],-.125,.11,arm,3,'leather')
        beam(side+'_shoulder_gold_top',(-.088,.123,-.132),(.074,.123,-.132),.026,.024,arm,10,'copper')
        beam(side+'_shoulder_gold_bottom',(-.102,-.10,-.132),(.10,-.112,-.132),.033,.024,arm,10,'copper')
        rings(side+'_forearm',[(.02,.076,-.072,.072),(-.23,.067,-.07,.07),(-.30,.064,-.065,.065)],elbow,8)
        rings(side+'_long_bracer',[(-.03,.096,-.097,.09),(-.21,.078,-.083,.08),(-.245,.075,-.078,.075)],elbow,3,'leather')
        for y,w in [(-.04,.098),(-.226,.08)]:
            rings(side+'_bracer_gold_'+str(y),[(y,w,-w,w),(y-.024,w,-w,w)],elbow,10,'copper',corner=.01)
        box(side+'_glove',(0,-.28,0),(.138,.10,.14),elbow,4,'leather')
        for i in range(3):
            box(side+'_finger_'+str(i),(-.043+i*.043,-.32,-.034),(.039,.075,.092),elbow,8,bevel=.002)
        box(side+'_thumb',(sign*.085,-.283,-.034),(.041,.076,.055),elbow,8,bevel=.002)
        rings(side+'_thigh',[(0,.112,-.118,.12),(-.20,.105,-.103,.105),(-.41,.083,-.09,.09)],leg,11)
        rings(side+'_shin',[(0,.088,-.09,.095),(-.34,.077,-.085,.083),(-.42,.09,-.10,.11)],knee,4,'leather')
        prism(side+'_knee_guard',[(-.094,.055),(.094,.055),(.088,-.10),(0,-.125),(-.089,-.10)],-.11,-.087,knee,3,'leather')
        beam(side+'_knee_trim',(-.093,.055,-.117),(.093,.055,-.117),.032,.025,knee,10,'copper')
        rings(side+'_knee_belt',[(-.071,.11,-.122,.105),(-.115,.108,-.12,.105)],knee,10,'copper',corner=.013)
        box(side+'_boot',(0,-.355,-.065),(.20,.15,.32),knee,4,'leather',.006)
        box(side+'_boot_toecap',(0,-.35,-.184),(.194,.13,.09),knee,3,'leather',.003)
        box(side+'_boot_sole',(0,-.421,-.066),(.21,.03,.33),knee,11,bevel=.002)
        box(side+'_boot_gold_toe',(0,-.279,-.16),(.19,.025,.075),knee,10,'copper',.002)


def equipment():
    rings('quiver_leather', [(-.32,.105,-.075,.085),(.26,.118,-.085,.095)],'quiver',15,'leather',corner=.025)
    for y in [-.285,.245]:
        rings('quiver_rim_'+str(y),[(y,.125,-.095,.10),(y+.045,.125,-.095,.10)],'quiver',10,'copper',corner=.015)
    for i in range(4):
        x=(i%2-.5)*.075; z=(i//2-.5)*.075
        top=.49+(i%3)*.055
        beam('quiver_arrow_'+str(i),(x,-.02,z),(x,top,z),.013,.013,'quiver',6,'wood')
        for side in [-1,1]:
            prism('arrow_feather_%s_%s'%(i,side),[(x,top-.09),(x+side*.034,top-.045),(x+side*.034,top+.045),(x,top+.017)],z-.008,z+.008,'quiver',7,bevel=0)
    box('bow_grip',(0,0,0),(.083,.21,.085),'bow',4,'leather',.003)
    # Front-facing bow arc is offset in X so the recurve is readable in the gameplay view.
    for sign in [-1,1]:
        points=[(0,sign*.075,0),(-.095,sign*.25,0),(-.165,sign*.43,0),(-.115,sign*.61,0),(-.16,sign*.71,0)]
        for i in range(4):
            beam('bow_limb_%s_%s'%(sign,i),points[i],points[i+1],.062 if i<2 else .044,.07,'bow',6,'wood')
        for i in [1,3,4]:
            p=points[i]
            box('bow_gold_wrap_%s_%s'%(sign,i),p,(.095,.087,.096),'bow',10,'copper',.002)
        diamond('bow_leaf_inlay_'+str(sign),(-.097,sign*.25,-.05),(.028,.032,.009),'bow',0,'gem')
    for node in ['bow_string_upper','bow_string_lower']:
        beam(node+'_mesh',(0,0,0),(0,1,0),.007,.007,node,7)
    beam('nocked_arrow',(0,0,.03),(0,0,-.65),.013,.013,'arrow_hand',6,'wood')
    m.mesh('nocked_arrow_head',[(-.03,0,-.63),(.03,0,-.63),(0,.012,-.735),(0,-.012,-.735)],[(0,1,2),(0,3,1),(0,2,3),(1,3,2)],'arrow_hand',7)


original_pose=m.pose


def pose(clip,t,length):
    original_pose(clip,t,length)
    # Updated arm target positions for the new shoulder pivots and graceful ready stance.
    if clip in ('idle','walk'):
        breath=math.sin(t/1.2*math.tau)*.005
        m.solve_arm('left',(.45,.13+breath,-.20),(1,0,.15),'bow',(0,-13,-7))
        m.solve_arm('right',(-.34,.01+breath,-.045),(-1,0,.1),'arrow_hand')
    # String follows the actual recurve endpoints and draw center in the bow frame.
    draw=0
    if clip in ('attack','special'):
        contact=.08 if clip=='attack' else .28
        draw=m.lerp_keys(t,[(0,0),(contact*.75,.29),(contact,.29),(contact+.025,0),(length,0)])
    from mathutils import Quaternion
    for name,sign in [('bow_string_upper',1),('bow_string_lower',-1)]:
        a=Vector((-.16,sign*.71,0)); b=Vector((0,0,.11+draw))
        m.nodes[name].location=m.vec(a)
        q=Vector((0,1,0)).rotation_difference((b-a).normalized())
        m.nodes[name].rotation_quaternion=(m.C@q.to_matrix()@m.C.inverted()).to_quaternion()
        m.nodes[name].scale=(1,1,(b-a).length)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m.kind='archer'
    collection=bpy.data.collections.new('EXPORT'); bpy.context.scene.collection.children.link(collection)
    image=bpy.data.images.load(str(m.ROOT/'art/textures/characters/archer_reference_atlas_source.png'))
    image.scale(1024,1024)
    image.filepath_raw=str(m.ROOT/'assets/models/textures/archer/hero_archer_material_atlas.png')
    image.file_format='PNG'; image.save(); image.pack()
    m.material_setup(image)
    # Quiet matte gold, not mirror-polished ornament.
    m.mats['copper'].node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value=.35
    m.mats['copper'].node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.55
    for name,color in [('eye_dark',(.018,.029,.021)),('eye_white',(.93,.94,.84)),('sclera_shadow',(.57,.64,.53)),('iris',(.045,.28,.115)),('iris_dark',(.02,.10,.06)),('iris_light',(.17,.44,.19)),('iris_gold',(.35,.48,.17)),('lid_skin',(.48,.24,.12)),('ear_inner',(.54,.19,.12)),('lip',(.28,.085,.049)),('gem',(.23,.32,.085))]:
        solid(name,color)
    empty('root',(0,0,0)); empty('torso',(0,.85,0),'root'); empty('head',(0,.695,0),'torso')
    for side,sign in [('right',-1),('left',1)]:
        empty(side+'_arm',(sign*.30,.545,0),'torso'); empty(side+'_elbow',(0,-.29,0),side+'_arm')
        empty(side+'_leg',(sign*.139,.85,0),'root'); empty(side+'_knee',(0,-.425,0),side+'_leg')
    for name,parent,pos in [('bow','left_arm',(0,-.57,0)),('arrow_hand','right_arm',(0,-.57,0)),('quiver','torso',(-.22,.40,.275)),('cloak','torso',(0,.56,.19)),('bow_string_upper','bow',(0,0,0)),('bow_string_lower','bow',(0,0,0))]:
        empty(name,pos,parent)
    head(); body(); limbs(); equipment()
    # Recalculate outward normals on closed meshes, while preserving facial decals.
    for obj in collection.objects:
        if obj.type=='MESH' and len(obj.data.polygons)>1:
            bm=bmesh.new(); bm.from_mesh(obj.data); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(obj.data); bm.free()
    m.pose=pose; m.animations()
    scene=bpy.context.scene
    scene.unit_settings.system='METRIC'
    scene['asset_front']='Blender +Y -> Godot -Z; original controller orientation'
    scene['art_direction']='User supplied blonde elf Archer target, September 26 2026; supersedes hood prototype'
    # Keep the exact user reference inside the .blend as a packed, non-exporting image.
    ref=bpy.data.images.load(str(m.ROOT/'art/references/issue-9/archer_approved_target.png')); ref.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(m.ROOT/'art/characters/archer/hero_archer.blend'),compress=True)


if __name__ == '__main__':
    main()
