# player.gd - Full Corrected Version (May 8th, addressing return path errors)
extends CharacterBody2D

# Player Stats / Configuration
@export var team_id: int = 0
@export var player_name: String = "Player1" # Default, SET UNIQUE IN EDITOR
@export var base_speed: float = 180.0
@export var max_stamina: float = 100.0
@export var agility: int = 15       # 1-40 scale
@export var tackle_power: int = 15  # 1-40 scale
@export var throwing: int = 15      # 1-40 scale
@export var catching: int = 15      # 1-40 scale
@export var kicking: int = 15       # 1-40 scale
@export var leadership: int = 15    # 1-40 scale (Placeholder for now)
@export var player_role : String = "Runner" # "Runner", "Passer", "Blocker"

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
var can_kick_timer: float = 0.0
const KICK_COOLDOWN: float = 0.7

# Node References
@onready var sprite = $Sprite2D
@onready var collision_shape = $CollisionShape2D
@onready var tackle_area = $TackleArea
@onready var tackle_collision_shape = $TackleArea/CollisionShape2D
@onready var role_indicator: ColorRect = $Sprite2D/RoleIndicator # Ensure this path is correct!

# Game World References
var ball_node = null
var game_manager = null # Optional

# Constants for AI/Movement
const FIELD_HALF_WIDTH: float = 960.0
const FIELD_HALF_HEIGHT: float = 540.0 # Added for y_spread calculation
const field_margin: float = 15.0     # Added for y_spread clamping
const GOAL_TARGET_Y: float = 0
const GOAL_TARGET_X_TEAM0: float = -750.0 # Team 0's End Zone (Attacked by Team 1)
const GOAL_TARGET_X_TEAM1: float = 750.0  # Team 1's End Zone (Attacked by Team 0)
const TEAM0_GOAL_CENTER = Vector2(GOAL_TARGET_X_TEAM0, GOAL_TARGET_Y)
const TEAM1_GOAL_CENTER = Vector2(GOAL_TARGET_X_TEAM1, GOAL_TARGET_Y)
const STAMINA_DRAIN_RATE: float = 2.0
const STAMINA_RECOVERY_RATE: float = 5.0

# Constants for AI Decisions
const PRESSURE_RADIUS: float = 100.0
const PRESSURE_RADIUS_SQ: float = PRESSURE_RADIUS * PRESSURE_RADIUS
const OPEN_RADIUS: float = 75.0
const OPEN_RADIUS_SQ: float = OPEN_RADIUS * OPEN_RADIUS
const BLOCKING_ENGAGEMENT_RADIUS: float = 150.0
const BLOCKING_ENGAGEMENT_RADIUS_SQ: float = BLOCKING_ENGAGEMENT_RADIUS * BLOCKING_ENGAGEMENT_RADIUS
const HANDOFF_RADIUS: float = 120.0
const HANDOFF_RADIUS_SQ: float = HANDOFF_RADIUS * HANDOFF_RADIUS
const MAX_LOOSE_BALL_ATTACKERS = 2
const SCORE_ATTEMPT_RANGE: float = 150.0
const SCORE_ATTEMPT_RANGE_SQ: float = SCORE_ATTEMPT_RANGE * SCORE_ATTEMPT_RANGE


func _ready():
    current_stamina = max_stamina
    ball_node = get_parent().find_child("Ball")
    if ball_node == null: printerr("Player %s couldn't find Ball node!" % player_name)

    # Set Role Indicator Color
    if role_indicator:
        if player_role == "Passer": role_indicator.color = Color.YELLOW
        elif player_role == "Runner": role_indicator.color = Color.GREEN
        elif player_role == "Blocker": role_indicator.color = Color.RED
        else: role_indicator.color = Color.GRAY
    else: printerr("Player %s: Cannot find RoleIndicator node! Path used: $Sprite2D/RoleIndicator" % player_name)

    # Set Player Texture
    if team_id == 0:
        if team0_texture: sprite.texture = team0_texture
        else: printerr("Player %s (Team 0) missing team0_texture!" % player_name)
        sprite.modulate = Color.WHITE
    else:
        if team1_texture: sprite.texture = team1_texture
        else: printerr("Player %s (Team 1) missing team1_texture!" % player_name)
        sprite.modulate = Color.WHITE

    # Fallback for player_name property
    if player_name == "" or player_name == "Player":
        player_name = name
        push_warning("Player node '%s' player_name property not set in Inspector, using node name." % name)


func _physics_process(delta):
    # Update Cooldown Timers
    if can_pass_timer > 0.0: can_pass_timer -= delta
    if can_kick_timer > 0.0: can_kick_timer -= delta

    # State Handling: Knockdown
    if get_is_knocked_down(): handle_knockdown(delta); return

    # --- Decision Making (if has ball) ---
    if has_ball:
        var attacking_goal_center = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER
        var distance_to_goal_sq = global_position.distance_squared_to(attacking_goal_center)

        if distance_to_goal_sq < SCORE_ATTEMPT_RANGE_SQ:
            # print_debug("%s is in scoring range, prioritizing run!" % player_name)
            pass # Fall through to standard movement logic which targets the goal
        
        elif player_role == "Blocker":
            var target_for_handoff = find_nearby_offensive_teammate()
            if target_for_handoff != null and can_pass_timer <= 0.0:
                # print_debug("Blocker %s attempting quick pass/handoff to %s" % [player_name, target_for_handoff.player_name])
                initiate_pass(target_for_handoff)
                velocity = Vector2.ZERO
            else:
                velocity = Vector2.ZERO
            move_and_slide()
            return

        elif can_kick_timer <= 0.0 and is_in_clearing_zone():
            initiate_kick()
            # has_ball becomes false, player continues to movement logic as non-carrier

        elif can_pass_timer <= 0.0:
            if is_under_pressure():
                var target_teammate = find_open_teammate()
                if target_teammate != null:
                    # print_debug("%s passing under pressure to OPEN teammate %s!" % [player_name, target_teammate.player_name])
                    initiate_pass(target_teammate)
                    velocity = Vector2.ZERO; move_and_slide(); return

    # --- Stamina ---
    if velocity.length_squared() > 10: current_stamina -= STAMINA_DRAIN_RATE * delta
    else: current_stamina += STAMINA_RECOVERY_RATE * delta
    current_stamina = clamp(current_stamina, 0.0, max_stamina)
    var stamina_factor = clamp(current_stamina / max_stamina, 0.2, 1.0)
    var effective_speed = base_speed * stamina_factor

    # --- AI Movement Targeting ---
    var target_position = determine_target_position()
    var direction = global_position.direction_to(target_position)
    if global_position.distance_squared_to(target_position) > 25: velocity = direction * effective_speed
    else: velocity = Vector2.ZERO

    # --- Execute Movement ---
    move_and_slide()

    # --- Update Sprite Rotation ---
    if velocity.length_squared() > 0: sprite.rotation = velocity.angle()


# -----------------------------------------------------------------------------
# AI TARGETING AND DECISION MAKING HELPERS
# -----------------------------------------------------------------------------
func determine_target_position() -> Vector2:
    if ball_node == null: return global_position

    var target_goal_center: Vector2 = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER

    if has_ball:
        return target_goal_center

    elif ball_node.current_possessor == null: # Ball is loose
        var players = get_all_players()
        var my_dist_sq = global_position.distance_squared_to(ball_node.global_position)
        var players_closer_count = 0
        for p in players:
            if p.global_position.distance_squared_to(ball_node.global_position) < my_dist_sq:
                players_closer_count += 1
        
        if players_closer_count < MAX_LOOSE_BALL_ATTACKERS:
            return ball_node.global_position
        else: # Not one of the designated attackers for loose ball.
            var defensive_hold_x_pos: float
            if team_id == 0: # Team 0 DEFENDS Left side (-X)
                defensive_hold_x_pos = -FIELD_HALF_WIDTH * 0.25
            else: # Team 1 DEFENDS Right side (+X)
                defensive_hold_x_pos = FIELD_HALF_WIDTH * 0.25
            var target_y = ball_node.global_position.y
            target_y += (hash(player_name) % int(FIELD_HALF_HEIGHT * 0.8)) - (FIELD_HALF_HEIGHT * 0.4)
            target_y = clamp(target_y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
            var strategic_target = Vector2(defensive_hold_x_pos, target_y)
            return global_position.lerp(strategic_target, 0.1)

    else: # Ball is held by someone else
        var carrier = ball_node.current_possessor
        if not is_instance_valid(carrier): return ball_node.global_position

        if carrier.team_id != self.team_id: # Defend opponent carrier
            return carrier.global_position
        else: # Offensive Support - ROLE BASED
            if player_role == "Blocker": return find_defender_to_block(carrier)
            elif player_role == "Runner": return find_open_route_position(carrier)
            elif player_role == "Passer": return calculate_basic_support_pos(carrier)
            else: push_warning("Player %s unknown role '%s'." % [player_name, player_role]); return calculate_basic_support_pos(carrier)

# --- Corrected Helper Functions (Return Paths) ---
func get_all_players() -> Array[Node]:
    var players: Array[Node] = []
    var parent = get_parent()
    if parent:
        for child in parent.get_children():
            if child.has_method("get_player_name") and child != self:
                 players.append(child)
    return players

func is_under_pressure() -> bool:
    var all_players = get_all_players()
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if global_position.distance_squared_to(opponent.global_position) < PRESSURE_RADIUS_SQ:
                return true
    return false

func find_open_teammate(): # Removed -> Node type hint for now
    var all_players = get_all_players()
    var best_teammate = null # Default to null
    for teammate in all_players:
        if teammate.team_id == self.team_id and teammate.has_method("get_is_knocked_down") and not teammate.get_is_knocked_down():
            if is_teammate_open(teammate, all_players):
                best_teammate = teammate
                # print_debug("%s found OPEN teammate: %s" % [player_name, best_teammate.player_name]) # Keep commented for noise
                return best_teammate # Return first open teammate found
    return null # Explicitly return null if no one found

func is_teammate_open(teammate_node: Node, all_players: Array[Node]) -> bool:
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if teammate_node.global_position.distance_squared_to(opponent.global_position) < OPEN_RADIUS_SQ:
                return false
    return true

func is_in_clearing_zone() -> bool:
    # print_debug("Checking kick zone for %s (Team %d) at pos %s" % [player_name, team_id, str(global_position.round())])
    var threshold = FIELD_HALF_WIDTH * 0.4
    if team_id == 0: # Team 0 DEFENDS Left (-X) side
        # print_debug("  Team 0 Check: %s < %s ? Result: %s" % [global_position.x, -threshold, global_position.x < -threshold])
        return global_position.x < -threshold
    elif team_id == 1: # Team 1 DEFENDS Right (+X) side
        # print_debug("  Team 1 Check: %s > %s ? Result: %s" % [global_position.x, threshold, global_position.x > threshold])
        return global_position.x > threshold
    return false

func find_defender_to_block(carrier: Node) -> Vector2:
    var all_players = get_all_players()
    var target_defender: Node = null
    var min_dist_sq_to_blocker = BLOCKING_ENGAGEMENT_RADIUS_SQ # Check within this range OF BLOCKER
    # Removed closest_defender_pos
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            var dist_sq_to_carrier = carrier.global_position.distance_squared_to(opponent.global_position)
            if dist_sq_to_carrier < BLOCKING_ENGAGEMENT_RADIUS_SQ:
                var dist_sq_to_me = global_position.distance_squared_to(opponent.global_position)
                if dist_sq_to_me < min_dist_sq_to_blocker:
                    min_dist_sq_to_blocker = dist_sq_to_me; target_defender = opponent
    if target_defender != null: return target_defender.global_position
    else: return calculate_basic_support_pos(carrier)

func calculate_basic_support_pos(carrier: Node) -> Vector2:
    var target_goal = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    var dir_to_goal = (target_goal - carrier.global_position).normalized()
    if dir_to_goal==Vector2.ZERO: dir_to_goal = (target_goal - global_position).normalized()
    if dir_to_goal==Vector2.ZERO: dir_to_goal = Vector2(1,0) if carrier.team_id==0 else Vector2(-1,0)
    var support_pos = carrier.global_position + dir_to_goal * 100.0
    var side_dir = Vector2(dir_to_goal.y, -dir_to_goal.x); var side_amt = (hash(player_name)%100-50)
    support_pos += side_dir * side_amt; return support_pos

# Calculates a target point downfield for Runners supporting the carrier
func find_open_route_position(carrier: Node) -> Vector2: # carrier parameter is now used
    # Determine the goal the CARRIER's team is attacking
    var carrier_target_goal: Vector2 = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER

    # Calculate direction from THIS RUNNER'S position to the CARRIER'S attacking goal
    var direction_to_goal = (carrier_target_goal - global_position).normalized()

    # Safety check for zero vector if runner is already at/near that goal
    if direction_to_goal == Vector2.ZERO:
        # Fallback direction based on which way the CARRIER'S team generally attacks
        # Team 0 (carrier) attacks Right (+X), Team 1 (carrier) attacks Left (-X)
        direction_to_goal = Vector2(1, 0) if carrier.team_id == 0 else Vector2(-1, 0)

    var route_distance = 300.0 # How far downfield to target (tune this)
    var random_angle_variation = randf_range(-PI / 10.0, PI / 10.0) # +/- 18 degrees approx
    var target_direction = direction_to_goal.rotated(random_angle_variation)

    var target_route_pos = global_position + target_direction * route_distance

    # print_debug("%s (Runner) running route towards %s" % [player_name, str(target_route_pos.round())])
    return target_route_pos

func find_nearby_offensive_teammate(): # Returns Node or null
    var players = get_all_players(); var closest_tm: Node = null
    var min_dist_sq = HANDOFF_RADIUS_SQ
    for tm in players:
        if tm.team_id == self.team_id and tm.has_method("get_is_knocked_down") and not tm.get_is_knocked_down() \
        and tm.has_method("get"):
            var role = tm.get("player_role")
            if role == "Runner" or role == "Passer":
                var dist_sq = global_position.distance_squared_to(tm.global_position)
                if dist_sq < min_dist_sq: min_dist_sq = dist_sq; closest_tm = tm
    return closest_tm

# ------------------------------------ BALL HANDLING / STATE CHANGES ------------------------------------
func pickup_ball():
    if not has_ball and not get_is_knocked_down(): has_ball = true; can_pass_timer = PASS_COOLDOWN; can_kick_timer = KICK_COOLDOWN; print_debug("%s picked up ball." % player_name)

func lose_ball():
    if has_ball: has_ball = false; print_debug("%s lost ball." % player_name)

func initiate_pass(target_teammate: Node):
    if has_ball and ball_node and not get_is_knocked_down():
        ball_node.initiate_pass(self, target_teammate)

func initiate_kick():
    if has_ball and ball_node and not get_is_knocked_down():
        var target_goal = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER
        print_debug("%s KICK towards %s" % [player_name, str(target_goal)])
        ball_node.initiate_kick(self, target_goal)
        can_kick_timer = KICK_COOLDOWN; can_pass_timer = PASS_COOLDOWN

# ------------------------------------ TACKLING & KNOCKDOWN ------------------------------------
func _on_tackle_area_body_entered(body):
    if body.has_method("get_player_name") and body != self and body.team_id != team_id \
    and body.has_method("get_is_knocked_down") and not body.get_is_knocked_down():
        if body.has_ball:
            if tackle_power > body.agility:
                print_debug("Tackle SUCCEEDED by %s on %s!" % [player_name, body.player_name])
                body.apply_knockdown(self)
                if ball_node and ball_node.current_possessor == body:
                    ball_node.set_loose(body.velocity)

func apply_knockdown(_tackler):
    if not get_is_knocked_down():
        print_debug(">>> %s applying knockdown, DISABLING shape: %s" % [player_name, collision_shape.name if collision_shape else "NULL"])
        is_knocked_down = true; knockdown_timer = KNOCKDOWN_DURATION; velocity = Vector2.ZERO
        if collision_shape: collision_shape.set_deferred("disabled", true)
        else: printerr("ERROR: %s missing collision_shape for knockdown!" % player_name)

func handle_knockdown(delta):
    knockdown_timer -= delta; velocity = velocity.move_toward(Vector2.ZERO, 300 * delta); move_and_slide()
    if knockdown_timer <= 0:
        is_knocked_down = false
        print_debug("<<< %s getting up, ENABLING shape: %s" % [player_name, collision_shape.name if collision_shape else "NULL"])
        if collision_shape and collision_shape.disabled: collision_shape.set_deferred("disabled", false)

# ------------------------------------ UTILITY / GETTERS / RESET ------------------------------------
func get_player_name() -> String: return str(player_name) if player_name != "" and player_name != "Player" else str(name)
func get_is_knocked_down() -> bool: return is_knocked_down
func reset_state(): print_debug("Reset state for %s" % player_name); is_knocked_down = false; knockdown_timer = 0.0; has_ball = false; can_pass_timer = 0.0; can_kick_timer = 0.0; current_stamina = max_stamina; if collision_shape and collision_shape.disabled: collision_shape.set_deferred("disabled", false); velocity = Vector2.ZERO
