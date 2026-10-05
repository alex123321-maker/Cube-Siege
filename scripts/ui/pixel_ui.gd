class_name PixelUI
extends RefCounted
## Reuses the selected pixel catalogue with immutable bitmap sources.
## The Godot importer controls runtime resolution; AtlasTextures trim source padding.

const TEXTURE_DIRECTORY: String = "res://assets/ui/pixel_catalogue/textures/"
const ALIASES: Dictionary[String, String] = {
	"ui_tooltip_panel_frame": "ui_action_slot_normal",
	"synergy_carnage": "synergy_slaughter",
	"warrior_dismemberment": "warrior_corpse_dismemberment",
	"warrior_triumph": "warrior_loud_triumph",
	"warrior_sword": "warrior_sword_attack",
	"warrior_dash": "warrior_combat_dash",
	"archer_eagle_eye": "archer_sniper_eye",
	"archer_roll": "archer_acrobat_roll",
	"engineer_hammer": "engineer_hammer_strike",
}

static var _textures: Dictionary[String, Texture2D] = {}


static func path(key: String) -> String:
	var canonical: String = ALIASES.get(key, key)
	return TEXTURE_DIRECTORY + canonical + ".tres"


static func texture(key: String) -> Texture2D:
	var resource_path: String = path(key)
	if _textures.has(resource_path):
		return _textures[resource_path]
	var result: Texture2D = load(resource_path) as Texture2D
	if result == null:
		push_error("PixelUI: missing texture '%s' (%s)" % [key, resource_path])
		return null
	_textures[resource_path] = result
	return result


## Content padding order is left, top, right, bottom, in logical UI pixels.
## Each call returns an independent StyleBox so callers may adjust colors or margins.
static func panel(key: String, padding: Vector4 = Vector4(12.0, 10.0, 12.0, 10.0)) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = texture(key)
	var margins: Vector4 = _slice_margins(ALIASES.get(key, key))
	style.set_texture_margin(SIDE_LEFT, margins.x)
	style.set_texture_margin(SIDE_TOP, margins.y)
	style.set_texture_margin(SIDE_RIGHT, margins.z)
	style.set_texture_margin(SIDE_BOTTOM, margins.w)
	style.content_margin_left = padding.x
	style.content_margin_top = padding.y
	style.content_margin_right = padding.z
	style.content_margin_bottom = padding.w
	return style


static func _slice_margins(key: String) -> Vector4:
	match key:
		"ui_health_bar_full", "ui_health_bar_danger", "ui_xp_bar_fill", "ui_wave_bar_fill", "ui_tooltip_divider":
			return Vector4.ZERO
		"ui_health_bar_bg":
			return Vector4(6.0, 2.0, 6.0, 2.0)
		"ui_xp_bar_bg":
			return Vector4(4.0, 1.0, 4.0, 1.0)
		"ui_wave_bar_bg":
			return Vector4(8.0, 2.0, 8.0, 2.0)
		"ui_keycap_frame_normal", "ui_keycap_frame_pressed":
			return Vector4(6.0, 5.0, 6.0, 5.0)
		"ui_resource_portrait_cell":
			return Vector4(14.0, 14.0, 10.0, 14.0)
		"ui_resource_counter_cell":
			return Vector4(8.0, 10.0, 8.0, 10.0)
		"ui_tooltip_panel":
			# Preserve its decorative header divider inside the fixed top slice.
			return Vector4(25.0, 57.0, 25.0, 25.0)
		"ui_day_night_panel":
			return Vector4(8.0, 7.0, 8.0, 7.0)
		_:
			return Vector4(16.0, 16.0, 16.0, 16.0)
