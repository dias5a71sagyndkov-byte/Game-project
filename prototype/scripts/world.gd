extends Spatial

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const RESOURCE_ART = {
	"wood": "res://assets/tree.svg",
	"stone": "res://assets/rock.svg",
	"berries": "res://assets/berry_bush.svg"
}

var player = null
var camera = null
var resources = []
var enemies = []
var fire_position = Vector3(0, 0, 0)
var fire_lit = false
var fire_light = null
var fire_sprite = null
var sun = null
var day_time = 0.0
var elapsed = 0.0
var kills = 0
var health_bar = null
var hunger_bar = null
var inventory_label = null
var clock_label = null
var objective_label = null
var prompt_label = null
var message_label = null
var death_overlay = null
var message_time = 0.0
var rng = RandomNumberGenerator.new()

func _ready():
	rng.seed = 7319
	_register_inputs()
	_build_environment()
	_build_floor()
	_build_camera()
	_build_campfire()
	_build_resources()
	player = PlayerScript.new()
	player.name = "Player"
	player.translation = Vector3(0, 0.1, 3.0)
	add_child(player)
	_build_ui()
	player.connect("stats_changed", self, "_update_ui")
	player.connect("died", self, "_on_player_died")
	_spawn_enemy(Vector3(9, 0.1, -6))
	_spawn_enemy(Vector3(-10, 0.1, -8))
	_spawn_enemy(Vector3(12, 0.1, 9))
	_update_ui()
	show_message("Топь просыпается. Найдите припасы и разожгите костёр.", 6.0)

func _register_inputs():
	var keys = {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"interact": [KEY_E], "attack": [KEY_SPACE], "dodge": [KEY_SHIFT],
		"eat": [KEY_F], "restart": [KEY_R]
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var event = InputEventKey.new()
			event.scancode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
	var click = InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	if not InputMap.action_has_event("attack", click):
		InputMap.action_add_event("attack", click)

func _build_environment():
	var environment_node = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1b3034")
	environment.ambient_light_color = Color("aec5af")
	environment.ambient_light_energy = 0.7
	environment.fog_enabled = true
	environment.fog_color = Color("304d49")
	environment.fog_depth_begin = 26.0
	environment.fog_depth_end = 65.0
	environment_node.environment = environment
	add_child(environment_node)
	sun = DirectionalLight.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_color = Color("ffe5a8")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)

func _material(color, unshaded = false):
	var material = SpatialMaterial.new()
	material.albedo_color = color
	material.flags_unshaded = unshaded
	material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	material.roughness = 1.0
	return material

func _build_floor():
	var floor_body = StaticBody.new()
	floor_body.name = "Ground"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 2 | 4
	var floor_mesh = MeshInstance.new()
	var box = CubeMesh.new()
	box.size = Vector3(46, 0.5, 46)
	floor_mesh.mesh = box
	floor_mesh.material_override = _material(Color("526347"))
	floor_mesh.translation.y = -0.25
	floor_body.add_child(floor_mesh)
	var collision = CollisionShape.new()
	var shape = BoxShape.new()
	shape.extents = Vector3(23, 0.25, 23)
	collision.shape = shape
	collision.translation.y = -0.25
	floor_body.add_child(collision)
	add_child(floor_body)
	for edge in [Vector3(-23, 1, 0), Vector3(23, 1, 0), Vector3(0, 1, -23), Vector3(0, 1, 23)]:
		var wall = StaticBody.new()
		wall.collision_layer = 1
		var wall_collision = CollisionShape.new()
		var wall_box = BoxShape.new()
		wall_box.extents = Vector3(0.5, 2, 23) if abs(edge.x) > 0 else Vector3(23, 2, 0.5)
		wall_collision.shape = wall_box
		wall.add_child(wall_collision)
		wall.translation = edge
		add_child(wall)
	for i in range(32):
		var patch = MeshInstance.new()
		var patch_mesh = CylinderMesh.new()
		patch_mesh.top_radius = rng.randf_range(1.0, 2.7)
		patch_mesh.bottom_radius = patch_mesh.top_radius
		patch_mesh.height = 0.018
		patch_mesh.radial_segments = 9
		patch.mesh = patch_mesh
		patch.material_override = _material(Color("3b544b") if i % 3 else Color("375c5e"))
		patch.translation = Vector3(rng.randf_range(-21, 21), 0.015, rng.randf_range(-21, 21))
		patch.scale.z = rng.randf_range(0.45, 0.85)
		patch.rotation.y = rng.randf_range(0, TAU)
		add_child(patch)

func _build_camera():
	camera = Camera.new()
	camera.name = "FollowCamera"
	camera.projection = Camera.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	camera.translation = Vector3(10, 14, 13)
	add_child(camera)
	camera.look_at(Vector3(0, 0, 3), Vector3.UP)
	camera.current = true

func _build_campfire():
	fire_sprite = Sprite3D.new()
	fire_sprite.texture = load("res://assets/campfire.svg")
	fire_sprite.pixel_size = 0.006
	fire_sprite.translation = fire_position + Vector3(0, 0.74, 0)
	fire_sprite.billboard = SpatialMaterial.BILLBOARD_ENABLED
	fire_sprite.modulate = Color(0.42, 0.42, 0.42)
	add_child(fire_sprite)
	fire_light = OmniLight.new()
	fire_light.translation = fire_position + Vector3(0, 1.4, 0)
	fire_light.light_color = Color("ffac50")
	fire_light.omni_range = 6.0
	fire_light.light_energy = 1.7
	fire_light.visible = false
	add_child(fire_light)

func _build_resources():
	_add_resource("wood", Vector3(-3.5, 0, 1.0))
	_add_resource("stone", Vector3(3.4, 0, 0.6))
	_add_resource("berries", Vector3(2.0, 0, 4.5))
	for kind in ["wood", "stone", "berries"]:
		for _i in range(10 if kind == "wood" else 7):
			var position = Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20))
			if position.length() < 6.0:
				position.x += 7.0
			_add_resource(kind, position)

func _add_resource(kind, position):
	var body = StaticBody.new()
	body.translation = position
	body.collision_layer = 1
	body.collision_mask = 2 | 4
	var collision = CollisionShape.new()
	var shape = CylinderShape.new()
	shape.radius = 0.38 if kind != "stone" else 0.6
	shape.height = 1.0
	collision.shape = shape
	collision.translation.y = 0.5
	body.add_child(collision)
	var sprite = Sprite3D.new()
	sprite.texture = load(RESOURCE_ART[kind])
	sprite.pixel_size = 0.008 if kind == "wood" else 0.006
	sprite.translation.y = sprite.texture.get_height() * sprite.pixel_size * 0.5
	sprite.billboard = SpatialMaterial.BILLBOARD_ENABLED
	body.add_child(sprite)
	add_child(body)
	resources.append({"kind": kind, "body": body, "sprite": sprite, "remaining": 3})

func _spawn_enemy(position):
	var enemy = EnemyScript.new()
	enemy.translation = position
	enemy.target = player
	add_child(enemy)
	enemies.append(enemy)

func _process(delta):
	if player == null:
		return
	var target = player.translation + Vector3(10, 14, 10)
	camera.translation = camera.translation.linear_interpolate(target, 1.0 - exp(-5.0 * delta))
	camera.look_at(player.translation + Vector3(0, 0.7, 0), Vector3.UP)
	if not player.alive:
		return
	elapsed += delta
	day_time = fmod(elapsed, 180.0) / 180.0
	sun.light_energy = 0.25 + 0.6 * (0.5 + 0.5 * cos(day_time * TAU))
	if fire_lit:
		fire_light.light_energy = 1.7 + sin(elapsed * 9.0) * 0.12
		if player.translation.distance_to(fire_position) < 3.0 and player.health < 100.0:
			player.health = min(100.0, player.health + 1.5 * delta)
	if message_time > 0.0:
		message_time -= delta
		message_label.visible = message_time > 0.0
	_update_ui()

func _unhandled_input(event):
	if event.is_action_pressed("restart") and not event.is_echo():
		get_tree().reload_current_scene()

func nearest_resource(who):
	var result = null
	var distance = 2.6
	for resource in resources:
		if resource.remaining <= 0 or not is_instance_valid(resource.body):
			continue
		var current = who.translation.distance_to(resource.body.translation)
		if current < distance:
			distance = current
			result = resource
	return result

func try_collect(who):
	if not who.alive:
		return false
	var resource = nearest_resource(who)
	if resource != null:
		who.add_item(resource.kind)
		resource.remaining -= 1
		show_message("+1 " + _resource_name(resource.kind), 1.0)
		if resource.remaining <= 0:
			resource.body.queue_free()
		return true
	if who.translation.distance_to(fire_position) < 2.7:
		if fire_lit:
			show_message("У костра раны заживают, а твари держатся в стороне.", 3.0)
			return true
		if who.inventory.wood >= 3 and who.inventory.stone >= 2:
			who.inventory.wood -= 3
			who.inventory.stone -= 2
			fire_lit = true
			fire_sprite.modulate = Color.white
			fire_light.visible = true
			who.emit_signal("stats_changed")
			show_message("Костёр зажжён. Теперь у вас есть убежище.", 5.0)
			return true
		show_message("Для костра нужны 3 дерева и 2 камня.", 3.0)
	return false

func attack_from(who, direction):
	var hit_count = 0
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.alive:
			continue
		var offset = enemy.translation - who.translation
		offset.y = 0.0
		if offset.length() <= 2.4 and (offset.length() < 0.1 or offset.normalized().dot(direction) >= 0.2):
			enemy.receive_hit(25.0, direction)
			hit_count += 1
	var arc = MeshInstance.new()
	var mesh = CubeMesh.new()
	mesh.size = Vector3(1.4, 0.06, 0.15)
	arc.mesh = mesh
	arc.material_override = _material(Color("f8d58a"), true)
	arc.translation = who.translation + direction * 1.1 + Vector3(0, 0.8, 0)
	arc.rotation.y = atan2(direction.x, direction.z)
	add_child(arc)
	var timer = get_tree().create_timer(0.12)
	timer.connect("timeout", arc, "queue_free")
	return hit_count

func enemy_defeated(_enemy):
	kills += 1
	player.add_item("berries", 1)
	show_message("Тварь повержена. +1 ягода", 2.0)

func _resource_name(kind):
	return {"wood": "дерево", "stone": "камень", "berries": "ягода"}[kind]

func _label(text, size = 18):
	var label = Label.new()
	label.text = text
	var font = DynamicFont.new()
	font.font_data = preload("res://assets/ui-font.ttf")
	font.size = size
	label.add_font_override("font", font)
	label.add_color_override("font_color", Color("f1ead3"))
	return label

func _panel(parent, left, top, right, bottom):
	var panel = PanelContainer.new()
	panel.rect_position = Vector2(left, top)
	panel.rect_size = Vector2(right - left, bottom - top)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.09, 0.09, 0.93)
	style.border_color = Color("72816b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _build_ui():
	var layer = CanvasLayer.new()
	add_child(layer)
	var root = Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var status_panel = _panel(root, 20, 20, 372, 190)
	var status = VBoxContainer.new()
	status.add_constant_override("separation", 7)
	status_panel.add_child(status)
	status.add_child(_label("ТИХАЯ ТОПЬ", 25))
	var health_row = HBoxContainer.new()
	health_row.add_child(_label("Жизнь    "))
	health_bar = _bar(Color("c46c58"))
	health_row.add_child(health_bar)
	status.add_child(health_row)
	var hunger_row = HBoxContainer.new()
	hunger_row.add_child(_label("Сытость "))
	hunger_bar = _bar(Color("b6a361"))
	hunger_row.add_child(hunger_bar)
	status.add_child(hunger_row)
	inventory_label = _label("")
	status.add_child(inventory_label)
	var goal_panel = _panel(root, -390, 20, -20, 145)
	goal_panel.anchor_left = 1.0
	goal_panel.anchor_right = 1.0
	goal_panel.margin_left = -390
	goal_panel.margin_right = -20
	var goal = VBoxContainer.new()
	goal.add_constant_override("separation", 6)
	goal_panel.add_child(goal)
	clock_label = _label("День 1", 22)
	goal.add_child(clock_label)
	objective_label = _label("Первое убежище\nСоберите 3 дерева и 2 камня.\nВернитесь к костру и нажмите E.", 16)
	goal.add_child(objective_label)
	var help_panel = _panel(root, 20, -86, -20, -20)
	help_panel.anchor_top = 1.0
	help_panel.anchor_bottom = 1.0
	help_panel.anchor_right = 1.0
	help_panel.margin_left = 20
	help_panel.margin_right = -20
	help_panel.margin_top = -86
	help_panel.margin_bottom = -20
	var help = VBoxContainer.new()
	help_panel.add_child(help)
	help.add_child(_label("WASD / стрелки — ходьба    E — собрать / костёр    ЛКМ / пробел — удар    Shift — рывок", 17))
	help.add_child(_label("F — съесть ягоду    R — начать заново    Перед атакой повернитесь к цели; рывок спасает от удара.", 15))
	prompt_label = _label("", 21)
	prompt_label.anchor_left = 0.5
	prompt_label.anchor_right = 0.5
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.margin_left = -310
	prompt_label.margin_right = 310
	prompt_label.margin_top = -132
	prompt_label.margin_bottom = -98
	prompt_label.align = Label.ALIGN_CENTER
	root.add_child(prompt_label)
	message_label = _label("", 18)
	message_label.anchor_left = 0.5
	message_label.anchor_right = 0.5
	message_label.margin_left = -350
	message_label.margin_right = 350
	message_label.margin_top = 210
	message_label.margin_bottom = 245
	message_label.align = Label.ALIGN_CENTER
	root.add_child(message_label)
	death_overlay = ColorRect.new()
	death_overlay.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	death_overlay.color = Color(0.03, 0.055, 0.055, 0.88)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(death_overlay)
	var death_label = _label("ТОПЬ ЗАБРАЛА ВАС\n\nНажмите R, чтобы попробовать снова.", 32)
	death_label.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	death_label.align = Label.ALIGN_CENTER
	death_label.valign = Label.VALIGN_CENTER
	death_overlay.add_child(death_label)
	death_overlay.visible = false

func _bar(color):
	var bar = ProgressBar.new()
	bar.rect_min_size = Vector2(200, 22)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100
	var foreground = StyleBoxFlat.new()
	foreground.bg_color = color
	foreground.set_corner_radius_all(3)
	bar.add_stylebox_override("fg", foreground)
	var background = StyleBoxFlat.new()
	background.bg_color = Color("243834")
	bar.add_stylebox_override("bg", background)
	return bar

func _update_ui():
	if health_bar == null:
		return
	health_bar.value = player.health
	hunger_bar.value = player.hunger
	inventory_label.text = "Дерево: %d   Камень: %d   Ягоды: %d" % [player.inventory.wood, player.inventory.stone, player.inventory.berries]
	var phase = "День" if day_time < 0.3 or day_time > 0.8 else ("Сумерки" if day_time < 0.45 or day_time > 0.7 else "Ночь")
	clock_label.text = "%s %d  ·  Побеждено: %d" % [phase, int(elapsed / 180.0) + 1, kills]
	if fire_lit:
		objective_label.text = "Убежище готово\nКостёр восстанавливает жизнь.\nИсследуйте топь и берегите припасы."
	var resource = nearest_resource(player)
	if resource != null:
		prompt_label.text = "E — собрать: " + _resource_name(resource.kind)
	elif player.translation.distance_to(fire_position) < 2.7:
		prompt_label.text = "Костёр · безопасное место" if fire_lit else "E — разжечь костёр (3 дерева, 2 камня)"
	else:
		prompt_label.text = ""

func show_message(text, seconds = 3.0):
	if message_label != null:
		message_label.text = text
		message_label.visible = true
		message_time = seconds

func _on_player_died():
	death_overlay.visible = true
	prompt_label.text = ""
	message_label.visible = false
