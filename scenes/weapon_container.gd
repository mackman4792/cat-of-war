extends Node3D

# --- НАСТРОЙКИ СВЕЯ (ПОКАЧИВАНИЯ) ОРУЖИЯ ---
const SWAY_AMOUNT = 0.03
const SWAY_MAX_AMOUNT = 0.06
const SWAY_SMOOTH = 4.0
const ROTATION_SWAY_AMOUNT = 0.05
const ROTATION_SMOOTH = 5.0

var is_suicide_anim: bool = false
var is_reloading: bool = false    # Блокирует стрельбу при смене магазина
var is_aiming: bool = false       # Режим прицеливания

# --- НАСТРОЙКИ СУРОВОЙ ОТДАЧИ И РАЗБРОСА ---
const BASE_SPREAD: float = 0.015       # Базовый разброс (когда стоим на месте)
const MOVE_SPREAD_FAC: float = 0.04    # Базовый штраф от скорости движения
const AIM_SPREAD_FAC: float = 0.3      # Коэффициент в прицеливании (уменьшает разброс)

# --- НАСТРОЙКИ АДРЕНАЛИНОВОГО ЗАМЕДЛЕНИЯ ВРЕМЕНИ ---
const ADRENALINE_HP_THRESHOLD: float = 30.0 # Порог здоровья для активации
const ADRENALINE_TIME_SCALE: float = 0.9     # Скорость времени мира (0.7 = замедление на 30%)
const ADRENALINE_SMOOTH_SPEED: float = 4.0   # Скорость плавного перехода времени

# Индивидуальные настройки для каждого ствола
const RECOIL_DATA = {
	Weapon.PP: {
		"up": 0.04, 
		"side": 0.02, 
		"move_accuracy_factor": 1.0
	},
	Weapon.MAKAROV: {
		"up": 0.002, 
		"side": 0.00003, 
		"move_accuracy_factor": 0.001 
	},
	Weapon.SHOVEL: {
		"up": 0.0, 
		"side": 0.0, 
		"move_accuracy_factor": 0.5
	}
}

# Переменные для автоматического возврата прицела (Recoil Recovery)
var target_recovery_rot_x: float = 0.0  # Сколько угла вверх нужно вернуть
var recovery_speed: float = 2.0         # Снизили скорость (было 5.0) для плавности
var recovery_delay: float = 0.0         # Таймер задержки перед началом возврата
const RECOIL_RECOVERY_DELAY: float = 0.15 # Задержка в секундах после выстрела

const WEAPON_DATA = {
	Weapon.PP: {"damage": 10.0, "fire_rate": 0.1, "weight": 0.10, "max_ammo": 35},
	Weapon.MAKAROV: {"damage": 25.0, "fire_rate": 0.4, "weight": 0.0, "max_ammo": 8},
	Weapon.SHOVEL: {"damage": 73.0, "fire_rate": 0.9, "weight": 0.02, "max_ammo": 0}
}

var is_swing: bool = false
const RECOIL_FORCE: float = 0.07         
var current_recoil_z: float = 0.0 
var fire_cooldown: float = 0.0   

# --- ТЕКУЩИЕ ПАТРОНЫ В МАГАЗИНАХ ---
# Лопату сюда не пишем, у неё бесконечный боезапас
var current_ammo = {
	Weapon.PP: 35,
	Weapon.MAKAROV: 8
}

# --- СИСТЕМА СМЕНЫ ОРУЖИЯ ---
enum Weapon { MAKAROV, PP, SHOVEL } 
var current_weapon: Weapon = Weapon.PP 

# --- ССЫЛКИ НА УЗЛЫ СЦЕНЫ (СВЯЗЫВАНИЕ) ---
@onready var player: CharacterBody3D = $"../../.." 
@onready var pp_ray: RayCast3D = $PP_Mesh/PPRay
@onready var makarov_ray: RayCast3D = $Makarov_Mesh/MakarovRay
@onready var shovel_ray: ShapeCast3D = $Shovel_Mesh/ShovelRay # Наша новая сапёрка

@onready var pp_mesh: Node3D = $PP_Mesh
@onready var makarov_mesh: Node3D = $Makarov_Mesh
@onready var shovel_mesh: Node3D = $Shovel_Mesh       # Моделька лопатки

@onready var muzzle_flash: GPUParticles3D = $MuzzleFlash
@onready var wall_sparks: GPUParticles3D = $WallSparks 

# ДЛЯ ПАРАЛЛЕЛЬНЫХ АНИМАЦИЙ (Оружие и Камера отдельно)
@onready var weapon_anim_player: AnimationPlayer = $"suicd" 
@onready var camera_anim_player: AnimationPlayer = $"camera"

# Звуковое сопровождение биопанк-кошмара
@onready var tik: AudioStreamPlayer = $tik 
@onready var pps_zatvor: AudioStreamPlayer = $pps_zatvor 
@onready var fuc: AudioStreamPlayer = $fuc 
@onready var click: AudioStreamPlayer = $click 
@onready var shovel_swing: AudioStreamPlayer = $shovel_swing # Твой новый сочный хлюп

var mouse_mov_x: float = 0.0
var mouse_mov_y: float = 0.0

func _ready() -> void:
	_switch_weapon(Weapon.PP)
	# Исключаем игрока из коллизий всех лучей, чтобы он сам себе ноги не отстрелил лопатой
	if pp_ray and player: pp_ray.add_exception(player)
	if makarov_ray and player: makarov_ray.add_exception(player)
	if shovel_ray and player: shovel_ray.add_exception(player)
	print("Биомеханические сенсоры: коллизии игрока успешно заблокированы!")
func _unhandled_input(event: InputEvent) -> void:
	if player and player.is_dead: return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_mov_x = event.relative.x
		mouse_mov_y = event.relative.y

	# Смена оружия на кнопки 1, 2 и 3 (для лопаты)
	if event is InputEventKey and event.pressed and not event.echo and not is_aiming and not is_reloading:
		if event.keycode == KEY_1 and not current_weapon == Weapon.PP:
			_switch_weapon(Weapon.PP)
			weapon_anim_player.play("get_PPS")
		elif event.keycode == KEY_2 and not current_weapon == Weapon.MAKAROV:
			_switch_weapon(Weapon.MAKAROV)
			weapon_anim_player.play("get_PM")
		elif event.keycode == KEY_3 and not current_weapon == Weapon.SHOVEL:
			_switch_weapon(Weapon.SHOVEL) # Переключаемся на лопату
			weapon_anim_player.play("death")
	# НАЖАТИЕ КОЛЁСИКА (reload) — НАЧАЛО ПЕРЕЗАРЯДКИ (Блокируем для лопаты)
	if event.is_action_pressed("reload") and not is_reloading and not is_suicide_anim and not is_aiming and not is_swing:
		if current_weapon != Weapon.SHOVEL: # Лопату перезаряжать не нужно
			if player and player.current_state != player.State.RAMMING:
				start_reload()

	# РВАНЫЙ ПРИЦЕЛ ЧЕРЕЗ ТВОИ АНИМАЦИИ (Блокируем прицеливание для лопаты)
	if event.is_action_pressed("aim") and not is_reloading and not is_suicide_anim and not is_swing:
		if current_weapon != Weapon.SHOVEL:
			is_aiming = true
			if camera_anim_player: camera_anim_player.play("aim")
			weapon_anim_player.play("pistol_aim")
			if player: player.block_dynamic_fov = true # Гасим партизана
			print("Имплант глаза: приближение")
		
	if event.is_action_released("aim") and not is_reloading and not is_suicide_anim and not is_swing:
		if current_weapon != Weapon.SHOVEL:
			is_aiming = false
			if camera_anim_player: camera_anim_player.play("unaim")
			weapon_anim_player.play("pistol_unaim")
			print("Имплант глаза: отдаление")

func _switch_weapon(new_weapon: Weapon) -> void:
	current_weapon = new_weapon
	
	# Переключаем видимость ТРЁХ моделек одной строчкой
	pp_mesh.visible = (current_weapon == Weapon.PP)
	makarov_mesh.visible = (current_weapon == Weapon.MAKAROV)
	shovel_mesh.visible = (current_weapon == Weapon.SHOVEL) # Наша лопатка
	
	if player: 
		player.current_weapon_weight = WEAPON_DATA[current_weapon]["weight"]
	print("Взято оружие: ", current_weapon, ". Вес режет скорость на: ", WEAPON_DATA[current_weapon]["weight"])

func _physics_process(delta: float) -> void:
	if player and player.is_dead: return
	# --- СИСТЕМА БИО-АДРЕНАЛИНА (ЗАМЕДЛЕНИЕ ПРИ НИЗКОМ ХП) ---
	if player:
		# Считаем реальное время кадра, независимое от замедления движка
		var real_delta = get_process_delta_time()
		
		# Если здоровья меньше 30 и игрок не мёртв — целевое время 0.7, иначе возвращаем 1.0 (норма)
		var target_time_scale = ADRENALINE_TIME_SCALE if player.health < ADRENALINE_HP_THRESHOLD else 1.0
		
		# Плавно двигаем глобальное время к цели
		Engine.time_scale = lerp(Engine.time_scale, target_time_scale, ADRENALINE_SMOOTH_SPEED * real_delta)
		
		# КОМПЕНСАЦИЯ ДЛЯ ИГРОКА: чтобы мир вокруг замедлялся, а сам игрок двигался и крутил головой
		# чуть бодрее (ведь его восприятие ускорилось), нам нужно умножить его скорость на коэффициент.
		# Если этого не сделать, управление покажется «кисельным».
		if Engine.time_scale < 0.95:
			# Рассчитываем множитель, компенсирующий падение скорости
			var _compensation = 1.0 / Engine.time_scale
			
			# Пример интеграции (в зависимости от того, как написан твой контроллер игрока):
			# Если в CharacterBody3D скорость считается каждый кадр, можно подкидывать
			# этот коэф в скрипт игрока. Пока просто выведем в консоль для теста:
			# player.adrenaline_speed_mod = compensation

	# Таймер скорострельности автомата, пистолета и лопаты
	if fire_cooldown > 0.0:
		fire_cooldown -= delta

	# ОБЩАЯ СТРЕЛЬБА И АТАКА ЛОПАТОЙ
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0 and not is_suicide_anim and not is_reloading and not is_swing:
		if player and player.current_state != player.State.RAMMING:
			# Макаров и Лопата бьют по одиночному клику, ППС — зажимаем ЛКМ
			if current_weapon == Weapon.MAKAROV and not Input.is_action_just_pressed("shoot"):
				pass 
			elif current_weapon == Weapon.SHOVEL and not Input.is_action_just_pressed("shoot"):
				pass 
			else:
				shoot_weapon()
				fire_cooldown = WEAPON_DATA[current_weapon]["fire_rate"]

	# --- РАСЧЕТ ДРОЖИ РУК ОТ НИЗКОГО ХП И ТАКТИЧЕСКИХ ДВИЖЕНИЙ ГГ ---
	var hand_shake_x: float = 0.0
	var hand_shake_y: float = 0.0
	var hand_shake_rot_z: float = 0.0

	if player and player.health < 60.0:
		var low_health_ratio = clamp((60.0 - player.health) / 60.0, 0.0, 1.0)
		var shake_time = Time.get_ticks_msec() * 0.035
		hand_shake_x = sin(shake_time * 1.1) * 0.009 * low_health_ratio
		hand_shake_y = cos(shake_time * 1.4) * 0.009 * low_health_ratio
		hand_shake_rot_z = sin(shake_time * 0.9) * deg_to_rad(4.0) * low_health_ratio

	# --- ДОБАВЛЕННЫЙ БЛОК: СМЕЩЕНИЕ ОРУЖИЯ ОТ СКОРОСТИ (CS2 STYLE) ---
	var velocity_offset_x: float = 0.0
	var velocity_offset_y: float = 0.0
	var velocity_offset_z: float = 0.0

	if player and not player.is_dead and player.current_state != player.State.RAMMING:
		var local_velocity = player.global_transform.basis.inverse() * player.velocity
		
		const VELOCITY_X_FAC = 0.008  
		const VELOCITY_Z_FAC = 0.009  
		const VELOCITY_Y_FAC = 0.004  
		
		velocity_offset_x = local_velocity.x * VELOCITY_X_FAC
		velocity_offset_z = -local_velocity.z * VELOCITY_Z_FAC  
		velocity_offset_y = local_velocity.y * VELOCITY_Y_FAC

		velocity_offset_x = clamp(velocity_offset_x, -0.04, 0.04)
		velocity_offset_z = clamp(velocity_offset_z, -0.05, 0.04)
		velocity_offset_y = clamp(velocity_offset_y, -0.03, 0.03)

		if is_aiming:
			velocity_offset_x *= 0.25
			velocity_offset_y *= 0.25
			velocity_offset_z *= 0.25

	current_recoil_z = lerp(current_recoil_z, 0.0, 12.0 * delta)
	
	var target_pos_x = clamp(-mouse_mov_x * SWAY_AMOUNT * delta, -SWAY_MAX_AMOUNT, SWAY_MAX_AMOUNT)
	var target_pos_y = clamp(mouse_mov_y * SWAY_AMOUNT * delta, -SWAY_MAX_AMOUNT, SWAY_MAX_AMOUNT)
	var target_rot_z = mouse_mov_x * ROTATION_SWAY_AMOUNT * delta
	var target_rot_y = mouse_mov_y * ROTATION_SWAY_AMOUNT * delta
	
	var target_weapon_height: float = 0.0
	var additional_rot_x: float = 0.0
	var additional_rot_y: float = 0.0
	var additional_rot_z: float = 0.0

	if is_suicide_anim:
		hand_shake_x *= 2.5
		hand_shake_y *= 2.5
		hand_shake_rot_z *= 2.5
	elif player:
		if player.current_state == player.State.RAMMING:
			if current_weapon == Weapon.SHOVEL:
				# ПОЗИЦИЯ ЛОПАТЫ ПРИ ТАРАНЕ (выставляем вперёд как штык)
				position.x = lerp(position.x, 0.0, 10.0 * delta)
				target_weapon_height = 0.02
				additional_rot_x = deg_to_rad(-10.0) 
				additional_rot_y = deg_to_rad(0.0)
				additional_rot_z = deg_to_rad(45.0) # Разворот ребром
			else:
				position.x = lerp(position.x, -0.01, 10.0 * delta)
				target_weapon_height = 0.05
				current_recoil_z += 0.02
				additional_rot_x = deg_to_rad(20.0)   
				additional_rot_y = deg_to_rad(45.0)   
				additional_rot_z = deg_to_rad(-15.0)  
			hand_shake_x = 0.0
			hand_shake_y = 0.0
			hand_shake_rot_z = 0.0
		elif player.current_state == player.State.SLIDING or player.current_state == player.State.PRONE:
			target_weapon_height = -0.12
	
	position.x = lerp(position.x, target_pos_x + hand_shake_x + velocity_offset_x, SWAY_SMOOTH * delta)
	position.y = lerp(position.y, target_pos_y + target_weapon_height + hand_shake_y + velocity_offset_y, 6.0 * delta)
	position.z = lerp(position.z, current_recoil_z + velocity_offset_z, 8.0 * delta)

	rotation.x = lerp_angle(rotation.x, target_rot_y + additional_rot_x, ROTATION_SMOOTH * delta)
	rotation.y = lerp_angle(rotation.y, additional_rot_y, ROTATION_SMOOTH * delta)
	rotation.z = lerp_angle(rotation.z, target_rot_z + additional_rot_z + hand_shake_rot_z, ROTATION_SMOOTH * delta)

	# --- ПЛАВНЫЙ ВОЗВРАТ ПРИЦЕЛА ПОСЛЕ ОТДАЧИ (С ЗАДЕРЖКОЙ) ---
	if recovery_delay > 0.0:
		recovery_delay -= delta  # Ждем, пока остынет ствол после стрельбы
	elif target_recovery_rot_x > 0.0 and player and player.head:
		# Плавная интерполяция (lerp) вместо жесткого шага сделает возврат очень приятным
		var current_recovery = lerp(0.0, target_recovery_rot_x, recovery_speed * delta)
		
		# Опускаем камеру
		player.head.rotation.x -= current_recovery
		target_recovery_rot_x -= current_recovery
		
		# Защита от бесконечно малых значений
		if target_recovery_rot_x < 0.001:
			target_recovery_rot_x = 0.0

	mouse_mov_x = 0.0
	mouse_mov_y = 0.0

func shoot_weapon() -> void:
	# --- БЛОК ЛОПАТЫ (БЛИЖНИЙ БОЙ) ---
	if current_weapon == Weapon.SHOVEL:
		_attack_with_shovel()
		return

	# --- БЛОК ОГНЕСТРЕЛА ---
	if current_ammo[current_weapon] <= 0:
		print("Сухой щелчок! Магазин пуст. Жми колёсико!")
		fuc.play()
		return
		
	current_ammo[current_weapon] -= 1
	print("Патронов осталось: ", current_ammo[current_weapon])
	
	current_recoil_z += RECOIL_FORCE
	
	if muzzle_flash:
		muzzle_flash.restart()
		muzzle_flash.emitting = true
	
	# Проверка стрельбы строго под себя (Макаров-джамп!)
	var is_shooting_down = (player and player.head and player.head.rotation.x < -1.4)
	var current_damage = WEAPON_DATA[current_weapon]["damage"]
	
	if is_shooting_down:
		if current_weapon == Weapon.MAKAROV:
			if player.health <= current_damage:
				player.health = 0.0
				player.die("makarov_suicide")
			else:
				player.take_damage(current_damage)
				player.velocity.y = player.JUMP_VELOCITY * 0.8
				player.jump_count = 1
			return
		else:
			return

	# --- 1. ФИЗИЧЕСКАЯ ОТДАЧА С ПАМЯТЬЮ ДЛЯ ВОЗВРАТА ---
	if player and player.head:
		var rec_up = RECOIL_DATA[current_weapon]["up"]
		var rec_side = RECOIL_DATA[current_weapon]["side"]
		var random_side = randf_range(-rec_side, rec_side)
		
		# Толкаем камеру вверх и вбок
		player.head.rotation.x += rec_up
		player.rotation.y += random_side
		
		# Запоминаем, сколько нужно вернуть по вертикали обратно
		target_recovery_rot_x += rec_up

	# --- 2. РАСЧЕТ ДИНАМИЧЕСКОГО РАЗБРОСА ---
	var current_spread: float = BASE_SPREAD
	
	if player:
		var is_moving: bool = player.velocity.length() > 0.1
		# Прицел полностью вернулся на место, если накопленная отдача близка к нулю
		var is_recoil_reset: bool = target_recovery_rot_x < 0.005 
		
		# ИДЕАЛЬНЫЙ ПЕРВЫЙ ВЫСТРЕЛ: если стоим на месте И прицел спокоен
		if not is_moving and is_recoil_reset:
			current_spread = 0.0 # Лазерная точность без разброса!
			print("Био-прицеливание: 100% точность первого выстрела")
		else:
			# Если мы бежим — накидываем штраф от движения
			if is_moving:
				var weapon_move_mod = RECOIL_DATA[current_weapon]["move_accuracy_factor"]
				current_spread += (player.velocity.length() * MOVE_SPREAD_FAC) * weapon_move_mod
			
			# Если мы стоим, но зажимаем (отдача не вернулась) — BASE_SPREAD работает как минимальный разброс зажима
	
	# Если при этом еще и прицелились — зажимаем оставшийся разброс (для промежуточных состояний)
	if is_aiming:
		current_spread *= AIM_SPREAD_FAC

	# Выбираем активный луч и стреляем
	var active_ray: RayCast3D = pp_ray if current_weapon == Weapon.PP else makarov_ray
	_process_raycast_hit(active_ray, current_damage, current_spread)

# КАСТОМНАЯ ФУНКЦИЯ УДАРА САПЁРНОЙ ЛОПАТОЙ (ВЕРСИЯ С SHAPECAST)
func _attack_with_shovel() -> void:
	print("ГГ размахнулся складной лопатой по площади!")
	if weapon_anim_player: weapon_anim_player.play("shovel_attaack")
	# 1. Воспроизводим звук вздоха/замаха
	if shovel_swing: shovel_swing.play()
	
	# 2. Пинок скорости вперед (Game Feel)
	if player and not player.is_dead:
		var forward_dir = -player.global_transform.basis.z.normalized()
		player.velocity += forward_dir * 3.5 
	
	# 3. Расчет адреналинового урона
	var base_damage = WEAPON_DATA[Weapon.SHOVEL]["damage"]
	if player and player.health < 30.0:
		base_damage *= 2.2 
		print("АДРЕНАЛИН! Лопата бьет с удвоенной яростью!")
	
	current_recoil_z += 0.04 
	await get_tree().create_timer(0.55).timeout
	# Сначала принудительно обновляем физику шейпкаста в этот кадр
	if shovel_ray:
		shovel_ray.force_shapecast_update()
	
	# 4. Проверка объемного попадания через ShapeCast
	if shovel_ray and shovel_ray.is_colliding():
		# Шейпкаст находит массивы объектов. Берём самый первый (ближайший)
		var hit_object = shovel_ray.get_collider(0)
		var hit_point = shovel_ray.get_collision_point(0)
		var hit_normal = shovel_ray.get_collision_normal(0)
		
		# Высекаем искры в точке контакта объекта с формой шейпкаста
		if wall_sparks:
			wall_sparks.global_position = hit_point
			var look_target = hit_point + hit_normal
			if wall_sparks.global_position.is_equal_approx(look_target) or hit_normal.is_equal_approx(Vector3.UP) or hit_normal.is_equal_approx(Vector3.DOWN):
				wall_sparks.look_at(hit_point + hit_normal, Vector3.FORWARD)
			else:
				wall_sparks.look_at(look_target, Vector3.UP)
			wall_sparks.restart()
			wall_sparks.emitting = true

		# Наносим урон врагам с твоей системой хедшотов
		if hit_object.has_method("take_damage"):
			# Получаем ID формы коллизии, в которую врезался шейпкаст
			var hit_collider_id = shovel_ray.get_collider_shape(0)
			var hit_owner = hit_object.shape_owner_get_owner(hit_collider_id)
			
			if hit_owner and hit_owner.name == "head":
				hit_object.take_damage(base_damage, "head")
				print("Размозжил голову через ShapeCast!")
			elif hit_owner and hit_owner.name == "body":
				hit_object.take_damage(base_damage, "body")
			else:
				hit_object.take_damage(base_damage)

func _process_raycast_hit(active_ray: RayCast3D, current_damage: float, spread: float) -> void:
	if not active_ray: return
	
	# Сохраняем исходное направление луча, чтобы не сломать его навсегда
	var original_target = active_ray.target_position
	
	# Считаем случайное смещение по осям X и Y на конце луча
	# Длина оригинального луча (обычно отрицательное число по Z, например -50.0)
	var ray_length = original_target.z 
	
	var spread_offset_x = randf_range(-spread, spread) * abs(ray_length)
	var spread_offset_y = randf_range(-spread, spread) * abs(ray_length)
	
	# Применяем разброс к вектору цели луча
	active_ray.target_position = Vector3(spread_offset_x, spread_offset_y, ray_length)
	
	# Принудительно заставляем движок пересчитать коллизию луча с новым вектором прямо сейчас!
	active_ray.force_raycast_update()
	
	# --- СТАНДАРТНАЯ ОБРАБОТКА ПОПАДАНИЯ (ТВОЙ КОД) ---
	if active_ray.is_colliding():
		var hit_object = active_ray.get_collider()
		var hit_point = active_ray.get_collision_point()
		var hit_normal = active_ray.get_collision_normal()
		
		if wall_sparks:
			wall_sparks.global_position = hit_point
			var look_target = hit_point + hit_normal
			if wall_sparks.global_position.is_equal_approx(look_target) or hit_normal.is_equal_approx(Vector3.UP) or hit_normal.is_equal_approx(Vector3.DOWN):
				wall_sparks.look_at(hit_point + hit_normal, Vector3.FORWARD)
			else:
				wall_sparks.look_at(look_target, Vector3.UP)
			wall_sparks.restart()
			wall_sparks.emitting = true
			
		if hit_object.has_method("take_damage"):
			var hit_collider_id = active_ray.get_collider_shape()
			var hit_owner = hit_object.shape_owner_get_owner(hit_collider_id)
			
			if hit_owner and hit_owner.name == "head":
				hit_object.take_damage(current_damage, "head")
			elif hit_owner and hit_owner.name == "body":
				hit_object.take_damage(current_damage, "body")
			else: 
				hit_object.take_damage(current_damage)

	# Возвращаем луч в исходное идеальное состояние для следующих выстрелов
	active_ray.target_position = original_target


# УПРАВЛЕНИЕ АНИМАЦИЕЙ ПЕРЕЗАРЯДКИ
func start_reload() -> void:
	is_reloading = true
	if current_weapon == Weapon.PP:
		if weapon_anim_player: weapon_anim_player.play("pps_reload")
		if weapon_anim_player and current_ammo[current_weapon] <= 0: weapon_anim_player.play("null_pps_reload")
	elif current_weapon == Weapon.MAKAROV:
		if weapon_anim_player: weapon_anim_player.play("makarov_reload")

	print("Испытуемый 3579 пытается переставить магазин...")

# Вызывается методом на последнем кадре анимаций перезарядки
func finish_reload() -> void:
	is_reloading = false
	current_ammo[current_weapon] = WEAPON_DATA[current_weapon]["max_ammo"]
	print("Магазин защёлкнут! Полная обойма: ", current_ammo[current_weapon])

# Твой сочный ТИК при завале пистолета назад-вверх в анимации
func recharge_pistol() -> void:
	if tik: tik.play()

# Эту функцию вызывает твой AnimationPlayer на последнем каде анимации unaim!
func enable_parfizan_fov() -> void:
	if player:
		player.block_dynamic_fov = false # Включаем динамический FOV игрока обратно
		print("Имплант глаза перезагружен, динамический FOV вернулся")

func clic() -> void:
	if click: click.play()

func PPS_Z() -> void:
	if pps_zatvor: pps_zatvor.play()
func swing() -> void:
	is_swing = true
func end_swing() -> void:
	is_swing = false
