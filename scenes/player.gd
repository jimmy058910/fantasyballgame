# player.gd - Includes pass cooldown, open teammate logic, reduced logging
extends CharacterBody2D

# Player Stats / Configuration
@export var team_id: int = 0
@export var player_name: String = "Player1" # Default, SET UNIQUE IN EDITOR
@export var base_speed: float = 180.0  # Pixels per second
@export var max_stamina: float = 100.0
@export var agility: int = 5 # Used for tackle evasion/contests
@export var tackle_power: int = 5 # Used for tackle contests
# Add other stats as needed (Throwing, Catching, Kicking, Awareness, etc.)

# Visuals
@export var team0_texture: Texture2D
@export var team1_texture: Texture2D

# State Variables
var current_stamina: float
var has_ball: bool = false
var is_knocked_down: bool = false # The state variable
var knockdown_timer: float = 0.0
const KNOCKDOWN_DURATION: float = 1.5 # How long a player stays down
var can_pass_timer: float = 0.0 # Cooldown timer for passing after pickup
const PASS_COOLDOWN: float = 0.5 # Wait half a second after pickup before passing

# Node References (Assign in the Inspector or use @onready)
@onready var sprite = $Sprite2D # Or whatever your visual node is called
@onready var collision_shape = $CollisionShape2D # Assuming this is the main body shape
@onready var tackle_area = $TackleArea # The Area2D used for initiating tackles
@onready var tackle_collision_shape = $TackleArea/CollisionShape2D # Shape for the tackle area

# Game World References (Need to be set externally or found)
var ball_node = null # Reference to the single ball instance in the game
var game_manager = null # Optional: Reference to a game manager/state node

# Constants for AI/Movement
const GOAL_TARGET_Y: float = 0 # Goals are horizontal now
const GOAL_TARGET_X_TEAM0: float = -750.0 # Team 0's End Zone Center (Attacked by Team 1)
const GOAL_TARGET_X_TEAM1: float = 750.0  # Team 1's End Zone Center (Attacked by Team 0)
const TEAM0_GOAL_CENTER = Vector2(GOAL_TARGET_X_TEAM0, GOAL_TARGET_Y)
const TEAM1_GOAL_CENTER = Vector2(GOAL_TARGET_X_TEAM1, GOAL_TARGET_Y)
const STAMINA_DRAIN_RATE: float = 2.0 # Stamina points per second while moving fast
const STAMINA_RECOVERY_RATE: float = 5.0 # Stamina points per second while idle/slow

# Constants for AI Passing
const PRESSURE_RADIUS: float = 100.0  # How close an opponent needs to be to cause pressure
const PRESSURE_RADIUS_SQ: float = PRESSURE_RADIUS * PRESSURE_RADIUS # Use squared distance for efficiency
const OPEN_RADIUS: float = 75.0 # How far an opponent needs to be from a teammate for them to be "open"
const OPEN_RADIUS_SQ: float = OPEN_RADIUS * OPEN_RADIUS # Squared version for efficiency


func _ready():
    current_stamina = max_stamina
    # Find the ball node (adjust path as needed)
    ball_node = get_parent().find_child("Ball")
    if ball_node == null:
        printerr("Player %s couldn't find Ball node!" % player_name)

    # --- Set Texture based on Team ID ---
    if team_id == 0:
        if team0_texture:
            sprite.texture = team0_texture
        else:
            printerr("Player %s (Team 0) missing team0_texture!" % player_name)
        sprite.modulate = Color.WHITE # Assuming texture has color
    else: # Assuming Team 1
        if team1_texture:
            sprite.texture = team1_texture
        else:
             printerr("Player %s (Team 1) missing team1_texture!" % player_name)
        sprite.modulate = Color.WHITE # Assuming texture has color

    # Make sure player name is set, fallback to node name if empty
    if player_name == "" or player_name == "Player":
        player_name = name
        push_warning("Player node '%s' player_name property not set in Inspector, using node name." % name)

func _physics_process(delta):
    # --- Update Cooldown Timer ---
    if can_pass_timer > 0.0:
        can_pass_timer -= delta

    # --- State Handling: Knockdown ---
    if get_is_knocked_down(): # Use getter
        handle_knockdown(delta)
        return # Don't do anything else while knocked down

    # --- Decision Making: Pass? ---
    # Check if player has ball AND the pass cooldown has expired
    if has_ball and can_pass_timer <= 0.0:
        if is_under_pressure():
            var target_teammate = find_open_teammate() # Uses new "open" logic
            if target_teammate != null:
                # Found target, initiate pass
                print_debug("%s passing under pressure to OPEN teammate %s!" % [player_name, target_teammate.player_name]) # Keep this log for now
                initiate_pass(target_teammate.global_position)
                velocity = Vector2.ZERO # Stop moving immediately after initiating pass
                move_and_slide() # Apply the stop
                # Exit physics process for this frame after deciding to pass
                return

    # --- If not passing, continue with Stamina, AI Movement etc. ---

    # --- Stamina ---
    if velocity.length_squared() > 10: # If moving significantly
        current_stamina -= STAMINA_DRAIN_RATE * delta
    else:
        current_stamina += STAMINA_RECOVERY_RATE * delta
    current_stamina = clamp(current_stamina, 0.0, max_stamina)

    # Calculate effective speed based on stamina
    var stamina_factor = clamp(current_stamina / max_stamina, 0.2, 1.0)
    var effective_speed = base_speed * stamina_factor

    # --- AI Decision Making & Movement ---
    var target_position = determine_target_position()
    var direction = global_position.direction_to(target_position)

    # Basic check to prevent jittering at target
    if global_position.distance_squared_to(target_position) > 25:
        velocity = direction * effective_speed
    else:
        velocity = Vector2.ZERO

    # --- Execute Movement ---
    move_and_slide()

    # --- Update Sprite ---
    if velocity.length_squared() > 0:
        sprite.rotation = velocity.angle() # May need + PI / 2.0 depending on sprite orientation


# -----------------------------------------------------------------------------
# AI TARGETING AND DECISION MAKING HELPERS
# -----------------------------------------------------------------------------

# Determines WHERE the player should move towards this frame
func determine_target_position() -> Vector2:
    if ball_node == null:
        # printerr("Player %s cannot find ball node in determine_target_position!" % player_name) # Reduce noise
        return global_position

    # Determine which goal this player is attacking
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
        if not is_instance_valid(carrier):
             # printerr("Player %s found invalid carrier node!" % player_name) # Reduce noise
             return ball_node.global_position # Target ball if carrier invalid

        if carrier.team_id != self.team_id:
            # --- Defensive AI ---
            # Move towards the opponent ball carrier
            # print_debug("%s (defender) moving to carrier %s at %s" % [player_name, carrier.player_name, str(carrier.global_position)]) # Reduce noise
            return carrier.global_position
        else:
            # --- Offensive AI (Teammate Support) ---
            # Teammate has the ball. Move towards opponent goal, offset from carrier.
            var carrier_target_goal: Vector2 = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
            var direction_to_goal = (carrier_target_goal - carrier.global_position).normalized()
            if direction_to_goal == Vector2.ZERO: direction_to_goal = (carrier_target_goal - global_position).normalized()
            if direction_to_goal == Vector2.ZERO: direction_to_goal = Vector2(1, 0) if carrier.team_id == 1 else Vector2(-1, 0)

            var support_position = carrier.global_position + direction_to_goal * 100.0
            var sideways_offset_dir = Vector2(direction_to_goal.y, -direction_to_goal.x)
            var sideways_amount = (hash(player_name) % 100 - 50)
            support_position += sideways_offset_dir * sideways_amount

            # print_debug("%s (support) moving towards %s" % [player_name, str(support_position)]) # Reduce noise
            return support_position

# Helper to get a list of other player nodes
func get_all_players() -> Array[Node]:
    var players: Array[Node] = []
    var parent = get_parent()
    if parent:
        for child in parent.get_children():
            if child.has_method("get_player_name") and child != self:
                 players.append(child)
    return players

# Check if an opponent is within the pressure radius
func is_under_pressure() -> bool:
    var all_players = get_all_players()
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if global_position.distance_squared_to(opponent.global_position) < PRESSURE_RADIUS_SQ:
                # --- COMMENTED OUT ---
                # print_debug("%s feels pressure from %s" % [player_name, opponent.player_name])
                # ---
                return true
    return false

# Finds the first available "open" teammate
func find_open_teammate() -> Node:
    var all_players = get_all_players()
    var best_teammate = null

    for teammate in all_players:
        if teammate.team_id == self.team_id and teammate.has_method("get_is_knocked_down") and not teammate.get_is_knocked_down():
            if is_teammate_open(teammate, all_players):
                best_teammate = teammate
                # --- COMMENTED OUT detailed logging ---
                # print("FOUND TEAMMATE ---- Node Name: ", best_teammate.name)
                # print("                 Player Name Property: ", best_teammate.player_name)
                # --- Keep the final confirmation ---
                print_debug("%s found OPEN teammate: %s" % [player_name, best_teammate.player_name]) # Keep this one active
                # --- END logging ---
                return best_teammate # Return the first open teammate found

    # print_debug("%s found NO open teammates" % player_name) # Reduce noise
    return null

# Helper function to check if a specific teammate is "open"
func is_teammate_open(teammate_node: Node, all_players: Array[Node]) -> bool:
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if teammate_node.global_position.distance_squared_to(opponent.global_position) < OPEN_RADIUS_SQ:
                # --- COMMENTED OUT ---
                # print_debug("Teammate %s is NOT open, defender %s is too close." % [teammate_node.player_name, opponent.player_name])
                # ---
                return false # This teammate is marked/covered
    return true # No opponents are close enough to this teammate

# -----------------------------------------------------------------------------
# BALL HANDLING / STATE CHANGES
# -----------------------------------------------------------------------------

func pickup_ball():
    # Called BY the ball script when this player picks it up
    if not has_ball and not get_is_knocked_down(): # Use getter
        has_ball = true
        can_pass_timer = PASS_COOLDOWN # Start cooldown on pickup
        print_debug("%s picked up the ball (set has_ball=true)." % player_name) # Keep this log

func lose_ball():
    # Called BY the ball script when this player loses it
    if has_ball:
        has_ball = false
        print_debug("%s lost the ball (set has_ball=false)." % player_name) # Keep this log

func initiate_pass(target_position: Vector2):
    # Called BY AI logic when deciding to pass
    if has_ball and ball_node and not get_is_knocked_down(): # Use getter
        # print_debug("%s attempting pass towards %s" % [player_name, str(target_position)]) # Can comment out if needed
        ball_node.initiate_pass(self, target_position)
    # elif not has_ball: # Reduce noise
        # print_debug("%s tried to pass but doesn't have the ball!" % player_name)


# -----------------------------------------------------------------------------
# TACKLING & KNOCKDOWN
# -----------------------------------------------------------------------------

func _on_tackle_area_body_entered(body):
    # Signal received from this player's TackleArea
    if body.has_method("get_player_name") and body != self and body.team_id != self.team_id \
        and body.has_method("get_is_knocked_down") and not body.get_is_knocked_down():

        if body.has_ball: # Check opponent's state
            # print_debug("Tackle Contest: %s(Pwr:%d) vs %s(Agi:%d)" % [player_name, tackle_power, body.player_name, body.agility]) # Reduce noise
            if tackle_power > body.agility: # TODO: Add randomness/more factors
                print_debug("Tackle SUCCEEDED by %s on %s!" % [player_name, body.player_name]) # Keep this log
                body.apply_knockdown(self)
                if ball_node and ball_node.current_possessor == body:
                    ball_node.set_loose(body.velocity)
                # elif ball_node and ball_node.current_possessor != body: # Reduce noise
                    # printerr("Tackle success, but possessor mismatch! Ball has %s, Body is %s" % [ball_node.current_possessor, body.name])
                    # ball_node.set_loose(body.velocity)
            # else: # Reduce noise
                # print_debug("Tackle FAILED/Evaded by %s against %s!" % [body.player_name, player_name])


func apply_knockdown(_tackler):
    # Called BY the player who successfully tackled THIS player
    if not get_is_knocked_down(): # Use getter
        # print_debug("%s knocked down by %s" % [player_name, tackler.player_name]) # Reduce noise
        is_knocked_down = true
        knockdown_timer = KNOCKDOWN_DURATION
        velocity = Vector2.ZERO
        if collision_shape:
            collision_shape.set_deferred("disabled", true)
        else:
            printerr("ERROR: %s cannot find collision_shape to disable!" % player_name)


func handle_knockdown(delta):
    # Called from _physics_process when is_knocked_down is true
    knockdown_timer -= delta
    velocity = velocity.move_toward(Vector2.ZERO, 300 * delta)
    move_and_slide()

    if knockdown_timer <= 0:
        is_knocked_down = false
        # print_debug("%s getting up." % player_name) # Reduce noise
        if collision_shape:
            collision_shape.set_deferred("disabled", false)

# -----------------------------------------------------------------------------
# UTILITY / GETTERS
# -----------------------------------------------------------------------------

func get_player_name() -> String:
    # Use the exported variable, fallback to node name if needed
    return str(player_name) if player_name != "" and player_name != "Player" else str(name)

func get_is_knocked_down() -> bool:
    # Getter function to safely check the state variable from other scripts
    return is_knocked_down
    
# Add this function to player.gd (if not already present)

func reset_state():
    print_debug("Resetting state for %s" % player_name)
    # Reset state variables
    is_knocked_down = false
    knockdown_timer = 0.0
    has_ball = false # Ensure player knows they don't have ball
    can_pass_timer = 0.0 # Reset pass cooldown

    # Reset Stamina
    current_stamina = max_stamina

    # Ensure collision shape is enabled (if it exists and was disabled)
    if collision_shape and collision_shape.disabled:
        collision_shape.set_deferred("disabled", false)

    # Reset velocity just in case
    velocity = Vector2.ZERO
