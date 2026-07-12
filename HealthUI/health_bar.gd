extends ProgressBar          # 繼承進度條節點 health_bar

func update_bar(current_hp: int, max_hp: int):
	self.max_value = max_hp  # 告訴血條最大值是多少
	
	# 用 Tween 讓血量平滑減少 (0.2秒內完成)
	# TRANS_SINE：讓動畫曲線呈現正弦波 (開始結束比較柔和)
	var tween = get_tree().create_tween()
	tween.tween_property(self, "value", current_hp, 0.2).set_trans(Tween.TRANS_SINE)
