extends CharacterBody3D

const SPEED = 4.2       # Скорость пса (чуть медленнее бега ГГ, чтобы можно было свалить)
const DAMAGE = 15.0     # Урон от одного укуса
const BITE_COOLDOWN = 1.0 # Как часто собака кусает (раз в секунду)

var health: float = 30.0 # Жизни собаки (Макаров убьет за 2 выстрела, ППС за 3)
var bite_timer: float = 0.0
enum AIState {STUNNED, PATROL}
@onready var bite_ray: RayCast3D = $BiteRay
var current_ai_state: AIState = AIState.PATROL

# ФИЗИКА ИМПУЛЬСА (ОТЛЕТ ОТ ТАРАНА И ПИНКА)
var knockback_velocity: Vector3 = Vector3.ZERO
const KNOCKBACK_FRICTION = 16.0 

# Самый ленивый и вечный способ найти игрока в Godot по KISS:
# Мы просто ищем его в дереве сцены по имени узла. Проверь, как называется узел игрока в main!
@onready var player = get_tree().current_scene.find_child("Player", true, false)

func _physics_process(delta: float) -> void:
	if not player or player.is_dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# 1. ТАЙМЕР КУСИКА 
	if bite_timer > 0.0:
		bite_timer -= delta

	# 2. ДВИЖЕНИЕ СТРОГО К ИГРОКУ
	var direction = (player.global_position - global_position).normalized()
	
	# Обнуляем Y, чтобы собака не пыталась взлететь в воздух, если игрок подпрыгнул
	direction.y = 0.0
	direction = direction.normalized()

	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED

	# Добавляем стандартную гравитацию, чтобы таблетка не летала над полом
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	# 3. ЮВЕЛИРНЫЙ РАЗВОРOТ ЛИЦОМ К ЖЕРТВЕ
	# Метод look_at может вылетать, если позиции совпали, поэтому проверяем дистанцию
	if global_position.distance_to(player.global_position) > 0.5:
		# Заставляем собаку смотреть на игрока, но без завала по вертикали
		var target_look = player.global_position
		target_look.y = global_position.y
		look_at(target_look, Vector3.UP)

	move_and_slide()

	# 4. ЛОГИКА УКРЫЗАНЬЯ
	if bite_ray.is_colliding() and bite_timer <= 0.0:
		var target = bite_ray.get_collider()
		if target == player and player.has_method("take_damage"):
			player.take_damage(DAMAGE)
			bite_timer = BITE_COOLDOWN
			print("АМ! Собака-таблетка откусила у ГГ ", DAMAGE, " ХП!")

# Функция получения урона (в неё стреляют твои ППС и Макаров!)
func take_damage(amount: float, hit_zone: String = "body") -> void:
	var final_damage = amount
	
	if hit_zone == "head":
		final_damage = amount * 5.2
		print("КРИТ В БОРДОВУЮ БАШКУ! Урон: ", final_damage)
	else:
		print("Попадание в туловище собаки. Урон: ", final_damage)
		
	health -= final_damage
	if health <= 0.0:
		print("Собака-таблетка аннигилировалась!")
		queue_free()
func take_ram_damage(amount: float, impulse: Vector3) -> void:
	health -= amount
	knockback_velocity = impulse
	current_ai_state = AIState.STUNNED 
	print("ИИ сбит с ног тараном! Осталось ХП: ", health)
	if health <= 0.0: _die()
func _die() -> void:
	print("Собака-таблетка аннигилировалась!")
	queue_free()
