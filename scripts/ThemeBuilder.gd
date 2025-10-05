extends Node
class_name ThemeBuilder

# ---------- Palette ----------
const BG_DARK        := "#000017"   # window background (top)
const BG_DARK_2      := "#000017"   # window background (bottom)
const SURFACE        := "#141C2A"   # panels/cards
const BORDER         := "#263145"   # dividers/borders
const TEXT_PRIMARY   := "#7EE6F2"   # main text (soft white-blue)
const TEXT_SECONDARY := "#55AEBD"

# Calmer primary (teal) — less contrast-y than the neon version
const PRI_N          := "#B32B9C"
const PRI_H          := "#BD33AA"
const PRI_P          := "#9A2485"

# Softer accents
const SUCCESS_N      := "#59B36B"
const SUCCESS_H      := "#62C279"
const SUCCESS_P      := "#4EA460"
const DANGER_N       := "#D05C63"
const DANGER_H       := "#DA6A70"
const DANGER_P       := "#BF545A"

const FOCUS_RING     := "#7AA2F7"

# ---------- Utilities ----------
static func _c(hex: String, a: float = 1.0) -> Color:
	if not hex.begins_with("#"):
		hex = "#" + hex
	var c := Color(hex)
	c.a = a
	return c

static func _mk_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _c(SURFACE)
	sb.border_color = _c(BORDER)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_right = 12
	sb.corner_radius_bottom_left = 12
	return sb

static func _mk_btn(col: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _c(col)
	sb.border_color = _c(col)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	return sb

static func _mk_btn_disabled(from_col: String) -> StyleBoxFlat:
	var sb := _mk_btn(from_col)
	var bg := sb.bg_color; bg.a = 0.55; sb.bg_color = bg
	var bc := sb.border_color; bc.a = 0.55; sb.border_color = bc
	return sb

static func _mk_input(normal: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _c(SURFACE)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	sb.corner_radius_bottom_left = 10
	sb.expand_margin_left = 6
	sb.expand_margin_right = 6
	sb.expand_margin_top = 6
	sb.expand_margin_bottom = 6
	if normal:
		sb.border_color = _c(BORDER)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
	else:
		sb.border_color = _c(FOCUS_RING)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
	return sb

static func _mk_bar(col: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _c(col)
	return sb

# ---------- Theme ----------
static func build_theme() -> Theme:
	var t := Theme.new()

	# Typography / colors
	t.set_color("font_color", "Label", _c(TEXT_PRIMARY))
	t.set_font_size("font_size", "Label", 16)
	t.set_font_size("font_size", "Button", 16)
	t.set_font_size("font_size", "LineEdit", 16)
	t.set_font_size("font_size", "SpinBox", 16)
	t.set_font_size("font_size", "OptionButton", 16)

	# Panels
	var PANEL := _mk_panel()
	t.set_stylebox("panel", "Panel", PANEL)
	t.set_stylebox("panel", "PanelContainer", PANEL)

	# Buttons (muted primary)
	var BTN_N := _mk_btn(PRI_N)
	var BTN_H := _mk_btn(PRI_H)
	var BTN_P := _mk_btn(PRI_P)
	var BTN_D := _mk_btn_disabled(PRI_N)

	t.set_stylebox("normal",  "Button", BTN_N)
	t.set_stylebox("hover",   "Button", BTN_H)
	t.set_stylebox("pressed", "Button", BTN_P)
	t.set_stylebox("disabled","Button", BTN_D)
	# Softer text on primary (not pure black, not pure white)
	t.set_color("font_color", "Button", _c("#F1F6F9"))  # readable but not stark

	# Inputs (LineEdit + applied box for SpinBox/OptionButton)
	var IN_N := _mk_input(true)
	var IN_F := _mk_input(false)
	t.set_stylebox("normal", "LineEdit", IN_N)
	t.set_stylebox("focus",  "LineEdit", IN_F)
	t.set_color("font_color", "LineEdit", _c(TEXT_PRIMARY))

	t.set_stylebox("normal", "SpinBox", IN_N)
	t.set_stylebox("focus",  "SpinBox", IN_F)
	t.set_stylebox("normal", "OptionButton", IN_N)
	t.set_stylebox("focus",  "OptionButton", IN_F)
	t.set_color("font_color", "SpinBox", _c(TEXT_PRIMARY))
	t.set_color("font_color", "OptionButton", _c(TEXT_PRIMARY))

	# ProgressBar (track + fill)
	var PB_BG := _mk_bar(BORDER)
	var PB_FG := _mk_bar(PRI_N)
	t.set_stylebox("background", "ProgressBar", PB_BG)
	t.set_stylebox("fill",       "ProgressBar", PB_FG)

	return t

# ---------- Background (adds a full-window gradient) ----------
#static func _make_gradient_texture() -> GradientTexture2D:
	#var grad := Gradient.new()
	#grad.remove_point(0) # ensure clean
	#grad.add_point(0.0, _c(BG_DARK))
	#grad.add_point(1.0, _c(BG_DARK_2))
#
	#var g := GradientTexture2D.new()
	#g.gradient = grad
	#g.width = 2048
	#g.height = 2048
	#g.fill = GradientTexture2D.FILL_LINEAR
	#g.fill_from = Vector2(0.0, 0.0)
	#g.fill_to = Vector2(0.0, 1.0) # vertical
	#return g
#
#static func ensure_background(root: Control) -> void:
	#if not is_instance_valid(root):
		#return
	#var existing := root.get_node_or_null("___BG")
	#if existing:
		#return
	#var tex := _make_gradient_texture()
	#var bg := TextureRect.new()
	#bg.name = "___BG"
	#bg.texture = tex
	#bg.stretch_mode = TextureRect.STRETCH_SCALE
	#bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	#bg.z_index = -1024
	#bg.anchor_left = 0.0
	#bg.anchor_top = 0.0
	#bg.anchor_right = 1.0
	#bg.anchor_bottom = 1.0
	#bg.offset_left = 0
	#bg.offset_top = 0
	#bg.offset_right = 0
	#bg.offset_bottom = 0
	## Insert as first child so everything else draws above
	#root.add_child(bg)
	#bg.move_to_front() # ensures it's at end of child list; with z_index negative it stays behind

static func apply(root_control: Control, add_background: bool = true) -> void:
	#if add_background:
		#ensure_background(root_control)
	root_control.theme = build_theme()

# ---------- Optional helpers for risk/success overrides ----------
static func make_danger_button() -> Dictionary:
	return {
		"normal":  _mk_btn(DANGER_N),
		"hover":   _mk_btn(DANGER_H),
		"pressed": _mk_btn(DANGER_P)
	}

static func make_success_button() -> Dictionary:
	return {
		"normal":  _mk_btn(SUCCESS_N),
		"hover":   _mk_btn(SUCCESS_H),
		"pressed": _mk_btn(SUCCESS_P)
	}
