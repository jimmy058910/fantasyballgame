# player.gd - Includes Throwing/Catching/Kicking stats, pass cooldown, reset_state, fixes
extends CharacterBody2D

# Player Stats / Configuration
@export var team_id: int = 0
@export var player_name: String = "Player1" # Default, SET UNIQUE IN EDITOR
@export var base_speed: float = 180.0
@export var max_stamina: float = 100.0
@export var agility: int = 5 # 1-40 scale
@export var tackle_power: int = 5 # 1-40 scale
@export var throwing: int = 15 # 1-40 scale
@export var catching: int = 15 # 1-40 scale
@export var kicking: int = 15 # 1-40 scale

# Visuals
@export var team0_texture: Texture2D
@export var team1_texture: Texture2D

# State Variables
var current_stamina: float
var has_ball: bool = false
var is_knocked_down: bool = false
var knockdown_timer: float = 0.0
const KNOCKDOWN_DURATION: float = 1.5
var can_pass_timer: float = 0.0
const PASS_COOLDOWN: float = 0.5
var can_kick_timer: float = 0.1 # Cooldown timer for kicking after pickup
const KICK_COOLDOWN: float = 0.7 # Make slightly longer than pass? Tune later


# Node References
@onready var sprite = $Sprite2D
@onready var collision_shape = $CollisionShape2D
@onready var tackle_area = $TackleArea
@onready var tackle_collision_shape = $TackleArea/CollisionShape2D

# Game World References
var ball_node = null
var game_manager = null

# Constants for AI/Movement
const FIELD_HALF_WIDTH: float = 960.0 # Needed for clearing zone check
const GOAL_TARGET_Y: float = 0
const GOAL_TARGET_X_TEAM0: float = -750.0 # Attacked by Team 1
const GOAL_TARGET_X_TEAM1: float = 750.0  # Attacked by Team 0
const TEAM0_GOAL_CENTER = Vector2(GOAL_TARGET_X_TEAM0, GOAL_TARGET_Y)
const TEAM1_GOAL_CENTER = Vector2(GOAL_TARGET_X_TEAM1, GOAL_TARGET_Y)
const STAMINA_DRAIN_RATE: float = 2.0
const STAMINA_RECOVERY_RATE: float = 5.0

# Constants for AI Passing
const PRESSURE_RADIUS: float = 100.0
const PRESSURE_RADIUS_SQ: float = PRESSURE_RADIUS * PRESSURE_RADIUS
const OPEN_RADIUS: float = 75.0
const OPEN_RADIUS_SQ: float = OPEN_RADIUS * OPEN_RADIUS


func _ready():
    current_stamina = max_stamina
    ball_node = get_parent().find_child("Ball")
    if ball_node == null: printerr("Player %s couldn't find Ball node!" % player_name)

    if team_id == 0:
        if team0_texture: sprite.texture = team0_texture
        else: printerr("Player %s (Team 0) missing team0_texture!" % player_name)
        sprite.modulate = Color.WHITE
    else:
        if team1_texture: sprite.texture = team1_texture
        else: printerr("Player %s (Team 1) missing team1_texture!" % player_name)
        sprite.modulate = Color.WHITE

    if player_name == "" or player_name == "Player":
        player_name = name
        push_warning("Player node '%s' player_name property not set in Inspector, using node name." % name)


func _physics_process(delta):
    if can_pass_timer > 0.0: can_pass_timer -= delta
    if can_kick_timer > 0.0: can_kick_timer -= delta

    if get_is_knocked_down(): handle_knockdown(delta); return

    if has_ball:
        if can_kick_timer <= 0.0 and is_in_clearing_zone():
            print_debug("%s is in clearing zone, attempting kick." % player_name)
            initiate_kick()
            # Player continues movement logic after kick decision

        elif can_pass_timer <= 0.0:
            if is_under_pressure():
                var target_teammate = find_open_teammate()
                if target_teammate != null:
                    print_debug("%s passing under pressure to OPEN teammate %s!" % [player_name, target_teammate.player_name])
                    initiate_pass(target_teammate.global_position)
                    velocity = Vector2.ZERO; move_and_slide(); return

    if velocity.length_squared() > 10: current_stamina -= STAMINA_DRAIN_RATE * delta
    else: current_stamina += STAMINA_RECOVERY_RATE * delta
    current_stamina = clamp(current_stamina, 0.0, max_stamina)
    var stamina_factor = clamp(current_stamina / max_stamina, 0.2, 1.0)
    var effective_speed = base_speed * stamina_factor

    var target_position = determine_target_position()
    var direction = global_position.direction_to(target_position)
    if global_position.distance_squared_to(target_position) > 25: velocity = direction * effective_speed
    else: velocity = Vector2.ZERO

    move_and_slide()

    if velocity.length_squared() > 0: sprite.rotation = velocity.angle()

# ------------------------------------ AI HELPERS ------------------------------------
func determine_target_position() -> Vector2:
    if ball_node == null: return global_position
    var target_goal_center: Vector2 = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER
    if has_ball: return target_goal_center
    elif ball_node.current_possessor == null: return ball_node.global_position
    else:
        var carrier = ball_node.current_possessor
        if not is_instance_valid(carrier): return ball_node.global_position
        if carrier.team_id != self.team_id: return carrier.global_position
        else:
            var carrier_target_goal: Vector2 = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
            var dir_to_goal = (carrier_target_goal - carrier.global_position).normalized()
            if dir_to_goal == Vector2.ZERO: dir_to_goal = (carrier_target_goal - global_position).normalized()
            if dir_to_goal == Vector2.ZERO: dir_to_goal = Vector2(1, 0) if carrier.team_id == 1 else Vector2(-1, 0)
            var support_pos = carrier.global_position + dir_to_goal * 100.0
            var side_dir = Vector2(dir_to_goal.y, -dir_to_goal.x)
            var side_amt = (hash(player_name) % 100 - 50)
            support_pos += side_dir * side_amt
            return support_pos

func get_all_players() -> Array[Node]:
    var players: Array[Node] = []
    var parent = get_parent()
    if parent:
        for child in parent.get_children():
            if child.has_method("get_player_name") and child != self:
                 players.append(child)
    # else: # No parent, players array will be empty
    #    printerr("Player %s cannot get parent!" % player_name) # Optional debug
    return players # ALWAYS return the array (even if empty)

func is_under_pressure() -> bool:
    var all_players = get_all_players()
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if global_position.distance_squared_to(opponent.global_position) < PRESSURE_RADIUS_SQ:
                return true # Exit and return true immediately if pressure found
    return false # Return false if loop completes without finding pressure

func find_open_teammate():
    var all_players = get_all_players()
    var best_teammate = null
    for teammate in all_players:
        if teammate.team_id == self.team_id and teammate.has_method("get_is_knocked_down") and not teammate.get_is_knocked_down():
            if is_teammate_open(teammate, all_players):
                best_teammate = teammate
                print_debug("%s found OPEN teammate: %s" % [player_name, best_teammate.player_name])
                return best_teammate # Return found teammate immediately
    return null # Return null explicitly if loop finishes

func is_teammate_open(teammate_node: Node, all_players: Array[Node]) -> bool:
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if teammate_node.global_position.distance_squared_to(opponent.global_position) < OPEN_RADIUS_SQ:
                return false # Return false immediately if any opponent is too close
    return true # Return true if loop completes without finding any close opponents

func is_in_clearing_zone() -> bool:
    print_debug("Checking kick zone for %s (Team %d) at pos %s" % [player_name, team_id, str(global_position.round())])
    if team_id == 0: return global_position.x > (FIELD_HALF_WIDTH * 0.4) # Team 0 starts Right (+X), own 30% is > 0.4*HalfWidth
    elif team_id == 1: return global_position.x < (-FIELD_HALF_WIDTH * 0.4) # Team 1 starts Left (-X), own 30% is < -0.4*HalfWidth
    else: return false

# ------------------------------------ BALL HANDLING / STATE CHANGES ------------------------------------
func pickup_ball():
    if not has_ball and not get_is_knocked_down(): has_ball = true; can_pass_timer = PASS_COOLDOWN; can_kick_timer = KICK_COOLDOWN; print_debug("%s picked up ball." % player_name)

func lose_ball():
    if has_ball: has_ball = false; print_debug("%s lost ball." % player_name)

func initiate_pass(target_position: Vector2):
    if has_ball and ball_node and not get_is_knocked_down(): ball_node.initiate_pass(self, target_position)

func initiate_kick():
    if has_ball and ball_node and not get_is_knocked_down(): var target_goal = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER; print_debug("%s KICK towards %s" % [player_name, str(target_goal)]); ball_node.initiate_kick(self, target_goal); can_kick_timer = KICK_COOLDOWN; can_pass_timer = PASS_COOLDOWN

# ------------------------------------ TACKLING & KNOCKDOWN ------------------------------------
func _on_tackle_area_body_entered(body):
    if body.has_method("get_player_name") and body != self and body.team_id != team_id and body.has_method("get_is_knocked_down") and not body.get_is_knocked_down(): if body.has_ball: if tackle_power > body.agility: print_debug("Tackle SUCCEEDED by %s on %s!" % [player_name, body.player_name]); body.apply_knockdown(self); if ball_node and ball_node.current_possessor == body: ball_node.set_loose(body.velocity)

# Called BY the player who successfully tackled THIS player
func apply_knockdown(_tackler): # Fixed unused parameter
    # Only apply if not already knocked down
    if not get_is_knocked_down(): # Use getter function
        print_debug("%s is knocked down!" % player_name) # Added a debug print here
        is_knocked_down = true # Set the state variable
        knockdown_timer = KNOCKDOWN_DURATION
        velocity = Vector2.ZERO # Stop movement

        # Disable collision shape safely
        if collision_shape:
            collision_shape.set_deferred("disabled", true)
        else:
            # Error if shape node not found
            printerr("ERROR in apply_knockdown for %s: Cannot find collision_shape node to disable!" % player_name)
func handle_knockdown(delta):
    knockdown_timer -= delta; velocity = velocity.move_toward(Vector2.ZERO, 300 * delta); move_and_slide()
    if knockdown_timer <= 0: is_knocked_down = false; if collision_shape and collision_shape.disabled: collision_shape.set_deferred("disabled", false)

# ------------------------------------ UTILITY / GETTERS / RESET ------------------------------------
func get_player_name() -> String: return str(player_name) if player_name != "" and player_name != "Player" else str(name)
func get_is_knocked_down() -> bool: return is_knocked_down
func reset_state(): print_debug("Reset state for %s" % player_name); is_knocked_down = false; knockdown_timer = 0.0; has_ball = false; can_pass_timer = 0.0; can_kick_timer = 0.0; current_stamina = max_stamina; if collision_shape and collision_shape.disabled: collision_shape.set_deferred("disabled", false); velocity = Vector2.ZERO
