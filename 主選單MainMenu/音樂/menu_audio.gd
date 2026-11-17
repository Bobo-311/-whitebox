extends Node
class_name MainMenuAudio

# ==================================================
# 主選單音訊管理器
#
# 負責：
# 1. 背景音樂及淡入動畫
# 2. 滑鼠懸停音效
# 3. 按鈕確認音效
# ==================================================

@export_group("背景音樂設定")

## 背景音樂淡入時間
@export_range(0.0, 5.0, 0.1) var music_fade_time: float = 1.8


# ==================================================
# 取得音訊播放器
# ==================================================

@onready var hover_sound: AudioStreamPlayer = $HoverSound
@onready var confirm_sound: AudioStreamPlayer = $ConfirmSound
@onready var music_player: AudioStreamPlayer = $MusicPlayer


# ==================================================
# 1. 初始化
# ==================================================

func _ready() -> void:

	# 進入主選單時播放背景音樂
	_play_background_music()


# ==================================================
# 2. 背景音樂
# ==================================================

func _play_background_music() -> void:

	# 檢查是否有音樂素材
	if music_player.stream == null:
		return

	# 保存 Inspector 設定的原始音量
	var target_volume: float = music_player.volume_db

	# 如果不需要淡入，直接播放
	if music_fade_time <= 0.0:
		music_player.play()
		return

	# 從接近無聲的音量開始播放
	music_player.volume_db = -60.0
	music_player.play()

	# 背景音樂逐漸恢復至設定音量
	var tween := create_tween()

	tween.tween_property(
		music_player,
		"volume_db",
		target_volume,
		music_fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ==================================================
# 3. 滑鼠懸停音效
# ==================================================

func play_hover() -> void:

	# 防止缺少素材時發生錯誤
	if hover_sound.stream == null:
		return

	# 確認音效播放期間不播放懸停音效
	if confirm_sound.playing:
		return

	# 播放懸停音效
	hover_sound.play()


# 播放確認音效，不等待播放結束
func play_confirm() -> void:
	if confirm_sound.stream == null:
		return

	hover_sound.stop()
	confirm_sound.play()


# 播放確認音效，並等待播放結束
# 適用於離開遊戲等需要等待的功能
func play_confirm_and_wait() -> void:
	if confirm_sound.stream == null:
		return

	play_confirm()
	await confirm_sound.finished
