extends KinematicBody

signal stats_changed
signal died

const MOVE_SPEED = 5.0
const GRAVITY = 22.0
const ATTACK_INTERVAL = 0.38
const DODGE_SPEED = 12.0
const DODGE_DURATION = 0.20
const DODGE_INTERVAL = 1.0
const DODGE_HUNGER_COST = 5.0
const HUNGER_DRAIN = 0.45
const STARVATION_DAMAGE = 4.0
const BERRY_NOURISHMENT = 25.0

var health = 100.0
var hunger = 100.0
var alive = true
var inventory = {"wood": 0, "stone": 0, "berries": 0}
var facing = Vector3(0, 0, -1)
var velocity = Vector3.ZERO
var attack_cooldown = 0.0
var dodge_cooldown = 0.0
var dodge_time_left = 0.0

var _move_direction = Vector3.ZERO
var _dodge_direction = Vector3.ZERO
var _starvation_time = 0.0
var _damage_flash = 0.0
var _sprite = null
var _camera = null


func _ready():
	collision_layer = 2
	collision_mask = 1

	var collision = CollisionShape.new()
	collision.name = "PlayerCollision"
	var capsule = CapsuleShape.new()
	capsule.radius = 0.32
	capsule.height = 0.90
	collision.shape = capsule
	collision.translation = Vector3(0, 0.80, 0)
	collision.rotation_degrees.x = 90.0
	add_child(collision)

	_sprite = Sprite3D.new()
	_sprite.name = "PlayerSprite"
	_sprite.texture = load("res://assets/player.svg")
	_sprite.pixel_size = 0.0055
	_sprite.translation = Vector3(0, 1.05, 0)
	_sprite.billboard = SpatialMaterial.BILLBOARD_ENABLED
	_sprite.shaded = false
	add_child(_sprite)

	_camera = get_node_or_null("../FollowCamera")
	emit_signal("stats_changed")


func _unhandled_input(event):
	if not alive or event.is_echo():
		return
	if event.is_action_pressed("attack"):
		attack()
	elif event.is_action_pressed("dodge"):
		try_dodge()
	elif event.is_action_pressed("eat"):
		try_eat()
	elif event.is_action_pressed("interact"):
		var world = get_parent()
		if world != null and world.has_method("try_collect"):
			world.try_collect(self)


func _physics_process(delta):
	attack_cooldown = max(0.0, attack_cooldown - delta)
	dodge_cooldown = max(0.0, dodge_cooldown - delta)
	_damage_flash = max(0.0, _damage_flash - delta)
	if not alive:
		_update_sprite()
		return

	_move_direction = _read_movement()
	if _move_direction.length_squared() > 0.001:
		facing = _move_direction.normalized()

	var horizontal_velocity = _move_direction * MOVE_SPEED
	if dodge_time_left > 0.0:
		horizontal_velocity = _dodge_direction * DODGE_SPEED
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0
	velocity.y -= GRAVITY * delta
	velocity = move_and_slide(velocity, Vector3.UP)
	dodge_time_left = max(0.0, dodge_time_left - delta)

	var previous_hunger = hunger
	hunger = max(0.0, hunger - HUNGER_DRAIN * delta)
	if hunger <= 0.0:
		_starvation_time += delta
		if _starvation_time >= 1.0:
			var ticks = floor(_starvation_time)
			_starvation_time -= ticks
			take_damage(STARVATION_DAMAGE * ticks)
	else:
		_starvation_time = 0.0
	if hunger != previous_hunger:
		emit_signal("stats_changed")
	_update_sprite()


func _read_movement():
	var horizontal = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var vertical = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var camera_right = Vector3.RIGHT
	var camera_forward = Vector3(0, 0, -1)
	if not is_instance_valid(_camera):
		_camera = get_node_or_null("../FollowCamera")
	if is_instance_valid(_camera):
		camera_right = _camera.global_transform.basis.x
		camera_forward = -_camera.global_transform.basis.z
		camera_right.y = 0.0
		camera_forward.y = 0.0
		camera_right = camera_right.normalized()
		camera_forward = camera_forward.normalized()
	var movement = camera_right * horizontal + camera_forward * vertical
	if movement.length_squared() > 1.0:
		movement = movement.normalized()
	return movement


func add_item(kind, amount = 1):
	if not alive or not inventory.has(kind) or amount <= 0:
		return false
	inventory[kind] += int(amount)
	emit_signal("stats_changed")
	return true


func take_damage(amount):
	if not alive or amount <= 0.0 or is_invulnerable():
		return false
	health = max(0.0, health - amount)
	_damage_flash = 0.15
	if health <= 0.0:
		alive = false
		velocity = Vector3.ZERO
		dodge_time_left = 0.0
	emit_signal("stats_changed")
	if not alive:
		emit_signal("died")
	return true


func reset_at(position):
	var spawn_transform = global_transform
	spawn_transform.origin = position
	global_transform = spawn_transform
	health = 100.0
	hunger = 100.0
	alive = true
	inventory = {"wood": 0, "stone": 0, "berries": 0}
	facing = Vector3(0, 0, -1)
	velocity = Vector3.ZERO
	attack_cooldown = 0.0
	dodge_cooldown = 0.0
	dodge_time_left = 0.0
	_move_direction = Vector3.ZERO
	_dodge_direction = Vector3.ZERO
	_starvation_time = 0.0
	_damage_flash = 0.0
	_update_sprite()
	emit_signal("stats_changed")


func attack():
	if not alive or attack_cooldown > 0.0 or dodge_time_left > 0.0:
		return false
	var world = get_parent()
	if world == null or not world.has_method("attack_from"):
		return false
	attack_cooldown = ATTACK_INTERVAL
	world.attack_from(self, facing)
	return true


func try_dodge():
	if not alive or dodge_cooldown > 0.0 or hunger < DODGE_HUNGER_COST:
		return false
	_dodge_direction = _read_movement()
	if _dodge_direction.length_squared() < 0.001:
		_dodge_direction = facing
	_dodge_direction = _dodge_direction.normalized()
	facing = _dodge_direction
	dodge_time_left = DODGE_DURATION
	dodge_cooldown = DODGE_INTERVAL
	hunger = max(0.0, hunger - DODGE_HUNGER_COST)
	emit_signal("stats_changed")
	return true


func try_eat():
	if not alive or inventory["berries"] <= 0 or hunger >= 100.0:
		return false
	inventory["berries"] -= 1
	hunger = min(100.0, hunger + BERRY_NOURISHMENT)
	_starvation_time = 0.0
	emit_signal("stats_changed")
	return true


func is_invulnerable():
	return alive and dodge_time_left > 0.0


func _update_sprite():
	if not is_instance_valid(_sprite):
		return
	if not alive:
		_sprite.modulate = Color(0.45, 0.45, 0.45, 1.0)
	elif _damage_flash > 0.0:
		_sprite.modulate = Color(1.0, 0.4, 0.4, 1.0)
	elif is_invulnerable():
		_sprite.modulate = Color(0.55, 0.85, 1.0, 0.75)
	else:
		_sprite.modulate = Color(1, 1, 1, 1)
	var lateral_facing = facing.x
	if is_instance_valid(_camera):
		lateral_facing = facing.dot(_camera.global_transform.basis.x)
	if abs(lateral_facing) > 0.1:
		_sprite.flip_h = lateral_facing < 0.0
