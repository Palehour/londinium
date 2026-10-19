extends KinematicBody2D

# yield stays in this comment and must not be reported.

onready var body = null
export var speed = 1
export(int, 0, 100) var armor = 0

func _ready():
	yield(get_tree(), "idle_frame")
	connect("pressed", self, "_on_pressed")
