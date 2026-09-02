extends RayCast3D

@onready var Player := $"../../.." 

# Переменная для хранения водки, на которую мы смотрели в ПРЕДЫДУЩЕМ кадре
var last_hovered_vodka: StaticBody3D = null

func _ready() -> void:
	add_exception(Player)

func _physics_process(_delta: float) -> void:
	force_raycast_update()
	
	var current_vodka: StaticBody3D = null
	
	if is_colliding():
		var collider = get_collider()
		if collider:
			var parent_node = collider.get_parent()
			if parent_node:
				var static_body = parent_node.get_node_or_null("StaticBody3D")
				
				if static_body and static_body.has_method("drink"):
					current_vodka = static_body


	# Логика переключения подсветки
	if current_vodka != last_hovered_vodka:
		if last_hovered_vodka and is_instance_valid(last_hovered_vodka):
			if last_hovered_vodka.has_method("set_highlight"):
				last_hovered_vodka.set_highlight(false)
		
		if current_vodka:
			if current_vodka.has_method("set_highlight"):
				current_vodka.set_highlight(true)
		
		last_hovered_vodka = current_vodka

	# Логика использования кнопки "use"
	if Input.is_action_just_pressed("use"):
		if current_vodka and is_instance_valid(current_vodka):
			if current_vodka.has_method("set_highlight"):
				current_vodka.set_highlight(false)
			last_hovered_vodka = null
			
			current_vodka.drink()
			print("Выпили водку!")
			if Player.has_method("heal"):
				Player.heal(25)
