extends StaticBody3D

func set_highlight(enabled: bool) -> void:
	# Получаем родителя "O vodka", где лежат кубы
	var parent_node = get_parent()
	if not parent_node:
		return
		
	# Перебираем все кубы блендеровской модели
	for child in parent_node.get_children():
		if child is MeshInstance3D:
			# ВАЖНО: теперь обращаемся строго к material_overlay!
			var material = child.material_overlay
			
			if material and material is ShaderMaterial:
				if enabled:
					material.set_shader_parameter("outline_intensity", 1.0)
				else:
					material.set_shader_parameter("outline_intensity", 0.0)

func drink() -> void:
	set_highlight(false)
	# Удаляем всю бутылку целиком со всеми кубами
	get_parent().queue_free()
