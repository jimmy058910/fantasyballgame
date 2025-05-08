# player.gd - Roles Implemented (Blocker targets defender, Runner runs route)
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
@export var leadership: int = 15 # 1-40 scale (Placeholder)
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
var game_manager = null

# Constants for AI/Movement
const FIELD_HALF_WIDTH: float = 960.0
const GOAL_TARGET_Y: float = 0
const GOAL_TARGET_X_TEAM0: float = -750.0 # Attacked by Team 1 (Left Goal)
const GOAL_TARGET_X_TEAM1: float = 750.0  # Attacked by Team 0 (Right Goal)
const TEAM0_GOAL_CENTER = Vector2(GOAL_TARGET_X_TEAM0, GOAL_TARGET_Y)
const TEAM1_GOAL_CENTER = Vector2(GOAL_TARGET_X_TEAM1, GOAL_TARGET_Y)
const STAMINA_DRAIN_RATE: float = 2.0
const STAMINA_RECOVERY_RATE: float = 5.0

# Constants for AI Passing / Roles
const PRESSURE_RADIUS: float = 100.0
const PRESSURE_RADIUS_SQ: float = PRESSURE_RADIUS * PRESSURE_RADIUS
const OPEN_RADIUS: float = 75.0
const OPEN_RADIUS_SQ: float = OPEN_RADIUS * OPEN_RADIUS
const BLOCKING_ENGAGEMENT_RADIUS: float = 150.0
const BLOCKING_ENGAGEMENT_RADIUS_SQ: float = BLOCKING_ENGAGEMENT_RADIUS * BLOCKING_ENGAGEMENT_RADIUS


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
    else: printerr("Player %s: Cannot find RoleIndicator node!" % player_name)

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

    # --- Decision Making: Kick? Pass? Run? ---
    if has_ball:
        # Check for Clearing Kick FIRST
        if can_kick_timer <= 0.0 and is_in_clearing_zone():
            # print_debug("%s is in clearing zone, attempting kick." % player_name) # Keep commented
            initiate_kick()
            # Player continues movement logic after kick decision

        # Check for Passing SECOND (only if didn't kick and pass cooldown ready)
        elif can_pass_timer <= 0.0:
            if is_under_pressure():
                var target_teammate = find_open_teammate()
                if target_teammate != null:
                    print_debug("%s passing under pressure to OPEN teammate %s!" % [player_name, target_teammate.player_name])
                    initiate_pass(target_teammate) # Pass the node
                    velocity = Vector2.ZERO; move_and_slide(); return # Stop and exit frame

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
# Determines WHERE the player should move towards this frame
func determine_target_position() -> Vector2:
    if ball_node == null: return global_position

    # Determine which goal this player is attacking
    # Team 0 (Left Start) attacks Right (+750), Team 1 (Right Start) attacks Left (-750)
    var target_goal_center: Vector2 = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER

    if has_ball:
        # Carrier runs for goal
        return target_goal_center
    elif ball_node.current_possessor == null:
        # Go to loose ball
        return ball_node.global_position
    else: # Ball held by someone else
        var carrier = ball_node.current_possessor
        if not is_instance_valid(carrier): return ball_node.global_position
        if carrier.team_id != self.team_id:
            # Defend opponent carrier
            return carrier.global_position
        else:
            # Offensive Support - ROLE BASED
            if player_role == "Blocker":
                return find_defender_to_block(carrier)
            elif player_role == "Runner":
                return find_open_route_position(carrier)
            elif player_role == "Passer":
                return calculate_basic_support_pos(carrier) # Basic support for now
            else: # Default/Unknown role
                push_warning("Player %s has unknown role '%s'." % [player_name, player_role])
                return calculate_basic_support_pos(carrier)


# Helper to get a list of other player nodes
func get_all_players() -> Array[Node]:
    # Initialize the typed array
    var players: Array[Node] = []
    # Get the parent node safely
    var parent = get_parent()

    # Only loop through children if the parent exists
    if parent:
        for child in parent.get_children():
            # Check if the child is another player (has the method and isn't self)
            if child.has_method("get_player_name") and child != self:
                 players.append(child) # Add the valid player node

    # ALWAYS return the array (it will be empty if no parent or no other players found)
    return players

# Check if an opponent is within the pressure radius
func is_under_pressure() -> bool:
    var all_players = get_all_players()
    for opponent in all_players:
        if opponent.team_id != team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if global_position.distance_squared_to(opponent.global_position) < PRESSURE_RADIUS_SQ:
                return true
    return false

# Finds the first available "open" teammate
func find_open_teammate(): # Removed -> Node hint
    var all_players = get_all_players()
    var best_teammate = null
    for teammate in all_players:
        if teammate.team_id == team_id and teammate.has_method("get_is_knocked_down") and not teammate.get_is_knocked_down():
            if is_teammate_open(teammate, all_players):
                best_teammate = teammate
                print_debug("%s found OPEN teammate: %s" % [player_name, best_teammate.player_name])
                return best_teammate
    return null

# Helper function to check if a specific teammate is "open"
func is_teammate_open(teammate_node: Node, all_players: Array[Node]) -> bool:
    for opponent in all_players:
        if opponent.team_id != team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if teammate_node.global_position.distance_squared_to(opponent.global_position) < OPEN_RADIUS_SQ:
                return false
    return true

# Checks if the player is within their own 30% of the field (defensive end)
func is_in_clearing_zone() -> bool:
    # print_debug("Checking kick zone for %s (Team %d) at pos %s" % [player_name, team_id, str(global_position.round())]) # Commented out
    var threshold = FIELD_HALF_WIDTH * 0.4 # = 384.0 if width is 960
    if team_id == 0: # Team 0 DEFENDS Left (-X) side
        # print_debug("  Team 0 Check: %s < %s ? Result: %s" % [global_position.x, -threshold, result]) # Keep commented
        return global_position.x < -threshold # Should kick if X < -384.0
    elif team_id == 1: # Team 1 DEFENDS Right (+X) side
        # print_debug("  Team 1 Check: %s > %s ? Result: %s" % [global_position.x, threshold, result]) # Keep commented
        return global_position.x > threshold # Should kick if X > 384.0
    else:
        return false


# Finds the best opponent defender near the carrier for a Blocker to target
func find_defender_to_block(carrier: Node) -> Vector2:
    var all_players = get_all_players()
    var target_defender: Node = null
    var min_dist_sq_to_blocker = INF # Find defender closest to ME

    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            # Check if opponent is reasonably close to the CARRIER
            var dist_sq_to_carrier = carrier.global_position.distance_squared_to(opponent.global_position)
            if dist_sq_to_carrier < BLOCKING_ENGAGEMENT_RADIUS_SQ:
                # Check distance to ME (the blocker)
                var dist_sq_to_me = global_position.distance_squared_to(opponent.global_position)
                if dist_sq_to_me < min_dist_sq_to_blocker:
                    # This is the closest relevant defender found so far *to me*
                    min_dist_sq_to_blocker = dist_sq_to_me
                    target_defender = opponent

    if target_defender != null:
        return target_defender.global_position # Target the defender
    else:
        # No relevant defender nearby, use basic support logic as fallback
        return calculate_basic_support_pos(carrier)


# Calculates basic support position (slightly ahead/offset from carrier) - Used by Passers/Fallback
func calculate_basic_support_pos(carrier: Node) -> Vector2:
    var carrier_target_goal: Vector2 = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    var direction_to_goal = (carrier_target_goal - carrier.global_position).normalized()
    if direction_to_goal == Vector2.ZERO: direction_to_goal = (carrier_target_goal - global_position).normalized()
    if direction_to_goal == Vector2.ZERO: direction_to_goal = Vector2(1, 0) if carrier.team_id == 0 else Vector2(-1, 0) # Team 0 attacks R, Team 1 attacks L

    var support_position = carrier.global_position + direction_to_goal * 100.0
    var sideways_offset_dir = Vector2(direction_to_goal.y, -direction_to_goal.x)
    var sideways_amount = (hash(player_name) % 100 - 50)
    support_position += sideways_offset_dir * sideways_amount
    return support_position


# Calculates a target point downfield for Runners supporting the carrier
func find_open_route_position(carrier: Node) -> Vector2:
    var carrier_target_goal: Vector2 = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    var direction_to_goal = (carrier_target_goal - global_position).normalized()
    if direction_to_goal == Vector2.ZERO:
        direction_to_goal = Vector2(1, 0) if team_id == 0 else Vector2(-1, 0)

    var route_distance = 300.0 # How far downfield to target (tune this)
    # --- UPDATED: Add random angle variation ---
    var random_angle_variation = randf_range(-PI / 10.0, PI / 10.0) # +/- 18 degrees approx
    var target_direction = direction_to_goal.rotated(random_angle_variation)
    # --- END UPDATE ---

    var target_route_pos = global_position + target_direction * route_distance

    # Future: Check if target_route_pos is open / clamp to field
    return target_route_pos


# ------------------------------------ BALL HANDLING / STATE CHANGES ------------------------------------
func pickup_ball():
    if not has_ball and not get_is_knocked_down():
        has_ball = true; can_pass_timer = PASS_COOLDOWN; can_kick_timer = KICK_COOLDOWN
        print_debug("%s picked up ball." % player_name)

func lose_ball():
    if has_ball:
        has_ball = false;
        print_debug("%s lost ball." % player_name)

func initiate_pass(target_teammate: Node): # Expects Node
    if has_ball and ball_node and not get_is_knocked_down():
        ball_node.initiate_pass(self, target_teammate) # Pass Node

func initiate_kick():
    if has_ball and ball_node and not get_is_knocked_down():
        var target_goal = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER
        print_debug("%s KICK towards %s" % [player_name, str(target_goal)])
        ball_node.initiate_kick(self, target_goal) # Pass target Vector
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

# Called BY the player who successfully tackled THIS player
func apply_knockdown(_tackler): # Fixed unused parameter
    # Only apply if not already knocked down
    if not get_is_knocked_down(): # Use getter function
        print_debug("%s is knocked down!" % player_name)
        is_knocked_down = true # Set the state variable
        knockdown_timer = KNOCKDOWN_DURATION
        velocity = Vector2.ZERO # Stop movement

        # --- Debug Print for Disabling ---
        print_debug(">>> %s applying knockdown, DISABLING shape: %s" % [player_name, collision_shape.name if collision_shape else "NULL"])
        # ---

        # Disable collision shape safely
        if collision_shape:
            collision_shape.set_deferred("disabled", true)
        else:
            # Error if shape node not found
            printerr("ERROR in apply_knockdown for %s: Cannot find collision_shape node to disable!" % player_name)


# Called from _physics_process when is_knocked_down is true
func handle_knockdown(delta):
    knockdown_timer -= delta
    # Apply friction/damping to stop any residual movement
    velocity = velocity.move_toward(Vector2.ZERO, 300 * delta)
    move_and_slide() # Apply damping movement

    # Check if timer is up
    if knockdown_timer <= 0:
        is_knocked_down = false # Update state

        # --- Debug Print for Enabling ---
        print_debug("<<< %s getting up, ENABLING shape: %s" % [player_name, collision_shape.name if collision_shape else "NULL"])
        # ---

        # Re-enable collision shape safely only if it exists and was disabled
        if collision_shape and collision_shape.disabled:
            collision_shape.set_deferred("disabled", false)

# ------------------------------------ UTILITY / GETTERS / RESET ------------------------------------
func get_player_name() -> String: return str(player_name) if player_name != "" and player_name != "Player" else str(name)
func get_is_knocked_down() -> bool: return is_knocked_down
func reset_state(): print_debug("Reset state for %s" % player_name); is_knocked_down = false; knockdown_timer = 0.0; has_ball = false; can_pass_timer = 0.0; can_kick_timer = 0.0; current_stamina = max_stamina; if collision_shape and collision_shape.disabled: collision_shape.set_deferred("disabled", false); velocity = Vector2.ZERO
