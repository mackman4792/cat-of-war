extends CharacterBody3D

# БАЗОВЫЕ НАСТРОЙКИ (НОРМАЛЬНЫЙ РОСТ ПЕРСОНАЖА)
var SPEED := 2.6
var JUMP_VELOCITY := 7.5  
var MOUSE_SENSITIVITY := 0.007
# --- НАСТРОЙКИ СИСТЕМЫ ВЕСА И РАЗГРУЗКИ ---
var current_weapon_weight: float = 0.0  # Вес текущего оружия в руках (например: Макаров = 0.0, Дробовик = 2.5)
var total_carried_weight: float = 0.0   # Общий вес ВСЕГО оружия за спиной
var health_ratio = clamp(health / MAX_HEALTH, 0.0, 1.0)
var adrenaline_multiplier = remap(health_ratio, 0.0, 1.0, 1.25, 1.0)
# Штраф от разгрузки (0.0 — базовая на 2 слота, 0.10 — от штурмовиков, 0.40 — тяжелая "танк" на 8 слотов)
var vest_weight_penalty: float = 0.0 
var ram_stun_timer: float = 0.0 # Таймер дезориентации от удара об стену
var air_control_lock_timer: float = 0.0 # Блокировка ввода в воздухе
var final_speed_modifier: float = 1.0  # Финальный множитель скорости (на сколько процентов режем бег)
var fov_cooldown: float = 0.0  # Таймер блокировки партизана
var block_dynamic_fov: bool = false # Выключатель для партизана

var ram_timer: float = 0.0
var ram_cooldown_timer: float = 0.0
var ram_direction: Vector3 = Vector3.ZERO

const AIR_CONTROL := 50.0
const AIR_SPEED_LIMIT = 50.0  # Максимальная скорость
const AIR_CONTROL_LIMIT = 4.0   # Макс. скорость, которую можно развить ТОЛЬКО КНОПКАМИ в воздухе
const AIR_ACCEL = 25.0          # Сила отзывчивости (чем выше, тем резче меняется направление)
const AIR_FRICTION = 0.2        # Почти нулевое торможение, чтобы не терять огромную скорость в полете

var can_sprint: bool = true # Разрешен ли бег в данный момент
var is_sprinting: bool = false
var is_leaning: bool = false

var max_jumps: int = 2
var jump_count: int = 0

# НАСТРОЙКИ СИСТЕМЫ СОСТОЯНИЙ И РЫВКА
enum State { NORMAL, DIVING, PRONE, SLIDING, RAMMING }
var current_state: State = State.NORMAL

const DIVE_FORCE := 5.5           
var PRONE_SPEED := 1.5            
var dive_timer: float = 0.0      
const DIVE_DURATION := 1.8       
var was_dive_triggered: bool = false

# НАСТРОЙКИ ЗАЖИМНОГО ПОДКАТА (SLIDE)
const SLIDE_INITIAL_FORCE = 5.0  
const SLIDE_MIN_SPEED = 0.1      
var slide_current_speed: float = 0.0
const SLIDE_CONTROL = 4.0        

# ХАРАКТЕРИСТИКИ ВЫСОТЫ ГОЛОВЫ
const BASE_HEAD_Y = 0.85         # Полный рост
const SLIDE_HEAD_Y = 0.45        # Подкат чуть выше, чтобы лучше видеть врагов при скольжении
const PRONE_HEAD_Y = 0.22        # Положение лёжа (пузом по земле)

# НАСТРОЙКИ ХЭДБОБИНГА
const BOB_FREQUENCY = 2.5     
const BOB_AMPLITUDE = 0.05    
const PRONE_BOB_FREQ = 2.0    
const PRONE_BOB_AMP_X = 0.05     
const PRONE_BOB_AMP_Y = 0.012    

var bob_time: float = 0.0     
var land_offset_y: float = 0.0   

# НАСТРОЙКИ FOV И СПРИНТА
var BASE_FOV: float = 89.0      
var SPRINT_FOV: float = 100.0    
var sprint_timer: float = 0.0
const SPRINT_DELAY: float = 0.2 
var maneuver_invul_time: float = 0.0

# ИММЕРСИВНЫЙ УДАР ПРИ ПРИЗЕМЛЕНИИ
var last_velocity_y: float = 0.0  
var land_bump: float = 0.0        
var land_tilt: float = 0.0        
var land_shake_x: float = 0.0     

# НАСТРОЙКИ НАКЛОНОВ (LEANING)
const LEAN_ANGLE = 12.0          
const LEAN_OFFSET = 0.32         
var target_lean_angle: float = 0.0
var target_lean_offset: float = 0.0
var lean_speed_modifier: float = 0.5  # <--- ДОБАВИТЬ: 1.0 (нет штрафа), 0.65 (замедлен на 35%)

# НАСТРОЙКИ СИСТЕМЫ ВЫНОСЛИВОСТИ И ПИНКА
var stamina: float = 100.0
const MAX_STAMINA = 100.0
const KICK_STAMINA_COST = 35.0  
const STAMINA_REGEN_SPEED = 15.0 
const KICK_DAMAGE = 40.0
const KICK_PUSH_FORCE = 15.0    

# НАСТРОЙКИ СИСТЕМЫ ЗДОРОВЬЯ
var health: float = 100.0
const MAX_HEALTH = 100.0
const REGEN_LIMIT = 30.0        
const HEALTH_REGEN_SPEED = 2.0  
var is_dead: bool = false

# ССЫЛКИ НА УЗЛЫ СЦЕНЫ
@onready var dead_music: AudioStreamPlayer = $dead
@onready var oh: AudioStreamPlayer = $oh
@onready var bg_music: AudioStreamPlayer = $BackgroundMusic
@onready var health_bar: TextureProgressBar = $Head/Camera3D/CanvasLayer/HealthBar
@onready var stamina_bar: TextureProgressBar = $Head/Camera3D/CanvasLayer/StaminaBar
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ceiling_ray: RayCast3D = $CeilingRay
@onready var ghost_rect: ColorRect = $Head/Camera3D/CanvasLayer/ColorRect
@onready var blood_rect: ColorRect = $Head/Camera3D/CanvasLayer/blood_rect
@onready var kick_cast: ShapeCast3D = $Head/Camera3D/KickCast

# ССЫЛКИ НА ТВОИ ХИТБОКСЫ
@onready var head_hitbox: CollisionShape3D = $HeadHitbox
@onready var body_hitbox: CollisionShape3D = $BodyHitbox
@onready var legs_hitbox: CollisionShape3D = $LegsHitbox

#АНИМАЦИИ
@onready var anim_suicide: AnimationPlayer = $Head/Camera3D/WeaponContainer/suicd

#ШЕЙДЕРЫ
@onready var panic_overlay: ColorRect = $Head/Camera3D/CanvasLayer/sorry
@onready var help_label: Label = $Head/Camera3D/CanvasLayer/Label # Проверь путь по дереву узлов слева!

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	head.position.y = BASE_HEAD_Y
	if ceiling_ray:
		ceiling_ray.add_exception(self)
	if kick_cast:
		kick_cast.add_exception(self)
func _unhandled_input(event: InputEvent) -> void:
		# 1. Сначала ПАУЗА (она должна работать ВСЕГДА, даже у трупа)
	if event.is_action_pressed("pause"):
		var pause_menu = $Head/Camera3D/CanvasLayer/PauseMenu
		if pause_menu:
			pause_menu.toggle_pause()
			return # Выходим, чтобы мертвый игрок не делал другие действия в этот кадр

	if is_dead: return

	if event is InputEventKey and event.keycode == KEY_K and help_label:
		# event.pressed возвращает true, когда кнопку нажали или держат, 
		# и false, когда её полностью отпустили
		if event.pressed:
			help_label.visible = true
			print("Кнопку удерживают, показываем помощь")
		else:
			help_label.visible = false
			print("Кнопку отпустили, прячем помощь")

	if event is InputEventMouseMotion:
		# ЕСЛИ ТАРАНИМ: режем чувствительность мыши в 15 раз (делаем камеру очень тяжелой)
		var current_sensitivity = MOUSE_SENSITIVITY
		if current_state == State.RAMMING:
			current_sensitivity = MOUSE_SENSITIVITY / 15.0
			
		rotate_y(-event.relative.x * current_sensitivity)
		head.rotate_x(-event.relative.y * current_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# Кнопка суицида на G
	if Input.is_action_just_pressed("suicide") and not is_dead and current_state == State.NORMAL:
		var weapon_ctrl = $Head/Camera3D/WeaponContainer
		anim_suicide.play("pew")
		
		if weapon_ctrl:
			var shader_mat = panic_overlay.material as ShaderMaterial
			if shader_mat:
				# За 0.2 секунды плавно размываем картинку и пускаем волны покачивания
				var tween_in = create_tween()
				tween_in.tween_property(shader_mat, "shader_parameter/panic_intensity", 1.0, 0.2)
				anim_suicide.play("pew")
			var suicide_tween = create_tween()
			suicide_tween.tween_interval(1.2) # 0.6 секунды смотрим на плывущий экран под анимацию
			
			suicide_tween.tween_callback(func():
				# Происходит роковой бабах со вспышкой!
				if weapon_ctrl.has_method("shoot_weapon"):
					weapon_ctrl.shoot_weapon()
				
				# МОМЕНТ ВЫСТРЕЛА: Полностью убираем мыло
				if shader_mat:
					shader_mat.set_shader_parameter("shader_parameter/panic_intensity", 0.0)
				
				# Твой старый код — тут здоровье падает в 0 и вызывается твой бордовый шейдер смерти
				health = 0.0
				die("suicide")
			)


func _physics_process(delta: float) -> void:
	if is_dead: return
	_handle_health_system(delta)
	if maneuver_invul_time > 0.0:
		maneuver_invul_time -= delta

	# ИЗМЕНЕНО: Добавили проверку "and can_sprint"цц
	if Input.is_action_pressed("sprint") and current_state == State.NORMAL and stamina > 0.0 and can_sprint:
		# УРОВЕНЬ 3: НЕИСТОВЫЙ СПРИНТ (на V) — Тратит 25 стамины в секунду (исходя из твоего move_toward)
		stamina = move_toward(stamina, 0.0, 25.0 * delta)
		var base_max_sprint = 11.0 * final_speed_modifier
		var absolute_max_sprint = base_max_sprint * adrenaline_multiplier

		SPEED = clamp(SPEED + 6.0 * delta, 2.6, absolute_max_sprint)
		
		var target_sens_drop = 0.003 * adrenaline_multiplier
		MOUSE_SENSITIVITY = clamp(MOUSE_SENSITIVITY - target_sens_drop * delta, 0.003, 0.007)
		JUMP_VELOCITY = clamp(JUMP_VELOCITY - 0.5 * delta, 5.5, 6.0)
		
		sprint_timer += delta
		if sprint_timer >= SPRINT_DELAY:
			max_jumps = 3
			
		# ИЗМЕНЕНО: Проверяем ноль ОДИН раз и сразу блочим can_sprint
		if stamina <= 0.001 and can_sprint:
			stamina = 0.0
			start_sprint_cooldown()
			
	elif Input.is_action_pressed("run") and current_state == State.NORMAL:
		# УРОВЕНЬ 2: ОБЫЧНЫЙ БЕГ (на Shift) — Не тратит стамину, но и НЕ регенерирует её
		var base_max_run = 5.5 * final_speed_modifier
		var absolute_max_run = base_max_run * adrenaline_multiplier
		SPEED = clamp(SPEED + 3.0 * delta, 2.6, absolute_max_run)
		MOUSE_SENSITIVITY = clamp(MOUSE_SENSITIVITY - 0.001 * delta, 0.005, 0.007)
		JUMP_VELOCITY = clamp(JUMP_VELOCITY - 0.2 * delta, 6.0, 6.8)
		sprint_timer = 0.0
		max_jumps = 2
		
	else:
		# УРОВЕНЬ 1: ТАКТИЧЕСКИЙ ШАГ / ХОДЬБА (без зажатых клавиш)
		# ИЗМЕНЕНО: Убрал отсюда дублирующуюся регенерацию, так как она все равно считается внизу скрипта
		var max_walk_speed = 3.5 * final_speed_modifier
		if max_walk_speed < 2.6: 
			max_walk_speed = 2.6
		
		SPEED = clamp(SPEED - 6.0 * delta, 2.6, max_walk_speed)
		MOUSE_SENSITIVITY = clamp(MOUSE_SENSITIVITY + 0.002 * delta, 0.004, 0.007)
		JUMP_VELOCITY = clamp(JUMP_VELOCITY - 0.5 * delta, 6.5, 7.5)
		sprint_timer = 0.0
		max_jumps = 2

	# --- ТАЙМЕРЫ ДЕЗОРИЕНТАЦИИ И БЛОКИРОВКИ ВВОДА ---
	if ram_stun_timer > 0.0:
		ram_stun_timer -= delta
	if air_control_lock_timer > 0.0:
		air_control_lock_timer -= delta

	# Считываем WASD
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# ЖЁСТКАЯ БЛОКИРОВКА ВВОДА: во время тарана ИЛИ если сработал воздушный лок (на 0.2 сек)
	if current_state == State.RAMMING or air_control_lock_timer > 0.0:
		input_dir = Vector2.ZERO
		
	var forward_basis = Basis.from_euler(Vector3(0.0, head.global_transform.basis.get_euler().y, 0.0))
	var direction := (forward_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Фиксация лока ввода, если прыгнули во время тарана
	if not is_on_floor() and current_state == State.RAMMING:
		air_control_lock_timer = 0.2

	# ИЗМЕНЕНО: Регенерация стамины теперь ЗАБЛОКИРОВАНА, если can_sprint == false (идет кулдаун 3 сек)
	if stamina < MAX_STAMINA and current_state != State.RAMMING and ram_stun_timer <= 0.0 and can_sprint:
		# Дополнительно: реген работает только если НЕ зажат обычный бег ("run"), как ты хотел на Уровне 2
		if not Input.is_action_pressed("run"):
			stamina = move_toward(stamina, MAX_STAMINA, STAMINA_REGEN_SPEED * delta)
	# --- ОБНОВЛЕННЫЙ БЛОК ТАРАНА С ЭФФЕКТОМ ОТСКОКА ОТ СТЕНЫ ---
	if current_state == State.RAMMING:
		ram_timer -= delta
		
		if is_on_wall() or ram_timer <= 0.0:
			if is_on_wall():
				# ВРЕЗАЛСЯ В СТЕНУ: Включаем контузию на 2 секунды!
				ram_stun_timer = 2.0
				land_bump = 0.25       
				land_tilt = 0.18       
				land_shake_x = randf_range(-0.08, 0.08) 
				take_damage(10.0)      
				print("ЖЕСТКАЯ КОНТУЗИЯ! Врезался лбом в стену окопа!")
				
				# ФИЗИЧЕСКИЙ ОТСКОК НАЗАД:
				# Толкаем игрока в противоположную от тарана сторону, чтобы отлипнуть от коллизии стены!
				var bounce_dir = -ram_direction.normalized()
				velocity.x = bounce_dir.x * 3.0 # Небольшая скорость отскока
				velocity.z = bounce_dir.z * 3.0
				velocity.y = 1.5                # Слегка подбрасываем вверх для сочности
			
			# ЖЕСТКИЙ СБРОС ВСЕХ ХВОСТОВ:
			current_state = State.NORMAL
			ram_timer = 0.0
			ram_cooldown_timer = 2.2 
		else:
			var camera_forward_dir = -forward_basis.z.normalized()
			ram_direction = camera_forward_dir
			var ram_penalty = (current_weapon_weight + total_carried_weight) * 0.05
			var current_ram_speed = max(6.0, 9.5 - ram_penalty)
			velocity.x = ram_direction.x * current_ram_speed
			velocity.z = ram_direction.z * current_ram_speed

	elif current_state == State.DIVING:
		dive_timer -= delta
		if dive_timer <= 0.0 or is_on_floor():
			if ceiling_ray and ceiling_ray.is_colliding():
				current_state = State.PRONE
				_change_collision_height(true)
			else:
				current_state = State.NORMAL
				was_dive_triggered = false
				_change_collision_height(false)
				
	elif current_state == State.SLIDING:
		slide_current_speed = lerp(slide_current_speed, 0.0, 0.8 * delta)
		if not Input.is_action_pressed("slide") or slide_current_speed <= SLIDE_MIN_SPEED:
			if ceiling_ray and ceiling_ray.is_colliding():
				current_state = State.PRONE
				_change_collision_height(true)
			else:
				current_state = State.NORMAL
				_change_collision_height(false)
	# ФИЗИКА ПАДЕНИЯ И ИММЕРСИВНЫЙ УДАР ПРИ ПРИЗЕМЛЕНИИ
	if not is_on_floor():
		velocity += get_gravity() * 1.6 * delta
		last_velocity_y = velocity.y
	else:
		if last_velocity_y < -1.0:
			var impact = abs(last_velocity_y)
			var multiplier = 2.5 if current_state == State.PRONE or current_state == State.DIVING else 1.0
			land_bump = clamp(impact * 0.01 * multiplier, 0.0, 0.15)
			land_tilt = clamp(impact * 0.009 * multiplier, 0.0, 0.12)
			land_shake_x = randf_range(-0.01, 0.01) * impact * multiplier
			
			if impact > 10.0:
				var fall_damage = (impact - 10.0) * 5.0
				take_damage(fall_damage)
			last_velocity_y = 0.0
		jump_count = 0

	# --- КНОПКИ ДЕЙСТВИЙ (ПОЛНОСТЬЮ АВТОНОМНЫЕ) ---
		  #ОПРОС КНОПКИ ПИНКА!
	if Input.is_action_just_pressed("kick") and current_state != State.RAMMING:
		try_kick()
	# Активация тарана
	# Активация тарана
	if Input.is_action_just_pressed("ram") and current_state == State.NORMAL and is_on_floor():
		if stamina >= 45.0 and ram_cooldown_timer <= 0.0: # Упростили проверку кулдауна
			stamina -= 45.0
			ram_cooldown_timer = 2.2 
			current_state = State.RAMMING
			ram_timer = 1.2          
			ram_direction = -forward_basis.z.normalized()

	# Автономный старт дайва и подката (исправлено заклинивание цепочки)
	if Input.is_action_just_pressed("dive") and current_state == State.NORMAL:
		current_state = State.DIVING
		dive_timer = DIVE_DURATION
		was_dive_triggered = true
		_change_collision_height(true)
		var dive_dir = direction if direction != Vector3.ZERO else -head.global_transform.basis.z
		dive_dir.y = 0.0
		dive_dir = dive_dir.normalized()
		velocity.x = dive_dir.x * DIVE_FORCE
		velocity.z = dive_dir.z * DIVE_FORCE
		velocity.y = JUMP_VELOCITY * 0.8
		
	elif Input.is_action_just_pressed("slide") and current_state == State.NORMAL and is_on_floor():
		current_state = State.SLIDING
		slide_current_speed = SLIDE_INITIAL_FORCE
		_change_collision_height(true)
		var slide_dir = direction if direction != Vector3.ZERO else -head.global_transform.basis.z
		slide_dir.y = 0.0
		slide_dir = slide_dir.normalized()
		velocity.x = slide_dir.x * slide_current_speed
		velocity.z = slide_dir.z * slide_current_speed

	elif Input.is_action_just_pressed("prone_toggle") and current_state != State.DIVING and current_state != State.SLIDING and current_state != State.RAMMING:
		if current_state == State.NORMAL:
			current_state = State.PRONE
			_change_collision_height(true)
		elif current_state == State.PRONE:
			if ceiling_ray and not ceiling_ray.is_colliding():
				current_state = State.NORMAL
				was_dive_triggered = false
				_change_collision_height(false)

	if current_state == State.PRONE and was_dive_triggered:
		if ceiling_ray and not ceiling_ray.is_colliding():
			current_state = State.NORMAL
			was_dive_triggered = false
			_change_collision_height(false)

	# ТАКТИЧЕСКИЕ НАКЛОНЫ И ПРЫЖКИ
	
# Наклоняться можно ТОЛЬКО в нормальном состоянии и строго на земле
	if current_state == State.NORMAL and is_on_floor():
		if Input.is_action_pressed("lean_left"):
			target_lean_angle = deg_to_rad(LEAN_ANGLE)
			target_lean_offset = -LEAN_OFFSET
			is_leaning = true
		elif Input.is_action_pressed("lean_right"):
			target_lean_angle = deg_to_rad(-LEAN_ANGLE)
			target_lean_offset = LEAN_OFFSET
			is_leaning = true
		else:
			target_lean_angle = 0.0
			target_lean_offset = 0.0
	else:
		# Если мы перешли в State.DIVING, State.SLIDING, State.PRONE или State.RAMMING:
		# Насильно возвращаем камеру в центр, чтобы персонаж не летел боком!
		target_lean_angle = 0.0
		target_lean_offset = 0.0

	# Вращаем и двигаем камеру (твой изначальный код, работает каждую секунду)
	camera.rotation.z = lerp_angle(camera.rotation.z, target_lean_angle, 10.0 * delta)
	head.position.x = lerp(head.position.x, target_lean_offset, 10.0 * delta)

# Опционально: можно слегка опускать камеру (ось Y) при наклоне, 
# чтобы имитировать присед под углом (тактический наклон корпуса)
	var target_vertical_offset = -0.1 if target_lean_offset != 0.0 else 0.0
	camera.position.y = lerp(camera.position.y, target_vertical_offset, 10.0 * delta)

	if Input.is_action_just_pressed("ui_accept"):
		if current_state == State.NORMAL:
			if is_on_floor():
				velocity.y = JUMP_VELOCITY
				jump_count = 1
			elif jump_count < max_jumps:
				velocity.y = JUMP_VELOCITY
				jump_count += 1
	# --- ВОССТАНОВЛЕННЫЙ РАСЧЕТ СКОРОСТИ И ДВИЖЕНИЯ ---
	if current_state == State.RAMMING or current_state == State.DIVING:
		pass 
	elif current_state == State.SLIDING:
		if direction:
			velocity.x = lerp(velocity.x, direction.x * slide_current_speed, SLIDE_CONTROL * delta)
			velocity.z = lerp(velocity.z, direction.z * slide_current_speed, SLIDE_CONTROL * delta)
		else:
			velocity.x = lerp(velocity.x, velocity.x * 0.9, delta)
			velocity.z = lerp(velocity.z, velocity.z * 0.9, delta)
	else:
		# Твоя оригинальная независимая проверка земли/воздуха
		if is_on_floor():
			if direction:
				var is_really_prone = (current_state == State.PRONE)
				var target_speed = PRONE_SPEED if is_really_prone else SPEED
				
				# КОНТУЗИЯ: Если таймер активен, режем скорость передвижения пополам!
				if ram_stun_timer > 0.0:
					target_speed *= 0.5
					
				velocity.x = lerp(velocity.x, direction.x * target_speed, 15.0 * delta)
				velocity.z = lerp(velocity.z, direction.z * target_speed, 15.0 * delta)

			else:
				velocity.x = lerp(velocity.x, 0.0, 10.0 * delta)
				velocity.z = lerp(velocity.z, 0.0, 10.0 * delta)
		else:
			# Физика в воздухе (WASD снова работает при прыжках)
			if direction:
				# 1. Узнаем, какую скорость персонаж УЖЕ имеет в направлении нажатой кнопки
				# (Используем векторное скалярное произведение dot)
				var current_speed_in_dir = velocity.dot(direction)
				
				# 2. Вычисляем, сколько скорости кнопки еще ИМЕЮТ ПРАВО добавить до лимита контроля
				var speed_to_add = AIR_CONTROL_LIMIT - current_speed_in_dir
				
				# 3. Если лимит контроля кнопками не превышен, добавляем импульс
				if speed_to_add > 0:
					var accel_amount = AIR_ACCEL * delta
					# Ограничиваем шаг разгона, чтобы не перешагнуть остаток лимита
					accel_amount = min(accel_amount, speed_to_add)
					
					# Мягко добавляем скорость строго по вектору движения
					velocity += direction * accel_amount
			else:
				# Когда кнопки отпущены, гасится только минимальное сопротивление воздуха.
				# Огромная скорость прыжка полностью сохраняется.
				velocity.x = move_toward(velocity.x, 0.0, AIR_FRICTION * delta)
				velocity.z = move_toward(velocity.z, 0.0, AIR_FRICTION * delta)
	# Физический сдвиг тела игрока
	move_and_slide()

	# Обработка удара по тушам нацистов
	if current_state == State.RAMMING:
		_process_ram_collisions()

	# ДИНАМИЧЕСКИЙ FOV И СДВИГ ВЫСОТЫ ГОЛОВЫ
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	# ТАЙМЕР СБРОСА ПАРТИЗАНА
	if fov_cooldown > 0.0:
		fov_cooldown -= delta

	# ДИНАМИЧЕСКИЙ FOV (Спит, если зажат ПКМ ИЛИ если включена блокировка из оружия)
	if not Input.is_action_pressed("aim") and not block_dynamic_fov:
		var target_fov = SPRINT_FOV if current_state == State.RAMMING else remap(horizontal_speed, 0.0, 8.0, BASE_FOV, SPRINT_FOV)
		camera.fov = lerp(camera.fov, target_fov, 8.0 * delta)

	var target_head_y = BASE_HEAD_Y
	if current_state == State.DIVING:
		target_head_y = PRONE_HEAD_Y * 1.3
	elif current_state == State.SLIDING:
		target_head_y = SLIDE_HEAD_Y 
	elif current_state == State.PRONE:
		target_head_y = PRONE_HEAD_Y
	else:
		target_head_y = BASE_HEAD_Y

	head.position.y = lerp(head.position.y, target_head_y, 12.0 * delta)

	# ХЭДБОБИНГ И ЭФФЕКТЫ ПАДЕНИЯ
	if is_on_floor() and direction != Vector3.ZERO and current_state != State.RAMMING:
		if current_state == State.PRONE or current_state == State.SLIDING:
			bob_time += delta * PRONE_BOB_FREQ
			camera.position.x = sin(bob_time) * PRONE_BOB_AMP_X + land_shake_x
			camera.position.y = abs(sin(bob_time * 2.0)) * PRONE_BOB_AMP_Y - land_bump
		else:
			bob_time += delta * velocity.length()
			camera.position.x = sin(bob_time * BOB_FREQUENCY * 0.5) * BOB_AMPLITUDE * 0.5 + land_shake_x
			camera.position.y = sin(bob_time * BOB_FREQUENCY) * BOB_AMPLITUDE - land_bump
	else:
		bob_time = 0.0
		camera.position.y = lerp(camera.position.y, 0.0 - land_bump, 10.0 * delta)
		camera.position.x = lerp(camera.position.x, 0.0 + land_shake_x, 10.0 * delta)
		
	camera.rotation.x = -land_tilt
	land_bump = lerp(land_bump, 0.0, 15.0 * delta)
	land_tilt = lerp(land_tilt, 0.0, 10.0 * delta)
	land_shake_x = lerp(land_shake_x, 0.0, 20.0 * delta)

	# === УЛЬТИМАТИВНЫЙ ШЕЙДЕР ДВОЕНИЯ (ХАРДКОРНОЕ УСИЛЕНИЕ ОТ ХП) ===
	if ghost_rect and ghost_rect.material:
		# ТВОИ БАЗОВЫЕ НАСТРОЙКИ (как ты просил — база 1.5 пикселя)
		var base_ghost: float = 1.5       
		var base_intensity: float = 0.2   # Начальная прозрачность контуров
		
		var target_ghost: float = base_ghost
		var target_intensity: float = base_intensity
		
		# === ШЕЙДЕР ДВОЕНИЯ С УЧЕТОМ КОНТУЗИИ ОБ СТЕНУ ===
		if current_state == State.RAMMING:
			target_ghost = 14.0       
			target_intensity = 0.6       
		elif ram_stun_timer > 0.0:
			# Пока голова гудит от удара об стену, выкручиваем лютое двоение!
			var stun_factor = ram_stun_timer / 2.0 # Плавно затухает от 1.0 до 0.0
			target_ghost = base_ghost + remap(stun_factor, 0.0, 1.0, 0.0, 11.0)
			target_intensity = base_intensity + remap(stun_factor, 0.0, 1.0, 0.0, 0.7)
		elif health < 50.0:
			# ... твой старый расчет двоения от низкого ХП ...

			# Начинаем колыхать экран уже с 50 ХП, чтобы эффект нарастал плавно
			var low_health_ratio = clamp((50.0 - health) / 50.0, 0.0, 1.0)
			
			# ЖЕСТКИЙ БУСТ: На 1 ХП сдвиг пикселей улетает до 12.0, а интенсивность — в абсолютный максимум (1.0)
			target_ghost = base_ghost + remap(low_health_ratio, 0.0, 1.0, 0.0, 10.5)
			target_intensity = base_intensity + remap(low_health_ratio, 0.0, 1.0, 0.0, 0.8)
			
		# Вытаскиваем текущие параметры из шейдера
		var current_ghost = ghost_rect.material.get_shader_parameter("ghost_pixel_shift")
		var current_intensity = ghost_rect.material.get_shader_parameter("ghost_intensity")
		
		# Плавно интерполируем к хардкорным значениям
		var next_ghost = lerp(current_ghost, target_ghost, 5.0 * delta)
		var next_intensity = lerp(current_intensity, target_intensity, 5.0 * delta)
		
		# Отправляем обновленные данные обратно в шейдер
		ghost_rect.material.set_shader_parameter("ghost_pixel_shift", next_ghost)
		ghost_rect.material.set_shader_parameter("ghost_intensity", next_intensity)

func BOB_AMAP_Y_HELPER() -> float:
	return BOB_AMPLITUDE
		
func _process(delta: float) -> void:
	if health < 25:
		BASE_FOV = 95.0
		SPRINT_FOV = 109.0
		var why = create_tween()
		why.tween_property(bg_music, "volume_db", -10, 0.01)
	# ЖЕЛЕЗОБЕТОННЫЙ СБРОС КУЛДАУНА ТАРАНА (Теперь тикает всегда!)
	if "ram_cooldown_timer" in self and ram_cooldown_timer > 0.0:
		ram_cooldown_timer -= delta
		if ram_cooldown_timer < 0.0:
			ram_cooldown_timer = 0.0
	if stamina < 30:
		var music_tween = create_tween()
		oh.volume_db = -30
		if not oh.playing:
			oh.play()
		music_tween.tween_property(oh, "volume_db", -8.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		if oh.playing:
			oh.stop()
	# ... дальше идет твой старый код (расчет штрафа веса, стамина, спринт на V и бег на Shift) ...
	# 1. Считаем общий штраф от веса оружия и разгрузки
	var total_penalty = (current_weapon_weight * 1.5) + total_carried_weight + vest_weight_penalty
	
	# Переводим штраф в множитель скорости
	final_speed_modifier = clamp(1.0 - total_penalty, 0.3, 1.0) 



	# === ОБНОВЛЕНИЕ ТЕСТОВОГО ИНТЕРФЕЙСА (HUD) ===
	if health_bar:
		# Плавно приравниваем значение полоски к текущему ХП игрока
		health_bar.value = health
		
	if stamina_bar:
		# Приравниваем значение к текущей выносливости
		stamina_bar.value = stamina
func _handle_health_system(delta: float) -> void:
	if is_dead: return
	if health > 0.0 and health < REGEN_LIMIT:
		health = move_toward(health, REGEN_LIMIT, HEALTH_REGEN_SPEED * delta)
		
	if blood_rect:
		var health_percentage = health / MAX_HEALTH
		var target_alpha = remap(health_percentage, 0.0, 0.6, 0.7, 0.0)
		target_alpha = clamp(target_alpha, 0.0, 0.7)
		blood_rect.color.a = lerp(blood_rect.color.a, target_alpha, 5.0 * delta)

func take_damage(amount: float) -> void:
	if is_dead: return
	health -= amount
	print("damage:", int(amount) )
	land_bump = clamp(land_bump + amount * 0.005, 0.0, 0.12)
	land_shake_x = randf_range(-0.02, 0.02) * amount * 0.2
	if health <= 0.0:
		health = 0.0
		die()
		print("Dead")
func heal(amount: float) -> void:
	if is_dead: return
	health += amount
	print("heal:", int(amount) )
	
func die(reason: String = "") -> void:
	if is_dead: return
	is_dead = true
	# СИСТЕМА УГАРНЫХ ПРИНТОВ СМЕРТИ
	if reason == "makarov_suicide":
		print("")
		print("ты блять долбаёб нахуй? не блять... аэээ")
	elif reason == "suicide":
		# Это твоя кнопка G (обманка на гранату)
		print("")
	else:
		# Обычная смерть от падения с высоты или от врагов
		print("")
		print("ты умер.")
		var shader_mat = panic_overlay.material as ShaderMaterial
		# За 0.2 секунды плавно размываем картинку и пускаем волны покачивания
		var tween_in = create_tween()
		tween_in.tween_property(shader_mat, "shader_parameter/panic_intensity", 1.0, 0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_change_collision_height(true) 
	var tween = create_tween().set_parallel(true)
	tween.tween_property(head, "position:y", 0.1, 0.5)
	tween.tween_property(camera, "rotation:z", deg_to_rad(65.0), 0.6)
	if blood_rect:
		var blood_tween = create_tween()
		blood_tween.tween_property(blood_rect, "color:a", 0.95, 0.8)
	if bg_music and bg_music.playing or dead_music and dead_music.playing:
		var music_tween = create_tween()
		# Плавно меняем параметр volume_db (громкость в децибелах) 
		# от текущего значения до -18.0 (это тихий гнетущий фон, не полный 0)
		# за 2.5 секунды с красивым плавным замедлением в конце
		music_tween.tween_property(bg_music, "volume_db", -18.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await music_tween.finished
		dead_music.play()
		bg_music.stop()
func _process_ram_collisions() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		
		if collider and collider.has_method("take_ram_damage"):
			# 1. Базовый расчет урона от тяжести эквипа (жилет + пушки)
			var weight_factor = 1.0 + vest_weight_penalty + ((current_weapon_weight + total_carried_weight) * 0.1)
			var base_ram_damage = 35.0
			var damage_from_weight = base_ram_damage * weight_factor
			
			# 2. МЕХАНИКА ОТЧАЯНИЯ (РАСЧЕТ МНОЖИТЕЛЯ ОТ ХП)
			# Формула: если health = 100, множитель = 1.0. Если health = 1, множитель = 2.0.
			# Используем clamp, чтобы при случайных значениях выше 100 или ниже 0 код не ломался.
			var health_damage_multiplier = remap(health_ratio, 0.0, 1.0, 2.0, 1.0)
			
			# Финальный урон: урон от веса умножаем на множитель здоровья
			var final_damage = damage_from_weight * health_damage_multiplier
			
			# Импульс отброса тоже увеличивается, если гг на грани смерти (панический толчок сильнее!)
			var push_force = (ram_direction * KICK_PUSH_FORCE * 1.3 * health_damage_multiplier) + Vector3(0, 3.0 * health_damage_multiplier, 0)
			
			# Выводим инфу в консоль, чтобы ты видел, как скачет урон при тестах
			print("ТАРАН! урон: ", int(final_damage))
			
			# Наносим урон врагу/двери
			collider.take_ram_damage(final_damage, push_force)
			
			# Эффект отдачи в камеру игрока (от яростного удара на 1 ХП камеру трясет сильнее)
			land_bump = 0.15 * health_damage_multiplier
			land_tilt = 0.09 * health_damage_multiplier
			land_shake_x = randf_range(-0.03, 0.03) * health_damage_multiplier
			
			# Если мы врезались в ДВЕРЬ (у нее есть переменная is_broken), летим дальше сквозь проем
			if "is_broken" in collider:
				continue 
				
			# Об обычных врагов останавливаемся
			current_state = State.NORMAL
			break

func try_kick() -> void:
	# Если стамины мало — пинок не сработает
	if stamina < KICK_STAMINA_COST: return
	
	stamina -= KICK_STAMINA_COST
	land_bump = 0.06  # Легкий клевок камеры от замаха ноги
	land_tilt = 0.09  # Наклон
	
	# Проверяем, врезался ли наш шейпкаст во что-нибудь
	if kick_cast and kick_cast.is_colliding():
		for i in kick_cast.get_collision_count():
			var hit_object = kick_cast.get_collider(i)
			
			# Наносим урон врагу, если у него есть метод take_damage
			if hit_object.has_method("take_damage"):
				hit_object.take_damage(KICK_DAMAGE)
				
			# Если пнули физический ящик или бочку (RigidBody3D) — смачно толкаем её
			if hit_object is RigidBody3D:
				var push_direction = -head.global_transform.basis.z
				push_direction.y = 0.1 # Небольшой пинок вверх, чтобы вещь летела сочнее
				push_direction = push_direction.normalized()
				hit_object.apply_central_impulse(push_direction * KICK_PUSH_FORCE)

func vodka():
	pass
func _change_collision_height(is_prone_active: bool, current_lean_offset: float = 0.0) -> void:
	# === ФИЗИЧЕСКИЙ СДВИГ ХИТБОКСОВ ПРИ НАКЛОНЕ ===
	if current_state == State.NORMAL:
		if head_hitbox:
			# Голова смещается ровно туда же, куда уехала камера
			head_hitbox.position.x = current_lean_offset
		if body_hitbox:
			# Тело наклоняется, но корень (таз) на месте, поэтому берем 60% от сдвига
			body_hitbox.position.x = current_lean_offset * 0.6
		if legs_hitbox:
			# Ноги стоят на полу, их ось X всегда в нуле
			legs_hitbox.position.x = 0.0
	else:
		# Если мы легли, прыгнули в дайв или подкат — сбрасываем боковые смещения в ноль
		if head_hitbox: head_hitbox.position.x = 0.0
		if body_hitbox: body_hitbox.position.x = 0.0
		if legs_hitbox: legs_hitbox.position.x = 0.0

	# === ТВОЙ КУСОК КОДА ДЛЯ ВЫСОТЫ И ОТКЛЮЧЕНИЙ (ОСТАЕТСЯ КАК БЫЛ) ===
	if is_prone_active:
		if current_state == State.SLIDING:
			if head_hitbox: head_hitbox.disabled = true   
			if body_hitbox: body_hitbox.disabled = false  
			if legs_hitbox and legs_hitbox.shape:
				legs_hitbox.disabled = false
				legs_hitbox.shape.height = 0.45           
				legs_hitbox.position.y = 0.225
		elif current_state == State.PRONE or current_state == State.DIVING:
			if head_hitbox: head_hitbox.disabled = true
			if body_hitbox: body_hitbox.disabled = true   
			if legs_hitbox and legs_hitbox.shape:
				legs_hitbox.disabled = false
				legs_hitbox.shape.height = 0.15           
				legs_hitbox.position.y = 0.075
	else:
		if head_hitbox: head_hitbox.disabled = false
		if body_hitbox: body_hitbox.disabled = false
		if legs_hitbox and legs_hitbox.shape:
			legs_hitbox.disabled = false
			legs_hitbox.shape.height = 0.45
			legs_hitbox.position.y = 0.225
func start_sprint_cooldown() -> void:
	can_sprint = false
	is_sprinting = false
	print("Стамина на нуле! Бег заблокирован на 3 секунды.")
	
	# Ждем 3 секунды. Пока can_sprint = false, эта функция больше не вызовется
	await get_tree().create_timer(3.0).timeout
	
	can_sprint = true
	print("Бег снова доступен!")
