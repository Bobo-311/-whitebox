extends Camera2D                 # 繼承鏡頭節點

# --- 鏡頭震動參數 ---
var shake_strength: float = 10.0  # 目前震動強度。數字越大晃越兇
var shake_decay: float = 20.0    # 震動衰減速度。數字越高停越快

func _process(delta: float) -> void: # 每一幀執行
	if shake_strength > 0:       # 如果目前還有震動強度
		# offset 是鏡頭的偏移量。randf_range 可以在正負強度之間隨機取數值，產生上下左右亂晃的感覺
		offset = Vector2(
			randf_range(-shake_strength, shake_strength), 
			randf_range(-shake_strength, shake_strength)  
		)
		
		# lerp (線性插值)：讓強度朝著 0 靠近，產生平滑的餘震衰減感
		shake_strength = lerp(shake_strength, 0.0, shake_decay * delta)
		
	else:                        # 如果沒有震動強度
		offset = Vector2.ZERO    # 確保偏移量歸零，讓畫面回到正中心，避免永久歪斜

func apply_shake(strength: float) -> void: # 🌟 供外部呼叫的公開函數
	shake_strength = strength    # 接收外部傳來的震動強度 (例如野豬死亡時傳入 15.0)
