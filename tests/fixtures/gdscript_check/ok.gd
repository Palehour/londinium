extends CharacterBody2D

signal pressed

@onready var body: Node2D = null
@export var speed: float = 1.0
@export_range(0, 10) var armor: int = 0

func _ready() -> void:
	pressed.connect(_on_pressed)

func _physics_process(_delta: float) -> void:
	move_and_slide()

func _on_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
