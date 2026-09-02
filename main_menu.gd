extends Control

# Указываем твою главную игровую сцену
@export_file("*.tscn") var game_level_scene: String = "res://scenes/main.tscn"

func _ready() -> void:
	# Освобождаем мышь для кликов
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_play_pressed() -> void:

	get_tree().change_scene_to_file(game_level_scene)

func _on_exit_pressed() -> void:
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
