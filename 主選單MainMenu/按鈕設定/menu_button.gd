extends Button

# ==========================================
# 《眠境 RE:COLOR》主選單按鈕動畫 V2
#
# 功能：
# 1. 滑鼠懸停漸變粉色
# 2. 文字平滑放大
# 3. 花藤裝飾向內浮現
# 4. 柔和文字陰影
# 5. 支援鍵盤焦點操作
# 6. 保留 Inspector 原本設定的字型
# ==========================================


@export_group("懸停動畫設定")

## 動畫時間
@export_range(0.01, 1.0) var hover_duration: float = 0.22

## 文字放大倍率
@export_range(1.0, 1.3) var hover_scale: float = 1.05


@export_group("花藤裝飾設定")

## 是否顯示左右花藤
@export var show_decoration: bool = true

## 單側花藤寬度
@export_range(30.0, 120.0) var decoration_width: float = 88.0

## 花藤與文字之間的距離
@export_range(0.0, 40.0) var decoration_gap: float = 14.0

## 可選填自訂裝飾圖片
## 留空時使用程式自動生成的花藤
@export var custom_decoration: Texture2D


@export_group("文字陰影設定")

## 陰影透明度，降低數值會更柔和
@export_range(0.0, 1.0) var shadow_opacity: float = 0.4


# ==========================================
# 內部變數
# ==========================================

var _caption: Label

var _left_decoration: TextureRect
var _right_decoration: TextureRect

var _normal_color: Color
var _hover_color: Color

var _highlight: float = 0.0
var _target: float = 0.0

var _mouse_inside: bool = false
var _keyboard_mode: bool = false

var _hover_tween: Tween

# 共用裝飾貼圖
# 四個按鈕不需要各自重複生成相同圖片
static var _shared_decoration: Texture2D


# ==========================================
# 初始化按鈕
# ==========================================

func _ready() -> void:

	# 保留 Inspector 的原始文字顏色
	_normal_color = get_theme_color("font_color")
	_hover_color = get_theme_color("font_hover_color")

	# 建立文字顯示節點
	_create_caption()

	# 移除原生按鈕底框
	_setup_button_style()

	# 建立左右花藤裝飾
	_create_decorations()

	# 自動連接滑鼠事件
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# 自動連接鍵盤焦點事件
	focus_entered.connect(_refresh_highlight)
	focus_exited.connect(_refresh_highlight)

	# 按鈕尺寸改變時更新裝飾位置
	resized.connect(_update_visual_layout)

	# 初始化顯示狀態
	_apply_highlight(0.0)


# ==========================================
# 建立文字顯示節點
# ==========================================

func _create_caption() -> void:

	_caption = Label.new()
	_caption.name = "AnimatedCaption"

	# 保留按鈕原本的文字內容
	_caption.text = text

	# 保留 Inspector 設定的字型與大小
	_caption.add_theme_font_override(
		"font",
		get_theme_font("font")
	)

	_caption.add_theme_font_size_override(
		"font_size",
		get_theme_font_size("font_size")
	)

	# 水平與垂直置中
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 避免文字攔截滑鼠事件
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 柔和的紫黑色陰影
	# 取代原本較厚重的黑色陰影
	_caption.add_theme_color_override(
		"font_shadow_color",
		Color(0.08, 0.04, 0.15, shadow_opacity)
	)

	_caption.add_theme_constant_override(
		"shadow_offset_x", 1
	)

	_caption.add_theme_constant_override(
		"shadow_offset_y", 2
	)

	add_child(_caption)

	_caption.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	_caption.resized.connect(_update_visual_layout)


# ==========================================
# 移除原生 Button 的預設外框
# ==========================================

func _setup_button_style() -> void:

	flat = true

	focus_mode = Control.FOCUS_ALL

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

	# 原生 Button 保留操作功能
	# 實際文字由 AnimatedCaption 顯示
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


# ==========================================
# 建立左右花藤
# ==========================================

func _create_decorations() -> void:

	if not show_decoration:
		return

	var decoration_texture: Texture2D = custom_decoration

	# 沒有自訂圖片時使用共用 SVG 貼圖
	if decoration_texture == null:

		if _shared_decoration == null:
			_shared_decoration = _generate_decoration()

		decoration_texture = _shared_decoration

	if decoration_texture == null:
		return

	# 左側裝飾
	_left_decoration = _create_decoration_node(
		"LeftFlourish",
		decoration_texture,
		false
	)

	# 右側使用相同圖片水平翻轉
	_right_decoration = _create_decoration_node(
		"RightFlourish",
		decoration_texture,
		true
	)


# ==========================================
# 建立單個裝飾 TextureRect
# ==========================================

func _create_decoration_node(
	node_name: String,
	decoration_texture: Texture2D,
	mirrored: bool
) -> TextureRect:

	var decoration := TextureRect.new()

	decoration.name = node_name

	decoration.texture = decoration_texture

	decoration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	decoration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# 右側裝飾進行鏡像
	decoration.flip_h = mirrored

	# 使用線性過濾，讓花藤線條更加細緻
	decoration.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	# 裝飾不得影響滑鼠操作
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 一般狀態下完全透明
	decoration.modulate.a = 0.0

	add_child(decoration)

	return decoration


# ==========================================
# 生成夢境花藤 SVG 貼圖
#
# 由曲線、葉片、星光組成
# 不需要使用外部圖片素材
# ==========================================

func _generate_decoration() -> Texture2D:

	var svg := """
	<svg xmlns="http://www.w3.org/2000/svg"
		width="96" height="40"
		viewBox="0 0 96 40">

		<defs>

			<linearGradient id="vine"
				x1="0" y1="0" x2="1" y2="0">

				<stop offset="0%"
					stop-color="#B49ACF"
					stop-opacity="0.25"/>

				<stop offset="55%"
					stop-color="#DDA9DE"/>

				<stop offset="100%"
					stop-color="#FFE3F4"/>

			</linearGradient>

		</defs>


		<!-- 柔和光暈 -->

		<path
			d="M3 20 C18 20 24 9 38 14
			   C51 19 59 28 76 20"
			fill="none"
			stroke="#D9A0DC"
			stroke-width="5"
			stroke-opacity="0.14"
			stroke-linecap="round"/>


		<!-- 花藤主線條 -->

		<path
			d="M3 20 C18 20 24 9 38 14
			   C51 19 59 28 76 20"
			fill="none"
			stroke="url(#vine)"
			stroke-width="1.5"
			stroke-linecap="round"/>


		<!-- 延伸的細小分枝 -->

		<path
			d="M24 15 Q20 7 12 7
			   M45 17 Q47 8 55 5
			   M57 23 Q61 32 72 32"
			fill="none"
			stroke="#E9C1E8"
			stroke-width="0.8"
			stroke-opacity="0.85"
			stroke-linecap="round"/>


		<!-- 左側花葉 -->

		<path
			d="M24 15 C12 17 9 9 12 7
			   C20 7 24 10 24 15 Z"
			fill="#DAB8E8"
			fill-opacity="0.85"/>


		<!-- 上方花葉 -->

		<path
			d="M45 17 C39 9 49 3 55 5
			   C56 12 50 15 45 17 Z"
			fill="#F2C3E1"/>


		<!-- 下方花葉 -->

		<path
			d="M57 23 C71 21 76 28 72 32
			   C65 34 59 28 57 23 Z"
			fill="#D9ADD8"/>


		<!-- 花葉的小型高光 -->

		<path
			d="M15 10 L23 14
			   M46 15 L52 7
			   M60 25 L70 30"
			stroke="#FFF0FA"
			stroke-width="0.7"
			stroke-opacity="0.65"
			fill="none"/>


		<!-- 星光外圈 -->

		<path
			d="M71 20 Q82 18 83 6
			   Q85 18 95 20
			   Q85 22 83 34
			   Q81 22 71 20 Z"
			fill="#E5B1E4"
			fill-opacity="0.17"/>


		<!-- 精緻四角星光 -->

		<path
			d="M74 20 Q82 19 83 10
			   Q84 19 93 20
			   Q84 21 83 30
			   Q82 21 74 20 Z"
			fill="#FFE7F5"/>


		<!-- 星光核心 -->

		<circle cx="83" cy="20"
			r="1.7"
			fill="#FFFFFF"/>


		<!-- 夢境微小光點 -->

		<circle cx="16" cy="24"
			r="1.2"
			fill="#D8B1E5"
			fill-opacity="0.7"/>

		<circle cx="66" cy="10"
			r="1.3"
			fill="#F5D8F2"
			fill-opacity="0.85"/>

	</svg>
	"""

	var image := Image.new()

	# 使用兩倍解析度生成清晰貼圖
	var result := image.load_svg_from_string(
		svg,
		2.0
	)

	if result != OK:

		push_warning("【主選單】花藤貼圖生成失敗")

		return null

	return ImageTexture.create_from_image(image)


# ==========================================
# 滑鼠移入
# ==========================================

func _on_mouse_entered() -> void:

	_mouse_inside = true
	_keyboard_mode = false

	_refresh_highlight()


# ==========================================
# 滑鼠移出
# ==========================================

func _on_mouse_exited() -> void:

	_mouse_inside = false

	_refresh_highlight()


# ==========================================
# 滑鼠與鍵盤操作模式切換
# ==========================================

func _input(event: InputEvent) -> void:

	if event is InputEventMouseMotion or event is InputEventMouseButton:

		if _keyboard_mode:

			_keyboard_mode = false
			_refresh_highlight()

	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:

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


# ==========================================
# 判斷選取狀態
# ==========================================

func _refresh_highlight() -> void:

	var active: bool = _mouse_inside

	if _keyboard_mode:

		active = has_focus()

	if disabled:

		active = false

	var target: float = 1.0 if active else 0.0

	_play_hover_animation(target)


# ==========================================
# 播放懸停動畫
# ==========================================

func _play_hover_animation(target: float) -> void:

	# 避免重複播放相同動畫
	if is_equal_approx(_target, target):
		return

	_target = target

	# 停止上一個動畫
	# 避免快速切換按鈕時產生衝突
	if _hover_tween and _hover_tween.is_valid():

		_hover_tween.kill()

	_hover_tween = create_tween()

	_hover_tween.set_trans(Tween.TRANS_QUAD)
	_hover_tween.set_ease(Tween.EASE_OUT)

	_hover_tween.tween_method(
		_apply_highlight,
		_highlight,
		target,
		hover_duration
	)


# ==========================================
# 更新文字及裝飾動畫
# ==========================================

func _apply_highlight(value: float) -> void:

	_highlight = value

	if not is_instance_valid(_caption):
		return

	# 文字由白色漸變成櫻花粉色
	var current_color: Color = _normal_color.lerp(
		_hover_color,
		value
	)

	_caption.add_theme_color_override(
		"font_color",
		current_color
	)

	# 文字從中心平滑放大
	var current_scale: float = lerpf(
		1.0,
		hover_scale,
		value
	)

	_caption.scale = Vector2.ONE * current_scale

	# 更新花藤位置、大小與透明度
	_update_visual_layout()


# ==========================================
# 更新畫面排版
# ==========================================

func _update_visual_layout() -> void:

	if not is_instance_valid(_caption):
		return

	# 文字縮放中心
	_caption.pivot_offset = _caption.size * 0.5

	if not is_instance_valid(_left_decoration):
		return

	if not is_instance_valid(_right_decoration):
		return

	# 取得目前文字的實際寬度
	var text_width: float = (
		_caption.get_minimum_size().x
		* _caption.scale.x
	)

	# 裝飾由外側向文字靠近
	var current_gap: float = lerpf(
		decoration_gap + 14.0,
		decoration_gap,
		_highlight
	)

	# 計算單側剩餘空間
	# 避免花藤覆蓋文字或超出按鈕
	var available_width: float = maxf(
		size.x * 0.5
		- text_width * 0.5
		- current_gap
		- 4.0,
		0.0
	)

	var final_width: float = minf(
		decoration_width,
		available_width
	)

	# 保持圖片比例
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

	_left_decoration.size = decoration_size
	_right_decoration.size = decoration_size

	var center: Vector2 = size * 0.5

	# 左側花藤位置
	_left_decoration.position = Vector2(
		center.x - text_width * 0.5
		- current_gap - final_width,

		center.y - final_height * 0.5
	)

	# 右側花藤位置
	_right_decoration.position = Vector2(
		center.x + text_width * 0.5
		+ current_gap,

		center.y - final_height * 0.5
	)

	# 隨著懸停動畫平滑淡入淡出
	var opacity: float = (
		_highlight
		if show_decoration
		else 0.0
	)

	_left_decoration.modulate.a = opacity
	_right_decoration.modulate.a = opacity

# ==========================================
# 主動啟用鍵盤選取效果
# ==========================================

func activate_keyboard_highlight() -> void:

	_keyboard_mode = true

	_refresh_highlight()
