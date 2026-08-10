extends GPUParticles2D

func _ready() -> void:
	# 🌟 用 Lifetime 倒數 + 0.2 秒保險，確保粒子發射完後才自動銷毀
	get_tree().create_timer(lifetime + 0.2).timeout.connect(queue_free)
