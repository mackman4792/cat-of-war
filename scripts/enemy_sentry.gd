extends CharacterBody3D

# ХАРАКТЕРИСТИКИ ЧАСОВОГО
@export var health: float = 100.0
@export var speed: float = 4.0
@export var damage_to_player: float = 8.0
@export var fov_angle: float = 75.0
var last_known_position: Vector3 = Vector3.ZERO
var strafe_timer: float = 0.0
var strafe_dir: float = 1.0
var _potential_player: CharacterBody3D = null
var safety_cooldown: float = 0.0

# НАСТРОЙКИ ИИ (С НАВИГАЦИЕЙ И ТОЧКОЙ ПОСТА)
@onready var shoot_timer: Timer = $ShootTimer
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var post_position: Vector3 = Vector3.ZERO  # Координаты поста часового
var post_rotation: Basis = Basis.IDENTITY  # Направление взгляда на посту

# ДОБАВИЛИ СОСТОЯНИЯ: INVESTIGATE (на шум) и RETURN_TO_POST (назад на пост)
enum AIState { IDLE, CHASE, STUNNED, INVESTIGATE, RETURN_TO_POST }
var current_ai_state: AIState = AIState.IDLE

# ФИЗИКА ИМПУЛЬСА (ОТЛЕТ ОТ ТАРАНА И ПИНКА)
var knockback_velocity: Vector3 = Vector3.ZERO
const KNOCKBACK_FRICTION = 16.0 

# СТРЕЛЬБА И ЦЕЛЬ
const FIRE_RATE = 0.6
var fire_cooldown: float = 0.0
var target_player: CharacterBody3D = null
@onready var vision_area: Area3D = $VisionArea

func _ready() -> void:
	if shoot_timer:
		shoot_timer.one_shot = true
		shoot_timer.wait_time = FIRE_RATE
		
	# Ждем синхронизации навигации
	await get_tree().physics_frame
	
	# Запоминаем стартовую позицию и разворот часового как его вечный пост
	post_position = global_position
	post_rotation = global_transform.basis

func _physics_process(delta: float) -> void:
	if health <= 0.0: return
		# Уменьшаем таймер безопасности в каждом кадре
	if safety_cooldown > 0.0:
		safety_cooldown -= delta

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

	# 3. Честная проверка конуса зрения
	if current_ai_state != AIState.CHASE:
		_check_vision_cone_logic(delta)


	# 4. Машина состояний Часового
	match current_ai_state:
		AIState.IDLE:
			velocity.x = 0
			velocity.z = 0
		AIState.CHASE:
			_process_chase(delta)
		AIState.INVESTIGATE:
			_process_investigate(delta) # Будет во второй части
		AIState.RETURN_TO_POST:
			_process_return_to_post(delta) # Будет во второй части
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

func _process_chase(delta: float) -> void:
	if not target_player or ("is_dead" in target_player and target_player.is_dead):
		_lose_player()
		return

	# Честно проверяем, виден ли игрок прямо сейчас через лучи
	var is_visible = _is_player_in_cone_vision()

	if is_visible:
		# Видим — стреляем и пишем актуальную точку
		_shoot_at_player()
		_smooth_look_at(target_player.global_position, delta)
		last_known_position = target_player.global_position
		nav_agent.target_position = last_known_position
	else:
		# Потеряли — жестко фиксируем взгляд на угле стены, БЕЗ пересчета на технические точки навигатора
		_smooth_look_at(last_known_position, delta)
		nav_agent.target_position = last_known_position

	# Считаем плоское расстояние до угла, где Артём скрылся
	var my_pos_flat = Vector3(global_position.x, 0.0, global_position.z)
	var target_pos_flat = Vector3(last_known_position.x, 0.0, last_known_position.z)
	var distance_to_corner = my_pos_flat.distance_to(target_pos_flat)

	# Если часовой добежал до угла ближе чем на 1.6 метра, а игрока там нет — возвращаемся на пост
	if not is_visible and (distance_to_corner < 1.6 or nav_agent.is_target_reached()):
		_lose_player() # Включает RETURN_TO_POST
		return

	# Твоя механика стрейфа
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
		var final_dir = (forward + right * strafe_dir * 0.5).normalized() if not is_visible else (-forward * 0.8 + right * strafe_dir * 0.5).normalized()
		calculated_velocity = final_dir * speed
	if is_visible:
		velocity.x = calculated_velocity.x
		velocity.z = calculated_velocity.z
	else:
		# Бежим к углу на хорошей скорости
		velocity.x = calculated_velocity.x * 0.8
		velocity.z = calculated_velocity.z * 0.8

# НОВАЯ ФУНКЦИЯ: ДВИЖЕНИЕ НА ШУМ ППС
func _process_investigate(delta: float) -> void:
	if _potential_player and _is_player_in_cone_vision():
		target_player = _potential_player
		current_ai_state = AIState.CHASE
		return

	# Если пришли на точку звука, а там пусто — командуем возвращаться на пост
	if nav_agent.is_target_reached():
		current_ai_state = AIState.RETURN_TO_POST
		return
		
	var next_path_pos = nav_agent.get_next_path_position()
	var dir = global_position.direction_to(next_path_pos)
	dir.y = 0.0
	dir = dir.normalized()
	
	_smooth_look_at(global_position + dir, delta)
	velocity.x = dir.x * (speed * 1.3) 
	velocity.z = dir.z * (speed * 1.3)

# НОВАЯ ФУНКЦИЯ: ВОЗВРАЩЕНИЕ НА СВОЙ ПОСТ
func _process_return_to_post(delta: float) -> void:
	if _potential_player and _is_player_in_cone_vision():
		target_player = _potential_player
		current_ai_state = AIState.CHASE
		return

	nav_agent.target_position = post_position
	
	# Если дошли до поста — замираем и плавно разворачиваем лицо в исходную сторону
	if nav_agent.is_target_reached():
		current_ai_state = AIState.IDLE
		global_transform.basis = global_transform.basis.slerp(post_rotation, 6.0 * delta)
		return
		
	var next_path_pos = nav_agent.get_next_path_position()
	var dir = global_position.direction_to(next_path_pos)
	dir.y = 0.0
	dir = dir.normalized()
	
	_smooth_look_at(global_position + dir, delta)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

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
	# Теперь часовой проверяет зрение в IDLE, при беге на шум и при возвращении обратно!
	var can_spot = [AIState.IDLE, AIState.INVESTIGATE, AIState.RETURN_TO_POST].has(current_ai_state)
	if can_spot and _potential_player:
		if _is_player_in_cone_vision():
			target_player = _potential_player
			current_ai_state = AIState.CHASE
func _is_player_in_cone_vision() -> bool:
		# Если мы только что потеряли игрока и бот еще "соображает" — зрение временно спит
	if safety_cooldown > 0.0: 
		return false

	var check_target = target_player if target_player else _potential_player
	if not check_target:
		check_target = get_tree().current_scene.find_child("Player", true, false)
		
	if not check_target: 
		return false
	
	var enemy_floor_pos = global_position
	var player_floor_pos = check_target.global_position
	var to_player = (player_floor_pos - enemy_floor_pos)
	to_player.y = 0.0
	
	if to_player.is_zero_approx(): 
		return false
	to_player = to_player.normalized()
	
	var forward_dir = -global_transform.basis.z 
	var angle_deg = rad_to_deg(forward_dir.angle_to(to_player))
	
	if angle_deg <= (fov_angle / 2.0):
		# Стреляем лучами из уровня глаз врага в центр игрока
		var origin_pos = global_position + Vector3(0, 1.0, 0)
		var target_pos = check_target.global_position + Vector3(0, 0.5, 0)
		
		# ПРЯМОЙ ОПРОС ФИЗИЧЕСКОГО МИРА (Обходит баги ноды RayCast3D)
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(origin_pos, target_pos)
		
		# Исключаем самого себя из проверки, чтобы не врезаться в свою коллизию
		query.exclude = [get_rid()] 
		# Насильно заставляем луч проверять Слой 1 (GridMap)
		query.collision_mask = 1 | 2 | 3 
		
		var result = space_state.intersect_ray(query)
		
		if result:
			var collider = result.collider
			# Если на пути луча встал сам игрок — значит стены нет, мы его видим!
			if collider == check_target or collider.get_parent() == check_target:
				if not target_player:
					_potential_player = check_target
				return true
				
		# Если луч уперся в призрачную GridMap/дверь или ничего не нашел — утеря видимости!
		return false
			
	return false

# НОВАЯ ФУНКЦИЯ: СЛУХ ЧАСОВОГО
func hear_noise(noise_position: Vector3) -> void:
	if current_ai_state == AIState.CHASE or current_ai_state == AIState.STUNNED or health <= 0.0: 
		return
	
	current_ai_state = AIState.INVESTIGATE
	nav_agent.target_position = noise_position
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
		current_ai_state = AIState.RETURN_TO_POST


func take_ram_damage(amount: float, impulse: Vector3) -> void:
	health -= amount
	knockback_velocity = impulse
	current_ai_state = AIState.STUNNED 
	_find_player_globally()
	print("Часовой сбит тараном! ХП: ", health)
	if health <= 0.0: _die()

func take_damage(amount: float, hit_zone: String = "body") -> void:
	var final_damage = amount
	if hit_zone == "head":
		final_damage = amount * 5.2
		print("Часовому в голову! Урон: ", final_damage)
	else:
		print("Попадание в туловище часового. Урон: ", final_damage)
		
	health -= final_damage
	_find_player_globally()
	current_ai_state = AIState.CHASE
	if health <= 0.0: _die()

func _find_player_globally() -> void:
	if target_player == null:
		var root = get_tree().current_scene
		var found_player = root.find_child("Player", true, false)
		if found_player:
			target_player = found_player as CharacterBody3D

func _smooth_look_at(target: Vector3, delta: float) -> void:
	var target_flat = Vector3(target.x, global_position.y, target.z)
	if global_position.distance_to(target_flat) < 0.2: 
		return
	var look_transform = global_transform.looking_at(target_flat, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(look_transform.basis, 6.0 * delta)

func _die() -> void:
	print("да блинаа часовой упал :(")
	queue_free()
