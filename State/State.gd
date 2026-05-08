extends Node                     # 繼承自 Node，讓它可以作為一個普通節點掛在場景樹上
class_name State                 # 定義類別為 State，供所有具體狀態（如 Idle, Attack）繼承

var character: BaseCharacter     # 宣告一個變數存放「這個狀態的主人是誰」，型態限定為 BaseCharacter
var state_machine: StateMachine  # 宣告一個變數存放「管理這個狀態的大腦是誰」

func enter() -> void:            # 進場函數：當狀態機切換到這個狀態時，執行一次
	pass                         # 內容由具體狀態實作

func exit() -> void:             # 退場函數：當狀態機準備離開這個狀態時，執行一次
	pass                         # 內容由具體狀態實作

func state_physics_update(_delta: float) -> void: # 邏輯更新函數：在狀態執行期間，每一幀(1/60秒)都會被呼叫
	pass                         # 內容由具體狀態實作
