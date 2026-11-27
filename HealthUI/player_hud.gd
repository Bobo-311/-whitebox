extends CanvasLayer

@onready var margin_container: MarginContainer = get_node_or_null("MarginContainer")
@onready var health_bar: ProgressBar = get_node_or_null("MarginContainer/HBoxContainer/VBoxContainer/HealthContainer/HealthBar")
@onready var damage_bar: ProgressBar = get_node_or_null("MarginContainer/HBoxContainer/VBoxContainer/HealthContainer/DamageBar")
@onready var ink_bar = get_node_or_null("MarginContainer/HBoxContainer/VBoxContainer/InkBar")
@onready var top_bar: ColorRect = get_node_or_null("CinematicBars/TopBar")
@onready var bottom_bar: ColorRect = get_node_or_null("CinematicBars/BottomBar")
@onready var quick_slot_ui: Control = get_node_or_null("QuickSlotUI")
@onready var gold_canvas_layer: CanvasLayer = get_node_or_null("GoldCanvasLayer")

var hp_pixel_ratio: float = 3.0
var original_hud_pos: Vector2
var damage_tween: Tween
var hp_heal_tween: Tween
var cinema_tween: Tween
var is_closing_early: bool = false

# 沿用 main：預設不顯示黑邊。需要黑邊的場景可在 Inspector 設為 120。
@export var bar_height: float = 0.0

# 找不到 Dialogic 對話版面時，供 HUD 黑邊使用的備用圖層。
@export var cinematic_layer: int = 2
var fallback_layer: CanvasLayer
var dialogue_bars: Control

func _ready():
	if margin_container:
		original_hud_pos = margin_container.position
	_ensure_cinematic_bars()
	get_tree().node_added.connect(_on_dialogue_node_added)
	for textbox in get_tree().root.find_children("VN_TextboxLayer", "Control", true, false):
		_on_dialogue_node_added(textbox)
	if not Dialogic.timeline_started.is_connected(_on_dialogic_started):
		Dialogic.timeline_started.connect(_on_dialogic_started)
	if not Dialogic.timeline_ended.is_connected(_on_dialogic_ended):
		Dialogic.timeline_ended.connect(_on_dialogic_ended)
	if not Dialogic.signal_event.is_connected(_on_dialogic_signal_ui):
		Dialogic.signal_event.connect(_on_dialogic_signal_ui)

func _ensure_cinematic_bars() -> void:
	var holder := get_node_or_null("CinematicBars") as Control
	if holder:
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var front := CanvasLayer.new()
	front.name = "CinematicBarsFront"
	fallback_layer = front
	front.layer = cinematic_layer
	if custom_viewport:
		front.custom_viewport = custom_viewport
	add_child(front)
	top_bar = _place_bar(top_bar, front, "TopBar", Control.PRESET_TOP_WIDE)
	bottom_bar = _place_bar(bottom_bar, front, "BottomBar", Control.PRESET_BOTTOM_WIDE)
	top_bar.item_rect_changed.connect(_refresh_dialogue_bars)
	bottom_bar.item_rect_changed.connect(_refresh_dialogue_bars)

func _refresh_dialogue_bars() -> void:
	if is_instance_valid(dialogue_bars):
		dialogue_bars.queue_redraw()

func _place_bar(bar: ColorRect, front: CanvasLayer, bar_name: String, preset: Control.LayoutPreset) -> ColorRect:
	if bar == null:
		bar = ColorRect.new()
		bar.name = bar_name
		front.add_child(bar)
	else:
		bar.reparent(front, false)
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_and_offsets_preset(preset)
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	bar.offset_bottom = 0.0
	return bar

# Dialogic 可在開始劇情或切換 style 時才建立版面。
func _on_dialogue_node_added(node: Node) -> void:
	if node.name == &"VN_TextboxLayer" and node is Control:
		_attach_dialogue_bars.call_deferred(weakref(node))

func _attach_dialogue_bars(reference: WeakRef) -> void:
	var textbox := reference.get_ref() as Control
	if not is_instance_valid(textbox) or not textbox.is_inside_tree():
		return
	var layout := textbox.get_parent() as CanvasLayer
	if layout == null or textbox.get_viewport() != top_bar.get_viewport():
		return
	if not layout.has_node("VN_PortraitLayer"):
		return
	if is_instance_valid(dialogue_bars):
		if dialogue_bars.get_parent() == layout:
			return
		dialogue_bars.hide()
		dialogue_bars.queue_free()
	var bars := Control.new()
	bars.name = "HUDLetterbox"
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.z_index = textbox.z_index
	layout.add_child(bars)
	layout.move_child(bars, textbox.get_index())
	bars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue_bars = bars
	bars.draw.connect(_draw_dialogue_bars.bind(bars))
	bars.tree_exiting.connect(_on_bars_exiting.bind(bars), CONNECT_ONE_SHOT)
	# 原黑邊的 Tween 驅動高度，畫面只顯示一組黑邊。
	fallback_layer.hide()
	bars.queue_redraw()

func _draw_dialogue_bars(bars: Control) -> void:
	var upper := top_bar.offset_bottom
	var lower := -bottom_bar.offset_top
	bars.draw_rect(Rect2(0, 0, bars.size.x, upper), Color.BLACK)
	bars.draw_rect(Rect2(0, bars.size.y - lower, bars.size.x, lower), Color.BLACK)

func _on_bars_exiting(bars: Control) -> void:
	if dialogue_bars == bars:
		dialogue_bars = null
		if is_instance_valid(fallback_layer):
			fallback_layer.show()

func _exit_tree() -> void:
	if is_instance_valid(dialogue_bars):
		dialogue_bars.hide()
		dialogue_bars.queue_free()

func update_hp(new_hp: int, max_hp: int):
	if not health_bar:
		return
	health_bar.max_value = max_hp
	health_bar.custom_minimum_size.x = max_hp * hp_pixel_ratio
	if damage_bar:
		damage_bar.max_value = max_hp
		damage_bar.custom_minimum_size.x = max_hp * hp_pixel_ratio

	if new_hp < health_bar.value:
		health_bar.value = new_hp
		health_bar.modulate = Color.WHITE
		shake_ui()
		if damage_bar:
			if damage_tween and damage_tween.is_running():
				damage_tween.kill()
			damage_tween = get_tree().create_tween()
			damage_tween.tween_interval(0.4)
			damage_tween.tween_property(damage_bar, "value", new_hp, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	elif new_hp > health_bar.value:
		if hp_heal_tween and hp_heal_tween.is_running():
			hp_heal_tween.kill()
		hp_heal_tween = create_tween().set_parallel(true)
		hp_heal_tween.tween_property(health_bar, "value", new_hp, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if damage_bar:
			hp_heal_tween.tween_property(damage_bar, "value", new_hp, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		health_bar.modulate = Color(2.0, 2.0, 2.0, 1.0)
		hp_heal_tween.tween_property(health_bar, "modulate", Color.WHITE, 0.3)

func shake_ui():
	if not margin_container:
		return
	var shake_tween = get_tree().create_tween()
	for i in range(4):
		var rand_x = randf_range(-6.0, 6.0)
		var rand_y = randf_range(-6.0, 6.0)
		shake_tween.tween_property(margin_container, "position", original_hud_pos + Vector2(rand_x, rand_y), 0.04)
	shake_tween.tween_property(margin_container, "position", original_hud_pos, 0.04)

func update_ink(current_ink: float, max_ink: float) -> void:
	if ink_bar and ink_bar.has_method("update_ink"):
		ink_bar.update_ink(current_ink, max_ink)

func set_ink_mode(mode_id: int) -> void:
	if ink_bar and ink_bar.has_method("set_mode"):
		ink_bar.set_mode(mode_id)

func update_ammo(current_ammo: int, max_ammo: int) -> void:
	if ink_bar and ink_bar.has_method("update_ink"):
		ink_bar.update_ink(current_ammo * 10.0, max_ammo * 10.0)

func preview_ink(preview_val: float) -> void:
	if ink_bar and ink_bar.has_method("preview_ink"):
		ink_bar.preview_ink(preview_val)

func confirm_ink_drop(final_val: float) -> void:
	if ink_bar and ink_bar.has_method("confirm_ink_drop"):
		ink_bar.confirm_ink_drop(final_val)

func _on_dialogic_started():
	is_closing_early = false
	print("【系統】對話開始，開啟電影黑邊")
	_animate_cinema(true, 0.5, Tween.EASE_OUT)

func _on_dialogic_signal_ui(argument: String):
	if argument == "fade_out_cinematic":
		is_closing_early = true
		print("【系統】收到提早退場暗號，同步收起電影黑邊與恢復 UI")
		_animate_cinema(false, 0.4, Tween.EASE_IN_OUT)

func _on_dialogic_ended():
	if is_closing_early:
		is_closing_early = false
		return
	print("【系統】對話結束，關閉電影黑邊")
	_animate_cinema(false, 0.5, Tween.EASE_IN_OUT)

func _animate_cinema(open: bool, duration: float, ease_type: Tween.EaseType) -> void:
	if cinema_tween and cinema_tween.is_running():
		cinema_tween.kill()
	cinema_tween = create_tween().set_parallel(true).set_ease(ease_type).set_trans(Tween.TRANS_CUBIC)
	var hud_alpha := 0.0 if open else 1.0
	var height := bar_height if open else 0.0
	if margin_container:
		cinema_tween.tween_property(margin_container, "modulate:a", hud_alpha, duration)
	if quick_slot_ui:
		cinema_tween.tween_property(quick_slot_ui, "modulate:a", hud_alpha, duration)
	if gold_canvas_layer:
		gold_canvas_layer.visible = not open
	cinema_tween.tween_property(top_bar, "offset_bottom", height, duration)
	cinema_tween.tween_property(bottom_bar, "offset_top", -height, duration)
