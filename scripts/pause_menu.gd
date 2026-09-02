extends Control

@onready var color_rect: ColorRect = $ColorRect

func _ready() -> void:
	# Полностью скрываем меню и сбрасываем размытие при старте
	hide()
	set_blur_weight(0.0)

func _input(event: InputEvent) -> void:
	# Если игра на паузе И нажата кнопка pause
	if get_tree().paused and event.is_action_pressed("pause"):
		# Говорим Godot, что мы обработали это нажатие, чтобы оно не шло дальше
		get_viewport().set_input_as_handled() 
		toggle_pause() # Выключаем паузу

func toggle_pause() -> void:
	# 1. Переключаем состояние паузы всей игры
	get_tree().paused = !get_tree().paused
	
	# 2. Отрабатываем логику в зависимости от нового состояния
	if get_tree().paused:
		show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Показываем курсор
		animate_blur(2.5, 0.15) # Плавно включаем размытие
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Прячем курсор в 3D
		animate_blur(0.0, 0.1) # Быстро убираем размытие
		await get_tree().create_timer(0.1).timeout # Ждем окончания анимации
		hide()

# Функция для плавной анимации ползунка шейдера
func animate_blur(target_value: float, duration: float) -> void:
	var tween = create_tween()
	# Анимируем параметр "blur_amount" внутри ShaderMaterial
	tween.tween_method(set_blur_weight, get_blur_weight(), target_value, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

# Вспомогательный метод для получения текущего значения размытия из шейдера
func get_blur_weight() -> float:
	if color_rect.material and color_rect.material is ShaderMaterial:
		return color_rect.material.get_shader_parameter("blur_amount")
	return 0.0

# Вспомогательный метод для записи значения размытия в шейдер
func set_blur_weight(value: float) -> void:
	if color_rect.material and color_rect.material is ShaderMaterial:
		color_rect.material.set_shader_parameter("blur_amount", value)

# --- Сигналы кнопок ---

func _on_resume_button_pressed() -> void:
	toggle_pause() # Снимаем с паузы

func _on_quit_button_pressed() -> void:
	get_tree().quit() # Закрываем игру
