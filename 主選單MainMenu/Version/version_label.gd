extends Label

# ==================================================
# 遊戲版本資訊
# 自動讀取專案設定中的遊戲版本
# 避免每次更新遊戲都需要手動修改 UI 文字
# ==================================================

func _ready() -> void:

	# 取得專案設定中的版本號
	var version: String = str(
		ProjectSettings.get_setting(
			"application/config/version",
			""
		)
	).strip_edges()

	# 防止專案版本未設定
	if version.is_empty():
		text = "開發測試版本"
		return

	# 更新畫面上的版本文字
	text = "v" + version
