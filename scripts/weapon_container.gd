extends Node3D

# НАСТРОЙКИ СВЕЯ (ПОКАЧИВАНИЯ) ОРУЖИЯ
const FOV_NORMAL = 89.0  # Обычный обзор при беге
const FOV_AIM = 65.0     # Приближение при прицеливании на ПКМ
const SWAY_AMOUNT = 0.03
const SWAY_MAX_AMOUNT = 0.06
const SWAY_SMOOTH = 4.0
const ROTATION_SWAY_AMOUNT = 0.05
const ROTATION_SMOOTH = 5.0
var is_suicide_anim: bool = false
var fov_frame_counter: int = 0

# ХАРАКТЕРИСТИКИ ОРУЖИЯ (Урон, Скорострельность, Вес, Макс. патронов)
const WEAPON_DATA = {
	Weapon.PP: {"damage": 10.0, "fire_rate": 0.1, "weight": 0.10, "max_ammo": 35}, # Каноничные 35 патронов ППС-43
	Weapon.MAKAROV: {"damage": 25.0, "fire_rate": 0.4, "weight": 0.0, "max_ammo": 8} # 8 патронов ПМ
}

# ТЕКУЩИЕ ПАТРОНЫ В КАРМАНАХ ИСПЫТУЕМОГО
var current_ammo = {
	Weapon.PP: 35,
	Weapon.MAKAROV: 8
}

const RECOIL_FORCE = 0.07         
var current_recoil_z: float = 0.0 
var fire_cooldown: float = 0.0   
var is_reloading: bool = false # флаг, который запретит стрельбу во время перезарядки
var is_aiming: bool = false

# СИСТЕМА СМЕНЫ ОРУЖИЯ
enum Weapon { MAKAROV, PP }
var current_weapon: Weapon = Weapon.PP 

# ССЫЛКИ НА УЗЛЫ СЦЕНЫ
@onready var camera: Camera3D = $"../" # Проверь свой путь по дереву узлов!
@onready var anim_player: AnimationPlayer = $suicd # ссылка на твою анимку (проверь имя узла!)
@onready var player: CharacterBody3D = $"../../.." 
@onready var pp_ray: RayCast3D = $PP_Mesh/PPRay
@onready var makarov_ray: RayCast3D = $Makarov_Mesh/MakarovRay
@onready var pp_mesh: Node3D = $PP_Mesh
@onready var makarov_mesh: Node3D = $Makarov_Mesh
@onready var muzzle_flash: GPUParticles3D = $MuzzleFlash
@onready var wall_sparks: GPUParticles3D = $WallSparks 
@onready var fuc: AudioStreamPlayer = $fuc
@onready var tik: AudioStreamPlayer = $tik
@onready var anim_camera: AnimationPlayer = $camera
var mouse_mov_x: float = 0.0
var mouse_mov_y: float = 0.0

func _ready() -> void:
	_switch_weapon(Weapon.PP)
	
	if pp_ray and player: pp_ray.add_exception(player)
	if makarov_ray and player: makarov_ray.add_exception(player)
	print("Кастомные рейкасты успешно проинструктированы игнорировать игрока!")
func _unhandled_input(event: InputEvent) -> void:
	if player and player.is_dead: return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_mov_x = event.relative.x
		mouse_mov_y = event.relative.y

	# Смена оружия на кнопки 1 и 2
	if event is InputEventKey and event.pressed and not event.echo and not is_reloading and not is_aiming:
		if event.keycode == KEY_1: _switch_weapon(Weapon.PP)
		elif event.keycode == KEY_2: _switch_weapon(Weapon.MAKAROV)
	# НАЖАТИЕ КОЛЁСИКА — НАЧАЛО ПЕРЕЗАРЯДКИ
	if event.is_action_pressed("reload") and not is_reloading and not is_suicide_anim and not is_aiming:
		if player and player.current_state != player.State.RAMMING:
			start_reload()
			
	# ЧИСТОЕ ПРИЦЕЛИВАНИЕ БЕЗ ЗАВИСАНИЙ
	if event.is_action_pressed("aim") and not is_reloading:
		is_aiming = true
		anim_player.play("pistol_aim")
		anim_camera.play("aim")
		if player: player.block_dynamic_fov = true # Намертво гасим партизана
		print("Имплант глаза: приближение")
		
	if event.is_action_released("aim") and not is_reloading:
		is_aiming = false
		anim_player.play("pistol_unaim")
		anim_camera.play("unaim")
		print("Имплант глаза: возврат обзора")
		# Мы НЕ включаем партизана здесь! Мы включим его ТОЛЬКО на последнем кадре анимации unaim!
func _switch_weapon(new_weapon: Weapon) -> void:
	current_weapon = new_weapon
	
	# Переключаем видимость мешей одной строчкой (KISS!)
	pp_mesh.visible = (current_weapon == Weapon.PP)
	makarov_mesh.visible = (current_weapon == Weapon.MAKAROV)
	
	if player: 
		player.current_weapon_weight = WEAPON_DATA[current_weapon]["weight"]
	print("Взято оружие: ", current_weapon, ". Вес: ", WEAPON_DATA[current_weapon]["weight"])
func _physics_process(delta: float) -> void:
	if player and player.is_dead: return
	# Таймер скорострельности
	if fire_cooldown > 0.0:
		fire_cooldown -= delta

	# ОБЩАЯ КНОПКА СТРЕЛЬБЫ ПОД ВСЁ (Убрали кашу ИИ)
	if Input.is_action_pressed("shoot") and fire_cooldown <= 0.0 and not is_suicide_anim and not is_reloading:
		if player and player.current_state != player.State.RAMMING:
			# Если Макаров — стреляем только по одиночному клику, если ПП — зажимом
			if current_weapon == Weapon.MAKAROV and not Input.is_action_just_pressed("shoot"):
				pass 
			else:
				shoot_weapon()
				fire_cooldown = WEAPON_DATA[current_weapon]["fire_rate"]

	# 1. РАСЧЕТ ХАОТИЧНОЙ ДРОЖИ РУК ОТ НИЗКОГО ХП
	var hand_shake_x: float = 0.0
	var hand_shake_y: float = 0.0
	var hand_shake_rot_z: float = 0.0

	if player and player.health < 60.0:
		var low_health_ratio = clamp((60.0 - player.health) / 60.0, 0.0, 1.0)
		var shake_time = Time.get_ticks_msec() * 0.035
		
		hand_shake_x = sin(shake_time * 1.1) * 0.009 * low_health_ratio
		hand_shake_y = cos(shake_time * 1.4) * 0.009 * low_health_ratio
		hand_shake_rot_z = sin(shake_time * 0.9) * deg_to_rad(4.0) * low_health_ratio

	# ЛОГИКА ОТДАЧИ И СВЕЯ МЫШИ
	current_recoil_z = lerp(current_recoil_z, 0.0, 12.0 * delta)
	position.z = current_recoil_z
	
	var target_pos_x = clamp(-mouse_mov_x * SWAY_AMOUNT * delta, -SWAY_MAX_AMOUNT, SWAY_MAX_AMOUNT)
	var target_pos_y = clamp(mouse_mov_y * SWAY_AMOUNT * delta, -SWAY_MAX_AMOUNT, SWAY_MAX_AMOUNT)
	
	var target_rot_z = mouse_mov_x * ROTATION_SWAY_AMOUNT * delta
	var target_rot_y = mouse_mov_y * ROTATION_SWAY_AMOUNT * delta
	
	var target_weapon_height: float = 0.0
	var additional_rot_x: float = 0.0
	var additional_rot_y: float = 0.0
	var additional_rot_z: float = 0.0

	# АНИМАЦИЯ САМОУБИЙСТВА НА G (ИММЕРСИВНЫЙ УХОД ПОД ЭКРАН)
	if is_suicide_anim:
		hand_shake_x *= 2.5
		hand_shake_y *= 2.5
		hand_shake_rot_z *= 2.5
		# Сюда можно добавить вращение самого меша, если крутишь кодом
	elif player:
		# Физические состояния игрока
		if player.current_state == player.State.RAMMING:
			position.x = lerp(position.x, -0.01, 10.0 * delta)
			target_weapon_height = 0.05
			position.z += 0.02
			additional_rot_x = deg_to_rad(20.0)   
			additional_rot_y = deg_to_rad(45.0)   
			additional_rot_z = deg_to_rad(-15.0)  
			hand_shake_x = 0.0
			hand_shake_y = 0.0
			hand_shake_rot_z = 0.0
		elif player.current_state == player.State.SLIDING or player.current_state == player.State.PRONE:
			target_weapon_height = -0.12
	
	# ПРИМЕНЕНИЕ СДВИГОВ ПОЗИЦИИ И ВРАЩЕНИЯ (Плавный Свей!)
	position.x = lerp(position.x, target_pos_x + hand_shake_x, SWAY_SMOOTH * delta)
	position.y = lerp(position.y, target_pos_y + target_weapon_height + hand_shake_y, 6.0 * delta)
	
	rotation.x = lerp_angle(rotation.x, target_rot_y + additional_rot_x, ROTATION_SMOOTH * delta)
	rotation.y = lerp_angle(rotation.y, additional_rot_y, ROTATION_SMOOTH * delta)
	rotation.z = lerp_angle(rotation.z, target_rot_z + additional_rot_z + hand_shake_rot_z, ROTATION_SMOOTH * delta)
	
	# Сброс дельты мыши
	mouse_mov_x = 0.0
	mouse_mov_y = 0.0

func shoot_weapon() -> void:
	# Проверяем, есть ли патроны. Если пустой магазин — выходим и не стреляем
	if current_ammo[current_weapon] <= 0:
		print("Сухой щелчок! Магазин пуст. Жми колёсико, еблан!")
		fuc.play()
		return
		
	# Тратим один патрон!
	current_ammo[current_weapon] -= 1
	print("Патронов осталось: ", current_ammo[current_weapon])

	# ТВОЙ СТАРЫЙ КОД СТРЕЛЬБЫ НАЧИНАЕТСЯ ОТСЮДА:
	current_recoil_z += RECOIL_FORCE
	if muzzle_flash:
		muzzle_flash.restart()
		muzzle_flash.emitting = true
	
	# Проверка стрельбы строго под себя (Ракет-джамп!)
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
			return # ПП под себя не подбрасывает

		# ОБЫЧНАЯ СТРЕЛЬБА ВПЕРЕД (Выбираем рейкаст на лету)
	var active_ray: RayCast3D = pp_ray if current_weapon == Weapon.PP else makarov_ray
	
	if active_ray and active_ray.is_colliding():
		var hit_object = active_ray.get_collider()
		var hit_point = active_ray.get_collision_point()     
		var hit_normal = active_ray.get_collision_normal()   
		
		print("Бабах! Попали из ", "ПП" if current_weapon == Weapon.PP else "Макарова", " в: ", hit_object.name)
		
		# --- МАГИЯ ИСКР НА СТЕНАХ ---
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
			# Узнаём имя конкретного коллайдера, в который врезался луч оружия
			var hit_collider_id = active_ray.get_collider_shape()
			var hit_owner = hit_object.shape_owner_get_owner(hit_collider_id)
			
			# Если имя коллизии совпало с твоим узлом "head"
			if hit_owner and hit_owner.name == "head":
				hit_object.take_damage(current_damage, "head")
			elif hit_owner and hit_owner.name == "head":
				hit_object.take_damage(current_damage, "body")
			else: hit_object.take_damage(current_damage)
func start_reload() -> void:
	is_reloading = true
	
	# Проверяем, какая пушка в руках, и запускаем нужную дискретную анимку
	if current_weapon == Weapon.PP:
		anim_player.play("pps_reload") 
	elif current_weapon == Weapon.MAKAROV:
		anim_player.play("makarov_reload")
		
	print("Испытуемый 3579 пытается переставить магазин...")

func finish_reload() -> void:
	is_reloading = false
	current_ammo[current_weapon] = WEAPON_DATA[current_weapon]["max_ammo"]
	print("Магазин защёлкнут! Полная обойма: ", current_ammo[current_weapon])

func recharge_pistol() -> void:
	tik.play()
func enable_parfizan_fov() -> void:
	if player:
		player.block_dynamic_fov = false # Партизан, просыпайся!
		print("Имплант глаза перезагружен, динамический FOV вернулся")
