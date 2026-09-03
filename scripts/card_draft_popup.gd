extends Control

signal card_selected(card_id: String)

var player: Node = null
var current_options: Array[Dictionary] = []

const CARD_POOL: Array[Dictionary] = [
	{
		"id": "SHARP_EDGE",
		"icon": "⚔️",
		"title": "Острый клинок",
		"desc": "+25% урона мечом и тяжелым взмахом",
		"color": Color(1.0, 0.5, 0.1)
	},
	{
		"id": "VITALITY_STONE",
		"icon": "🛡️",
		"title": "Камень стойкости",
		"desc": "+50 к максимальному HP и лечение на 40 HP",
		"color": Color(0.2, 0.95, 0.35)
	},
	{
		"id": "WINDSTRIDER",
		"icon": "⚡",
		"title": "Поступь ветра",
		"desc": "+20% к скорости бега и -35% кулдауна рывка",
		"color": Color(0.2, 0.85, 1.0)
	},
	{
		"id": "HEAVY_MASONRY",
		"icon": "🏰",
		"title": "Укрепленная кладка",
		"desc": "+150 HP всем существующим и будущим постройкам",
		"color": Color(0.95, 0.75, 0.2)
	},
	{
		"id": "TOWER_BALLISTICS",
		"icon": "🏹",
		"title": "Баллистика вышек",
		"desc": "Луковые вышки стреляют на 35% быстрее и на 3м дальше",
		"color": Color(0.85, 0.35, 1.0)
	},
	{
		"id": "GREED_HARVESTER",
		"icon": "🪵",
		"title": "Жадный добытчик",
		"desc": "Удвоенный сбор ресурсов со всех деревьев и жил (x2)",
		"color": Color(1.0, 0.85, 0.25)
	},
	{
		"id": "VAMPIRIC_STRIKE",
		"icon": "🩸",
		"title": "Вампиризм",
		"desc": "Каждый удар по врагу восстанавливает +4 HP",
		"color": Color(1.0, 0.2, 0.35)
	}
]

@onready var title_label: Label = $CenterContainer/Panel/VBox/TitleLabel
@onready var cards_container: HBoxContainer = $CenterContainer/Panel/VBox/CardsContainer

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_1 and current_options.size() >= 1:
			pick_card(0)
		elif event.keycode == KEY_2 and current_options.size() >= 2:
			pick_card(1)
		elif event.keycode == KEY_3 and current_options.size() >= 3:
			pick_card(2)

func open_draft(p_player: Node, new_level: int) -> void:
	player = p_player
	visible = true
	Engine.time_scale = 0.05 # Dramatic slow-motion

	title_label.text = "★ НОВЫЙ УРОВЕНЬ %d! ВЫБЕРИТЕ УЛУЧШЕНИЕ ★" % new_level

	# Pick 3 random unique cards
	var shuffled: Array = CARD_POOL.duplicate()
	shuffled.shuffle()
	current_options = [shuffled[0], shuffled[1], shuffled[2]]

	# Populate card panels
	for i in range(3):
		var card_data: Dictionary = current_options[i]
		var card_panel: PanelContainer = cards_container.get_child(i) as PanelContainer
		var btn: Button = card_panel.get_node("VBox/BtnSelect") as Button
		var icon_lbl: Label = card_panel.get_node("VBox/IconLabel") as Label
		var name_lbl: Label = card_panel.get_node("VBox/NameLabel") as Label
		var desc_lbl: Label = card_panel.get_node("VBox/DescLabel") as Label
		var key_lbl: Label = card_panel.get_node("VBox/KeyHint") as Label

		icon_lbl.text = card_data.icon
		name_lbl.text = card_data.title
		name_lbl.modulate = card_data.color
		desc_lbl.text = card_data.desc
		key_lbl.text = "Клавиша [%d]" % (i + 1)

		if btn.pressed.is_connected(_on_btn_pressed):
			btn.pressed.disconnect(_on_btn_pressed)
		btn.pressed.connect(_on_btn_pressed.bind(i))

func _on_btn_pressed(index: int) -> void:
	pick_card(index)

func pick_card(index: int) -> void:
	if index < 0 or index >= current_options.size():
		return

	var chosen: Dictionary = current_options[index]
	if player and is_instance_valid(player) and player.has_method("apply_card_upgrade"):
		player.apply_card_upgrade(chosen.id)

	emit_signal("card_selected", chosen.id)
	Engine.time_scale = 1.0
	visible = false
