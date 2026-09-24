extends Node2D

@onready var particles: GPUParticles2D = $GPUParticles2D

func _ready() -> void:
	particles.emitting = true
	# 當裡面的粒子播放完畢時，把整個包裝盒 (自己) 刪除
	particles.finished.connect(func(): queue_free())
