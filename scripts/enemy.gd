extends CharacterBody3D

# ХАРАКТЕРИСТИКИ ВРАГА
@export var health: float = 100.0
@export var speed: float = 4.0
@export var damage_to_player: float = 8.0
@export var fov_angle: float = 75.0

var strafe_timer: float = 0.0
var strafe_dir: float = 1.0
var _potential_player: CharacterBody3D = null

# НАСТРОЙКИ ПАТРУЛИРОВАНИЯ И ИИ
@onready var shoot_timer: Timer = $ShootTimer
@export var patrol_points: Array[Vector3] = [] 
var current_patrol_index: int = 0

enum AIState { PATROL, CHASE, STUNNED }
var current_ai_state: AIState = AIState.PATROL

# ФИЗИКА ИМПУЛЬСА (ОТЛЕТ ОТ ТАРАНА И ПИНКА)
var knockback_velocity: Vector3 = Vector3.ZERO
const KNOCKBACK_FRICTION = 16.0 

# СТРЕЛЬБА И ЦЕЛЬ
const FIRE_RATE = 0.6
var fire_cooldown: float = 0.0
var target_player: CharacterBody3D = null
@onready var vision_area: Area3D = $VisionArea
@onready var ai_raycast: RayCast3D = $RayCast3D

func _ready() -> void:
	if shoot_timer:
		shoot_timer.one_shot = true
		shoot_timer.wait_time = FIRE_RATE

func _physics_process(delta: float) -> void:
	if health <= 0.0: return
	
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
	else:
		fire_cooldown = 0.0

	# 1. Применяем гравитацию
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0

	# 2. Плавно гасим импульс отброса
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)

	# ЗДЕСЬ СБРАСЫВАЕМ СКОРОСТЬ
	velocity.x = 0
	velocity.z = 0

	# !!! ВОТ ЭТА СТРОЧКА ОБЯЗАТЕЛЬНО ДОЛЖНА БЫТЬ ТУТ !!!
	_check_vision_cone_logic(delta)

	# 4. Машина состояний ИИ
	match current_ai_state:
		AIState.PATROL:
			_process_patrol(delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.STUNNED:
			velocity.x = 0
			velocity.z = 0
			if knockback_velocity.length() < 0.5:
				current_ai_state = AIState.CHASE 

	# 5. Накладываем импульс отброса ПОВЕРХ шагов ИИ
	velocity.x += knockback_velocity.x
	velocity.z += knockback_velocity.z
	velocity.y += knockback_velocity.y

	# 6. Двигаем тело
	move_and_slide()

# ЛОГИКА ПАТРУЛИРОВАНИЯ
func _process_patrol(delta: float) -> void:
	if patrol_points.is_empty(): 
		return
	
	var target_pos = patrol_points[current_patrol_index]
	var dir = (target_pos - global_position)
	dir.y = 0.0
	
	if dir.length() < 0.5:
		current_patrol_index += 1
		if current_patrol_index >= patrol_points.size():
			current_patrol_index = 0
	else:
		dir = dir.normalized()
		_smooth_look_at(global_position + dir, delta)
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed

# ЛОГИКА ПРЕСЛЕДОВАНИЯ И СТРЕЙФА (Интегрирована первая часть вашего кода)
func _process_chase(delta: float) -> void:
	if not target_player or ("is_dead" in target_player and target_player.is_dead):
		_lose_player()
		return
		
	# Железобетонный выстрел и разворот лица
	_shoot_at_player()
	_smooth_look_at(target_player.global_position, delta)

	# Таймер стрейфа
	strafe_timer -= delta
	if strafe_timer <= 0.0:
		strafe_timer = randf_range(0.8, 1.5)
		strafe_dir = 1.0 if randf() > 0.5 else -1.0

	var dir_to_player = (target_player.global_position - global_position)
	dir_to_player.y = 0.0
	var distance = dir_to_player.length()
	var forward = dir_to_player.normalized()
	var right = forward.cross(Vector3.UP).normalized()
	var calculated_velocity = Vector3.ZERO
	
	# Расчет движения в зависимости от дистанции
	if distance > 3.5:
		var final_dir = (forward + right * strafe_dir * 0.3).normalized()
		calculated_velocity = final_dir * (speed * 1.5)
	elif distance > 2.0:
		var final_dir = (forward * 0.6 + right * strafe_dir * 0.8).normalized()
		calculated_velocity = final_dir * (speed * 1.2)
	else:
		var final_dir = (-forward * 0.8 + right * strafe_dir * 0.5).normalized()
		calculated_velocity = final_dir * speed

	# Проверка физической видимости для изменения скорости (в окопе медленнее)
	if _is_player_in_cone_vision():
		velocity.x = calculated_velocity.x
		velocity.z = calculated_velocity.z
	else:
		# Если потеряли из виду в процессе погони — замедляемся
		velocity.x = calculated_velocity.x * 0.5
		velocity.z = calculated_velocity.z * 0.5

func _shoot_at_player() -> void:
	if fire_cooldown > 0.01 or not target_player: 
		return
		
	if "is_dead" in target_player and target_player.is_dead:
		return

	# Целимся на ту же высоту (0.5), что и при проверке зрения
	var player_target_pos = target_player.global_position + Vector3(0, 0.5, 0)
	
	$RayCastCenter.target_position = $RayCastCenter.to_local(player_target_pos)
	$RayCastCenter.force_raycast_update()
	
	if $RayCastCenter.is_colliding() and $RayCastCenter.get_collider() == target_player:
		fire_cooldown = FIRE_RATE
		print("[ИИ УЗЕЛ] Честное попадание по Артёму!")
		if target_player.has_method("take_damage"):
			target_player.take_damage(damage_to_player)


func _on_vision_area_body_entered(body: Node) -> void:
	if "Player" in body.name or (body.get_parent() and "Player" in body.get_parent().name):
		var found_node = body.get_parent() if body.name != "Player" else body
		_potential_player = found_node as CharacterBody3D
		
		# Если мы УЖЕ гонимся (например, сагрились от урона), сразу пишем в цель
		if current_ai_state == AIState.CHASE:
			target_player = _potential_player

func _on_vision_area_body_exited(body: Node) -> void:
	if body == _potential_player:
		_potential_player = null
	if body == target_player and current_ai_state != AIState.STUNNED:
		_lose_player()

# Функция постоянной проверки конуса видимости
func _check_vision_cone_logic(_delta: float) -> void:
	if current_ai_state == AIState.PATROL and _potential_player:
		if _is_player_in_cone_vision():
			target_player = _potential_player
			current_ai_state = AIState.CHASE
			print("НАЦИСТ НАПРЯМУЮ ЗАМЕТИЛ АРТЁМА В КОНУСЕ ОБЗОРА! Перехожу в CHASE.")

func _is_player_in_cone_vision() -> bool:
	var current_target = target_player if target_player else _potential_player
	if not current_target: 
		return false
	
	# 1. Горизонтальный расчет угла (конус обзора)
	var enemy_floor_pos = global_position
	var player_floor_pos = current_target.global_position
	
	var to_player = (player_floor_pos - enemy_floor_pos)
	to_player.y = 0.0
	
	if to_player.is_zero_approx(): 
		return false
	to_player = to_player.normalized()
	
	# Проверка угла FOV
	var forward_dir = -global_transform.basis.z 
	var angle_deg = rad_to_deg(forward_dir.angle_to(to_player))
	
	if angle_deg <= (fov_angle / 2.0):
		# 2. Глобальные точки кастинга лучей (ОПУЩЕНЫ НИЖЕ ЛИЦА)
		# Сдвигаем начало лучей на уровень пояса высокого врага
		var _enemy_low_vision_pos = global_position + Vector3(0, 0.4, 0) 
		# Направляем лучи в центр тела Артёма
		var player_target_pos = current_target.global_position + Vector3(0, 0.5, 0)
		
		# Ширина Артёма (боковые лучи для детекции плеч/боков)
		var left_offset = current_target.global_transform.basis.x * -0.4
		var right_offset = current_target.global_transform.basis.x * 0.4
		
		# Направляем лучи из их текущего положения в пространстве
		$RayCastCenter.target_position = $RayCastCenter.to_local(player_target_pos)
		$RayCastLeft.target_position = $RayCastLeft.to_local(player_target_pos + left_offset)
		$RayCastRight.target_position = $RayCastRight.to_local(player_target_pos + right_offset)
		
		# Мгновенный апдейт физики лучей
		$RayCastCenter.force_raycast_update()
		$RayCastLeft.force_raycast_update()
		$RayCastRight.force_raycast_update()
		
		# Проверка коллизий
		var hit_center: bool = $RayCastCenter.is_colliding() and $RayCastCenter.get_collider() == current_target
		var hit_left: bool = $RayCastLeft.is_colliding() and $RayCastLeft.get_collider() == current_target
		var hit_right: bool = $RayCastRight.is_colliding() and $RayCastRight.get_collider() == current_target
		
		if hit_center or hit_left or hit_right:
			return true
			
	return false

func _lose_player() -> void:
	target_player = null
	current_ai_state = AIState.PATROL
	print("Цель потеряна, бот вернулся в патруль.")

# ПОЛУЧЕНИЕ УРОНА И ТАРАН
func take_ram_damage(amount: float, impulse: Vector3) -> void:
	health -= amount
	knockback_velocity = impulse
	current_ai_state = AIState.STUNNED 
	
	_find_player_globally()
	
	print("Бот сбит тараном! ХП: ", health)
	if health <= 0.0: _die()

func take_damage(amount: float, hit_zone: String = "body") -> void:
	var final_damage = amount
	if hit_zone == "head":
		final_damage = amount * 5.2
		print("Попадание в голову.. Урон: ", final_damage)
	else:
		print("Попадание в туловище. Урон: ", final_damage)
		
	health -= final_damage
	
	_find_player_globally()
	current_ai_state = AIState.CHASE
	
	if health <= 0.0:
		print("Собака-таблетка аннигилировалась!")
		_die()

func _find_player_globally() -> void:
	if target_player == null:
		var root = get_tree().current_scene
		var found_player = root.find_child("Player", true, false)
		
		if found_player:
			target_player = found_player as CharacterBody3D
			print("Бот взломал реальность и нашёл Артёма по имени узла!")

func _smooth_look_at(target: Vector3, delta: float) -> void:
	if global_position.is_equal_approx(target): return
	var look_transform = global_transform.looking_at(target, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(look_transform.basis, 6.0 * delta)

func _die() -> void:
	print("да блинаа :(")
	queue_free()
