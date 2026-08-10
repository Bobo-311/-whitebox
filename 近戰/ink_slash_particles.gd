# InkSlashParticles.gd
extends GPUParticles2D

func _ready() -> void:
	emitting = true
	# 🌟 Godot 4 粒子發射結束訊號，自動回收節點
	finished.connect(queue_free)
