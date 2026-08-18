extends Label3D

# Функция, которая будет скрывать текст
func _on_area_3d_body_entered(body: Node3D):
	# Проверяем, что в зону зашёл именно игрок (поменяй "Player" на имя своего узла игрока)
	if body.name == "Player":
		hide() # или visible = false
