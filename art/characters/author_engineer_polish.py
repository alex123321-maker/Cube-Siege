"""Blender authoring pass: stocky leather-clad engineer, quiet materials, angular face."""
import sys
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_support_heroes as m
from author_archer_reference import rings

original=m.engineer_geometry

def geometry():
    original()
    for name in ['work_jacket','head_face','hair_cap','hair_back','beard','nose']:
        bpy.data.objects.remove(bpy.data.objects[name],do_unlink=True)
    rings('work_jacket',[(0,.275,-.18,.185),(.20,.29,-.21,.19),(.48,.335,-.19,.20),(.66,.245,-.14,.16)],'torso',2,corner=.04)
    rings('angular_face',[(.015,.16,-.15,.14),(.11,.225,-.21,.17),(.34,.23,-.21,.18),(.47,.21,-.17,.17)],'head',8,corner=.03)
    m.box('neck',(0,-.04,0),(.17,.13,.15),'head',8,bevel=.004)
    rings('hair_cap',[(.35,.241,-.15,.21),(.47,.253,-.195,.22),(.55,.19,-.14,.17)],'head',9,corner=.032)
    for i,(x,y,z,w) in enumerate([(-.17,.49,-.175,.13),(-.06,.54,-.16,.12),(.055,.54,-.13,.12),(.16,.49,-.19,.13),(-.17,.38,.20,.13)]):
        m.box('hair_lock_'+str(i),(x,y,z),(w,.105,.09),'head',9,bevel=.003)
    m.prism('beard',[(-.205,.13),(-.09,.13),(-.075,.075),(.075,.075),(.09,.13),(.205,.13),(.175,-.02),(.075,-.09),(-.085,-.08),(-.175,-.025)],-.219,-.12,'head',9,bevel=.003)
    m.box('nose',(0,.185,-.236),(.082,.09,.06),'head',8,bevel=.005)
    m.box('moustache_left',(-.059,.12,-.239),(.10,.04,.035),'head',9,bevel=.002)
    m.box('moustache_right',(.059,.12,-.239),(.10,.04,.035),'head',9,bevel=.002)
    for side,sign in [('right',-1),('left',1)]:
        m.prism(side+'_shoulder_pad',[(-.14,.06),(-.11,.15),(.09,.15),(.15,.045),(.125,-.095),(-.12,-.085)],-.14,.12,side+'_arm',3,'leather')
        m.beam(side+'_shoulder_seam',(-.12,-.08,-.145),(.125,-.09,-.145),.021,.022,side+'_arm',12,'copper')
        for i in range(3):
            m.box(side+'_glove_finger_'+str(i),(-.065+i*.064,-.315,-.035),(.058,.10,.095),side+'_elbow',3,'leather',.004)
    # Recessed vents and bolts belong to the pack, never painted across unrelated faces.
    for y in [-.06,.025,.11]:
        m.box('pack_vent_'+str(y),(0,y,.254),(.26,.023,.025),'powerpack',11,'iron',.003)
    for x in [-.22,.22]:
        for y in [-.23,.23]:
            m.box('pack_bolt_'+str(x)+str(y),(x,y,.236),(.027,.027,.025),'powerpack',12,'copper',.003)

m.engineer_geometry=geometry
m.main()
