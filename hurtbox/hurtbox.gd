extends Area2D                   # 繼承自 Area2D，因為這只是一個用來感應的區域，沒有實體碰撞
class_name Hurtbox               # 宣告這是一個正式的「受傷區」類別，方便其他腳本辨識

# --- 接收攻擊的痛覺受器 ---
func take_damage(amount: float, hit_position: Vector2 = Vector2.ZERO, hit_direction: Vector2 = Vector2.ZERO): # 接收傷害數值與方向
	var parent = get_parent()    # 抓取這個 Hurtbox 的父節點 (也就是真正的主人，例如 Player 或 Enemy)
	print("💥【", parent.name, "】的 Hurtbox 被打到了") # 在後台印出哪一個主人的受傷區被打中

	if parent.has_method("take_damage"): # 檢查主人身上有沒有寫 "take_damage" 這個函數 (確認主人會不會痛)
		parent.take_damage(amount, hit_position, hit_direction) # 如果主人有這個功能，就把收到的傷害資料全部轉交給主人處理
