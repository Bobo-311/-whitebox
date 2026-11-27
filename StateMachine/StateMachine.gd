
extends Node
class_name StateMachine

# ============================================================
# 《眠境 RE:RECOLOR》
# StateMachine V2.1｜共用角色狀態機與玩家戰鬥輸入隔離
# Godot 4.5.1
# STEP 10.7.7-F-5.1
# ============================================================
# 主要職責：
# 1. 管理角色狀態及初始化
# 2. 執行角色物理更新
# 3. 管理角色狀態切換
# 4. 防止死亡角色進入一般狀態
# 5. 驗證玩家戰鬥操作權限
# 6. 管理玩家近戰攻擊輸入
# 7. 防止過期攻擊輸入殘留
#
# V2.1 修改重點：
# A. 改用 _input() 接收原始攻擊事件。
# B. 避免一般 HUD 提前消耗攻擊事件。
# C. 保留商店、筆記本及劇情操作鎖。
# D. 新增近戰輸入診斷紀錄。
#
# 相容性：
# 不限制敵人、精英敵人及 Boss 的 AI 攻擊。
# 不修改存檔、攻擊數值及武器平衡。
# ============================================================

# ============================================================
# 1. 狀態機核心資料
# ============================================================

## 目前正在執行的狀態。
var current_state: State = null

## 已登記的角色狀態。
var states: Dictionary = {}

## 所屬角色實體。
var character: BaseCharacter = null

# ============================================================
# 2. 玩家攻擊輸入紀錄
# ============================================================

## -1 代表目前沒有有效攻擊要求。
var _attack_input_physics_frame: int = -1

@export_group("除錯設定")

## 開發期間顯示近戰輸入診斷紀錄。
@export var debug_attack_input: bool = true

# ============================================================
# 3. 狀態機初始化
# ============================================================

func _ready() -> void:
	for child in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			child.character = character
			child.state_machine = self

	# 尚未取得角色實體前，不接收玩家操作。
	set_process_input(false)

# ============================================================
# 4. 正式角色初始化
# ============================================================

func init(parent_character: BaseCharacter) -> void:
	character = parent_character
	_attack_input_physics_frame = -1

	# 將角色實體分發至所有子狀態。
	for child in get_children():
		if child is State:
			child.character = character

	# 只有玩家需要接收硬體攻擊輸入。
	# 敵人及 Boss 不監聽玩家按鍵。
	set_process_input(character is Player)

	# 啟動原本預設的第一個狀態。
	if get_child_count() > 0:
		change_state(get_child(0).name)

	if character is Player and OS.is_debug_build():
		print("【StateMachine】V2.1 玩家戰鬥輸入初始化完成")

# ============================================================
# 5. 玩家戰鬥操作權限
# ============================================================

## 回傳目前禁止玩家攻擊的原因。
## 空字串代表允許正常戰鬥操作。
func _get_combat_block_reason() -> String:
	if not is_instance_valid(character):
		return "角色尚未初始化"

	var player := character as Player

	if player == null:
		return "不是玩家角色"

	# A. 死亡及正式重生期間。
	if player.is_dead or RespawnManager.is_respawning:
		return "玩家死亡或正在重生"

	# B. 正式場景切換期間。
	if SceneTransition.is_transitioning:
		return "場景正在切換"

	# C. 遊戲暫停期間。
	if get_tree().paused:
		return "遊戲正在暫停"

	# D. 狀態機已被其他系統停止。
	if not can_process():
		return "玩家狀態機已停止"

	# E. 正式劇情演出期間。
	if player.is_in_dialogue:
		return "玩家正在進行劇情"

	if Dialogic.current_timeline != null:
		return "Dialogic 劇本正在執行"

	# F. 商店操作期間。
	if player.is_shopping:
		return "玩家正在購物"

	# G. 筆記本及畫架操作期間。
	if player.is_reading_book:
		return "玩家正在操作筆記本或畫架"

	# H. 尚未解鎖正式戰鬥能力。
	if not DataManager.can_combat():
		return "尚未解鎖戰鬥"

	return ""

## 提供所有玩家戰鬥狀態共用的權限接口。
func can_accept_player_combat_input() -> bool:
	return _get_combat_block_reason().is_empty()

# ============================================================
# 6. 玩家原始攻擊輸入接收器
#
# V2.1：
# 不再依賴 _unhandled_input()。
# 避免一般 HUD 消耗滑鼠事件後，
# 玩家無法正常執行近戰攻擊。
# ============================================================

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("attack"):
		return

	# 先確認玩家目前是否具備操作權限。
	var block_reason: String = _get_combat_block_reason()

	if not block_reason.is_empty():
		_attack_input_physics_frame = -1

		if debug_attack_input and OS.is_debug_build():
			print("【玩家戰鬥】已阻擋近戰輸入：", block_reason)

		return

	# 記錄有效攻擊要求。
	# 實際攻擊仍交由玩家狀態的物理更新處理。
	_attack_input_physics_frame = Engine.get_physics_frames()

	if debug_attack_input and OS.is_debug_build():
		print("【玩家戰鬥】已接收原始近戰輸入")

	# 此處不強制吃掉事件。
	# 避免影響原本滑鼠特效及其他輸入系統。

# ============================================================
# 7. 消耗玩家攻擊要求
# ============================================================

## 每次有效攻擊輸入只能被消耗一次。
func consume_player_attack_input() -> bool:
	if _attack_input_physics_frame < 0:
		return false

	var input_frame: int = _attack_input_physics_frame

	# 先清除紀錄，防止重複執行。
	_attack_input_physics_frame = -1

	# 正式執行前再次確認玩家操作權限。
	if not can_accept_player_combat_input():
		return false

	# 防止過期攻擊要求殘留。
	var frame_difference: int = Engine.get_physics_frames() - input_frame

	if frame_difference < 0 or frame_difference > 1:
		return false

	return true

# ============================================================
# 8. 角色物理狀態更新
# ============================================================

func _physics_process(delta: float) -> void:
	# 開發期間協助診斷輸入事件是否被提前攔截。
	if character is Player:
		if debug_attack_input and OS.is_debug_build():
			if Input.is_action_just_pressed("attack"):
				if can_accept_player_combat_input():
					if _attack_input_physics_frame < 0:
						print("【玩家戰鬥診斷】偵測到 attack 按鍵，但未收到原始攻擊事件")

	# 執行目前角色狀態。
	if current_state:
		current_state.state_physics_update(delta)

	# 本次物理更新未使用的攻擊要求直接清除。
	_attack_input_physics_frame = -1

# ============================================================
# 9. 核心狀態切換
# ============================================================

func change_state(state_name: String) -> void:
	var normalized_name: String = state_name.to_lower()
	var new_state = states.get(normalized_name)

	# A. 防止切換至不存在或相同的狀態。
	if not new_state or new_state == current_state:
		return

	# B. 防止尚未初始化的角色進行狀態切換。
	if not is_instance_valid(character):
		return

	# C. 保留原本死亡狀態保護。
	if character.is_dead and not normalized_name.contains("die"):
		return

	# D. 玩家近戰攻擊的第二層操作保護。
	# 不影響敵人及 Boss 的 AI 狀態切換。
	if character is Player and normalized_name == "playerattack":
		if not can_accept_player_combat_input():
			return

	# E. 執行原本狀態的退場流程。
	if current_state:
		current_state.exit()

	# F. 正式切換並執行新狀態。
	current_state = new_state
	current_state.enter()
