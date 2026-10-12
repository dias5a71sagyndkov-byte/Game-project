extends KinematicBody

var health = 45.0
var alive = true
var target = null
var velocity = Vector3.ZERO
var attack_timer = 0.0
var windup = 0.0
var stagger = 0.0
var attack_direction = Vector3.ZERO
var sprite = null

func _ready():
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 | 2
	var shape = CollisionShape.new()
	var capsule = CapsuleShape.new()
	capsule.radius = 0.38
	capsule.height = 0.55
	shape.shape = capsule
	shape.translation.y = 0.7
	shape.rotation_degrees.x = 90.0
	add_child(shape)
	sprite = Sprite3D.new()
	sprite.texture = load("res://assets/enemy.svg")
	sprite.pixel_size = 0.006
	sprite.translation.y = 0.72
	sprite.billboard = SpatialMaterial.BILLBOARD_ENABLED
	add_child(sprite)
	var shadow = MeshInstance.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.48
	mesh.bottom_radius = 0.48
	mesh.height = 0.016
	mesh.radial_segments = 16
	shadow.mesh = mesh
	var material = SpatialMaterial.new()
	material.albedo_color = Color(0.06, 0.09, 0.08)
	material.flags_unshaded = true
	shadow.material_override = material
	shadow.translation.y = 0.015
	add_child(shadow)

func _physics_process(delta):
	if not alive or target == null or not target.alive:
		return
	attack_timer = max(0.0, attack_timer - delta)
	stagger = max(0.0, stagger - delta)
	var offset = target.global_transform.origin - global_transform.origin
	offset.y = 0.0
	var distance = offset.length()
	var direction = offset.normalized()
	if stagger > 0.0:
		velocity.x = lerp(velocity.x, 0.0, delta * 7.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 7.0)
	elif windup > 0.0:
		windup = max(0.0, windup - delta)
		velocity.x = 0.0
		velocity.z = 0.0
		sprite.modulate = Color(1.6, 0.6, 0.35)
		if windup <= 0.0:
			if distance < 1.8 and direction.dot(attack_direction) > 0.25:
				target.take_damage(14.0)
			attack_timer = 1.2
	elif distance < 1.35 and attack_timer <= 0.0:
		windup = 0.65
		attack_direction = direction
	elif distance < 10.0:
		var fleeing = get_parent().fire_lit and target.translation.distance_to(get_parent().fire_position) < 3.0
		var speed = 2.0 if not fleeing else -2.5
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		sprite.modulate = Color.white
		sprite.flip_h = direction.x < 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		sprite.modulate = Color.white
	velocity.y -= 20.0 * delta
	velocity = move_and_slide(velocity, Vector3.UP)

func receive_hit(amount, direction):
	if not alive:
		return
	health -= amount
	windup = 0.0
	stagger = 0.25
	velocity.x = direction.x * 7.0
	velocity.z = direction.z * 7.0
	sprite.modulate = Color(1.8, 1.8, 1.8)
	if health <= 0.0:
		alive = false
		get_parent().enemy_defeated(self)
		queue_free()
