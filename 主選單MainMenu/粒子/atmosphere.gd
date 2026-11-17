extends Node2D

# ==================================================
# 主選單環境特效系統
# 負責櫻花飄落、微光粒子與環境氛圍
# 不修改原始背景圖片，也不影響 UI 操作
# ==================================================

@export_group("櫻花粒子設定")

## 遠景櫻花數量
@export_range(0, 100) var far_petal_count: int = 24

## 近景櫻花數量
@export_range(0, 100) var near_petal_count: int = 12

## 櫻花整體飄動速度
@export_range(0.1, 2.0, 0.05) var petal_speed: float = 1.0


@export_group("微光粒子設定")

## 森林微光數量
@export_range(0, 100) var light_count: int = 24

## 微光整體移動速度
@export_range(0.1, 2.0, 0.05) var light_speed: float = 1.0


# ==================================================
# 1. 初始化環境特效
# ==================================================

func _ready() -> void:

	# 建立櫻花材質
	var petal_texture := _create_petal_texture()

	if petal_texture != null:
		if far_petal_count > 0:
			_create_petal_layer(petal_texture, false)

		if near_petal_count > 0:
			_create_petal_layer(petal_texture, true)

	# 建立森林微光
	if light_count > 0:
		var light_texture := _create_light_texture()

		if light_texture != null:
			_create_light_layer(light_texture)


# ==================================================
# 2. 共用粒子產生器
# ==================================================

func _create_emitter(
	node_name: String,
	particle_texture: Texture2D,
	particle_count: int,
	particle_lifetime: float,
	origin: Vector2,
	extents: Vector2
) -> CPUParticles2D:

	var particles := CPUParticles2D.new()

	particles.name = node_name
	particles.texture = particle_texture

	# 粒子數量及生命週期
	particles.amount = particle_count
	particles.lifetime = particle_lifetime

	# 預先模擬粒子
	# 避免玩家剛進入主選單時畫面沒有粒子
	particles.preprocess = particle_lifetime

	# 讓粒子跟隨 Design 節點的解析度縮放
	particles.local_coords = true

	# 使用平滑材質過濾
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	# 設定矩形生成範圍
	particles.position = origin
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = extents

	# 持續且分散地生成粒子
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.emitting = true

	return particles


# ==================================================
# 3. 櫻花飄落效果
# ==================================================

func _create_petal_layer(
	petal_texture: Texture2D,
	is_near: bool
) -> void:

	var count: int = near_petal_count if is_near else far_petal_count
	var lifetime: float = 14.0 if is_near else 18.0
	var layer_name: String = "NearPetals" if is_near else "FarPetals"

	var particles := _create_emitter(
		layer_name,
		petal_texture,
		count,
		lifetime,
		Vector2(760, 220),
		Vector2(860, 320)
	)

	# 模擬風向，使花瓣往右下方飄落
	particles.direction = Vector2(0.7, 1.0).normalized()
	particles.spread = 35.0

	# 近景花瓣較快、遠景花瓣較慢
	particles.initial_velocity_min = 22.0 if is_near else 10.0
	particles.initial_velocity_max = 48.0 if is_near else 26.0

	# 輕微重力與風力
	particles.gravity = Vector2(0.8, 1.3)

	# 隨機生成角度
	particles.angle_min = -180.0
	particles.angle_max = 180.0

	# 飄落過程中自然旋轉
	particles.angular_velocity_min = -30.0
	particles.angular_velocity_max = 30.0

	# 利用花瓣大小營造遠近層次
	particles.scale_amount_min = 0.38 if is_near else 0.18
	particles.scale_amount_max = 0.68 if is_near else 0.36

	particles.speed_scale = petal_speed

	# 讓粒子自然淡入、淡出
	var opacity: float = 0.88 if is_near else 0.48
	particles.color_ramp = _create_fade_gradient(opacity)

	add_child(particles)


# ==================================================
# 4. 森林微光效果
# ==================================================

func _create_light_layer(light_texture: Texture2D) -> void:

	var particles := _create_emitter(
		"FloatingLights",
		light_texture,
		light_count,
		16.0,
		Vector2(800, 450),
		Vector2(760, 395)
	)

	# 光點緩慢向上浮動
	particles.direction = Vector2.UP
	particles.spread = 65.0

	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 13.0

	# 微光不受到重力影響
	particles.gravity = Vector2.ZERO

	# 隨機大小
	particles.scale_amount_min = 0.16
	particles.scale_amount_max = 0.40

	particles.speed_scale = light_speed

	# 柔和淡入淡出
	particles.color_ramp = _create_fade_gradient(0.60)

	add_child(particles)


# ==================================================
# 5. 粒子透明度漸層
# ==================================================

func _create_fade_gradient(opacity: float) -> Gradient:

	var gradient := Gradient.new()

	# 出生時完全透明
	gradient.set_color(0, Color(1, 1, 1, 0))

	# 生命週期結束時完全透明
	gradient.set_color(1, Color(1, 1, 1, 0))

	# 淡入、維持亮度、淡出
	gradient.add_point(0.13, Color(1, 1, 1, opacity))
	gradient.add_point(0.78, Color(1, 1, 1, opacity))

	return gradient


# ==================================================
# 6. 程式生成櫻花材質
# 不需要額外 PNG 圖片
# ==================================================

func _create_petal_texture() -> Texture2D:

	var svg := """
	<svg xmlns="http://www.w3.org/2000/svg"
		width="48" height="48" viewBox="0 0 48 48">

		<defs>
			<linearGradient id="petal" x1="0" y1="1" x2="1" y2="0">
				<stop offset="0%" stop-color="#CA82B0"/>
				<stop offset="55%" stop-color="#F2BAD8"/>
				<stop offset="100%" stop-color="#FFF0F8"/>
			</linearGradient>
		</defs>

		<path
			d="M 7 36 C 4 21 16 5 36 6
			L 34 12 L 40 9
			C 43 24 25 41 7 36 Z"
			fill="url(#petal)"
		/>

		<path
			d="M 8 35 Q 22 25 35 11"
			stroke="#FFF0F8"
			stroke-width="0.8"
			stroke-opacity="0.55"
			fill="none"
		/>

	</svg>
	"""

	return _svg_to_texture(svg)


# ==================================================
# 7. 程式生成柔光材質
# ==================================================

func _create_light_texture() -> Texture2D:

	var svg := """
	<svg xmlns="http://www.w3.org/2000/svg"
		width="32" height="32" viewBox="0 0 32 32">

		<defs>
			<radialGradient id="glow">
				<stop offset="0%" stop-color="#FFFFFF" stop-opacity="1"/>
				<stop offset="25%" stop-color="#FFE0F5" stop-opacity="0.9"/>
				<stop offset="60%" stop-color="#D5BFFF" stop-opacity="0.3"/>
				<stop offset="100%" stop-color="#D5BFFF" stop-opacity="0"/>
			</radialGradient>
		</defs>

		<circle cx="16" cy="16" r="16" fill="url(#glow)"/>

	</svg>
	"""

	return _svg_to_texture(svg)


# ==================================================
# 8. SVG 轉換為 Godot Texture2D
# ==================================================

func _svg_to_texture(svg: String) -> Texture2D:

	var image := Image.new()
	var result := image.load_svg_from_string(svg, 1.0)

	# 避免材質生成失敗時造成遊戲中斷
	if result != OK:
		push_warning("主選單：環境粒子材質生成失敗")
		return null

	return ImageTexture.create_from_image(image)
