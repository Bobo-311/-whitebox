extends Area2D # 繼承 Area2D 用來偵測觸碰

var lost_gold: int = 0 # 宣告變數：記錄這團靈魂保管了多少錢
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D # 抓取動畫播放節點

func _ready() -> void: # 靈魂生成時執行
	anim.play("default") # 播放原地飄浮動畫
		
	var tween = create_tween().set_loops() # 建立無限循環的動畫控制器
	tween.tween_property(anim, "position:y", anim.position.y - 10, 1.0).set_trans(Tween.TRANS_SINE) # 花 1 秒向上移動 10 像素
	tween.tween_property(anim, "position:y", anim.position.y, 1.0).set_trans(Tween.TRANS_SINE) # 再花 1 秒移回原本的高度

func _on_body_entered(body: Node2D) -> void: # 當實體碰到靈魂的感應區時觸發
	if body is Player: # 完美防呆：檢查碰到的實體是不是玩家本人
		if DataManager: # 如果全域大腦存在
			DataManager.total_gold += lost_gold # 將靈魂保管的錢加回大腦的總金額裡
			
			DataManager.has_soul_on_ground = false # 錢拿回來了，清空大腦的靈魂存在紀錄
			DataManager.soul_stored_gold = 0 # 將大腦紀錄的靈魂金額歸零
			
			print("【系統】收回靈魂，拿回金幣：" + str(lost_gold)) # 後台印出提示
		
		var t = create_tween() # 建立一次性動畫控制器處理消失特效
		t.set_parallel(true) # 設定為多屬性同時進行模式
		t.tween_property(self, "modulate:a", 0.0, 0.3) # 花 0.3 秒將透明度降為 0
		t.tween_property(self, "position:y", position.y - 30, 0.3) # 同時花 0.3 秒往上飄散 30 像素
		t.set_parallel(false) # 恢復為正常的序列模式
		
		t.tween_callback(queue_free) # 動畫播完後，徹底刪除這團靈魂
