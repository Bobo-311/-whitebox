
extends Button

# ============================================================
# 《眠境 RE:RECOLOR》共用選單按鈕動畫 V3
#
# 功能：
# 1. 滑鼠懸停時文字漸變粉色
# 2. 文字平滑放大
# 3. 左右 Hover Skin 淡入、向文字靠近
# 4. 左右裝飾使用固定寬度
# 5. 不因文字長短自動縮小裝飾
# 6. 不改變按鈕本身的點擊範圍
# 7. 支援鍵盤及控制器焦點操作
# 8. 保留 Inspector 設定的字型
# 9. 支援全域預設圖片與個別覆蓋圖片
#
# 適用：
# - 主選單
# - 設定頁
# - 音量設定頁
# - 按鍵設定頁
# - 夢境紀錄返回按鈕
# - 共用確認視窗
# ============================================================


# ============================================================
# 1. 共用預設 Hover Skin
#
# 所有未指定 Custom Decoration 的按鈕，
# 都會自動使用這張圖片。
#
# 只要更換此路徑，就能更新共用 Skin。
# ============================================================

const DEFAULT_DECORATION: Texture2D = preload(
	"res://主選單MainMenu/素材/01_silver_starlight_hover_left.png"
)


# ============================================================
# 2. Inspector：懸停動畫
# ============================================================

@export_group("懸停動畫設定")

## 動畫持續時間
@export_range(0.01, 1.0, 0.01)
var hover_duration: float = 0.22

## 文字在懸停時的放大倍率
@export_range(1.0, 1.3, 0.01)
var hover_scale: float = 1.05


# ============================================================
# 3. Inspector：Hover 裝飾
# ============================================================

@export_group("花藤裝飾設定")

## 是否使用左右裝飾
@export var show_decoration: bool = true

## 單側裝飾的固定顯示寬度
##
## 此數值不再受文字長短或按鈕寬度限制。
## 因此應避免將並排按鈕的尺寸設得過大。
@export_range(20.0, 240.0, 1.0)
var decoration_width: float = 150.0

## 裝飾與文字之間的距離
@export_range(0.0, 40.0, 1.0)
var decoration_gap: float = 14.0

## 自訂 Hover 裝飾
##
## 留空：使用 DEFAULT_DECORATION
## 指定圖片：只覆蓋此按鈕
@export var custom_decoration: Texture2D


# ============================================================
# 4. Inspector：文字陰影
# ============================================================

@export_group("文字陰影設定")

## 柔和陰影透明度
@export_range(0.0, 1.0, 0.01)
var shadow_opacity: float = 0.4


# ============================================================
# 5. 內部節點
# ============================================================

var _caption: Label

var _left_decoration: TextureRect
var _right_decoration: TextureRect


# ============================================================
# 6. 內部動畫資料
# ============================================================

var _normal_color: Color
var _hover_color: Color

## 目前動畫進度：0.0～1.0
var _highlight: float = 0.0

## 目標動畫進度
var _target: float = 0.0

## 滑鼠是否在按鈕範圍內
var _mouse_inside: bool = false

## 是否以鍵盤或控制器操作
var _keyboard_mode: bool = false

## Hover Tween
var _hover_tween: Tween


# ============================================================
# 7. 初始化
# ============================================================

func _ready() -> void:

	# 先取得 Inspector 指定的文字顏色
	# 必須在清除原生文字前取得
	_normal_color = get_theme_color("font_color")
	_hover_color = get_theme_color("font_hover_color")

	# 建立自訂文字顯示節點
	_create_caption()

	# 設定無框按鈕樣式
	_setup_button_style()

	# 建立左右裝飾
	_create_decorations()

	# 滑鼠操作
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# 鍵盤焦點操作
	focus_entered.connect(_refresh_highlight)
	focus_exited.connect(_refresh_highlight)

	# 按鈕尺寸改變時重新計算位置
	resized.connect(_update_visual_layout)

	# 初始為一般狀態
	_apply_highlight(0.0)


# ============================================================
# 8. 建立文字顯示節點
#
# 使用 Label 顯示原本 Button 的文字，
# 才能獨立控制文字顏色與縮放。
# ============================================================

func _create_caption() -> void:

	_caption = Label.new()
	_caption.name = "AnimatedCaption"

	# 保留原本按鈕文字
	_caption.text = text

	# 保留 Inspector 原本設定的字型
	_caption.add_theme_font_override(
		"font",
		get_theme_font("font")
	)

	# 保留原本字體大小
	_caption.add_theme_font_size_override(
		"font_size",
		get_theme_font_size("font_size")
	)

	# 文字水平及垂直置中
	_caption.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	_caption.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	# 不攔截滑鼠
	_caption.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	# 柔和紫黑色陰影
	_caption.add_theme_color_override(
		"font_shadow_color",
		Color(
			0.08,
			0.04,
			0.15,
			shadow_opacity
		)
	)

	_caption.add_theme_constant_override(
		"shadow_offset_x",
		1
	)

	_caption.add_theme_constant_override(
		"shadow_offset_y",
		2
	)

	add_child(_caption)

	# 文字顯示區域與按鈕一致
	_caption.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	# 當文字節點尺寸變動時更新排版
	_caption.resized.connect(
		_update_visual_layout
	)


# ============================================================
# 9. 設定按鈕外觀
# ============================================================

func _setup_button_style() -> void:

	# 移除按鈕預設底框
	flat = true

	# 保留鍵盤操作功能
	focus_mode = Control.FOCUS_ALL

	# 不裁切超出按鈕範圍的裝飾
	#
	# 這是固定尺寸 Hover Skin 的重要設定。
	# 但不會擴大按鈕實際點擊範圍。
	clip_contents = false

	var empty_style := StyleBoxEmpty.new()

	for style_name in [
		"normal",
		"hover",
		"pressed",
		"hover_pressed",
		"disabled",
		"focus"
	]:

		add_theme_stylebox_override(
			style_name,
			empty_style
		)

	# 隱藏原生 Button 文字
	# 文字由 AnimatedCaption 負責顯示
	for color_name in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_hover_pressed_color",
		"font_focus_color",
		"font_disabled_color",
		"font_outline_color"
	]:

		add_theme_color_override(
			color_name,
			Color.TRANSPARENT
		)


# ============================================================
# 10. 建立左右 Hover 裝飾
# ============================================================

func _create_decorations() -> void:

	if not show_decoration:
		return

	# 優先使用個別指定的圖片
	# 未指定時使用共用預設圖片
	var decoration_texture: Texture2D = (
		custom_decoration
		if custom_decoration != null
		else DEFAULT_DECORATION
	)

	if decoration_texture == null:

		push_warning(
			"【共用按鈕】找不到 Hover 裝飾圖片"
		)

		return

	# 左側使用原圖
	_left_decoration = _create_decoration_node(
		"LeftFlourish",
		decoration_texture,
		false
	)

	# 右側使用水平鏡像
	_right_decoration = _create_decoration_node(
		"RightFlourish",
		decoration_texture,
		true
	)


# ============================================================
# 11. 建立單側裝飾節點
# ============================================================

func _create_decoration_node(
	node_name: String,
	decoration_texture: Texture2D,
	mirrored: bool
) -> TextureRect:

	var decoration := TextureRect.new()

	decoration.name = node_name
	decoration.texture = decoration_texture

	# 忽略原圖尺寸，由程式指定顯示尺寸
	decoration.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)

	# 保留原圖比例
	decoration.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)

	# 左右鏡像
	decoration.flip_h = mirrored

	# 線性過濾，避免裝飾邊緣粗糙
	decoration.texture_filter = (
		CanvasItem.TEXTURE_FILTER_LINEAR
	)

	# 不干擾滑鼠點擊
	decoration.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	# 初始完全透明
	decoration.modulate.a = 0.0

	add_child(decoration)

	return decoration


# ============================================================
# 12. 滑鼠移入
# ============================================================

func _on_mouse_entered() -> void:

	_mouse_inside = true

	_keyboard_mode = false

	_refresh_highlight()


# ============================================================
# 13. 滑鼠移出
# ============================================================

func _on_mouse_exited() -> void:

	_mouse_inside = false

	_refresh_highlight()


# ============================================================
# 14. 滑鼠／鍵盤操作模式
# ============================================================

func _input(event: InputEvent) -> void:

	# 滑鼠移動或點擊：
	# 切換回滑鼠操作模式
	if (
		event is InputEventMouseMotion
		or event is InputEventMouseButton
	):

		if _keyboard_mode:

			_keyboard_mode = false

			_refresh_highlight()

		return

	# 鍵盤及控制器操作
	if (
		event is InputEventKey
		or event is InputEventJoypadButton
		or event is InputEventJoypadMotion
	):

		if (
			event.is_action_pressed("ui_up")
			or event.is_action_pressed("ui_down")
			or event.is_action_pressed("ui_left")
			or event.is_action_pressed("ui_right")
			or event.is_action_pressed("ui_focus_next")
			or event.is_action_pressed("ui_focus_prev")
			or event.is_action_pressed("ui_accept")
		):

			_keyboard_mode = true

			_refresh_highlight()


# ============================================================
# 15. 更新選取狀態
# ============================================================

func _refresh_highlight() -> void:

	# 滑鼠模式：
	# 由滑鼠是否在按鈕內決定
	var active: bool = _mouse_inside

	# 鍵盤模式：
	# 由按鈕是否具有焦點決定
	if _keyboard_mode:

		active = has_focus()

	# 停用按鈕不顯示 Hover
	if disabled:

		active = false

	var target: float = (
		1.0 if active else 0.0
	)

	_play_hover_animation(target)


# ============================================================
# 16. 播放 Hover 動畫
# ============================================================

func _play_hover_animation(
	target: float
) -> void:

	# 目標相同時不重複播放
	if is_equal_approx(_target, target):
		return

	_target = target

	# 中斷之前的 Tween
	if (
		_hover_tween
		and _hover_tween.is_valid()
	):

		_hover_tween.kill()

	_hover_tween = create_tween()

	_hover_tween.set_trans(
		Tween.TRANS_QUAD
	)

	_hover_tween.set_ease(
		Tween.EASE_OUT
	)

	_hover_tween.tween_method(
		_apply_highlight,
		_highlight,
		target,
		hover_duration
	)


# ============================================================
# 17. 套用動畫進度
# ============================================================

func _apply_highlight(
	value: float
) -> void:

	_highlight = value

	if not is_instance_valid(_caption):
		return

	# 文字顏色漸變
	var current_color: Color = (
		_normal_color.lerp(
			_hover_color,
			value
		)
	)

	_caption.add_theme_color_override(
		"font_color",
		current_color
	)

	# 文字平滑放大
	var current_scale: float = lerpf(
		1.0,
		hover_scale,
		value
	)

	_caption.scale = (
		Vector2.ONE * current_scale
	)

	# 更新左右裝飾
	_update_visual_layout()


# ============================================================
# 18. 更新文字與裝飾排版
#
# V3 核心修正：
#
# 左右裝飾使用固定的 decoration_width，
# 不再根據文字長度或 Button 寬度縮小。
#
# 裝飾仍會跟著文字置中位置移動，
# 不會改變按鈕實際的點擊範圍。
# ============================================================

func _update_visual_layout() -> void:

	if not is_instance_valid(_caption):
		return

	# --------------------------------------------------------
	# A. 設定文字縮放中心
	# --------------------------------------------------------

	_caption.pivot_offset = (
		_caption.size * 0.5
	)

	# 沒有裝飾時只處理文字
	if not is_instance_valid(_left_decoration):
		return

	if not is_instance_valid(_right_decoration):
		return

	# --------------------------------------------------------
	# B. 計算文字實際顯示寬度
	# --------------------------------------------------------

	var text_width: float = (
		_caption.get_minimum_size().x
		* _caption.scale.x
	)

	# --------------------------------------------------------
	# C. 計算裝飾與文字的間距
	#
	# 一般狀態比較遠，
	# Hover 時逐漸向文字靠近。
	# --------------------------------------------------------

	var current_gap: float = lerpf(
		decoration_gap + 14.0,
		decoration_gap,
		_highlight
	)

	# --------------------------------------------------------
	# D. 固定裝飾寬度
	#
	# 【重要】
	# 不使用舊版 available_width。
	#
	# 不因「返回」或「恢復預設」
	# 的文字長度不同而改變圖片大小。
	# --------------------------------------------------------

	var final_width: float = (
		decoration_width
	)

	# --------------------------------------------------------
	# E. 保留圖片的原始長寬比例
	# --------------------------------------------------------

	var texture_size: Vector2 = (
		_left_decoration.texture.get_size()
	)

	var final_height: float = (
		final_width
		* texture_size.y
		/ maxf(texture_size.x, 1.0)
	)

	var decoration_size := Vector2(
		final_width,
		final_height
	)

	_left_decoration.size = (
		decoration_size
	)

	_right_decoration.size = (
		decoration_size
	)

	# --------------------------------------------------------
	# F. 計算按鈕中心
	# --------------------------------------------------------

	var center: Vector2 = size * 0.5

	# --------------------------------------------------------
	# G. 左側裝飾位置
	# --------------------------------------------------------

	_left_decoration.position = Vector2(
		center.x
		- text_width * 0.5
		- current_gap
		- final_width,

		center.y
		- final_height * 0.5
	)

	# --------------------------------------------------------
	# H. 右側裝飾位置
	# --------------------------------------------------------

	_right_decoration.position = Vector2(
		center.x
		+ text_width * 0.5
		+ current_gap,

		center.y
		- final_height * 0.5
	)

	# --------------------------------------------------------
	# I. 動畫透明度
	# --------------------------------------------------------

	var opacity: float = (
		_highlight
		if show_decoration
		else 0.0
	)

	_left_decoration.modulate.a = (
		opacity
	)

	_right_decoration.modulate.a = (
		opacity
	)


# ============================================================
# 19. 主動啟用鍵盤選取效果
#
# 提供其他 UI 控制器呼叫。
# ============================================================

func activate_keyboard_highlight() -> void:

	_keyboard_mode = true

	_refresh_highlight()
