extends Node                     # 繼承自 Node
class_name StateMachine          # 定義類別為 StateMachine (狀態機)

var current_state: State = null  # 用來記錄「現在」正在執行的狀態節點，預設為空
var states: Dictionary = {}      # 建立一個字典(口袋)，用來儲存底下所有的狀態節點
@onready var character: BaseCharacter = get_parent() # 抓取自己的父節點當作主人 (通常是 Player 或 Enemy)

func _ready() -> void:           # 遊戲開始時執行一次
	for child in get_children(): # 迴圈拜訪掛在這個狀態機底下的所有子節點
		if child is State:       # 如果這個子節點是我們定義的 State 類型
			states[child.name.to_lower()] = child # 把節點的名字轉成小寫當作鑰匙，把節點存進字典裡
			child.character = character           # 告訴這個狀態：「你的主人是這個角色」
			child.state_machine = self            # 告訴這個狀態：「管理你的大腦是我(self)」
	
	if get_child_count() > 0:    # 如果狀態機底下有掛載至少一個狀態
		change_state(get_child(0).name) # 預設切換到最上面的第一個狀態作為開局狀態

func _physics_process(delta: float) -> void: # 每一幀執行一次的物理更新
	if current_state:            # 如果目前有正在執行的狀態
		current_state.state_physics_update(delta) # 呼叫該狀態的更新函數，把時間差(delta)傳進去

func change_state(state_name: String) -> void: # 核心切換狀態函數，接收想要切換的狀態名稱
	var new_state = states.get(state_name.to_lower()) # 用小寫名稱去字典裡把新狀態拿出來
	
	if not new_state or new_state == current_state: # 如果找不到新狀態，或者新狀態跟現在的一模一樣
		return                   # 直接跳出，不做任何切換

	if character.is_dead and not state_name.to_lower().contains("die"): # 如果角色已經死了，且新狀態名稱不包含 "die"
		return                   # 不准切換！死人不能做其他動作

	if current_state:            # 如果現在有舊的狀態正在執行
		current_state.exit()     # 先呼叫舊狀態的退場函數(exit)清理環境

	current_state = new_state    # 正式把目前狀態替換成新狀態
	current_state.enter()        # 呼叫新狀態的進場函數(enter)開始執行
