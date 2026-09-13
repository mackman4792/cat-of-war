extends CharacterBody3D

# ХАРАКТЕРИСТИКИ ВРАГА
@export var health: float = 100.0
@export var speed: float = 4.0
@export var damage_to_player: float = 8.0
@export var fov_angle: float = 75.0
@export var patrol_points: Array[Vector3] = [] 
var last_known_position: Vector3 = Vector3.ZERO
var wall_ray: RayCast3D
var foot_wall_ray: RayCast3D 
var cliff_ray: RayCast3D
var strafe_timer: float = 0.0
var strafe_dir: float = 1.0
var _potential_player: CharacterBody3D = null
var current_patrol_index: int = 0

# НАСТРОЙКИ ПАТРУЛИРОВАНИЯ И ИИ
@onready var shoot_timer: Timer = $ShootTimer
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var spawn_position: Vector3 = Vector3.ZERO  # Центр зоны патруля
var current_patrol_target: Vector3 = Vector3.ZERO  # Куда бот идёт прямо сейчас
const MAX_RADIUS: float = 7.0  
const MIN_RADIUS: float = 3.0  

enum AIState { PATROL, CHASE, STUNNED, INVESTIGATE }
var current_ai_state: AIState = AIState.PATROL
var safety_cooldown: float = 0.0  

# ФИЗИКА ИМПУЛЬСА
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
	
	# Ждем синхронизации навигационного сервера
	await get_tree().physics_frame
	
	# 1. Луч для детекции стен (колени)
	wall_ray = RayCast3D.new()
	add_child(wall_ray)
	wall_ray.enabled = true
	wall_ray.position = Vector3(0, 0.4, 0)
	wall_ray.target_position = Vector3(0, 0, -1.5) 
	wall_ray.add_exception(self)

	# 2. Луч для детекции препятствий у самого пола (стопы)
	foot_wall_ray = RayCast3D.new()
	add_child(foot_wall_ray)
	foot_wall_ray.enabled = true
	foot_wall_ray.position = Vector3(0, 0.1, 0)
	foot_wall_ray.target_position = Vector3(0, 0, -1.5)
	foot_wall_ray.add_exception(self)
	
	# 3. Луч для детекции пропасти
	cliff_ray = RayCast3D.new()
	add_child(cliff_ray)
	cliff_ray.enabled = true
	cliff_ray.position = Vector3(0, 0.1, -0.5)
	cliff_ray.target_position = Vector3(0, -2.0, -1.0)
	cliff_ray.add_exception(self)

	spawn_position = global_position
	_generate_new_random_target()
	
func _physics_process(delta: float) -> void:
	if health <= 0.0: return
		# Уменьшаем таймер безопасности в каждом кадре
	if safety_cooldown > 0.0:
		safety_cooldown -= delta

	if fire_cooldown > 0.0:
		fire_cooldown -= delta
	else:
		fire_cooldown = 0.0

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0

	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)

	velocity.x = 0
	velocity.z = 0

	_check_vision_cone_logic(delta)

	match current_ai_state:
		AIState.PATROL:
			_process_patrol(delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.INVESTIGATE:
			_process_investigate(delta)
		AIState.STUNNED:
			velocity.x = 0
			velocity.z = 0
			if knockback_velocity.length() < 0.5:
				current_ai_state = AIState.CHASE 

	velocity.x += knockback_velocity.x
	velocity.z += knockback_velocity.z
	velocity.y += knockback_velocity.y

	move_and_slide()

func _process_patrol(delta: float) -> void:
	if safety_cooldown > 0.0:
		safety_cooldown -= delta
	else:
		safety_cooldown = 0.0

	# --- ТВОЯ ПРОВЕРКА НА СТЕНУ ИЛИ ПРОПАСTЬ ---
	if safety_cooldown <= 0.0:
		var hit_wall: bool = false
		if wall_ray.is_colliding():
			var collider = wall_ray.get_collider()
			if collider != target_player and collider != _potential_player:
				hit_wall = true

		if foot_wall_ray.is_colliding():
			var collider = foot_wall_ray.get_collider()
			if collider != target_player and collider != _potential_player:
				hit_wall = true

		if hit_wall or not cliff_ray.is_colliding():
			_generate_new_random_target()
			safety_cooldown = 0.5
			return
	# --------------------------------------

	# КРИТИЧЕСКИЙ ФИКС: Задаем цель агенту ТОЛЬКО если она поменялась в памяти,
	# чтобы не спамить поиском пути каждый кадр!
	if nav_agent.target_position != current_patrol_target:
		nav_agent.target_position = current_patrol_target
	
	# Если дошли — генерируем новую точку
	if nav_agent.is_target_reached():
		_generate_new_random_target()
		return
		
	var next_path_pos = nav_agent.get_next_path_position()
	var dir = global_position.direction_to(next_path_pos)
	dir.y = 0.0
	dir = dir.normalized()
	
	_smooth_look_at(global_position + dir, delta)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
func _process_chase(delta: float) -> void:
	if not target_player or ("is_dead" in target_player and target_player.is_dead):
		_lose_player()
		return

	var is_visible = _is_player_in_cone_vision()

	if is_visible:
		_shoot_at_player()
		_smooth_look_at(target_player.global_position, delta)
		last_known_position = target_player.global_position
		nav_agent.target_position = last_known_position
	else:
		# Если потерял из виду — бежим строго к последней точке
		nav_agent.target_position = last_known_position
		var next_nav = nav_agent.get_next_path_position()
		_smooth_look_at(next_nav, delta)

	# ЧЕСТНЫЙ ЧЕК РАССТОЯНИЯ: считаем плоскую дистанцию до угла стены
	var my_pos_flat = Vector3(global_position.x, 0.0, global_position.z)
	var target_pos_flat = Vector3(last_known_position.x, 0.0, last_known_position.z)
	var distance_to_corner = my_pos_flat.distance_to(target_pos_flat)

	# Если мы не видим игрока И добежали до угла ближе чем на 1.5 метра (и там пусто)
	if not is_visible and (distance_to_corner < 1.5 or nav_agent.is_target_reached()):
		_lose_player()
		return

	strafe_timer -= delta
	if strafe_timer <= 0.0:
		strafe_timer = randf_range(0.8, 1.5)
		strafe_dir = 1.0 if randf() > 0.5 else -1.0

	var dir_to_target = (last_known_position - global_position)
	dir_to_target.y = 0.0
	var distance_to_player = dir_to_target.length()
	
	var next_path_pos = nav_agent.get_next_path_position()
	var forward = global_position.direction_to(next_path_pos)
	forward.y = 0.0
	forward = forward.normalized()
	
	var right = forward.cross(Vector3.UP).normalized()
	var calculated_velocity = Vector3.ZERO
	
	if distance_to_player > 3.5:
		var final_dir = (forward + right * strafe_dir * 0.3).normalized()
		calculated_velocity = final_dir * (speed * 1.5)
	elif distance_to_player > 2.0:
		var final_dir = (forward * 0.6 + right * strafe_dir * 0.8).normalized()
		calculated_velocity = final_dir * (speed * 1.2)
	else:
		# Если не видим — бежим только вперед к углу, не пятимся!
		var final_dir = (forward + right * strafe_dir * 0.5).normalized() if not is_visible else (-forward * 0.8 + right * strafe_dir * 0.5).normalized()
		calculated_velocity = final_dir * speed

	if is_visible:
		velocity.x = calculated_velocity.x
		velocity.z = calculated_velocity.z
	else:
		# Накинем скорости при потере из виду (0.8 вместо 0.5), чтобы они бодрее бежали проверять угол
		velocity.x = calculated_velocity.x * 0.8
		velocity.z = calculated_velocity.z * 0.8

func _process_investigate(delta: float) -> void:
	if _potential_player and _is_player_in_cone_vision():
		target_player = _potential_player
		current_ai_state = AIState.CHASE
		return

	# Если агент дошел до точки шума — возвращаемся в патруль
	if nav_agent.is_target_reached():
		current_ai_state = AIState.PATROL
		_generate_new_random_target()
		return
		
	var next_path_pos = nav_agent.get_next_path_position()
	var dir = global_position.direction_to(next_path_pos)
	dir.y = 0.0
	dir = dir.normalized()
	
	_smooth_look_at(global_position + dir, delta)
	velocity.x = dir.x * (speed * 1.3) 
	velocity.z = dir.z * (speed * 1.3)
	
func _shoot_at_player() -> void:
	if fire_cooldown > 0.01 or not target_player: 
		return
		
	if "is_dead" in target_player and target_player.is_dead:
		return

	var player_target_pos = target_player.global_position + Vector3(0, 0.5, 0)
	
	$RayCastCenter.target_position = $RayCastCenter.to_local(player_target_pos)
	$RayCastCenter.force_raycast_update()
	
	if $RayCastCenter.is_colliding() and $RayCastCenter.get_collider() == target_player:
		fire_cooldown = FIRE_RATE
		if target_player.has_method("take_damage"):
			target_player.take_damage(damage_to_player)

func _on_vision_area_body_entered(body: Node) -> void:
	if "Player" in body.name or (body.get_parent() and "Player" in body.get_parent().name):
		var found_node = body.get_parent() if body.name != "Player" else body
		_potential_player = found_node as CharacterBody3D
		
		if current_ai_state == AIState.CHASE:
			target_player = _potential_player

func _on_vision_area_body_exited(body: Node) -> void:
	if body == _potential_player:
		_potential_player = null
	if body == target_player and current_ai_state != AIState.STUNNED:
		_lose_player()

func _check_vision_cone_logic(_delta: float) -> void:
	if (current_ai_state == AIState.PATROL or current_ai_state == AIState.INVESTIGATE) and _potential_player:
		if _is_player_in_cone_vision():
			target_player = _potential_player
			current_ai_state = AIState.CHASE
			print("ВРАГ ЗАМЕТИЛ ИГРОКА! Перехожу в CHASE.")

func _is_player_in_cone_vision() -> bool:
		# Если мы только что потеряли игрока и бот еще "соображает" — зрение временно спит
	if safety_cooldown > 0.0: 
		return false

	var current_target = target_player if target_player else _potential_player
	if not current_target: 
		return false
	
	var enemy_floor_pos = global_position
	var player_floor_pos = current_target.global_position
	var to_player = (player_floor_pos - enemy_floor_pos)
	to_player.y = 0.0
	
	if to_player.is_zero_approx(): 
		return false
	to_player = to_player.normalized()
	
	var forward_dir = -global_transform.basis.z 
	var angle_deg = rad_to_deg(forward_dir.angle_to(to_player))
	
	if angle_deg <= (fov_angle / 2.0):
		var player_target_pos = current_target.global_position + Vector3(0, 0.5, 0)
		var left_offset = current_target.global_transform.basis.x * -0.4
		var right_offset = current_target.global_transform.basis.x * 0.4
		
		$RayCastCenter.target_position = $RayCastCenter.to_local(player_target_pos)
		$RayCastLeft.target_position = $RayCastLeft.to_local(player_target_pos + left_offset)
		$RayCastRight.target_position = $RayCastRight.to_local(player_target_pos + right_offset)
		
		$RayCastCenter.force_raycast_update()
		$RayCastLeft.force_raycast_update()
		$RayCastRight.force_raycast_update()
		
		var hit_center: bool = $RayCastCenter.is_colliding() and $RayCastCenter.get_collider() == current_target
		var hit_left: bool = $RayCastLeft.is_colliding() and $RayCastLeft.get_collider() == current_target
		var hit_right: bool = $RayCastRight.is_colliding() and $RayCastRight.get_collider() == current_target
		
		if hit_center or hit_left or hit_right:
			return true
			
	return false

func _lose_player() -> void:
	target_player = null
	
	# КРИТИЧЕСКИЙ ФИКС: Сбрасываем сохраненную точку в позицию самого бота,
	# чтобы навигатор больше не пытался бежать внутрь блока GridMap!
	last_known_position = global_position 
	
	# Даем таймеру безопасности (safety_cooldown) 1.5–2 секунды.
	# Пока тикает этот таймер, бот не будет пытаться снова включить зрение на Артёма сквозь этот угол!
	safety_cooldown = 2.0 
	
	# Для обычного врага ставим PATROL, для часового — RETURN_TO_POST
	if "post_position" in self:
		current_ai_state = AIState.PATROL
	else:
		current_ai_state = AIState.PATROL

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
		_die()

# НОВАЯ ФУНКЦИЯ: СЛУХ ВРАГА
func hear_noise(noise_position: Vector3) -> void:
	if current_ai_state == AIState.CHASE or current_ai_state == AIState.STUNNED or health <= 0.0: 
		return
	
	current_ai_state = AIState.INVESTIGATE
	nav_agent.target_position = noise_position

func _find_player_globally() -> void:
	if target_player == null:
		var root = get_tree().current_scene
		var found_player = root.find_child("Player", true, false)
		if found_player:
			target_player = found_player as CharacterBody3D

func _smooth_look_at(target: Vector3, delta: float) -> void:
	# Игнорируем разницу по высоте, чтобы бота не наклоняло в пол
	var target_flat = Vector3(target.x, global_position.y, target.z)
	
	# Если точка взгляда находится слишком близко к телу бота (меньше 20 см) — не крутимся, 
	# иначе начнется бешеная тряска
	if global_position.distance_to(target_flat) < 0.2: 
		return
		
	var look_transform = global_transform.looking_at(target_flat, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(look_transform.basis, 6.0 * delta)

func _generate_new_random_target() -> void:
	var random_angle = randf_range(0.0, TAU) 
	var random_distance = randf_range(MIN_RADIUS, MAX_RADIUS)
	var offset = Vector3(
		cos(random_angle) * random_distance, 
		0.0, 
		sin(random_angle) * random_distance
	)
	current_patrol_target = spawn_position + offset

func _die() -> void:
	queue_free()
