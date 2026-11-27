extends BaseCharacter
class_name Player

# ============================================================
# 《眠境 RE:RECOLOR》
# Player｜正式死亡重生整合版
#
# Godot 4.5.1
# STEP 10.6.7
#
# ============================================================
# 主要職責
# ============================================================
#
# 1. 玩家移動及狀態機管理
# 2. 玩家生命值、受傷及無敵時間
# 3. 翻滾及獨立冷卻系統
# 4. 三色武器及墨水系統
# 5. 貼紙、裝備及戰鬥道具
# 6. 筆記本與購物操作
# 7. Dialogic 過場演出
# 8. 玩家動畫及方向管理
# 9. 開發者測試工具
# 10. 正式死亡重生相容性
# 11. 死亡靈魂實體還原
#
# ============================================================
# 本版本修改重點
# ============================================================
#
# A. 正式過圖與死亡重生由 SceneTransition 定位。
# B. 舊版重生座標只允許在相同地圖內使用。
# C. 死亡靈魂延後至地圖初始化完成後生成。
# D. 死亡期間禁止玩家操作筆記本及快捷鍵。
# E. 死亡時清理筆記本、購物及武器蓄力狀態。
# F. 正式死亡重生交由 RespawnManager 管理。
#
# 不直接操作正式存檔 JSON。
# 不修改既有劇情完成紀錄。
# 不改變原本武器及戰鬥平衡數值。
# ============================================================


# ============================================================
# 1. 基礎物理與攻擊數值
# ============================================================

## 正常走路速度
@export var walk_speed: int = 1201

## 翻滾衝刺速度
@export var dash_speed: float = 1500.0

## 翻滾持續時間
@export var dash_duration: float = 0.2

## 基礎近戰攻擊力
@export var basic_attack_damage: float = 20.0

## 受傷後無敵時間
@export var invincibility_duration: float = 0.6

## 是否處於無敵狀態
var is_invincible: bool = false

## 記錄角色精靈圖原始比例
var original_sprite_scale: Vector2 = Vector2.ONE

## 無裝備時的基礎最大血量
@export var base_max_hp: int = 100


# ============================================================
# 2. 翻滾冷卻系統
#
# 使用獨立 CD 取代傳統體力條。
# ============================================================

@export_group("翻滾冷卻系統")

## 翻滾冷卻時間
@export var dash_cd_time: float = 2.0

## 目前剩餘冷卻時間
var dash_cd_timer: float = 0.0

## 是否可以使用翻滾
var is_dash_ready: bool = true

## 預載翻滾冷卻完成特效
const DASH_READY_PARTICLES = preload(
	"res://DashEffect/dash_ready_particles.tscn"
)


# ============================================================
# 3. 墨水、武器及玩家動作狀態
# ============================================================

## 遠程射擊後的減速懲罰時間
var shoot_slow_timer: float = 0.0

## 是否正在播放甩魔法動畫
var is_casting: bool = false

## 玩家移動輸入向量
var input_direction: Vector2 = Vector2.ZERO

## 最後面朝方向
var facing_direction: String = "down"

## 是否正在翻滾
var is_dashing: bool = false

## 是否正在閱讀素描本
var is_reading_book: bool = false

## 素描本是否由畫架存檔點開啟
var opened_from_savepoint: bool = false

## 是否正在購物
var is_shopping: bool = false


# ============================================================
# 4. 三色武器模式
# ============================================================

enum WeaponMode {
	BLUE,
	RED,
	YELLOW
}

## 目前使用的武器模式
var current_weapon: WeaponMode = WeaponMode.BLUE

## 武器切換色印特效位置
@export var ink_switch_badge_offset := Vector2(0, -36)

## 武器切換共用特效節點
var _ink_switch_effect: InkSwitchEffect

## 最大墨水容量
var max_ink: float = 60.0

## 目前墨水容量
var current_ink: float = 60.0


# ============================================================
# 5. 節點引用
# ============================================================

@onready var state_machine: StateMachine = $StateMachine

@onready var animated_sprite_2d: AnimatedSprite2D = (
	$AnimatedSprite2D
)

@onready var player_hud: CanvasLayer = $PlayerHUD

@onready var magic_brush: Node2D = $MagicBrush

@onready var knockback_component: KnockbackComponent = (
	get_node_or_null("KnockbackComponent")
)

@onready var notebook_ui = $MenuLayer/NotebookUI


# ============================================================
# 6. 劇情與開發者拍照模式
# ============================================================

## 玩家是否正在進行 Dialogic 劇情
var is_in_dialogue: bool = false

## 劇照拍照模式開關
var _photo_mode_Active: bool = false

## 記錄拍照模式所隱藏的節點
var _photo_mode_hidden_nodes: Array[Node] = []


# ============================================================
# 7. 武器墨水消耗表
#
# 保留原本三色武器消耗設定。
# ============================================================

func get_weapon_cost() -> float:

	match current_weapon:

		WeaponMode.BLUE:

			return 10.0

		WeaponMode.RED:

			return 15.0

		WeaponMode.YELLOW:

			return 20.0

	return 10.0


## 玩家目前高度層級
## 0 = 平地
## 1 = 二樓
## 2 = 三樓
var current_elevation: int = 0


# ============================================================
# 8. 玩家生命週期初始化
#
# 初始化順序：
#
# A. 父類別生命週期
# B. 註冊玩家至 DataManager
# C. 綁定 Dialogic 及裝備訊號
# D. 重算玩家數值
# E. 相容舊版重生定位
# F. 還原重生血量
# G. 初始化 HUD
# H. 延後還原死亡靈魂
# I. 啟動狀態機
# ============================================================

func _ready():

	super._ready()

	# 保留原本團隊 GitHub 更新確認訊息。
	print("以防大家沒看到 王力口是牛")

	# --------------------------------------------------------
	# A. 記錄精靈圖原始比例
	# --------------------------------------------------------

	if animated_sprite_2d:

		original_sprite_scale = animated_sprite_2d.scale

	# --------------------------------------------------------
	# B. 註冊目前玩家實體
	# --------------------------------------------------------

	DataManager.player_node = self

	# --------------------------------------------------------
	# C. 綁定 Dialogic 過場動畫訊號
	# --------------------------------------------------------

	if not Dialogic.signal_event.is_connected(
		_on_dialogic_signal
	):

		Dialogic.signal_event.connect(
			_on_dialogic_signal
		)

	# --------------------------------------------------------
	# D. 綁定裝備變更訊號
	# --------------------------------------------------------

	if not DataManager.equipment_changed.is_connected(
		recalculate_stats
	):

		DataManager.equipment_changed.connect(
			recalculate_stats
		)

	# 初始化玩家最大血量及裝備數值。

	recalculate_stats()

	# --------------------------------------------------------
	# E. 正式死亡重生定位相容性
	#
	# SceneTransition 負責正式讀檔、一般過圖
	# 以及正式死亡重生的出生定位。
	#
	# 舊版 DataManager 重生座標只在非轉場
	# 的地圖刷新流程中使用。
	#
	# 必須確認玩家確實位於存檔地圖，
	# 防止將其他地圖的畫架座標套用至本地圖。
	# --------------------------------------------------------

	_restore_legacy_spawn_position()

	# --------------------------------------------------------
	# F. 還原存檔點重生血量
	# --------------------------------------------------------

	if DataManager and DataManager.saved_hp > 0:

		current_hp = min(
			DataManager.saved_hp,
			max_hp
		)

	# --------------------------------------------------------
	# G. 初始化玩家 HUD
	# --------------------------------------------------------

	if player_hud:

		player_hud.update_hp(
			current_hp,
			max_hp
		)

		if player_hud.has_method("set_ink_mode"):

			player_hud.set_ink_mode(
				current_weapon
			)

			player_hud.update_ink(
				current_ink,
				max_ink
			)

	update_hp_bar()

	# --------------------------------------------------------
	# H. 延後還原死亡靈魂
	#
	# 不在地圖尚未初始化完成時，
	# 直接使用 current_scene 生成靈魂。
	# --------------------------------------------------------

	call_deferred("_restore_death_soul")

	# --------------------------------------------------------
	# I. 啟動玩家狀態機
	# --------------------------------------------------------

	if state_machine:

		state_machine.init(self)

	# --------------------------------------------------------
	# J. 執行防呆動畫檢查
	# --------------------------------------------------------

	_run_bug_radar(
		get_tree().root
	)


# ============================================================
# 9. 舊版運行時重生座標相容性
#
# 保留原本 SaveMenuUI 的地圖刷新方式，
# 以及 F6 開發模式的死亡重生。
#
# 正式 SceneTransition 轉場期間，
# 不允許舊版座標覆蓋正式定位點。
#
# 使用玩家的父節點向上搜尋所屬地圖，
# 避免 _ready() 時 current_scene 尚未更新。
# ============================================================

func _restore_legacy_spawn_position() -> void:

	if SceneTransition.is_transitioning:

		return

	if DataManager.save_map_path.is_empty():

		return

	var map_ancestor: Node = get_parent()

	while is_instance_valid(map_ancestor):

		if (
			map_ancestor.scene_file_path
			== DataManager.save_map_path
		):

			global_position = (
				DataManager.last_save_position
			)

			return

		map_ancestor = map_ancestor.get_parent()


# ============================================================
# 10. 死亡靈魂實體還原
#
# 保留原本魂類遊戲的撿屍機制。
#
# 死亡靈魂資料由 PlayerDie 負責記錄。
# Player 負責在死亡地圖內生成靈魂實體。
#
# 只有符合死亡地圖時才生成。
# 不會將靈魂帶到其他地圖。
# ============================================================

func _restore_death_soul() -> void:

	if not DataManager.has_soul_on_ground:

		return

	# 等待地圖完成初始化。

	await get_tree().process_frame

	var current_map: Node = get_tree().current_scene

	if not is_instance_valid(current_map):

		return

	# 確認目前玩家屬於本張地圖。

	if not current_map.is_ancestor_of(self):

		return

	# 等待期間死亡靈魂狀態可能已經變更。

	if not DataManager.has_soul_on_ground:

		return

	# 確認目前地圖為死亡地圖。

	if (
		DataManager.soul_map_path
		!= current_map.scene_file_path
	):

		return

	# 避免同一張地圖重複還原本次死亡靈魂。

	if not get_tree().get_nodes_in_group(
		"restored_death_soul"
	).is_empty():

		return

	# --------------------------------------------------------
	# A. 載入原本的靈魂場景
	# --------------------------------------------------------

	var soul_scene: PackedScene = (
		load("res://soul/Soul.tscn") as PackedScene
	)

	if soul_scene == null:

		push_warning(
			"【Player】找不到死亡靈魂場景"
		)

		return

	var soul = soul_scene.instantiate()

	# --------------------------------------------------------
	# B. 還原遺失金幣及原本靈魂比例
	# --------------------------------------------------------

	soul.lost_gold = (
		DataManager.soul_stored_gold
	)

	soul.scale = Vector2(
		2.0,
		2.0
	)

	# --------------------------------------------------------
	# C. 還原死亡世界座標
	# --------------------------------------------------------

	if current_map is Node2D:

		soul.position = current_map.to_local(
			DataManager.soul_spawn_pos
		)

	else:

		soul.position = DataManager.soul_spawn_pos

	# --------------------------------------------------------
	# D. 加入目前地圖
	# --------------------------------------------------------

	soul.add_to_group("restored_death_soul")

	current_map.add_child(soul)

	print(
		"【Player】已還原死亡靈魂，金幣：",
		DataManager.soul_stored_gold
	)

	print(
		"【Player】靈魂位置：",
		DataManager.soul_spawn_pos
	)


# ============================================================
# 11. 相機邊界控制系統
# ============================================================

func update_camera_limits(
	left: int,
	top: int,
	right: int,
	bottom: int
) -> void:

	var camera = $Camera2D

	if camera:

		camera.limit_left = left

		camera.limit_top = top

		camera.limit_right = right

		camera.limit_bottom = bottom

		print(
			"【系統】相機邊界已更新：",
			left,
			", ",
			top,
			", ",
			right,
			", ",
			bottom
		)


# ============================================================
# 12. 玩家硬體輸入攔截
#
# 死亡、重生、劇情及購物期間，
# 禁止一般玩家操作。
#
# 保留原本筆記本及開發者快捷鍵。
# ============================================================

func _input(event):

	# --------------------------------------------------------
	# A. 死亡及重生操作鎖
	# --------------------------------------------------------

	if is_dead or RespawnManager.is_respawning:

		return

	# --------------------------------------------------------
	# B. 劇情與購物操作鎖
	# --------------------------------------------------------

	if is_in_dialogue:

		return

	if is_shopping:

		return

	var pressed_cancel = (
		event.is_action_pressed("TAB")
		or event.is_action_pressed("ESC")
	)

	# --------------------------------------------------------
	# C. 關閉素描本
	# --------------------------------------------------------

	if is_reading_book and pressed_cancel:

		if opened_from_savepoint:

			if notebook_ui:

				notebook_ui.hide()

				notebook_ui.is_open = false

			opened_from_savepoint = false

			var save_menus = (
				get_tree().get_nodes_in_group("save_menu")
			)

			if save_menus.size() > 0:

				save_menus[0].show()

		else:

			is_reading_book = false

			state_machine.process_mode = (
				Node.PROCESS_MODE_INHERIT
			)

			if notebook_ui:

				notebook_ui.toggle_notebook(false)

		return

	# --------------------------------------------------------
	# D. 開啟素描本
	# --------------------------------------------------------

	if (
		not is_reading_book
		and event.is_action_pressed("TAB")
	):

		is_reading_book = true

		velocity = Vector2.ZERO

		state_machine.process_mode = (
			Node.PROCESS_MODE_DISABLED
		)

		if notebook_ui:

			notebook_ui.toggle_notebook(false)

	# --------------------------------------------------------
	# E. 開發者綜合測試快捷鍵
	#
	# 保留原本 cheater 功能：
	# 印鈔、戰鬥解鎖、墨水補給、
	# 商人貨物、木屋鑰匙及藍色顏料。
	# --------------------------------------------------------

	if event.is_action_pressed("cheater") and DataManager:

		DataManager.total_gold += 100

		DataManager.combat_unlocked = true

		DataManager.mark_cutscene_completed("got_cargo")

		DataManager.mark_cutscene_completed("got_key")

		DataManager.unlock_auto_refill_item("hp_paint")

		refill_full_ink()

		if magic_brush:

			magic_brush.visible = true

		print(
			"【開發者外掛】印鈔 100 元 + 解鎖戰鬥/顏料"
			+ " + 獲得貨物(got_cargo)與鑰匙(got_key)！總金額：",
			DataManager.total_gold
		)

	# --------------------------------------------------------
	# F. 開發者獨立測試快捷鍵
	# --------------------------------------------------------

	if (
		event is InputEventKey
		and event.pressed
		and not event.is_echo()
		and DataManager
	):

		match event.keycode:

			# ================================================
			# F1｜戰鬥解鎖狀態切換
			# ================================================

			KEY_F1:

				DataManager.combat_unlocked = (
					not DataManager.combat_unlocked
				)

				refill_full_ink()

				if magic_brush:

					magic_brush.visible = (
						DataManager.can_combat()
					)

				print(
					"【開發者測試】F1 切換戰鬥狀態！目前是否可戰鬥：",
					DataManager.can_combat()
				)

			# ================================================
			# F2｜商人貨物取得狀態切換
			# ================================================

			KEY_F2:

				if DataManager.is_cutscene_completed(
					"got_cargo"
				):

					DataManager.completed_cutscenes.erase(
						"got_cargo"
					)

					print(
						"【開發者測試】F2 已移除貨物 (got_cargo = false)"
					)

				else:

					DataManager.mark_cutscene_completed(
						"got_cargo"
					)

					print(
						"【開發者測試】F2 已獲得商人貨物 (got_cargo = true)！"
					)

			# ================================================
			# F3｜小木屋鑰匙取得狀態切換
			# ================================================

			KEY_F3:

				if DataManager.is_cutscene_completed(
					"got_key"
				):

					DataManager.completed_cutscenes.erase(
						"got_key"
					)

					print(
						"【開發者測試】F3 已移除小木屋鑰匙 (got_key = false)"
					)

				else:

					DataManager.mark_cutscene_completed(
						"got_key"
					)

					print(
						"【開發者測試】F3 已獲得小木屋鑰匙 (got_key = true)！"
					)

			# ================================================
			# F4｜劇照拍照模式
			#
			# 隱藏戰鬥 UI、提示圖示及畫筆。
			# 再次按下時恢復原本可見節點。
			# ================================================

			KEY_F4:

				_photo_mode_Active = (
					not _photo_mode_Active
				)

				if _photo_mode_Active:

					_photo_mode_hidden_nodes.clear()

					if is_instance_valid(_ink_switch_effect):

						_ink_switch_effect.hide()

					for node in get_tree().root.find_children(
						"*",
						"CanvasLayer",
						true,
						false
					):

						if (
							node.visible
							and not ("Transition" in node.name)
						):

							node.visible = false

							_photo_mode_hidden_nodes.append(node)

					if magic_brush and magic_brush.visible:

						magic_brush.visible = false

						_photo_mode_hidden_nodes.append(
							magic_brush
						)

					print(
						"【劇照模式開啟】已隱藏所有戰鬥 UI！"
						+ "再按一次 F4 即可恢復。"
					)

				else:

					for node in _photo_mode_hidden_nodes:

						if is_instance_valid(node):

							node.visible = true

					_photo_mode_hidden_nodes.clear()

					print(
						"【劇照模式關閉】已恢復所有 UI 顯示！"
					)

			# ================================================
			# F5｜遊戲時間定格
			# ================================================

			KEY_F5:

				if Engine.time_scale > 0.0:

					Engine.time_scale = 0.0

					print(
						"【畫面已定格】遊戲時間停止！按 F5 恢復。"
					)

				else:

					Engine.time_scale = 1.0

					print(
						"【畫面恢復】遊戲時間繼續。"
					)

			# ================================================
			# F7｜戰鬥道具測試
			# ================================================

			KEY_F7:

				DataManager.grant_combat_items()

				print(
					"【開發者測試】獲得藍色橡皮擦、"
					+ "紅色蠟筆、黃色的尺各 1 個。"
				)

			# ================================================
			# F11｜全螢幕及視窗化切換
			# ================================================

			KEY_F11:

				var current_mode = (
					DisplayServer.window_get_mode()
				)

				if (
					current_mode
					== DisplayServer.WINDOW_MODE_FULLSCREEN

					or current_mode
					== DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
				):

					DisplayServer.window_set_mode(
						DisplayServer.WINDOW_MODE_WINDOWED
					)

					print(
						"【系統】已切換為視窗模式"
					)

				else:

					DisplayServer.window_set_mode(
						DisplayServer.WINDOW_MODE_FULLSCREEN
					)

					print(
						"【系統】已切換為全螢幕模式"
					)


# ============================================================
# 13. 玩家數值重算
#
# 對接原本貼紙及裝備系統。
# ============================================================

func recalculate_stats():

	var bonus_hp = 0

	if DataManager.has_sticker("001"):

		bonus_hp += DataManager.STICKER_DB["001"].value

	max_hp = base_max_hp + bonus_hp

	if current_hp > max_hp:

		current_hp = max_hp

	update_hp_bar()

	print(
		"【系統】玩家能力已更新，目前最大血量：",
		max_hp
	)


# ============================================================
# 14. 核心物理及遊戲邏輯迴圈
#
# 負責：
#
# A. 死亡與劇情操作鎖
# B. 素描本及購物操作鎖
# C. 玩家輸入
# D. 武器切換
# E. 遠程射擊與墨水消耗
# F. 戰鬥道具使用
# G. 翻滾冷卻
# H. 移動及射擊減速
# ============================================================

func _physics_process(delta: float) -> void:

	# --------------------------------------------------------
	# A. 死亡及重生期間停止玩家操作
	# --------------------------------------------------------

	if is_dead or RespawnManager.is_respawning:

		velocity = Vector2.ZERO

		input_direction = Vector2.ZERO

		move_and_slide()

		return

	# --------------------------------------------------------
	# B. 劇情期間停止玩家操作
	# --------------------------------------------------------

	if is_in_dialogue:

		velocity = Vector2.ZERO

		move_and_slide()

		return

	if not is_dead:

		# ----------------------------------------------------
		# C. 素描本及購物操作鎖
		# ----------------------------------------------------

		if is_reading_book or is_shopping:

			velocity = Vector2.ZERO

			if (
				state_machine.process_mode
				!= Node.PROCESS_MODE_DISABLED
			):

				state_machine.process_mode = (
					Node.PROCESS_MODE_DISABLED
				)

			move_and_slide()

			return

		else:

			if (
				state_machine.process_mode
				== Node.PROCESS_MODE_DISABLED
			):

				state_machine.process_mode = (
					Node.PROCESS_MODE_INHERIT
				)

		# ----------------------------------------------------
		# D. 取得目前狀態及玩家移動輸入
		# ----------------------------------------------------

		var current_state_name = ""

		if state_machine and state_machine.current_state:

			current_state_name = (
				state_machine.current_state.name.to_lower()
			)

		if (
			"attack" in current_state_name
			or "hurt" in current_state_name
		):

			input_direction = Vector2.ZERO

		else:

			input_direction = Input.get_vector(
				"left",
				"right",
				"up",
				"down"
			)

		# ----------------------------------------------------
		# E. 紅色武器蓄力時限制移動
		# ----------------------------------------------------

		if magic_brush and magic_brush.is_charging:

			input_direction = Vector2.ZERO

			var is_in_knockback: bool = (
				knockback_component
				and knockback_component.knockback_force.length() > 0.0
			)

			if not is_dashing and not is_in_knockback:

				velocity = Vector2.ZERO

		# ----------------------------------------------------
		# F. 快捷欄及武器切換
		# ----------------------------------------------------

		if Input.is_action_just_pressed("slot_left"):

			DataManager.rotate_quick_slot(-1)

		if Input.is_action_just_pressed("slot_right"):

			DataManager.rotate_quick_slot(1)

		if Input.is_action_just_pressed("switch_weapon"):

			switch_next_weapon()

		# ----------------------------------------------------
		# G. 遠程射擊與墨水消耗
		#
		# 尚未正式解鎖戰鬥前，
		# 不允許玩家使用遠程武器。
		# ----------------------------------------------------

		if (
			DataManager.can_combat()
			and state_machine.current_state.name != "PlayerHeal"
		):

			var cost = get_weapon_cost()

			# ================================================
			# 按下射擊鍵
			# ================================================

			if Input.is_action_just_pressed("skill_01"):

				if current_ink >= cost:

					var current_buff: float = (
						DataManager.combat_item_multiplier("ruler")
					)

					if DataManager.has_sticker("006"):

						current_buff *= (
							DataManager.STICKER_DB["006"].value
						)

					# ----------------------------------------
					# 紅色武器：開始蓄力
					# ----------------------------------------

					if current_weapon == WeaponMode.RED:

						var max_stages = floor(
							current_ink / 15.0
						)

						magic_brush.press_shoot(
							current_buff,
							max_stages
						)

					# ----------------------------------------
					# 藍色、黃色武器：直接射擊
					# ----------------------------------------

					else:

						magic_brush.press_shoot(
							current_buff
						)

						play_shoot_animation()

						current_ink -= cost

						if current_weapon == WeaponMode.YELLOW:

							shoot_slow_timer = 0.4

						else:

							shoot_slow_timer = 0.3

						if (
							player_hud
							and player_hud.has_method("update_ink")
						):

							player_hud.update_ink(
								current_ink,
								max_ink
							)

				else:

					print(
						"墨水用盡！請使用近戰揮刀補充墨水！"
					)

			# ================================================
			# 按住射擊鍵：紅色武器蓄力預覽
			# ================================================

			if (
				Input.is_action_pressed("skill_01")
				and current_weapon == WeaponMode.RED
			):

				if magic_brush and magic_brush.is_charging:

					var stage = (
						magic_brush.get_current_stage()
					)

					var preview_val = (
						current_ink - (stage * 15.0)
					)

					if (
						player_hud
						and player_hud.has_method("preview_ink")
					):

						player_hud.preview_ink(
							preview_val
						)

			# ================================================
			# 放開射擊鍵：紅色武器蓄力結算
			# ================================================

			if Input.is_action_just_released("skill_01"):

				if (
					current_weapon == WeaponMode.RED
					and magic_brush
					and magic_brush.is_charging
				):

					var stage = (
						magic_brush.get_current_stage()
					)

					if stage > 0:

						var current_buff: float = (
							DataManager.combat_item_multiplier("ruler")
						)

						if DataManager.has_sticker("006"):

							current_buff *= (
								DataManager.STICKER_DB["006"].value
							)

						magic_brush.release_shoot(
							current_buff
						)

						play_shoot_animation()

						current_ink -= (
							stage * 15.0
						)

						shoot_slow_timer = 0.6

						if (
							player_hud
							and player_hud.has_method("confirm_ink_drop")
						):

							player_hud.confirm_ink_drop(
								current_ink
							)

						elif (
							player_hud
							and player_hud.has_method("update_ink")
						):

							player_hud.update_ink(
								current_ink,
								max_ink
							)

					else:

						# 蓄力不足，取消射擊。

						magic_brush.cancel_shoot()

						if (
							player_hud
							and player_hud.has_method("preview_ink")
						):

							player_hud.preview_ink(
								current_ink
							)

		# ----------------------------------------------------
		# H. 使用目前快捷欄道具
		# ----------------------------------------------------

		if Input.is_action_just_pressed("USESKILL"):

			if state_machine.current_state.name != "PlayerHeal":

				DataManager.use_current_item()

		# ----------------------------------------------------
		# I. 翻滾冷卻倒數
		# ----------------------------------------------------

		if not is_dash_ready:

			dash_cd_timer -= delta

			if dash_cd_timer <= 0:

				is_dash_ready = true

				_play_dash_ready_effect()

	# --------------------------------------------------------
	# J. 射擊減速及最終位移
	# --------------------------------------------------------

	var is_in_knockback: bool = (
		knockback_component
		and knockback_component.knockback_force.length() > 0.0
	)

	if shoot_slow_timer > 0:

		shoot_slow_timer -= delta

		if not is_dashing and not is_in_knockback:

			velocity *= 0.05

	move_and_slide()


# ============================================================
# 15. 翻滾冷卻完成特效
#
# 使用角色閃光與腳底粒子，
# 讓玩家不必一直觀察 UI 即可知道翻滾已恢復。
# ============================================================

func _play_dash_ready_effect() -> void:

	# --------------------------------------------------------
	# A. 角色閃光
	# --------------------------------------------------------

	if animated_sprite_2d:

		var tween = create_tween()

		animated_sprite_2d.modulate = Color(
			0.5,
			1.0,
			1.5,
			1.0
		)

		tween.tween_property(
			animated_sprite_2d,
			"modulate",
			Color.WHITE,
			0.3
		)

	# --------------------------------------------------------
	# B. 腳底冷卻完成粒子
	# --------------------------------------------------------

	if DASH_READY_PARTICLES:

		var p = DASH_READY_PARTICLES.instantiate()

		p.global_position = global_position

		get_parent().add_child(p)


# ============================================================
# 16. 武器模式切換
#
# 藍色 → 紅色 → 黃色 → 藍色
#
# 保留原本腳底墨環與頭頂色印特效。
# ============================================================

func switch_next_weapon() -> void:

	current_weapon = (
		(current_weapon + 1) % 3
		as WeaponMode
	)

	if magic_brush and magic_brush.has_method("set_mode"):

		magic_brush.set_mode(
			current_weapon
		)

	if player_hud and player_hud.has_method("set_ink_mode"):

		player_hud.set_ink_mode(
			current_weapon
		)

	# 拍照模式中不顯示武器切換特效。

	if not _photo_mode_Active:

		if not is_instance_valid(_ink_switch_effect):

			_ink_switch_effect = InkSwitchEffect.new()

			_ink_switch_effect.z_index = 8

			add_child(_ink_switch_effect)

		_ink_switch_effect.replay(
			current_weapon,
			ink_switch_badge_offset
		)


# ============================================================
# 17. 墨水恢復系統
# ============================================================

func add_ink(
	amount: float = 10.0
) -> void:

	if current_ink < max_ink:

		current_ink = min(
			current_ink + amount,
			max_ink
		)

		if (
			player_hud
			and player_hud.has_method("update_ink")
		):

			player_hud.update_ink(
				current_ink,
				max_ink
			)


# ============================================================
# 18. 外部墨水恢復接口
#
# 供 Boss 觸手、敵人及其他道具呼叫。
# ============================================================

func restore_ink(
	amount: float = 10.0
) -> void:

	add_ink(amount)


func refill_full_ink() -> void:

	current_ink = max_ink

	if (
		player_hud
		and player_hud.has_method("update_ink")
	):

		player_hud.update_ink(
			current_ink,
			max_ink
		)


# ============================================================
# 19. 舊版彈藥系統相容接口
#
# 保留原本近戰回充 Ammo 的呼叫方式。
# 實際恢復內容已改為墨水。
# ============================================================

func add_ammo(
	amount: int = 1
) -> void:

	add_ink(amount * 10.0)


func restore_ammo(
	amount: int = 1
) -> void:

	add_ink(amount * 10.0)


func refill_full_ammo() -> void:

	refill_full_ink()


# ============================================================
# 20. 玩家受傷及戰鬥結算
# ============================================================

func take_damage(
	amount: float,
	attacker_pos: Vector2 = Vector2.ZERO,
	dir: Vector2 = Vector2.ZERO,
	is_melee: bool = false,
	extra_knockback: float = 1.0
) -> void:

	# 死亡、無敵及正式重生期間不接受傷害。

	if (
		is_dead
		or is_invincible
		or RespawnManager.is_respawning
	):

		return

	# --------------------------------------------------------
	# A. 結算實際傷害
	#
	# 保留藍色橡皮擦防禦道具效果。
	# --------------------------------------------------------

	current_hp = max(
		current_hp
		- amount * DataManager.combat_item_multiplier("eraser"),
		0
	)

	update_hp_bar()

	# --------------------------------------------------------
	# B. 打擊頓幀
	# --------------------------------------------------------

	if (
		DataManager
		and DataManager.has_method("trigger_hitstop")
	):

		DataManager.trigger_hitstop(
			0.07,
			0.05
		)

	# --------------------------------------------------------
	# C. 受傷擊退方向
	# --------------------------------------------------------

	var knockback_dir = (
		dir
		if dir != Vector2.ZERO
		else (global_position - attacker_pos).normalized()
	)

	if (
		knockback_component
		and knockback_dir != Vector2.ZERO
	):

		knockback_component.apply_knockback(
			knockback_dir,
			-1.0,
			extra_knockback
		)

	# --------------------------------------------------------
	# D. 相機震動
	# --------------------------------------------------------

	var camera = get_viewport().get_camera_2d()

	if camera and camera.has_method("apply_shake"):

		camera.apply_shake(14.0)

	# --------------------------------------------------------
	# E. 受傷視覺及無敵時間
	# --------------------------------------------------------

	play_hurt_effects()

	start_invincibility()

	# --------------------------------------------------------
	# F. 判斷死亡或一般受傷
	# --------------------------------------------------------

	if current_hp <= 0:

		die()

	else:

		handle_hurt()


# ============================================================
# 21. 受傷視覺特效
#
# 保留原本角色變紅、壓扁及回彈效果。
# ============================================================

func play_hurt_effects() -> void:

	if animated_sprite_2d:

		var tween = (
			create_tween().set_parallel(true)
		)

		animated_sprite_2d.modulate = Color(
			3.0,
			0.4,
			0.4
		)

		tween.tween_property(
			animated_sprite_2d,
			"modulate",
			Color.WHITE,
			0.15
		)

		animated_sprite_2d.scale = Vector2(
			original_sprite_scale.x * 1.2,
			original_sprite_scale.y * 0.8
		)

		tween.tween_property(
			animated_sprite_2d,
			"scale",
			original_sprite_scale,
			0.15
		).set_trans(
			Tween.TRANS_BACK
		).set_ease(
			Tween.EASE_OUT
		)


# ============================================================
# 22. 受傷無敵時間
#
# 使用半透明閃爍提示玩家目前處於無敵狀態。
# ============================================================

func start_invincibility() -> void:

	is_invincible = true

	var tween = create_tween().set_loops(
		int(invincibility_duration / 0.1)
	)

	tween.tween_property(
		animated_sprite_2d,
		"modulate:a",
		0.3,
		0.05
	)

	tween.tween_property(
		animated_sprite_2d,
		"modulate:a",
		1.0,
		0.05
	)

	await get_tree().create_timer(
		invincibility_duration
	).timeout

	is_invincible = false

	animated_sprite_2d.modulate.a = 1.0


# ============================================================
# 23. 貼紙及近戰傷害結算
#
# 保留低血量增傷貼紙與紅色蠟筆效果。
# ============================================================

func get_current_basic_attack_damage() -> float:

	var final_base_damage: float = basic_attack_damage

	if DataManager.has_sticker("008"):

		var threshold: float = (
			DataManager.STICKER_DB["008"].threshold
		)

		if (
			float(current_hp) / float(max_hp)
			<= threshold
		):

			final_base_damage *= (
				DataManager.STICKER_DB["008"].value
			)

	return (
		final_base_damage
		* DataManager.combat_item_multiplier("calyon")
	)


# ============================================================
# 24. 擊殺敵人回血貼紙
# ============================================================

func on_enemy_killed():

	if DataManager.has_sticker("004"):

		var heal_percent: float = (
			DataManager.STICKER_DB["004"].value
		)

		var heal_amount: int = int(
			max_hp * heal_percent
		)

		current_hp = min(
			current_hp + heal_amount,
			max_hp
		)

		update_hp_bar()


# ============================================================
# 25. 受傷狀態處理
#
# 受傷時中斷閱讀及購物。
# 保留原本暈眩、喘氣狀態判斷。
# ============================================================

func handle_hurt():

	# --------------------------------------------------------
	# A. 中斷素描本
	# --------------------------------------------------------

	if is_reading_book:

		is_reading_book = false

		state_machine.process_mode = (
			Node.PROCESS_MODE_INHERIT
		)

		if notebook_ui:

			notebook_ui.close_notebook()

	# --------------------------------------------------------
	# B. 中斷購物
	# --------------------------------------------------------

	if is_shopping:

		is_shopping = false

		state_machine.process_mode = (
			Node.PROCESS_MODE_INHERIT
		)

		for node in get_tree().root.get_children():

			if node.name == "ShopUI":

				node.queue_free()

	# --------------------------------------------------------
	# C. 特殊狀態防止受傷動畫覆蓋
	# --------------------------------------------------------

	var state_name = (
		state_machine.current_state.name.to_lower()
	)

	if "stun" in state_name or "pant" in state_name:

		return

	state_machine.change_state("PlayerHurt")


# ============================================================
# 26. 玩家治療
#
# 保留治療量提升貼紙效果。
# ============================================================

func heal(amount: int) -> void:

	var final_amount = amount

	if DataManager.has_sticker("016"):

		var bonus = (
			DataManager.STICKER_DB["016"].value
		)

		final_amount += bonus

	if current_hp < max_hp:

		current_hp = min(
			current_hp + final_amount,
			max_hp
		)

		update_hp_bar()


# ============================================================
# 27. 正式玩家死亡入口
#
# 死亡時：
#
# A. 防止重複死亡
# B. 停止玩家移動
# C. 中斷素描本及畫架介面
# D. 中斷購物
# E. 取消武器蓄力
# F. 恢復狀態機
# G. 進入 PlayerDie
#
# 本函式不處理金幣懲罰。
# 不直接決定死亡重生位置。
# ============================================================

func die() -> void:

	if is_dead:

		return

	is_dead = true

	velocity = Vector2.ZERO

	input_direction = Vector2.ZERO

	is_casting = false

	is_dashing = false

	# --------------------------------------------------------
	# A. 關閉素描本及畫架狀態
	# --------------------------------------------------------

	if is_reading_book:

		if notebook_ui:

			notebook_ui.close_notebook()

	is_reading_book = false

	opened_from_savepoint = false

	# 關閉仍存在的畫架選單。

	for save_menu in get_tree().get_nodes_in_group(
		"save_menu"
	):

		if is_instance_valid(save_menu):

			save_menu.queue_free()

	# --------------------------------------------------------
	# B. 中斷購物
	# --------------------------------------------------------

	is_shopping = false

	for node in get_tree().root.get_children():

		if node.name == "ShopUI":

			node.queue_free()

	# --------------------------------------------------------
	# C. 取消尚未完成的武器蓄力
	# --------------------------------------------------------

	if is_instance_valid(magic_brush):

		if magic_brush.has_method("cancel_shoot"):

			magic_brush.cancel_shoot()

	# --------------------------------------------------------
	# D. 確保死亡狀態機可以運作
	# --------------------------------------------------------

	if is_instance_valid(state_machine):

		state_machine.process_mode = (
			Node.PROCESS_MODE_INHERIT
		)

		state_machine.change_state("PlayerDie")


# ============================================================
# 28. 玩家血量及失色 Shader 同步
#
# 玩家血量越低，角色彩度越低。
# 保留《眠境 RE:RECOLOR》的失色視覺設計。
# ============================================================

func update_hp_bar():

	if player_hud:

		player_hud.update_hp(
			current_hp,
			max_hp
		)

	var hp_ratio: float = max(
		float(current_hp) / float(max_hp),
		0.0
	)

	if animated_sprite_2d.material:

		var tween = get_tree().create_tween()

		tween.tween_property(
			animated_sprite_2d.material,
			"shader_parameter/saturation",
			hp_ratio,
			0.3
		)


# ============================================================
# 29. 玩家動畫播放封裝系統
#
# 支援：
#
# 1. 四方向動畫
# 2. 八方向移動動畫
# 3. 動畫不存在時自動降級
# 4. 甩魔法動畫優先權
# 5. 翻滾及受傷動畫相容性
# ============================================================

func play_animation(
	prefix: String,
	_dir: Vector2 = Vector2.ZERO
):

	var anim = get_node_or_null(
		"AnimatedSprite2D"
	)

	if anim == null:

		return

	# --------------------------------------------------------
	# A. 甩魔法動畫保護
	#
	# Idle 與 Move 不允許覆蓋甩魔法動畫。
	# 其他攻擊、翻滾及受傷動畫仍可以中斷。
	# --------------------------------------------------------

	if is_casting:

		if prefix == "idle" or prefix == "move":

			return

		else:

			is_casting = false

	var target_suffix = facing_direction

	# --------------------------------------------------------
	# B. 八方向移動判斷
	#
	# 只有移動狀態允許 WASD 更新角色面向。
	# --------------------------------------------------------

	if (
		prefix == "move"
		and not is_dashing
		and input_direction != Vector2.ZERO
	):

		var y_str = ""

		var x_str = ""

		# 容錯值避免搖桿微量飄移。

		if input_direction.y < -0.1:

			y_str = "up"

		elif input_direction.y > 0.1:

			y_str = "down"

		if input_direction.x < -0.1:

			x_str = "left"

		elif input_direction.x > 0.1:

			x_str = "right"

		var eight_way_dir = ""

		if y_str != "" and x_str != "":

			eight_way_dir = y_str + "_" + x_str

		else:

			eight_way_dir = (
				y_str
				if y_str != ""
				else x_str
			)

		# ----------------------------------------------------
		# C. 記錄四方向面向
		#
		# 供待機、攻擊及其他四方向動畫使用。
		# ----------------------------------------------------

		if abs(input_direction.x) > abs(input_direction.y):

			facing_direction = (
				"right"
				if input_direction.x > 0
				else "left"
			)

		else:

			facing_direction = (
				"down"
				if input_direction.y > 0
				else "up"
			)

		target_suffix = eight_way_dir

	# --------------------------------------------------------
	# D. 組合正式動畫名稱
	# --------------------------------------------------------

	var animation_name = (
		prefix + "_" + target_suffix
	)

	# --------------------------------------------------------
	# E. 動畫不存在時降級至四方向
	# --------------------------------------------------------

	if not anim.sprite_frames.has_animation(
		animation_name
	):

		animation_name = (
			prefix + "_" + facing_direction
		)

	if not anim.sprite_frames.has_animation(
		animation_name
	):

		return

	anim.play(animation_name)


# ============================================================
# 30. 遠程武器甩魔法動畫
#
# 依照滑鼠射擊方向，
# 選擇四方向射擊動畫：
#
# shoot_up
# shoot_down
# shoot_left
# shoot_right
# ============================================================

func play_shoot_animation(
	custom_dir: Vector2 = Vector2.ZERO
) -> void:

	if (
		is_in_dialogue
		or is_dead
		or not animated_sprite_2d
		or not animated_sprite_2d.sprite_frames
	):

		return

	# --------------------------------------------------------
	# A. 計算射擊方向
	# --------------------------------------------------------

	var shoot_dir: Vector2 = custom_dir

	if shoot_dir == Vector2.ZERO:

		shoot_dir = (
			get_global_mouse_position()
			- global_position
		).normalized()

	# --------------------------------------------------------
	# B. 更新角色四方向面向
	# --------------------------------------------------------

	if shoot_dir != Vector2.ZERO:

		if abs(shoot_dir.x) > abs(shoot_dir.y):

			facing_direction = (
				"right"
				if shoot_dir.x > 0
				else "left"
			)

		else:

			facing_direction = (
				"down"
				if shoot_dir.y > 0
				else "up"
			)

	var anim_name: String = (
		"shoot_" + facing_direction
	)

	if not animated_sprite_2d.sprite_frames.has_animation(
		anim_name
	):

		return

	# --------------------------------------------------------
	# C. 防止射擊動畫循環播放
	# --------------------------------------------------------

	animated_sprite_2d.sprite_frames.set_animation_loop(
		anim_name,
		false
	)

	# --------------------------------------------------------
	# D. 從第一幀播放甩魔法動畫
	# --------------------------------------------------------

	is_casting = true

	animated_sprite_2d.stop()

	animated_sprite_2d.play(anim_name)

	# --------------------------------------------------------
	# E. 動畫播放完畢後解除動作鎖
	# --------------------------------------------------------

	await animated_sprite_2d.animation_finished

	if animated_sprite_2d.animation == anim_name:

		is_casting = false


# ============================================================
# 31. 動畫防呆檢查系統
#
# 遞迴檢查場景中的 AnimatedSprite2D。
# 找出沒有指定動畫名稱的異常節點。
# ============================================================

func _run_bug_radar(node: Node):

	if node is AnimatedSprite2D:

		if node.animation == "":

			print(
				"\n===================================="
			)

			print(
				"抓到空動畫節點！"
			)

			print(
				"節點絕對路徑：",
				node.get_path()
			)

			print(
				"來源場景檔案：",
				node.owner.scene_file_path
				if node.owner
				else "無"
			)

			print(
				"====================================\n"
			)

	for child in node.get_children():

		_run_bug_radar(child)


# ============================================================
# 32. Dialogic 演員動畫接收器
#
# 阿尼專用的過場動畫控制接口。
#
# 此處只負責演員動作。
# 不負責永久劇情完成判斷。
#
# StoryProgress、CutsceneDirector、SavePoint
# 仍使用原本的正式劇情處理流程。
# ============================================================

func _on_dialogic_signal(argument: String):

	match argument:

		"ani_stand_up":

			if animated_sprite_2d:

				animated_sprite_2d.play(
					"idle_right"
				)

		"ani_search":

			if animated_sprite_2d:

				animated_sprite_2d.play(
					"idle_down"
				)


# ============================================================
# 33. 跨場景角色面向接收器
#
# 對接 SceneTransition。
#
# 將 Vector2 方向轉換為玩家動畫使用的
# up、down、left、right。
# ============================================================

func set_facing_direction(
	dir: Vector2
) -> void:

	if dir == Vector2.ZERO:

		return

	if abs(dir.x) >= abs(dir.y):

		facing_direction = (
			"right"
			if dir.x > 0
			else "left"
		)

	else:

		facing_direction = (
			"down"
			if dir.y > 0
			else "up"
		)

	# 更新轉場後的角色待機面向。

	play_animation("idle")


# ============================================================
# 34. 武器切換視覺特效
#
# InkSwitchEffect
#
# 保留原本：
#
# A. 腳底擴散墨環
# B. 頭頂武器色印
# C. 藍色墨滴圖示
# D. 紅色光束圖示
# E. 黃色三向散射圖示
# F. 連續切換時重新播放
#
# 使用共用 Node2D，避免反覆生成大量特效節點。
# ============================================================

class InkSwitchEffect extends Node2D:

	const COLORS := [
		Color("#58caff"),
		Color("#ff697f"),
		Color("#ffd453")
	]

	const EDGE := Color("#251c38")

	const DURATION := 0.78

	var mode: int

	var elapsed := DURATION

	var badge_offset := Vector2(
		0,
		-36
	)

	# --------------------------------------------------------
	# A. 重新播放切換特效
	# --------------------------------------------------------

	func replay(
		new_mode: int,
		offset: Vector2
	) -> void:

		mode = new_mode

		badge_offset = offset

		elapsed = 0.0

		show()

		set_process(true)

		queue_redraw()

	# --------------------------------------------------------
	# B. 特效時間更新
	# --------------------------------------------------------

	func _process(delta: float) -> void:

		elapsed += delta

		if elapsed >= DURATION:

			hide()

			set_process(false)

		else:

			queue_redraw()

	# --------------------------------------------------------
	# C. 繪製腳底墨環及武器色印
	# --------------------------------------------------------

	func _draw() -> void:

		var ink: Color = COLORS[mode]

		var burst := clampf(
			elapsed / 0.36,
			0.0,
			1.0
		)

		# ====================================================
		# 腳底擴散墨環
		# ====================================================

		if burst < 1.0:

			var radius := lerpf(
				7.0,
				36.0,
				ease(burst, 0.45)
			)

			draw_set_transform(
				Vector2.ZERO,
				0.0,
				Vector2(1.0, 0.48)
			)

			for i in range(6):

				var angle := (
					TAU * i / 6.0
					+ burst * 0.35
				)

				draw_arc(
					Vector2.ZERO,
					radius,
					angle,
					angle + 0.78,
					7,
					Color(
						ink,
						1.0 - burst
					),
					2.0
				)

				var drop := (
					Vector2.from_angle(angle)
					* (radius + 4.0)
				)

				draw_circle(
					drop,
					2.2 - burst,
					Color(
						ink,
						1.0 - burst
					)
				)

		# ====================================================
		# 頭頂武器色印
		# ====================================================

		var enter := clampf(
			elapsed / 0.12,
			0.0,
			1.0
		)

		var fade := clampf(
			(DURATION - elapsed) / 0.20,
			0.0,
			1.0
		)

		var center := (
			badge_offset
			+ Vector2.DOWN
			* (
				4.0 * (1.0 - enter)
				- 3.0 * (1.0 - fade)
			)
		)

		draw_set_transform(
			center.round(),
			0.0,
			Vector2.ONE
			* (
				1.0
				+ 0.22 * sin(PI * enter)
			)
		)

		var outline := PackedVector2Array([
			Vector2(0, -10),
			Vector2(12, 0),
			Vector2(0, 10),
			Vector2(-12, 0)
		])

		draw_colored_polygon(
			outline,
			Color(EDGE, fade)
		)

		outline.append(outline[0])

		draw_polyline(
			outline,
			Color(ink, fade),
			1.5
		)

		var mark := Color(
			ink.lightened(0.35),
			fade
		)

		# ====================================================
		# 三色武器圖示
		# ====================================================

		match mode:

			# 藍色武器：墨滴

			0:

				draw_colored_polygon(
					PackedVector2Array([
						Vector2(0, -6),
						Vector2(4, 1),
						Vector2(3, 4),
						Vector2(0, 5),
						Vector2(-3, 4),
						Vector2(-4, 1)
					]),
					mark
				)

			# 紅色武器：光束

			1:

				draw_line(
					Vector2(-4, 4),
					Vector2(4, -4),
					mark,
					3.0
				)

				draw_line(
					Vector2(0, -4),
					Vector2(4, -4),
					mark,
					2.0
				)

			# 黃色武器：三向散射

			2:

				for i in range(-1, 2):

					draw_line(
						Vector2(i, 3),
						Vector2(i * 5, -3),
						mark,
						2.0
					)
