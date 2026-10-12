extends SceneTree

var passed = 0
var failed = 0
var world = null

func _init():
	call_deferred("_run")

func check(condition, description):
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failed += 1
		printerr("FAIL: " + description)

func wait_seconds(seconds):
	yield(create_timer(seconds), "timeout")

func action_event(action):
	var event = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event

func resource_of(kind):
	for resource in world.resources:
		if resource.kind == kind and resource.remaining > 0:
			return resource
	return null

func stand_beside(resource):
	# Stay clear of both the resource collider and other nearby resources.
	for i in range(8):
		var angle = i * PI / 4.0
		world.player.translation = resource.body.translation + Vector3(cos(angle), 0.1, sin(angle)) * 1.25
		world.player.velocity = Vector3.ZERO
		if world.nearest_resource(world.player) == resource:
			return true
	return false

func _run():
	var scene = load("res://world.tscn")
	if scene == null:
		check(false, "world scene loads")
		quit(1)
		return
	world = scene.instance()
	get_root().add_child(world)
	current_scene = world
	var player = world.player
	check(player != null and world.camera != null, "world creates a player and follow camera")
	if player == null or world.camera == null:
		world.queue_free()
		yield(wait_seconds(0.05), "completed")
		quit(1)
		return
	for enemy in world.enemies:
		enemy.set_physics_process(false)

	player.translation = Vector3(0, 3, 3)
	yield(wait_seconds(0.9), "completed")
	check(player.is_on_floor() and abs(player.translation.y) < 0.12, "gravity lands the player on the ground")
	var ground_height = player.translation.y
	yield(wait_seconds(0.15), "completed")
	check(abs(player.translation.y - ground_height) < 0.02, "ground collision prevents falling through the floor")
	var start = player.translation
	var camera_start = world.camera.translation
	var forward = -world.camera.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	Input.action_press("move_forward")
	yield(wait_seconds(0.23), "completed")
	Input.action_release("move_forward")
	var travelled = player.translation - start
	travelled.y = 0
	check(travelled.length() > 0.6 and travelled.normalized().dot(forward) > 0.9, "forward input moves along the camera's ground plane")
	start = player.translation
	var right = world.camera.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	Input.action_press("move_right")
	yield(wait_seconds(0.23), "completed")
	Input.action_release("move_right")
	travelled = player.translation - start
	travelled.y = 0
	check(travelled.length() > 0.6 and travelled.normalized().dot(right) > 0.9, "right input moves right relative to the camera")
	yield(wait_seconds(0.7), "completed")
	check(world.camera.translation.distance_to(camera_start) > 0.5 and world.camera.translation.distance_to(player.translation + Vector3(10, 14, 10)) < 0.25, "camera follows the moving player")
	check(player.hunger < 99.5, "survival time consumes hunger")

	player.translation = Vector3(0, 0.1, -1.1)
	check(not world.try_collect(player) and not world.fire_lit, "campfire refuses missing materials")
	for kind in ["wood", "stone", "berries"]:
		var resource = resource_of(kind)
		check(resource != null and stand_beside(resource), "a reachable " + kind + " resource exists")
		if resource == null:
			continue
		var amount = 3 if kind == "wood" else (2 if kind == "stone" else 1)
		for _i in range(amount):
			check(world.try_collect(player), "collect " + kind)
		check(player.inventory[kind] == amount and resource.remaining == 3 - amount, "gathering updates " + kind + " inventory and depletion")
	yield(wait_seconds(0.05), "completed")
	check(not is_instance_valid(world.resources[0].body), "depleted tree is removed")
	player.hunger = 40.0
	check(player.try_eat() and player.hunger == 65.0 and player.inventory.berries == 0, "eating consumes one berry and restores hunger")
	check(not player.try_eat(), "eating requires a berry")
	player.translation = Vector3(0, 0.1, -1.1)
	check(world.try_collect(player) and world.fire_lit and world.fire_light.visible, "three wood and two stone light the campfire")
	check(player.inventory.wood == 0 and player.inventory.stone == 0, "campfire consumes its recipe")
	player.health = 60.0
	yield(wait_seconds(0.4), "completed")
	check(player.health > 60.2, "the lit campfire heals a nearby survivor")

	player.reset_at(Vector3(0, 0.1, 10))
	player.facing = Vector3(0, 0, -1)
	var front = world.enemies[0]
	var behind = world.enemies[1]
	var distant = world.enemies[2]
	front.translation = player.translation + Vector3(0, 0, -1.6)
	behind.translation = player.translation + Vector3(0, 0, 1.6)
	distant.translation = player.translation + Vector3(0, 0, -4)
	check(player.attack() and front.health == 20.0 and behind.health == 45.0 and distant.health == 45.0, "melee hits only enemies within its facing arc and range")
	check(not player.attack() and front.health == 20.0, "attack cooldown prevents an immediate second hit")
	yield(wait_seconds(0.43), "completed")
	check(player.attack() and not front.alive and world.kills == 1 and player.inventory.berries == 1, "second timed hit defeats the enemy and grants its reward")
	yield(wait_seconds(0.05), "completed")
	check(not is_instance_valid(front), "defeated enemy is removed")

	player.reset_at(Vector3(0, 0.1, 10))
	player.hunger = 50.0
	check(player.try_dodge() and player.hunger == 45.0 and player.is_invulnerable(), "dodge consumes hunger and grants temporary invulnerability")
	check(not player.take_damage(14.0) and player.health == 100.0, "dodge blocks incoming damage")
	check(not player.try_dodge(), "dodge cooldown prevents repeated dodges")
	yield(wait_seconds(0.3), "completed")
	check(not player.is_invulnerable() and player.take_damage(14.0) and player.health == 86.0, "damage applies after dodge protection expires")
	check(not player.try_dodge(), "dodge remains on cooldown after protection ends")
	yield(wait_seconds(0.8), "completed")
	check(player.try_dodge(), "dodge becomes available after cooldown")
	yield(wait_seconds(0.25), "completed")
	player.reset_at(Vector3(0, 0.1, 10))
	player.hunger = 4.0
	check(not player.try_dodge() and player.hunger == 4.0, "insufficient hunger prevents a dodge")

	player.reset_at(Vector3(0, 0.1, 10))
	behind.translation = player.translation + Vector3(0, 0, -1.0)
	behind.velocity = Vector3.ZERO
	behind.attack_timer = 0.0
	behind.windup = 0.0
	behind.stagger = 0.0
	behind.set_physics_process(true)
	yield(wait_seconds(0.08), "completed")
	check(behind.windup > 0.0 and player.health == 100.0, "nearby enemy telegraphs before dealing damage")
	yield(wait_seconds(0.25), "completed")
	check(behind.windup > 0.0 and player.health == 100.0, "enemy windup gives time to react")
	yield(wait_seconds(0.45), "completed")
	check(player.health == 86.0 and behind.attack_timer > 0.0, "enemy strike damages the player after its windup")
	behind.set_physics_process(false)

	player.reset_at(Vector3(0, 0.1, 5))
	player.hunger = 0.0
	player.health = 50.0
	yield(wait_seconds(1.2), "completed")
	check(player.health == 46.0, "starvation causes periodic health loss")
	check(player.take_damage(200.0) and not player.alive and player.health == 0.0 and world.death_overlay.visible, "lethal damage shows the death state")
	check(not player.attack() and not player.try_dodge() and not player.try_eat() and not world.try_collect(player), "dead player cannot fight, dodge, eat or gather")
	start = player.translation
	Input.action_press("move_right")
	yield(wait_seconds(0.15), "completed")
	Input.action_release("move_right")
	check(player.translation.distance_to(start) < 0.01, "dead player cannot move")
	world._unhandled_input(action_event("restart"))
	yield(wait_seconds(0.25), "completed")
	world = current_scene
	check(world != null and world.player.alive and world.player.health == 100.0 and world.player.hunger > 99.0 and not world.death_overlay.visible, "restart creates a living survivor with full stats")
	if world == null:
		quit(1)
		return
	check(not world.fire_lit and world.kills == 0 and world.player.inventory.wood == 0 and world.player.inventory.stone == 0 and world.player.inventory.berries == 0 and world.enemies.size() == 3 and world.resources[0].remaining == 3, "restart resets resources, enemies, inventory and campfire")
	current_scene = null
	world.queue_free()
	yield(wait_seconds(0.1), "completed")
	print("SMOKE: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
