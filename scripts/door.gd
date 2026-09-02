extends StaticBody3D

@export var is_locked: bool = true
var is_broken: bool = false

# Тот самый метод получения урона от тарана, который вызывает игрок!
func take_ram_damage(_damage_amount: float, push_impulse: Vector3) -> void:
	if is_broken: return
	
	# Если это хлипкая дверь окопа, выносим её с одного удара!
	is_broken = true
	print("БАБАХ! Дверь выбита плечом!")
	
	# 1. Отключаем коллизию двери, чтобы игрок ПРОЛЕТЕЛ НАСКВОЗЬ, не останавливаясь об неё
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true
		
	# 2. ИММЕРСИВНОСТЬ: Эффект вылетания двери.
	# Вместо сложных осколков мы можем просто заставить её резко упасть на пол или улететь вперед
	var tween = create_tween().set_parallel(true)
	
	# Поворачиваем дверь плашмя на землю в сторону удара (имитация выбитой петли)
	var target_rotation = rotation
	target_rotation.x += deg_to_rad(90.0) 
	tween.tween_property(self, "rotation", target_rotation, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	# Слегка толкаем модельку вперед по вектору удара
	var target_position = global_position + (push_impulse.normalized() * 1.5)
	target_position.y -= 0.5 # Опускаем к полу
	tween.tween_property(self, "global_position", target_position, 0.3)
	
	# Опционально: спавним партиклы щепок, если они у тебя настроены
