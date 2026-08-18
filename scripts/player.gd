extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

# Чувствительность мыши (подкрути под себя)
const MOUSE_SENSITIVITY = 0.003

# Ссылки на узлы головы и камеры
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

func _ready() -> void:
	# Прячем курсор мыши при старте игры
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# Если двигаем мышкой
	if event is InputEventMouseMotion:
		# Поворачиваем персонажа влево-вправо
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		# Поворачиваем голову вверх-вниз
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		# Ограничиваем обзор вверх/вниз, чтобы шея не сломалась (на 89 градусов)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		
	# Если нажали ESC — возвращаем курсор
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Гравитация
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Прыжок
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Вектор движения
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# ВАЖНО: теперь движение считается относительно направления взгляда головы!
	var direction := (head.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
