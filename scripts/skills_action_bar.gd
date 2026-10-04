extends HBoxContainer

const CLASS_ACTIONS: Dictionary = {
    0: [
        ["warrior_sword_attack", "МЕЧ", "Базовая атака мечом"],
        ["warrior_cleave", "РАССЕЧЬ", "Рассечение перед собой"],
        ["warrior_dash", "РЫВОК", "Боевой рывок"],
        ["warrior_parry", "ПАРИРОВАТЬ", "Парирование щитом"],
        ["warrior_duel", "ДУЭЛЬ", "Вызвать цель на дуэль"],
    ],
    1: [
        ["archer_shot", "СТРЕЛА", "Базовый выстрел"],
        ["archer_piercing_shot", "ПРОБОЙ", "Пробивающий выстрел"],
        ["archer_roll", "КУВЫРОК", "Уклонение кувырком"],
        ["archer_decoy", "ПРИМАНКА", "Создать приманку"],
        ["archer_eagle_eye", "ОРЛ. ГЛАЗ", "F — Eagle Eye"],
    ],
    2: [
        ["engineer_hammer", "МОЛОТ", "Удар инженерным молотом"],
        ["engineer_turret", "ТУРЕЛЬ", "Развернуть турель"],
        ["engineer_dash", "РЫВОК", "Реактивный рывок"],
        ["engineer_mine", "ПОСТАВИТЬ", "Q — установить дистанционную мину"],
        ["engineer_tactical_nuke", "ЯДЕРНЫЙ", "F — Tactical Nuke"],
    ],
}
const ICON_TEXTURES: Dictionary = {
    "warrior_sword_attack": preload("res://assets/ui/hud_visual_kit/icons/warrior_sword_attack.png"),
    "warrior_cleave": preload("res://assets/ui/hud_visual_kit/icons/warrior_cleave.png"),
    "warrior_dash": preload("res://assets/ui/hud_visual_kit/icons/warrior_dash.png"),
    "warrior_parry": preload("res://assets/ui/hud_visual_kit/icons/warrior_parry.png"),
    "warrior_duel": preload("res://assets/ui/hud_visual_kit/icons/warrior_duel.png"),
    "archer_shot": preload("res://assets/ui/hud_visual_kit/icons/archer_shot.png"),
    "archer_piercing_shot": preload("res://assets/ui/hud_visual_kit/icons/archer_piercing_shot.png"),
    "archer_roll": preload("res://assets/ui/hud_visual_kit/icons/archer_roll.png"),
    "archer_decoy": preload("res://assets/ui/hud_visual_kit/icons/archer_decoy.png"),
    "archer_eagle_eye": preload("res://assets/ui/hud_visual_kit/icons/archer_eagle_eye.png"),
    "engineer_hammer": preload("res://assets/ui/hud_visual_kit/icons/engineer_hammer.png"),
    "engineer_turret": preload("res://assets/ui/hud_visual_kit/icons/engineer_turret.png"),
    "engineer_dash": preload("res://assets/ui/hud_visual_kit/icons/engineer_dash.png"),
    "engineer_mine": preload("res://assets/ui/hud_visual_kit/icons/engineer_mine.png"),
    "engineer_tactical_nuke": preload("res://assets/ui/hud_visual_kit/icons/engineer_tactical_nuke.png"),
    "global_build": preload("res://assets/ui/hud_visual_kit/icons/global_build.png"),
}
const ACTION_KEYS: Array[String] = ["ЛКМ", "ПКМ", "SPACE", "Q", "F"]
const ACTION_SLOTS: Array[String] = ["SlotLMB", "SlotRMB", "SlotSpace", "SlotQ", "SlotF"]

var player: PlayerPrototype
var action_slots: Array[HUDActionSlot] = []
var build_slot: HUDActionSlot
var event_bus: Node
var _active_class_id: int = -1
var _mine_state_initialized: bool = false
var _mine_is_active: bool = false
var _tooltip_refresh_remaining: float = 0.0

func _ready() -> void:
    for slot_name: String in ACTION_SLOTS:
        action_slots.append(get_node(slot_name) as HUDActionSlot)
    build_slot = get_node("SlotTab") as HUDActionSlot
    build_slot.set_action(ICON_TEXTURES["global_build"], "СТРОИТЬ", "TAB", "Открыть режим строительства")
    event_bus = get_node_or_null("/root/EventBus")
    if event_bus and not event_bus.player_class_changed.is_connected(_on_player_class_changed):
        event_bus.player_class_changed.connect(_on_player_class_changed)
    _find_player()
    if player:
        _apply_class_actions(int(player.current_class))
    else:
        _set_actions_unavailable()

func _process(delta: float) -> void:
    if not is_instance_valid(player):
        _find_player()
        if player:
            _apply_class_actions(int(player.current_class))
    if not is_instance_valid(player):
        if _active_class_id != -1:
            _set_actions_unavailable()
        return
    _refresh_mine_action()
    _tooltip_refresh_remaining -= delta
    if _tooltip_refresh_remaining <= 0.0:
        _tooltip_refresh_remaining = 0.2
        _refresh_tooltips()
    var movement: PlayerMovement = player.movement
    var cooldowns: Array[float] = [
        player.attack_cooldown_timer,
        player.special_cooldown_timer,
        movement.dash_cooldown_timer if movement else 0.0,
        player.parry_cooldown_timer,
        player.ultimate_cooldown_timer,
    ]
    for index: int in action_slots.size():
        action_slots[index].set_cooldown(cooldowns[index])

func _find_player() -> void:
    for candidate: Node in get_tree().get_nodes_in_group("player"):
        if candidate is PlayerPrototype:
            player = candidate
            return

func _on_player_class_changed(new_class: int) -> void:
    if not is_instance_valid(player):
        _find_player()
    _apply_class_actions(new_class)

func _refresh_action_set() -> void:
    if not is_instance_valid(player):
        _set_actions_unavailable()
        return
    _apply_class_actions(int(player.current_class))

func _apply_class_actions(class_id: int) -> void:
    var actions: Array = CLASS_ACTIONS.get(class_id, [])
    if actions.is_empty():
        _set_actions_unavailable()
        return
    _active_class_id = class_id
    _mine_state_initialized = false
    for index: int in action_slots.size():
        var action: Array = actions[index]
        action_slots[index].set_action(
            ICON_TEXTURES[action[0]] as Texture2D,
            action[1],
            ACTION_KEYS[index],
            action[2]
        )
    _refresh_mine_action()
    _refresh_tooltips()

func _refresh_tooltips() -> void:
    if not is_instance_valid(player):
        return
    for index: int in action_slots.size():
        action_slots[index].tooltip_text = HUDAbilityDetails.describe(player, index)

func _refresh_mine_action() -> void:
    if not is_instance_valid(player) or _active_class_id != 2:
        return
    var mine: Node3D = player.active_remote_mine
    var has_active_mine: bool = is_instance_valid(mine) and not mine.is_queued_for_deletion()
    if _mine_state_initialized and has_active_mine == _mine_is_active:
        return
    _mine_state_initialized = true
    _mine_is_active = has_active_mine
    if has_active_mine:
        action_slots[3].set_action(
            ICON_TEXTURES["engineer_mine"],
            "ПОДОРВАТЬ",
            "Q",
            "Q — подорвать установленную мину"
        )
    else:
        action_slots[3].set_action(
            ICON_TEXTURES["engineer_mine"],
            "ПОСТАВИТЬ",
            "Q",
            "Q — установить дистанционную мину"
        )

func _set_actions_unavailable() -> void:
    _active_class_id = -1
    _mine_state_initialized = false
    for slot: HUDActionSlot in action_slots:
        slot.set_unavailable(true)

func _exit_tree() -> void:
    if is_instance_valid(event_bus) and event_bus.player_class_changed.is_connected(_on_player_class_changed):
        event_bus.player_class_changed.disconnect(_on_player_class_changed)
