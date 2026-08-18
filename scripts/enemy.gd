extends CharacterBody3D

# ХАРАКТЕРИСТИКИ ВРАГА
@export var health: float = 100.0
@export var speed: float = 16.0
@export var damage_to_player: float = 8.0
var strafe_timer: float = 0.0
var strafe_dir: float = 1.0

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

	# 3. Обнуляем горизонтальную скорость перед расчетом шагов
	velocity.x = 0
	velocity.z = 0

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
	if ai_raycast.is_colliding() and ai_raycast.get_collider() == target_player:
		velocity.x = calculated_velocity.x
		velocity.z = calculated_velocity.z
	else:
		velocity.x = calculated_velocity.x * 0.5
		velocity.z = calculated_velocity.z * 0.5

func _shoot_at_player() -> void:
	if fire_cooldown > 0.01 or not target_player: 
		return
		
	if "is_dead" in target_player and target_player.is_dead:
		return

	var target_pos = target_player.global_position + Vector3(0, 0.5, 0)
	ai_raycast.look_at(target_pos, Vector3.UP)
	ai_raycast.force_raycast_update()
	
	if ai_raycast.is_colliding():
		var collider = ai_raycast.get_collider()
		if collider == target_player:
			fire_cooldown = FIRE_RATE
			print("[ИИ УЗЕЛ] Честное попадание по Артёму!")
			if target_player.has_method("take_damage"):
				target_player.take_damage(damage_to_player)

# СИГНАЛЫ ВИДИМОСТИ
func _on_vision_area_body_entered(body: Node) -> void:
	if "Player" in body.name or (body.get_parent() and "Player" in body.get_parent().name):
		if body.name != "Player":
			target_player = body.get_parent() as CharacterBody3D
		else:
			target_player = body as CharacterBody3D
			
		current_ai_state = AIState.CHASE
		print("НАЦИСТ НАПРЯМУЮ ЗАМЕТИЛ АРТЁМА! Перехожу в CHASE.")

func _on_vision_area_body_exited(body: Node) -> void:
	if body == target_player and health >= 100.0:
		_lose_player()

func _lose_player() -> void:
	target_player = null
	current_ai_state = AIState.PATROL
	print("Цель потеряна, бот вернулся в патруль.")

# ПОЛУЧЕНИЕ УРОНА И ТАРАН (ИСПРАВЛЕНО: Теперь ищет Артема при получении урона!)
func take_ram_damage(amount: float, impulse: Vector3) -> void:
	health -= amount
	knockback_velocity = impulse
	current_ai_state = AIState.STUNNED 
	
	# Авто-агр на игрока по группе при таране
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
	
	# ИСПРАВЛЕНО: Если урон прилетел издалека/сзади, насильно ищем Артёма на карте
	_find_player_globally()
	current_ai_state = AIState.CHASE
	
	if health <= 0.0:
		print("Собака-таблетка аннигилировалась!")
		_die()

func _find_player_globally() -> void:
	if target_player == null:
		# Нагло ищем узел с именем Player на всей активной сцене
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
	queue_free()

func _can_see_player() -> bool:
	if not target_player: return false
	var space_state = get_world_3d().direct_space_state
	var start_pos = $MeshInstance3D.global_position + Vector3(0, 1.1, 0)
	var end_pos = target_player.global_position + Vector3(0, 1.2, 0)
	
	var query = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.collision_mask = 1 | 2
	
	var exceptions = [self.get_rid()]
	query.exclude = exceptions
	
	var result = space_state.intersect_ray(query)
	if result and result.collider == target_player:
		return true
		
	return false
