import json
import uuid

def uid():
    return str(uuid.uuid4())

def make_cube(name, p_from, p_to, origin, color=0, rot=[0,0,0]):
    return {
        "name": name,
        "uuid": uid(),
        "from": p_from,
        "to": p_to,
        "origin": origin,
        "rotation": rot,
        "color": color,
        "faces": {
            "north": {"uv": [0, 0, 8, 8]},
            "south": {"uv": [0, 0, 8, 8]},
            "east": {"uv": [0, 0, 8, 8]},
            "west": {"uv": [0, 0, 8, 8]},
            "up": {"uv": [0, 0, 8, 8]},
            "down": {"uv": [0, 0, 8, 8]}
        }
    }

# 1. Head & Armor
c_head = make_cube("head", [-4, 24, -4], [4, 32, 4], [0, 24, 0], color=0)
c_crest = make_cube("helmet_crest", [-1, 32, -4.5], [1, 35.5, 4.5], [0, 24, 0], color=5)
c_visor = make_cube("helmet_visor", [-4.3, 26, -4.8], [4.3, 29, -3.6], [0, 24, 0], color=7)

# 2. Torso & Armor
c_torso = make_cube("torso", [-4, 12, -2], [4, 24, 2], [0, 12, 0], color=1)
c_breastplate = make_cube("breastplate", [-4.4, 14.5, -2.6], [4.4, 23.5, 2.6], [0, 12, 0], color=8)

# 3. Right Arm
c_r_arm = make_cube("right_arm", [-8, 12, -2], [-4, 24, 2], [-6, 22, 0], color=0)

# SWORD: held in right hand (pivot at [-6, 12.5, 0])
# Now extending into -Z (Forward)
c_sword_handle = make_cube("sword_handle", [-6.5, 11.5, -1.5], [-5.5, 13.5, 2.0], [-6, 12.5, 0], color=4)
c_sword_pommel = make_cube("sword_pommel", [-6.8, 11.2, 2.0], [-5.2, 13.8, 3.0], [-6, 12.5, 0], color=3)
c_sword_guard  = make_cube("sword_guard",  [-8.8, 11.0, -2.5],  [-3.2, 14.0, -1.5],  [-6, 12.5, 0], color=3)
c_sword_blade  = make_cube("sword_blade",  [-6.4, 11.8, -17.0],  [-5.6, 13.2, -2.5], [-6, 12.5, 0], color=9)

# 4. Left Arm & Shield
c_l_arm = make_cube("left_arm", [4, 12, -2], [8, 24, 2], [6, 22, 0], color=0)
c_shield = make_cube("shield", [7.8, 10.5, -4.5], [8.8, 23.5, 4.5], [6, 16, 0], color=5)
c_shield_boss = make_cube("shield_boss", [8.8, 15.0, -1.5], [9.4, 19.0, 1.5], [6, 16, 0], color=8)

# 5. Legs
c_r_leg = make_cube("right_leg", [-4, 0, -2], [0, 12, 2], [-2, 12, 0], color=7)
c_l_leg = make_cube("left_leg", [0, 0, -2], [4, 12, 2], [2, 12, 0], color=7)

elements = [
    c_head, c_crest, c_visor,
    c_torso, c_breastplate,
    c_r_arm, c_sword_handle, c_sword_pommel, c_sword_guard, c_sword_blade,
    c_l_arm, c_shield, c_shield_boss,
    c_r_leg, c_l_leg
]

# Bone Hierarchy
bone_sword = {
    "name": "sword",
    "uuid": uid(),
    "origin": [-6, 12.5, 0],
    "children": [c_sword_handle["uuid"], c_sword_pommel["uuid"], c_sword_guard["uuid"], c_sword_blade["uuid"]]
}

bone_shield = {
    "name": "shield",
    "uuid": uid(),
    "origin": [6, 16, 0],
    "children": [c_shield["uuid"], c_shield_boss["uuid"]]
}

bone_head = {
    "name": "head",
    "uuid": uid(),
    "origin": [0, 24, 0],
    "children": [c_head["uuid"], c_crest["uuid"], c_visor["uuid"]]
}

bone_r_arm = {
    "name": "right_arm",
    "uuid": uid(),
    "origin": [-6, 22, 0],
    "children": [c_r_arm["uuid"], bone_sword]
}

bone_l_arm = {
    "name": "left_arm",
    "uuid": uid(),
    "origin": [6, 22, 0],
    "children": [c_l_arm["uuid"], bone_shield]
}

bone_torso = {
    "name": "torso",
    "uuid": uid(),
    "origin": [0, 12, 0],
    "children": [c_torso["uuid"], c_breastplate["uuid"], bone_head, bone_r_arm, bone_l_arm]
}

bone_r_leg = {
    "name": "right_leg",
    "uuid": uid(),
    "origin": [-2, 12, 0],
    "children": [c_r_leg["uuid"]]
}

bone_l_leg = {
    "name": "left_leg",
    "uuid": uid(),
    "origin": [2, 12, 0],
    "children": [c_l_leg["uuid"]]
}

outliner = [
    {
        "name": "root",
        "uuid": uid(),
        "origin": [0, 0, 0],
        "children": [bone_torso, bone_r_leg, bone_l_leg]
    }
]

def kf(time, x, y, z):
    return {
        "channel": "rotation",
        "time": time,
        "interpolation": "linear",
        "data_points": [{"x": str(x), "y": str(y), "z": str(z)}]
    }

def kf_pos(time, x, y, z):
    return {
        "channel": "position",
        "time": time,
        "interpolation": "linear",
        "data_points": [{"x": str(x), "y": str(y), "z": str(z)}]
    }

# 1. IDLE: Ready combat posture
anim_idle = {
    "name": "idle",
    "uuid": uid(),
    "loop": "loop",
    "length": 1.2,
    "animators": {
        bone_torso["uuid"]: {
            "name": "torso",
            "type": "bone",
            "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.6, 0, -0.5, 0), kf_pos(1.2, 0, 0, 0)],
            "rotation": [kf(0.0, 5, 0, 0), kf(0.6, 7, 0, 0), kf(1.2, 5, 0, 0)]
        },
        bone_head["uuid"]: {
            "name": "head",
            "type": "bone",
            "rotation": [kf(0.0, -5, 0, 0), kf(0.6, -7, 0, 0), kf(1.2, -5, 0, 0)]
        },
        bone_r_arm["uuid"]: {
            "name": "right_arm",
            "type": "bone",
            "rotation": [kf(0.0, -10, -5, 5), kf(0.6, -8, -5, 7), kf(1.2, -10, -5, 5)]
        },
        bone_sword["uuid"]: {
            "name": "sword",
            "type": "bone",
            "rotation": [kf(0.0, -15, 0, 0), kf(0.6, -15, 0, 0), kf(1.2, -15, 0, 0)]
        },
        bone_l_arm["uuid"]: {
            "name": "left_arm",
            "type": "bone",
            "rotation": [kf(0.0, -10, 5, -5), kf(0.6, -12, 7, -7), kf(1.2, -10, 5, -5)]
        }
    }
}

# 2. WALK: Stride
anim_walk = {
    "name": "walk",
    "uuid": uid(),
    "loop": "loop",
    "length": 0.8,
    "animators": {
        bone_r_leg["uuid"]: {
            "name": "right_leg",
            "type": "bone",
            "rotation": [kf(0.0, -30, 0, 0), kf(0.4, 30, 0, 0), kf(0.8, -30, 0, 0)]
        },
        bone_l_leg["uuid"]: {
            "name": "left_leg",
            "type": "bone",
            "rotation": [kf(0.0, 30, 0, 0), kf(0.4, -30, 0, 0), kf(0.8, 30, 0, 0)]
        },
        bone_r_arm["uuid"]: {
            "name": "right_arm",
            "type": "bone",
            "rotation": [kf(0.0, 30, 0, 5), kf(0.4, -30, 0, 5), kf(0.8, 30, 0, 5)]
        },
        bone_sword["uuid"]: {
            "name": "sword",
            "type": "bone",
            "rotation": [kf(0.0, -15, 0, 0), kf(0.4, -15, 0, 0), kf(0.8, -15, 0, 0)]
        },
        bone_l_arm["uuid"]: {
            "name": "left_arm",
            "type": "bone",
            "rotation": [kf(0.0, -30, 5, -5), kf(0.4, 30, 5, -5), kf(0.8, -30, 5, -5)]
        },
        bone_torso["uuid"]: {
            "name": "torso",
            "type": "bone",
            "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.2, 0, 0.5, 0), kf_pos(0.4, 0, 0, 0), kf_pos(0.6, 0, 0.5, 0), kf_pos(0.8, 0, 0, 0)],
            "rotation": [kf(0.0, 5, -5, 0), kf(0.4, 5, 5, 0), kf(0.8, 5, -5, 0)]
        }
    }
}

# 3. ATTACK: Reworked Wide Cleave Slash
anim_attack = {
    "name": "attack",
    "uuid": uid(),
    "loop": "once",
    "length": 0.50,
    "animators": {
        bone_r_arm["uuid"]: {
            "name": "right_arm",
            "type": "bone",
            "rotation": [
                kf(0.00, -10, -5, 5),
                kf(0.12, -135, 10, -20),  # Cock arm way back and up
                kf(0.25, 45, 45, -20),    # Cleave forward and down
                kf(0.38, 20, 20, -10),
                kf(0.50, -10, -5, 5)
            ]
        },
        bone_sword["uuid"]: {
            "name": "sword",
            "type": "bone",
            "rotation": [
                kf(0.00, -15, 0, 0),
                kf(0.12, 10, 0, 0),
                kf(0.25, -45, 0, 0),      # Tilt sword down during swing
                kf(0.38, -15, 0, 0),
                kf(0.50, -15, 0, 0)
            ]
        },
        bone_torso["uuid"]: {
            "name": "torso",
            "type": "bone",
            "position": [
                kf_pos(0.00, 0, 0, 0),
                kf_pos(0.12, 0, -0.4, -0.5),
                kf_pos(0.25, 0, -0.8, 1.8),
                kf_pos(0.38, 0, -0.4, 0.8),
                kf_pos(0.50, 0, 0, 0)
            ],
            "rotation": [
                kf(0.00, 5, 0, 0),
                kf(0.12, -2, -30, 0),
                kf(0.25, 15, 25, -5),
                kf(0.38, 8, 15, 0),
                kf(0.50, 5, 0, 0)
            ]
        },
        bone_l_arm["uuid"]: {
            "name": "left_arm",
            "type": "bone",
            "rotation": [
                kf(0.00, -10, 5, -5),
                kf(0.12, 10, 10, -20),
                kf(0.25, -20, 0, -10),
                kf(0.50, -10, 5, -5)
            ]
        }
    }
}

# 4. BLOCK: Reworked Frontal Shield Wall
anim_block = {
    "name": "block",
    "uuid": uid(),
    "loop": "hold",
    "length": 0.35,
    "animators": {
        bone_l_arm["uuid"]: {
            "name": "left_arm",
            "type": "bone",
            "position": [
                kf_pos(0.00, 0, 0, 0),
                kf_pos(0.18, 0, 1.0, 2.0), 
                kf_pos(0.35, 0, 1.5, 3.0)  
            ],
            "rotation": [
                kf(0.00, -10, 5, -5),
                kf(0.18, -40, 45, 15),       # Pitch up (-X), Swing inward (+Y)
                kf(0.35, -60, 60, 25)        
            ]
        },
        bone_shield["uuid"]: {
            "name": "shield",
            "type": "bone",
            "rotation": [
                kf(0.00, 0, 0, 0),
                kf(0.35, 0, 0, 0)            # No need to rotate locally!
            ]
        },
        bone_torso["uuid"]: {
            "name": "torso",
            "type": "bone",
            "position": [
                kf_pos(0.00, 0, 0, 0),
                kf_pos(0.18, 0, -0.8, -0.4),
                kf_pos(0.35, 0, -1.2, -0.6)
            ],
            "rotation": [
                kf(0.00, 5, 0, 0),
                kf(0.18, 12, -10, 0),
                kf(0.35, 15, -15, 0)
            ]
        },
        bone_r_arm["uuid"]: {
            "name": "right_arm",
            "type": "bone",
            "rotation": [
                kf(0.00, -10, -5, 5),
                kf(0.18, 5, -10, 10),
                kf(0.35, 15, -15, 15)
            ]
        },
        bone_head["uuid"]: {
            "name": "head",
            "type": "bone",
            "rotation": [
                kf(0.00, -5, 0, 0),
                kf(0.18, -8, 8, 0),
                kf(0.35, -10, 12, 0)
            ]
        }
    }
}

bbmodel = {
    "meta": {
        "format_version": "4.5",
        "model_format": "free",
        "box_uv": False
    },
    "name": "hero_warrior",
    "resolution": {"width": 64, "height": 64},
    "elements": elements,
    "outliner": outliner,
    "textures": [],
    "animations": [anim_idle, anim_walk, anim_attack, anim_block]
}

with open("d:/Repository/game/assets/models/sources/hero_warrior.bbmodel", "w", encoding="utf-8") as f:
    json.dump(bbmodel, f, indent=2)

print("hero_warrior.bbmodel updated with correct sword direction and shield block!")
