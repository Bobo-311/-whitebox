extends GPUParticles2D

func _ready() -> void:
	emitting = true
	# 🌟 粒子播放完畢後自動清理，避免洩漏記憶體
	finished.connect(queue_free)
