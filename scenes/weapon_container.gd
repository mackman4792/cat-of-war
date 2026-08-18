extends Node3D

# НАСТРОЙКИ СВЕЯ (ПОКАЧИВАНИЯ) ОРУЖИЯ
const SWAY_AMOUNT = 0.03
const SWAY_MAX_AMOUNT = 0.06
const SWAY_SMOOTH = 4.0
const ROTATION_SWAY_AMOUNT = 0.05
const ROTATION_SMOOTH = 5.0
var is_suicide_anim: bool = false
var is_reloading: bool = false # Блокирует стрельбу при смене магазина
var is_aiming: bool = false
# ХАРАКТЕРИСТИКИ ОРУЖИЯ (Урон, Скорострельность, Вес, Макс. патронов)
const WEAPON_DATA = {
	Weapon.PP: {"damage": 10.0, "fire_rate": 0.1, "weight": 0.10, "max_ammo": 35},
	Weapon.MAKAROV: {"damage": 25.0, "fire_rate": 0.4, "weight": 0.0, "max_ammo": 8}
}

const RECOIL_FORCE = 0.07         
var current_recoil_z: float = 0.0 
var fire_cooldown: float = 0.0   

# ТЕКУЩИЕ ПАТРОНЫ В МАГАЗИНАХ
var current_ammo = {
	Weapon.PP: 35,
	Weapon.MAKAROV: 8
}

# СИСТЕМА СМЕНЫ ОРУЖИЯ
enum Weapon { MAKAROV, PP }
var current_weapon: Weapon = Weapon.PP 

# ССЫЛКИ НА УЗЛЫ СЦЕНЫ
@onready var player: CharacterBody3D = $"../../.." 
@onready var pp_ray: RayCast3D = $PP_Mesh/PPRay
@onready var makarov_ray: RayCast3D = $Makarov_Mesh/MakarovRay
@onready var pp_mesh: Node3D = $PP_Mesh
@onready var makarov_mesh: Node3D = $Makarov_Mesh
@onready var muzzle_flash: GPUParticles3D = $MuzzleFlash
@onready var wall_sparks: GPUParticles3D = $WallSparks 

# ДЛЯ ПАРАЛЛЕЛЬНЫХ АНИМАЦИЙ (Оружие и Камера отдельно)
@onready var weapon_anim_player: AnimationPlayer = $"suicd" 
@onready var camera_anim_player: AnimationPlayer = $"camera"

# Твой кастомный звук передергивания затвора ПМ
@onready var tik: AudioStreamPlayer = $tik 
@onready var pps_zatvor: AudioStreamPlayer = $pps_zatvor 
@onready var fuc: AudioStreamPlayer = $fuc 
@onready var click: AudioStreamPlayer = $click 
var mouse_mov_x: float = 0.0
var mouse_mov_y: float = 0.0

func _ready() -> void:
	_switch_weapon(Weapon.PP)
	# Исключаем игрока из коллизий лучей, чтобы не прострелить себе хитбокс
	if pp_ray and player: pp_ray.add_exception(player)
	if makarov_ray and player: makarov_ray.add_exception(player)
	print("Кастомные рейкасты успешно проинструктированы игнорировать игрока!")

func _unhandled_input(event: InputEvent) -> void:
	if player and player.is_dead: return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_mov_x = event.relative.x
		mouse_mov_y = event.relative.y

	# Смена оружия на кнопки 1 и 2
	if event is InputEventKey and event.pressed and not event.echo and not is_aiming and not is_reloading:
		if event.keycode == KEY_1: _switch_weapon(Weapon.PP)
		elif event.keycode == KEY_2: _switch_weapon(Weapon.MAKAROV)

	# НАЖАТИЕ КОЛЁСИКА (reload) — НАЧАЛО ПЕРЕЗАРЯДКИ
	if event.is_action_pressed("reload") and not is_reloading and not is_suicide_anim and not is_aiming:
		if player and player.current_state != player.State.RAMMING:
			start_reload()

	# РВАНЫЙ ПРИЦЕЛ ЧЕРЕЗ ТВОИ АНИМАЦИИ (aim / unaim)
	if event.is_action_pressed("aim") and not is_reloading and not is_suicide_anim:
		is_aiming = true
		if camera_anim_player: camera_anim_player.play("aim")
		weapon_anim_player.play("pistol_aim")
		if player: player.block_dynamic_fov = true # Гасим партизана сразу при нажатии ПКМ
		print("Имплант глаза: приближение")
		
	if event.is_action_released("aim") and not is_reloading and not is_suicide_anim:
		is_aiming = false
		if camera_anim_player: camera_anim_player.play("unaim")
		weapon_anim_player.play("pistol_unaim")
		print("Имплант глаза: отдаление")

func _switch_weapon(new_weapon: Weapon) -> void:
	current_weapon = new_weapon
	
	# Переключаем видимость лоу-поли моделек одной строчкой
	pp_mesh.visible = (current_weapon == Weapon.PP)
	makarov_mesh.visible = (current_weapon == Weapon.MAKAROV)
	
	if player: 
		player.current_weapon_weight = WEAPON_DATA[current_weapon]["weight"]
	print("Взято оружие: ", current_weapon, ". Вес режет скорость на: ", WEAPON_DATA[current_weapon]["weight"])

func _physics_process(delta: float) -> void:
	if player and player.is_dead: return

	# Таймер скорострельности автомата и пистолета
	if fire_cooldown > 0.0:
		fire_cooldown -= delta

	# ОБЩАЯ СТРЕЛЬБА (Проверяем кулдаун, суицид и перезарядку)
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0 and not is_suicide_anim and not is_reloading:
		if player and player.current_state != player.State.RAMMING:
			# Если Макаров — стреляем только по одиночному клику, если ППС — зажимаем ЛКМ
			if current_weapon == Weapon.MAKAROV and not Input.is_action_just_pressed("shoot"):
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
		# Переводим глобальную скорость игрока в локальные координаты его тела
		var local_velocity = player.global_transform.basis.inverse() * player.velocity
		
		# Коэффициенты силы смещения (меняй под себя)
		const VELOCITY_X_FAC = 0.008  # Влияние стрейфа (влево/вправо)
		const VELOCITY_Z_FAC = 0.009  # Влияние ходьбы вперед/назад
		const VELOCITY_Y_FAC = 0.004  # Влияние падения/прыжка
		
		velocity_offset_x = local_velocity.x * VELOCITY_X_FAC
		velocity_offset_z = -local_velocity.z * VELOCITY_Z_FAC  
		velocity_offset_y = local_velocity.y * VELOCITY_Y_FAC

		# Ограничиваем максимальный уход пушки
		velocity_offset_x = clamp(velocity_offset_x, -0.04, 0.04)
		velocity_offset_z = clamp(velocity_offset_z, -0.05, 0.04)
		velocity_offset_y = clamp(velocity_offset_y, -0.03, 0.03)

		# При прицеливании гасим инерцию движения, чтобы не мешать стрелять
		if is_aiming:
			velocity_offset_x *= 0.25
			velocity_offset_y *= 0.25
			velocity_offset_z *= 0.25

	# Плавный возврат отдачи по оси Z
	current_recoil_z = lerp(current_recoil_z, 0.0, 12.0 * delta)
	
	# Расчет базового свея от мыши
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
	
	# ПРИМЕНЕНИЕ ВСЕХ СДВИГОВ С УЧЕТОМ ИНЕРЦИИ СКОРОСТИ
	position.x = lerp(position.x, target_pos_x + hand_shake_x + velocity_offset_x, SWAY_SMOOTH * delta)
	position.y = lerp(position.y, target_pos_y + target_weapon_height + hand_shake_y + velocity_offset_y, 6.0 * delta)
	position.z = lerp(position.z, current_recoil_z + velocity_offset_z, 8.0 * delta) # Включаем плавный lerp для оси Z

	rotation.x = lerp_angle(rotation.x, target_rot_y + additional_rot_x, ROTATION_SMOOTH * delta)
	rotation.y = lerp_angle(rotation.y, additional_rot_y, ROTATION_SMOOTH * delta)
	rotation.z = lerp_angle(rotation.z, target_rot_z + additional_rot_z + hand_shake_rot_z, ROTATION_SMOOTH * delta)
	
	mouse_mov_x = 0.0
	mouse_mov_y = 0.0

# ЕДИНАЯ ФУНКЦИЯ ВЫСТРЕЛА
func shoot_weapon() -> void:
	# Проверка патронов
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
				# Если выжил — прострелил колени и полетел к потолку!
				player.take_damage(current_damage)
				player.velocity.y = player.JUMP_VELOCITY * 0.8
				player.jump_count = 1
			return
		else:
			return # ПП под себя не подбрасывает

	# ОБЫЧНАЯ СТРЕЛЬБА ВПЕРЕД (Выбираем рейкаст на дуле ствола)
	var active_ray: RayCast3D = pp_ray if current_weapon == Weapon.PP else makarov_ray
	
	if active_ray and active_ray.is_colliding():
		var hit_object = active_ray.get_collider()
		var hit_point = active_ray.get_collision_point()     
		var hit_normal = active_ray.get_collision_normal()   
		
		# --- ПОЧИНЕННАЯ МАГИЯ ИСКР НА СТЕНАХ ---
		if wall_sparks:
			wall_sparks.global_position = hit_point
			var look_target = hit_point + hit_normal
			
			if wall_sparks.global_position.is_equal_approx(look_target) or hit_normal.is_equal_approx(Vector3.UP) or hit_normal.is_equal_approx(Vector3.DOWN):
				wall_sparks.look_at(hit_point + hit_normal, Vector3.FORWARD)
			else:
				wall_sparks.look_at(look_target, Vector3.UP)

			wall_sparks.restart()
			wall_sparks.emitting = true
		
		# ЮВЕЛИРНЫЕ ХЕДШОТЫ Х5.2 ПО СОБАКАМ-ТАБЛЕТКАМ И НАЦИСТАМ
		if hit_object.has_method("take_damage"):
			var hit_collider_id = active_ray.get_collider_shape()
			var hit_owner = hit_object.shape_owner_get_owner(hit_collider_id)
			
			if hit_owner and hit_owner.name == "head":
				hit_object.take_damage(current_damage, "head")
			elif hit_owner and hit_owner.name == "head":
				hit_object.take_damage(current_damage, "body")
			else: 
				hit_object.take_damage(current_damage) # Для безголовых капсул-нацистов

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
