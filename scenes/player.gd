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
@export var leadership: int = 15 # 1-40 scale (Example default) # Added placeholder
@export var player_role : String = "Runner" # Default role (e.g., "Runner", "Passer", "Blocker")

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
@onready var role_indicator: ColorRect = $Sprite2D/RoleIndicator

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
const BLOCKING_ENGAGEMENT_RADIUS: float = 150.0 # How close Blocker targets defender near carrier
const BLOCKING_ENGAGEMENT_RADIUS_SQ: float = BLOCKING_ENGAGEMENT_RADIUS * BLOCKING_ENGAGEMENT_RADIUS

func _ready():
    current_stamina = max_stamina
    ball_node = get_parent().find_child("Ball")
    if ball_node == null: printerr("Player %s couldn't find Ball node!" % player_name)

    if role_indicator: # Check if node exists
        if player_role == "Passer":
            role_indicator.color = Color.YELLOW
        elif player_role == "Runner":
            role_indicator.color = Color.GREEN
        elif player_role == "Blocker":
            role_indicator.color = Color.RED
        else: # Default/Unknown
            role_indicator.color = Color.GRAY
    else:
        printerr("Player %s: Cannot find RoleIndicator node!" % player_name)

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
                    initiate_pass(target_teammate)
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

# -----------------------------------------------------------------------------
# AI TARGETING AND DECISION MAKING HELPERS
# -----------------------------------------------------------------------------
# Determines WHERE the player should move towards this frame
func determine_target_position() -> Vector2:
    if ball_node == null:
        # printerr("Player %s cannot find ball node in determine_target_position!" % player_name) # Reduce noise
        return global_position # Stay put if no ball

    # Determine which goal this player is attacking (the one they score in)
    # If player is team 0, they attack TEAM1_GOAL_CENTER. If team 1, they attack TEAM0_GOAL_CENTER.
    var target_goal_center: Vector2 = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER

    if has_ball:
        # --- Offensive AI (Ball Carrier) --- RUNNING
        # Target the center of the opponent's goal zone
        # print_debug("%s (carrier, Team %d) RUNNING towards %s" % [player_name, team_id, str(target_goal_center)]) # Reduce noise
        return target_goal_center

    elif ball_node.current_possessor == null:
        # --- Ball is loose ---
        # Move towards the ball (Consider only closest players later)
        # print_debug("%s moving to loose ball at %s" % [player_name, str(ball_node.global_position)]) # Reduce noise
        return ball_node.global_position

    else: # Ball is held by someone else
        var carrier = ball_node.current_possessor
        # Check if carrier node is still valid
        if not is_instance_valid(carrier):
             # printerr("Player %s found invalid carrier node!" % player_name) # Reduce noise
             return ball_node.global_position # Target ball if carrier invalid

        # --- Determine if carrier is teammate or opponent ---
        if carrier.team_id != self.team_id:
            # --- Defensive AI ---
            # Move towards the opponent ball carrier
            # print_debug("%s (defender) moving to carrier %s at %s" % [player_name, carrier.player_name, str(carrier.global_position)]) # Reduce noise
            return carrier.global_position
        else:
            # --- Offensive AI (Teammate Support) --- ROLE BASED ---
            # Teammate has the ball, determine action based on this player's role
            if player_role == "Blocker":
                # Blocker targets the nearest relevant defender
                # print_debug("%s (Blocker) looking for defender to block near %s" % [player_name, carrier.player_name]) # Optional debug
                return find_defender_to_block(carrier) # Call the blocker helper function

            elif player_role == "Runner":
                # Runner runs a route downfield towards open space
                # print_debug("%s (Runner) running route." % player_name) # Optional debug
                return find_open_route_position(carrier) # Call the runner helper function

            elif player_role == "Passer":
                # Passer uses basic support logic for now (can be refined later)
                # print_debug("%s (Passer) using basic support logic." % player_name) # Optional debug
                return calculate_basic_support_pos(carrier) # Call the basic helper

            else: # Default/Unknown role - use basic support as fallback
                push_warning("Player %s has unknown role '%s', using default support." % [player_name, player_role])
                return calculate_basic_support_pos(carrier) # Call the basic helper

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

# CORRECTED LOGIC (Team 0 starts/defends Left, Team 1 starts/defends Right)
func is_in_clearing_zone() -> bool:
    # print_debug("Checking kick zone for %s (Team %d) at pos %s" % [player_name, team_id, str(global_position.round())]) # Keep commented out for now
    var threshold = FIELD_HALF_WIDTH * 0.4 # 384.0 if width is 960

    if team_id == 0: # Team 0 DEFENDS Left (-X) side
        return global_position.x < -threshold # Should kick if X < -384.0
    elif team_id == 1: # Team 1 DEFENDS Right (+X) side
        return global_position.x > threshold # Should kick if X > 384.0
    else:
        return false

# ------------------------------------ BALL HANDLING / STATE CHANGES ------------------------------------
func pickup_ball():
    if not has_ball and not get_is_knocked_down(): has_ball = true; can_pass_timer = PASS_COOLDOWN; can_kick_timer = KICK_COOLDOWN; print_debug("%s picked up ball." % player_name)

func lose_ball():
    if has_ball: has_ball = false; print_debug("%s lost ball." % player_name)

func initiate_pass(target_teammate: Node): # Ensure argument is the Node
    if has_ball and ball_node and not get_is_knocked_down():
        # Pass the actual teammate node itself, not just its position
        print_debug("%s attempting pass towards %s" % [player_name, target_teammate.player_name])
        ball_node.initiate_pass(self, target_teammate)

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

# Finds the best opponent defender near the carrier for a Blocker to target
func find_defender_to_block(carrier: Node) -> Vector2:
    var all_players = get_all_players()
    var target_defender: Node = null
    # --- CHANGE: Find defender closest to THIS BLOCKER ---
    var min_dist_sq_to_blocker = INF # Find defender closest to ME
    # ---

    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            # Check if the opponent is reasonably close to the CARRIER first
            var dist_sq_to_carrier = carrier.global_position.distance_squared_to(opponent.global_position)
            if dist_sq_to_carrier < BLOCKING_ENGAGEMENT_RADIUS_SQ:
                # Opponent is near the carrier, now check distance to ME (the blocker)
                var dist_sq_to_me = global_position.distance_squared_to(opponent.global_position)
                if dist_sq_to_me < min_dist_sq_to_blocker:
                    # This is the closest relevant defender found so far *to me*
                    min_dist_sq_to_blocker = dist_sq_to_me
                    target_defender = opponent

    if target_defender != null:
         # Target the found defender
        # print_debug("%s (Blocker) targeting defender %s near carrier." % [player_name, target_defender.player_name])
        return target_defender.global_position
    else:
        # No defender close enough to the carrier, fallback to basic support
        # print_debug("%s (Blocker) found no defender near carrier, using basic support." % player_name)
        # Use the basic support calculation as fallback
        return calculate_basic_support_pos(carrier) # Call helper
        
func calculate_basic_support_pos(carrier: Node) -> Vector2:
    var carrier_target_goal: Vector2 = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    var direction_to_goal = (carrier_target_goal - carrier.global_position).normalized()
    if direction_to_goal == Vector2.ZERO: direction_to_goal = (carrier_target_goal - global_position).normalized()
    if direction_to_goal == Vector2.ZERO: direction_to_goal = Vector2(1, 0) if carrier.team_id == 1 else Vector2(-1, 0)

    var support_position = carrier.global_position + direction_to_goal * 100.0 # Slightly ahead
    var sideways_offset_dir = Vector2(direction_to_goal.y, -direction_to_goal.x)
    var sideways_amount = (hash(player_name) % 100 - 50) # Simple spread
    support_position += sideways_offset_dir * sideways_amount
    return support_position
    
# Add this helper function somewhere in player.gd
func find_open_route_position(carrier: Node) -> Vector2:
    # Simple route: Target a point significantly further downfield towards the goal
    var carrier_target_goal: Vector2 = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    var direction_to_goal = (carrier_target_goal - global_position).normalized()
    if direction_to_goal == Vector2.ZERO: # Avoid zero vector if already near goal
         direction_to_goal = Vector2(1, 0) if carrier.team_id == 1 else Vector2(-1, 0)
    # Target a point ~300 pixels downfield from current position
    var target_route_pos = global_position + direction_to_goal * 300.0
    # Optional improvement: Could check if target_route_pos is "open" using something
    # similar to is_teammate_open, but checking near the target point.
    # For now, just run straight towards that downfield point.
    # Optional improvement 2: Add slight random angle variation to routes
    # target_route_pos = global_position + direction_to_goal.rotated(randf_range(-PI/8, PI/8)) * 300.0
    #print_debug("%s (Runner) running route towards %s" % [player_name, str(target_route_pos.round())])
    return target_route_pos
