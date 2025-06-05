# player.gd - Full Version with Passer Quality Check for Passes
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

# --- FSM State Definition ---
enum PlayerState {
    IDLE,
    PURSUING_BALL,
    SUPPORTING_OFFENSE,
    HAS_BALL,
    DEFENDING,
    KNOCKED_DOWN,
    BLOCKER_ENGAGING
}
var current_state: PlayerState = PlayerState.IDLE

# State Variables
var current_stamina: float
var has_ball: bool = false
var is_knocked_down: bool = false # Actual state variable
var knockdown_timer: float = 0.0
const KNOCKDOWN_DURATION: float = 1.5
var can_pass_timer: float = 0.0
const PASS_COOLDOWN: float = 0.5
var can_kick_timer: float = 0.0
const KICK_COOLDOWN: float = 0.7
var blocker_hold_ball_timer: float = 0.0
const BLOCKER_MAX_HOLD_TIME: float = 2.0
var current_block_target_node: Node = null
var can_aggressive_tackle_timer: float = 0.0
const AGGRESSIVE_TACKLE_COOLDOWN: float = 1.0 

# Node References
@onready var sprite = $Sprite2D
@onready var collision_shape = $CollisionShape2D
@onready var tackle_area = $TackleArea
@onready var tackle_collision_shape = $TackleArea/CollisionShape2D
@onready var role_indicator: ColorRect = $Sprite2D/RoleIndicator

# Game World References
var ball_node = null
var field_node = null # Added for accessing field properties like currently_targeted_defenders

# Constants for AI/Movement
const FIELD_HALF_WIDTH: float = 960.0
const FIELD_HALF_HEIGHT: float = 540.0
const field_margin: float = 15.0
const GOAL_TARGET_Y: float = 0
# User confirmed: Team 0 starts Left, attacks Right (+X); Team 1 starts Right, attacks Left (-X)
const GOAL_TARGET_X_TEAM0: float = -750.0 # Team 0's DEFENDED Goal (Attacked by Team 1)
const GOAL_TARGET_X_TEAM1: float = 750.0  # Team 1's DEFENDED Goal (Attacked by Team 0)
const TEAM0_GOAL_CENTER = Vector2(GOAL_TARGET_X_TEAM0, GOAL_TARGET_Y) # Goal at Left
const TEAM1_GOAL_CENTER = Vector2(GOAL_TARGET_X_TEAM1, GOAL_TARGET_Y) # Goal at Right
const STAMINA_DRAIN_RATE: float = 2.0
const STAMINA_RECOVERY_RATE: float = 5.0

# Constants for AI Decisions
const PRESSURE_RADIUS: float = 100.0
const PRESSURE_RADIUS_SQ: float = PRESSURE_RADIUS * PRESSURE_RADIUS
const OPEN_RADIUS: float = 75.0 # How close an opponent can be for a teammate to still be "open"
const OPEN_RADIUS_SQ: float = OPEN_RADIUS * OPEN_RADIUS
# const BLOCKING_ENGAGEMENT_RADIUS: float = 150.0 # Original
# const BLOCKING_ENGAGEMENT_RADIUS_SQ: float = BLOCKING_ENGAGEMENT_RADIUS * BLOCKING_ENGAGEMENT_RADIUS # Original
const BLOCKING_ENGAGEMENT_RADIUS: float = 100.0 # Reduced
const BLOCKING_ENGAGEMENT_RADIUS_SQ: float = BLOCKING_ENGAGEMENT_RADIUS * BLOCKING_ENGAGEMENT_RADIUS # Reduced
const HANDOFF_RADIUS: float = 120.0
const HANDOFF_RADIUS_SQ: float = HANDOFF_RADIUS * HANDOFF_RADIUS
const MAX_LOOSE_BALL_ATTACKERS = 1 # Changed from 2 to 1
const TEAMMATE_TOO_CLOSE_RADIUS: float = 100.0 
const TEAMMATE_TOO_CLOSE_RADIUS_SQ: float = TEAMMATE_TOO_CLOSE_RADIUS * TEAMMATE_TOO_CLOSE_RADIUS

# Constants for Pass Leading
const PASS_LEAD_TIME_FACTOR: float = 0.3 
const MIN_LEAD_DISTANCE: float = 30.0
const MIN_LEAD_DISTANCE_SQ: float = MIN_LEAD_DISTANCE * MIN_LEAD_DISTANCE
const MAX_LEAD_DISTANCE_SCALE: float = 1.5 # Max factor by which lead distance can exceed current distance to target

const SCORE_ATTEMPT_RANGE: float = 250.0 # Increased from 150
const SCORE_ATTEMPT_RANGE_SQ: float = SCORE_ATTEMPT_RANGE * SCORE_ATTEMPT_RANGE
const AGGRESSIVE_TACKLE_ATTEMPT_RANGE: float = 40.0
const AGGRESSIVE_TACKLE_ATTEMPT_RANGE_SQ: float = AGGRESSIVE_TACKLE_ATTEMPT_RANGE * AGGRESSIVE_TACKLE_ATTEMPT_RANGE
const MIN_PASS_QUALITY_SCORE_UNDER_PRESSURE: float = 600.0 # New constant for pass decision

# General Gameplay Constants
const MIN_MOVEMENT_DIST_SQ: float = 5.0 * 5.0 # Min distance before player tries to move
const STAMINA_VELOCITY_THRESHOLD_SQ: float = 10.0 * 10.0 # Velocity squared below which stamina recovers (10 was a bit low)
const PLAYER_STAMINA_MIN_FACTOR: float = 0.2 # Minimum speed factor due to low stamina

# AI Behavior Constants
const AGGRESSIVE_TACKLE_ENGAGEMENT_CREEP_FACTOR: float = 0.05 # Speed factor when creeping towards tackle target
const AGGRESSIVE_TACKLE_BUFFER_MULTIPLIER: float = 1.1 # Buffer for tackle engagement distance check
const DEFENSIVE_HOLD_X_MULTIPLIER: float = 0.25 # Factor for X position when holding defensively
const DEFENSIVE_HOLD_Y_SPREAD_MAX_FACTOR: float = 0.8 # Y spread factor for defensive holding (applied to half_height)
const DEFENSIVE_HOLD_Y_SPREAD_MID_FACTOR: float = 0.4 # Y spread factor for defensive holding (applied to half_height, then subtracted)
const DEFENSIVE_REGROUP_LERP_FACTOR: float = 0.1 # Lerp factor for regrouping loose ball non-attackers
const RUNNER_PASS_CHANCE_UNDER_PRESSURE: float = 0.1 # Chance for a runner to pass when pressured
const BLOCKER_DESPERATION_KICK_DISTANCE: float = 150.0 # Distance for blocker's desperation kick
const BASIC_SUPPORT_DISTANCE: float = 100.0 # Base distance for basic offensive support
const BASIC_SUPPORT_SIDE_SPREAD_MAX: int = 100 # Max value for side spread calculation (e.g., hash() % 100)
const BASIC_SUPPORT_SIDE_SPREAD_MID: int = 50  # Mid value for side spread calculation (e.g., -50 to make it centered)
const RUNNER_ROUTE_DISTANCE: float = 300.0 # Base distance for a runner's open route
const RUNNER_ROUTE_ANGLE_VARIATION: float = PI / 10.0 # Max random angle variation for runner's route
const PASSER_SUPPORT_IDEAL_DISTANCE: float = 150.0 # Ideal distance for passer to support carrier
const PASSER_SUPPORT_ROTATION_MAIN: float = PI # Main angle for passer support (behind carrier)
const PASSER_SUPPORT_ROTATION_SIDE_A: float = PI * 0.8 # Side A angle for passer support
const PASSER_SUPPORT_ROTATION_SIDE_B: float = PI * 1.2 # Side B angle for passer support
const PASSER_SUPPORT_ROTATION_LATERAL_A: float = PI * 0.5 # Lateral A angle for passer support
const PASSER_SUPPORT_ROTATION_LATERAL_B: float = PI * 1.5 # Lateral B angle for passer support
const PASSER_SUPPORT_LATERAL_DISTANCE_FACTOR: float = 0.7 # Factor to reduce lateral support distance
const TARGET_VELOCITY_THRESHOLD_SQ: float = 1.0 * 1.0 # Min velocity sq for target to be considered moving for a lead pass
const MAX_EFFECTIVE_PASS_BASE_DIST: float = 150.0 # Base distance for max effective pass calculation
const MAX_EFFECTIVE_PASS_THROW_STAT_MULTIPLIER: float = 10.0 # Multiplier for throwing stat in pass distance
const PASS_SCORE_PROGRESS_TO_GOAL_FACTOR: float = 0.1 # Factor for progress towards goal in pass score
const PASS_SCORE_OPENNESS_FACTOR: float = 0.05 # Factor for receiver openness in pass score
const PASS_SCORE_RUNNER_BONUS: float = 1000.0 # Bonus score for passing to a runner
const PASS_SCORE_PASSER_BONUS: float = 500.0  # Bonus score for passing to another passer
const PASS_SCORE_OTHER_BONUS: float = 100.0   # Bonus score for passing to other roles
const PASS_SCORE_TOO_FAR_PENALTY: float = 2000.0 # Penalty for passes exceeding max effective range
const CLEARING_ZONE_THRESHOLD_MULTIPLIER: float = 0.4 # Defines own half portion for clearing kicks (e.g. 40% of half-width)
const RUNNER_SPREAD_NUDGE_MIN_STRENGTH: float = 0.7 # Min strength for sideways nudge for runner spacing
const RUNNER_SPREAD_NUDGE_MAX_STRENGTH: float = 1.2 # Max strength for sideways nudge for runner spacing
const PASSER_SPREAD_SHIFT_DISTANCE: float = 50.0 # Distance to shift passer support position if too close to a teammate


func _ready():
    current_stamina = max_stamina
    ball_node = get_parent().find_child("Ball")
    if ball_node == null: printerr("Player %s couldn't find Ball node!" % player_name)
    
    # Get reference to the field node
    var current_node = get_parent()
    while current_node != null and not current_node.is_in_group("Field"): # Assuming field node is in group "Field"
        current_node = current_node.get_parent()
    field_node = current_node
    if field_node == null:
        printerr("Player %s couldn't find Field node! Ensure the root field node is in the 'Field' group." % player_name)


    if role_indicator:
        if player_role == "Passer": role_indicator.color = Color.YELLOW
        elif player_role == "Runner": role_indicator.color = Color.GREEN
        elif player_role == "Blocker": role_indicator.color = Color.RED
        else: role_indicator.color = Color.GRAY
    else: printerr("Player %s: Cannot find RoleIndicator node! Path used: $Sprite2D/RoleIndicator" % player_name)

    if team_id == 0:
        if team0_texture: sprite.texture = team0_texture
        else: printerr("Player %s (Team 0) missing team0_texture!" % player_name)
    else:
        if team1_texture: sprite.texture = team1_texture
        else: printerr("Player %s (Team 1) missing team1_texture!" % player_name)
    sprite.modulate = Color.WHITE

    if player_name == "" or player_name == "Player":
        player_name = name
        push_warning("Player node '%s' player_name property not set in Inspector, using node name." % name)
    
    set_state(PlayerState.IDLE)


func _physics_process(delta):
    if can_pass_timer > 0.0: can_pass_timer -= delta
    if can_kick_timer > 0.0: can_kick_timer -= delta
    if can_aggressive_tackle_timer > 0.0: can_aggressive_tackle_timer -= delta
    if player_role == "Blocker" and current_state == PlayerState.HAS_BALL and has_ball:
        if blocker_hold_ball_timer > 0.0: blocker_hold_ball_timer -= delta

    match current_state:
        PlayerState.IDLE:                  _state_idle(delta)
        PlayerState.PURSUING_BALL:         _state_pursuing_ball(delta)
        PlayerState.SUPPORTING_OFFENSE:    _state_supporting_offense(delta)
        PlayerState.HAS_BALL:              _state_has_ball(delta)
        PlayerState.DEFENDING:             _state_defending(delta)
        PlayerState.KNOCKED_DOWN:          _state_knocked_down(delta)
        PlayerState.BLOCKER_ENGAGING:      _state_blocker_engaging(delta)
        _: set_state(PlayerState.IDLE)

    var state_handled_movement = false
    if (current_state == PlayerState.HAS_BALL and player_role == "Blocker") or \
       current_state == PlayerState.KNOCKED_DOWN or \
       (current_state == PlayerState.BLOCKER_ENGAGING and is_instance_valid(current_block_target_node) and \
        global_position.distance_squared_to(current_block_target_node.global_position) < AGGRESSIVE_TACKLE_ATTEMPT_RANGE_SQ * AGGRESSIVE_TACKLE_BUFFER_MULTIPLIER ):
        state_handled_movement = true

    if not state_handled_movement:
        var stamina_factor = clamp(current_stamina / max_stamina if max_stamina > 0 else 1.0, PLAYER_STAMINA_MIN_FACTOR, 1.0)
        var effective_speed = base_speed * stamina_factor
        var target_position = determine_target_position()
        var direction = global_position.direction_to(target_position)
        if global_position.distance_squared_to(target_position) > MIN_MOVEMENT_DIST_SQ: velocity = direction * effective_speed
        else: velocity = Vector2.ZERO
    
    move_and_slide()

    if velocity.length_squared() > STAMINA_VELOCITY_THRESHOLD_SQ: current_stamina -= STAMINA_DRAIN_RATE * delta
    else: current_stamina += STAMINA_RECOVERY_RATE * delta
    current_stamina = clamp(current_stamina, 0.0, max_stamina)

    if velocity.length_squared() > 0 and current_state != PlayerState.KNOCKED_DOWN:
        sprite.rotation = velocity.angle()

# ------------------------------------
# --- STATE UPDATE FUNCTIONS ---
# ------------------------------------
func _state_idle(_delta):
    if ball_node == null: return
    if get_is_knocked_down(): set_state(PlayerState.KNOCKED_DOWN); return
    if ball_node.current_possessor == null: set_state(PlayerState.PURSUING_BALL)
    elif is_instance_valid(ball_node.current_possessor):
        if ball_node.current_possessor == self: set_state(PlayerState.HAS_BALL)
        elif ball_node.current_possessor.team_id == self.team_id:
            if player_role == "Blocker": set_state(PlayerState.BLOCKER_ENGAGING)
            else: set_state(PlayerState.SUPPORTING_OFFENSE)
        else: set_state(PlayerState.DEFENDING)

func _state_pursuing_ball(_delta):
    if ball_node and is_instance_valid(ball_node.current_possessor):
        if ball_node.current_possessor == self: set_state(PlayerState.HAS_BALL)
        elif ball_node.current_possessor.team_id == self.team_id:
            if player_role == "Blocker": set_state(PlayerState.BLOCKER_ENGAGING)
            else: set_state(PlayerState.SUPPORTING_OFFENSE)
        else: set_state(PlayerState.DEFENDING)

func _state_supporting_offense(_delta):
    if ball_node == null: return
    if ball_node.current_possessor == null: set_state(PlayerState.PURSUING_BALL)
    elif is_instance_valid(ball_node.current_possessor) and ball_node.current_possessor.team_id != self.team_id:
        set_state(PlayerState.DEFENDING)
    elif not is_instance_valid(ball_node.current_possessor): set_state(PlayerState.PURSUING_BALL)

func _state_has_ball(_delta):
    var attacking_goal_center = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER
    var distance_to_goal_sq = global_position.distance_squared_to(attacking_goal_center)

    if distance_to_goal_sq < SCORE_ATTEMPT_RANGE_SQ: return 
    
    if player_role == "Blocker":
        var target_info_handoff = find_open_teammate_with_score() # Blockers also use this for handoff info
        var target_for_handoff: Node = target_info_handoff.node
        var handoff_pos: Vector2 = target_info_handoff.anticipated_pos # Use anticipated for handoff too
        if target_for_handoff != null and can_pass_timer <= 0.0:
            initiate_pass(target_for_handoff, handoff_pos); velocity = Vector2.ZERO
        elif blocker_hold_ball_timer <= 0.0:
            var forward_direction = (attacking_goal_center - global_position).normalized()
            if forward_direction == Vector2.ZERO: forward_direction = Vector2(1,0) if team_id == 0 else Vector2(-1,0) # Default direction if at goal
            var desperation_target = global_position + forward_direction * BLOCKER_DESPERATION_KICK_DISTANCE
            initiate_kick(desperation_target); velocity = Vector2.ZERO
        else: velocity = Vector2.ZERO
        return

    var can_consider_clearing_kick = true
    if team_id == 0: if global_position.x > 0: can_consider_clearing_kick = false # Team 0 on right side of field
    elif team_id == 1: if global_position.x < 0: can_consider_clearing_kick = false # Team 1 on left side of field
    
    if player_role == "Runner":
        if can_kick_timer <= 0.0 and is_in_clearing_zone() and can_consider_clearing_kick:
            initiate_kick(); return
        elif can_pass_timer <= 0.0 and is_under_pressure():
            if randf() < RUNNER_PASS_CHANCE_UNDER_PRESSURE: 
                var target_info = find_open_teammate_with_score()
                var target_teammate: Node = target_info.node
                var anticipated_pass_pos: Vector2 = target_info.anticipated_pos
                # var pass_quality_score: float = target_info.score # Not using score for Runner's desperation pass yet
                if target_teammate != null: # Just pass if any target found, regardless of score for now
                    initiate_pass(target_teammate, anticipated_pass_pos); velocity = Vector2.ZERO; return
        return # Runner defaults to running

    # Passer (or other roles) logic
    if can_kick_timer <= 0.0 and is_in_clearing_zone() and can_consider_clearing_kick:
        initiate_kick(); return
    elif can_pass_timer <= 0.0:
        # print_debug("%s considering pass (timer ready)" % player_name)
        var am_under_pressure = is_under_pressure() # Check once
        # print_debug("%s under pressure: %s" % [player_name, am_under_pressure])
        if am_under_pressure: # Only find target if under pressure for now, can expand later
            var target_info = find_open_teammate_with_score()
            var target_teammate: Node = target_info.node
            var pass_quality_score: float = target_info.score
            var anticipated_pass_pos: Vector2 = target_info.anticipated_pos
            ## print_debug("%s found target: %s, score: %s, ant_pos: %s" % [player_name, target_teammate, pass_quality_score, anticipated_pass_pos])

            if target_teammate != null and pass_quality_score > MIN_PASS_QUALITY_SCORE_UNDER_PRESSURE:
                ## print_debug("%s initiating pass to %s at %s" % [player_name, target_teammate.player_name, anticipated_pass_pos])
                initiate_pass(target_teammate, anticipated_pass_pos)
                velocity = Vector2.ZERO
            ## else: Passer holds ball if no good pass option, will run by default
            ## print_debug("%s no good pass option or target. Holding ball." % player_name)
            return # Return whether pass was attempted or not

func _state_defending(_delta):
    if player_role == "Blocker":
        if ball_node and is_instance_valid(ball_node.current_possessor):
            var carrier = ball_node.current_possessor
            if carrier.team_id != self.team_id:
                if global_position.distance_squared_to(carrier.global_position) < AGGRESSIVE_TACKLE_ATTEMPT_RANGE_SQ:
                    attempt_aggressive_tackle(carrier)
    if ball_node and ball_node.current_possessor == null: set_state(PlayerState.PURSUING_BALL)
    elif ball_node and is_instance_valid(ball_node.current_possessor) and ball_node.current_possessor.team_id == self.team_id:
        if player_role == "Blocker": set_state(PlayerState.BLOCKER_ENGAGING)
        else: set_state(PlayerState.SUPPORTING_OFFENSE)

func _state_knocked_down(delta):
    knockdown_timer -= delta; velocity = Vector2.ZERO
    if knockdown_timer <= 0.0:
        is_knocked_down = false
        if collision_shape and collision_shape.disabled: collision_shape.set_deferred("disabled", false)
        set_state(PlayerState.IDLE)

func _state_blocker_engaging(_delta):
    # Condition for losing/changing target:
    # 1. Target is no longer valid (knocked down, etc.)
    # 2. Ball situation changed (handled by state transitions in IDLE check)
    if not is_target_still_valid(current_block_target_node):
        clear_block_target() # This will also remove from field list
        # No immediate state change here, determine_target_position will try to find a new one or go to support.
        # If IDLE conditions met (e.g., opponent gets ball), that will trigger a state change.
        # print_debug("%s: Blocker engaging, target %s became invalid." % [player_name, current_block_target_node.name if current_block_target_node else "N/A"])
    
    # If ball situation changes (e.g., opponent gets ball, ball loose), transition out
    if (ball_node and ball_node.current_possessor != null and ball_node.current_possessor.team_id != self.team_id) or \
       (ball_node and ball_node.current_possessor == null):
        # print_debug("%s: Blocker engaging, but ball situation changed. Transitioning to IDLE." % player_name)
        set_state(PlayerState.IDLE) # This will call clear_block_target via set_state logic
        return

    if is_instance_valid(current_block_target_node):
        var dist_to_block_target_sq = global_position.distance_squared_to(current_block_target_node.global_position)
        if dist_to_block_target_sq < AGGRESSIVE_TACKLE_ATTEMPT_RANGE_SQ:
            attempt_aggressive_tackle(current_block_target_node)
            velocity = (current_block_target_node.global_position - global_position).normalized() * (base_speed * AGGRESSIVE_TACKLE_ENGAGEMENT_CREEP_FACTOR)
    # Else, velocity determined by determine_target_position, which will call find_defender_to_block if target is null

# ------------------------------------
# AI TARGETING AND DECISION MAKING HELPERS
# ------------------------------------
func determine_target_position() -> Vector2:
    if ball_node == null:
        return global_position 

    # Attacking goal for THIS player
    var attacking_goal_center: Vector2 = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER

    match current_state:
        PlayerState.HAS_BALL:
            # Carrier runs for goal (Blocker's specific ball-carrying actions are handled in _state_has_ball)
            return attacking_goal_center
        
        PlayerState.PURSUING_BALL:
            # This state is active when the ball is loose and this player is considering going for it.
            if ball_node.current_possessor != null: 
                # Ball just got picked up. State transition will be handled by _state_pursuing_ball().
                # For this frame, just hold position until next state logic kicks in.
                return global_position 
            
            var players = get_all_players()
            var my_dist_sq = global_position.distance_squared_to(ball_node.global_position)
            var players_closer_count = 0
            for p in players:
                if p.global_position.distance_squared_to(ball_node.global_position) < my_dist_sq:
                    players_closer_count += 1
            
            if players_closer_count < MAX_LOOSE_BALL_ATTACKERS:
                # This player IS one of the closest designated attackers, go for the ball.
                return ball_node.global_position
            else:
                # --- CORRECTED LOGIC for Non-Pursuers on Loose Ball ---
                # Not one of the designated attackers.
                # Move to a cautious defensive/neutral position on own side of midfield,
                # slightly shadowing the ball's Y position and spreading out.
                var defensive_hold_x_pos: float
                # Team 0 DEFENDS Left side (-X), Team 1 DEFENDS Right side (+X)
                if team_id == 0: 
                    defensive_hold_x_pos = -FIELD_HALF_WIDTH * DEFENSIVE_HOLD_X_MULTIPLIER 
                else: 
                    defensive_hold_x_pos = FIELD_HALF_WIDTH * DEFENSIVE_HOLD_X_MULTIPLIER

                var target_y = ball_node.global_position.y
                # Spread players out a bit on Y axis based on their name hash
                target_y += (hash(player_name) % int(FIELD_HALF_HEIGHT * DEFENSIVE_HOLD_Y_SPREAD_MAX_FACTOR)) - (FIELD_HALF_HEIGHT * DEFENSIVE_HOLD_Y_SPREAD_MID_FACTOR) 
                target_y = clamp(target_y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
                
                var strategic_target = Vector2(defensive_hold_x_pos, target_y)
                # Move a fraction towards this point each frame for smoother regrouping
                return global_position.lerp(strategic_target, DEFENSIVE_REGROUP_LERP_FACTOR) 
        
        PlayerState.SUPPORTING_OFFENSE:
            var carrier = ball_node.current_possessor
            if is_instance_valid(carrier) and carrier.team_id == self.team_id:
                # Blocker state is BLOCKER_ENGAGING when supporting, not SUPPORTING_OFFENSE
                if player_role == "Runner": return find_open_route_position(carrier)
                elif player_role == "Passer": return find_passer_support_position(carrier)
                else: # Includes Blockers if they somehow end up here (should be BLOCKER_ENGAGING) or unknown roles
                    return calculate_basic_support_pos(carrier) 
            else: # Teammate lost ball or no carrier
                # State transition handled by _state_supporting_offense
                return global_position 

        PlayerState.BLOCKER_ENGAGING:
            var offensive_carrier = ball_node.current_possessor 
            if is_instance_valid(offensive_carrier) and offensive_carrier.team_id == self.team_id: # Teammate still has ball
                if not is_instance_valid(current_block_target_node): # Find new block target if needed
                    # find_defender_to_block will now handle setting/clearing target on field_node
                    find_defender_to_block(offensive_carrier) # No need to assign directly, function does it
                
                if is_instance_valid(current_block_target_node):
                    return current_block_target_node.global_position
                else: # No defender to block, provide basic support for the carrier
                    return calculate_basic_support_pos(offensive_carrier)
            else: # Teammate lost ball, or no carrier, or opponent has ball
                # State transition handled by _state_blocker_engaging
                return global_position

        PlayerState.DEFENDING:
            if is_instance_valid(ball_node.current_possessor) and ball_node.current_possessor.team_id != self.team_id:
                return ball_node.current_possessor.global_position # Target opponent carrier
            else: # Ball became loose or own team got it
                # State transition handled by _state_defending
                return global_position 

        PlayerState.IDLE:
            # Fallback targeting if still in IDLE state (should be transitioned quickly by _state_idle)
            if ball_node.current_possessor == null: return ball_node.global_position # Pursue loose ball
            elif is_instance_valid(ball_node.current_possessor):
                var L_carrier = ball_node.current_possessor
                if L_carrier.team_id == self.team_id: # Teammate has ball
                    if player_role == "Blocker":
                        # var block_target = find_defender_to_block(L_carrier) # find_defender_to_block now sets member var
                        find_defender_to_block(L_carrier)
                        if is_instance_valid(current_block_target_node): return current_block_target_node.global_position
                        else: return calculate_basic_support_pos(L_carrier)
                    elif player_role == "Runner": return find_open_route_position(L_carrier)
                    elif player_role == "Passer": return find_passer_support_position(L_carrier)
                    else: return calculate_basic_support_pos(L_carrier)
                else: # Opponent has ball
                    return L_carrier.global_position
            return global_position # Fallback if something unexpected

        PlayerState.KNOCKED_DOWN:
            return global_position # Stay put (actual velocity is zeroed in _state_knocked_down)

    return global_position # Ultimate fallback if no state matched or other logic failed

func get_all_players() -> Array[Node]:
    var players: Array[Node] = [] # Initialize the typed array
    var parent = get_parent()      # Get the parent node

    if parent: # Only proceed if a parent exists
        for child in parent.get_children():
            # Check if the child is in the "players" group and is not the current player itself
            if child.is_in_group("players") and child != self:
                players.append(child)
    
    # Always return the players array (it will be empty if no parent or no other players found)
    return players

func is_under_pressure() -> bool:
    var all_players = get_all_players()
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if global_position.distance_squared_to(opponent.global_position) < PRESSURE_RADIUS_SQ: return true
    return false

# --- RENAMED and MODIFIED to return Dictionary ---
func find_open_teammate_with_score() -> Dictionary:
    var all_players = get_all_players()
    var best_target: Node = null
    var best_target_score: float = -INF
    var attacking_goal_x_direction = 1.0 if team_id == 0 else -1.0

    var open_runners: Array[Node] = []
    var open_passers: Array[Node] = []
    var open_others: Array[Node] = []

    for teammate in all_players:
        if teammate.team_id == self.team_id and \
           teammate.has_method("get_is_knocked_down") and not teammate.get_is_knocked_down() and \
           teammate.has_method("get"):
            if is_teammate_open(teammate, all_players):
                var role = teammate.get("player_role")
                if role == "Runner": open_runners.append(teammate)
                elif role == "Passer": open_passers.append(teammate)
                else: open_others.append(teammate)
    
    var current_passer_throwing_stat = get("throwing") # Get own throwing stat for range check

    # Check Runners
    for runner_node in open_runners:
        var score = 0.0
        score += (runner_node.global_position.x * attacking_goal_x_direction) * PASS_SCORE_PROGRESS_TO_GOAL_FACTOR 
        var closest_def_dist_sq = INF
        for opp in all_players:
            if opp.team_id != self.team_id and not opp.get_is_knocked_down(): closest_def_dist_sq = min(closest_def_dist_sq, runner_node.global_position.distance_squared_to(opp.global_position))
        if closest_def_dist_sq > OPEN_RADIUS_SQ: score += sqrt(closest_def_dist_sq) * PASS_SCORE_OPENNESS_FACTOR
        score += PASS_SCORE_RUNNER_BONUS 
        var dist_to_target_sq = global_position.distance_squared_to(runner_node.global_position)
        var max_effective_pass_dist_sq = pow(MAX_EFFECTIVE_PASS_BASE_DIST + (current_passer_throwing_stat * MAX_EFFECTIVE_PASS_THROW_STAT_MULTIPLIER), 2)
        if dist_to_target_sq > max_effective_pass_dist_sq: score -= PASS_SCORE_TOO_FAR_PENALTY
        if score > best_target_score: best_target_score = score; best_target = runner_node
    
    if best_target != null: # Early exit if a runner is already a good target (common case)
        var anticipated_runner_pos = best_target.global_position
        var dist_sq_to_runner = global_position.distance_squared_to(best_target.global_position)
        if best_target.has_method("get") and typeof(best_target.get("velocity")) == TYPE_VECTOR2:
            var runner_vel = best_target.get("velocity")
            if runner_vel.length_squared() > TARGET_VELOCITY_THRESHOLD_SQ and dist_sq_to_runner > MIN_LEAD_DISTANCE_SQ:
                var lead_pos_run = best_target.global_position + (runner_vel * PASS_LEAD_TIME_FACTOR)
                var max_lead_run = sqrt(dist_sq_to_runner) * MAX_LEAD_DISTANCE_SCALE
                if best_target.global_position.distance_to(lead_pos_run) > max_lead_run: lead_pos_run = best_target.global_position + (lead_pos_run - best_target.global_position).normalized() * max_lead_run
                anticipated_runner_pos = lead_pos_run
        anticipated_runner_pos.x = clamp(anticipated_runner_pos.x, -FIELD_HALF_WIDTH + field_margin, FIELD_HALF_WIDTH - field_margin)
        anticipated_runner_pos.y = clamp(anticipated_runner_pos.y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
        return {"node": best_target, "score": best_target_score, "anticipated_pos": anticipated_runner_pos}

    # Check Passers if no Runner found or if their score is better
    for passer_node in open_passers:
        var score = 0.0
        score += (passer_node.global_position.x * attacking_goal_x_direction) * PASS_SCORE_PROGRESS_TO_GOAL_FACTOR
        var closest_def_dist_sq = INF
        for opp in all_players:
            if opp.team_id != self.team_id and not opp.get_is_knocked_down(): closest_def_dist_sq = min(closest_def_dist_sq, passer_node.global_position.distance_squared_to(opp.global_position))
        if closest_def_dist_sq > OPEN_RADIUS_SQ: score += sqrt(closest_def_dist_sq) * PASS_SCORE_OPENNESS_FACTOR
        score += PASS_SCORE_PASSER_BONUS
        var dist_to_target_sq = global_position.distance_squared_to(passer_node.global_position)
        var max_effective_pass_dist_sq = pow(MAX_EFFECTIVE_PASS_BASE_DIST + (current_passer_throwing_stat * MAX_EFFECTIVE_PASS_THROW_STAT_MULTIPLIER), 2)
        if dist_to_target_sq > max_effective_pass_dist_sq: score -= PASS_SCORE_TOO_FAR_PENALTY
        if score > best_target_score: best_target_score = score; best_target = passer_node

    if best_target != null: # Early exit if a passer is now the best target
        var anticipated_passer_pos = best_target.global_position
        var dist_sq_to_passer = global_position.distance_squared_to(best_target.global_position)
        if best_target.has_method("get") and typeof(best_target.get("velocity")) == TYPE_VECTOR2:
            var passer_vel = best_target.get("velocity")
            if passer_vel.length_squared() > TARGET_VELOCITY_THRESHOLD_SQ and dist_sq_to_passer > MIN_LEAD_DISTANCE_SQ:
                var lead_pos_pass = best_target.global_position + (passer_vel * PASS_LEAD_TIME_FACTOR)
                var max_lead_pass = sqrt(dist_sq_to_passer) * MAX_LEAD_DISTANCE_SCALE
                if best_target.global_position.distance_to(lead_pos_pass) > max_lead_pass: lead_pos_pass = best_target.global_position + (lead_pos_pass - best_target.global_position).normalized() * max_lead_pass
                anticipated_passer_pos = lead_pos_pass
        anticipated_passer_pos.x = clamp(anticipated_passer_pos.x, -FIELD_HALF_WIDTH + field_margin, FIELD_HALF_WIDTH - field_margin)
        anticipated_passer_pos.y = clamp(anticipated_passer_pos.y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
        return {"node": best_target, "score": best_target_score, "anticipated_pos": anticipated_passer_pos}

    # Check Others if no Runner/Passer found or if their score is better
    for other_node in open_others:
        var score = 0.0
        score += (other_node.global_position.x * attacking_goal_x_direction) * PASS_SCORE_PROGRESS_TO_GOAL_FACTOR
        var closest_def_dist_sq = INF
        for opp in all_players:
            if opp.team_id != self.team_id and not opp.get_is_knocked_down(): closest_def_dist_sq = min(closest_def_dist_sq, other_node.global_position.distance_squared_to(opp.global_position))
        if closest_def_dist_sq > OPEN_RADIUS_SQ: score += sqrt(closest_def_dist_sq) * PASS_SCORE_OPENNESS_FACTOR
        score += PASS_SCORE_OTHER_BONUS
        var dist_to_target_sq = global_position.distance_squared_to(other_node.global_position)
        var max_effective_pass_dist_sq = pow(MAX_EFFECTIVE_PASS_BASE_DIST + (current_passer_throwing_stat * MAX_EFFECTIVE_PASS_THROW_STAT_MULTIPLIER), 2)
        if dist_to_target_sq > max_effective_pass_dist_sq: score -= PASS_SCORE_TOO_FAR_PENALTY
        if score > best_target_score: best_target_score = score; best_target = other_node
    
    # Final determination of anticipated position for the overall best_target
    if best_target:
        var anticipated_position = best_target.global_position
        var dist_sq_to_target = global_position.distance_squared_to(best_target.global_position)

        if best_target.has_method("get") and typeof(best_target.get("velocity")) == TYPE_VECTOR2:
            var target_velocity = best_target.get("velocity")
            if target_velocity.length_squared() > TARGET_VELOCITY_THRESHOLD_SQ and dist_sq_to_target > MIN_LEAD_DISTANCE_SQ: 
                var lead_pos = best_target.global_position + (target_velocity * PASS_LEAD_TIME_FACTOR)
                var max_lead_dist = sqrt(dist_sq_to_target) * MAX_LEAD_DISTANCE_SCALE
                if best_target.global_position.distance_to(lead_pos) > max_lead_dist:
                    lead_pos = best_target.global_position + (lead_pos - best_target.global_position).normalized() * max_lead_dist
                
                anticipated_position = lead_pos

        # Clamp anticipated_position to field boundaries
        anticipated_position.x = clamp(anticipated_position.x, -FIELD_HALF_WIDTH + field_margin, FIELD_HALF_WIDTH - field_margin)
        anticipated_position.y = clamp(anticipated_position.y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)

        ## print_debug("%s found BEST target overall: %s (Role: %s, Score: %.1f), Anticipated Pos: %s" % [player_name, best_target.player_name, best_target.get("player_role"), best_target_score, anticipated_position])
        return {"node": best_target, "score": best_target_score, "anticipated_pos": anticipated_position}
    else:
        ## print_debug("%s found NO suitable open teammate." % player_name)
        return {"node": null, "score": -INF, "anticipated_pos": Vector2.ZERO} # Return Vector2.ZERO if no target


func is_teammate_open(teammate_node: Node, all_players: Array[Node]) -> bool:
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if teammate_node.global_position.distance_squared_to(opponent.global_position) < OPEN_RADIUS_SQ: return false
    return true

func is_in_clearing_zone() -> bool:
    var threshold = FIELD_HALF_WIDTH * CLEARING_ZONE_THRESHOLD_MULTIPLIER
    if team_id == 0: return global_position.x < -threshold # Team 0 DEFENDS Left (-X)
    elif team_id == 1: return global_position.x > threshold # Team 1 DEFENDS Right (+X)
    return false

func find_defender_to_block(carrier_or_ball: Node): # No longer returns Node, sets member var
    if not is_instance_valid(carrier_or_ball) or field_node == null:
        if is_instance_valid(current_block_target_node): clear_block_target()
        return

    var all_players = get_all_players()
    var best_target_defender: Node = null
    var min_dist_sq_to_blocker = BLOCKING_ENGAGEMENT_RADIUS_SQ 

    for opponent in all_players:
        if opponent.team_id != self.team_id and \
           opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down() and \
           is_instance_valid(opponent): 

            if field_node.is_defender_targeted(opponent):
                var existing_blocker = field_node.get_blocker_for_defender(opponent)
                if is_instance_valid(existing_blocker) and \
                   existing_blocker != self and \
                   existing_blocker.has_method("get_is_knocked_down") and not existing_blocker.get_is_knocked_down() and \
                   existing_blocker.current_block_target_node == opponent and \
                   (existing_blocker.current_state == PlayerState.BLOCKER_ENGAGING): 
                    ## print_debug("%s: Defender %s already targeted by %s. Skipping." % [player_name, opponent.player_name, existing_blocker.player_name])
                    continue 

            var dist_sq_to_ref_point = carrier_or_ball.global_position.distance_squared_to(opponent.global_position)
            if dist_sq_to_ref_point < BLOCKING_ENGAGEMENT_RADIUS_SQ: 
                var dist_sq_to_me = global_position.distance_squared_to(opponent.global_position)
                if dist_sq_to_me < min_dist_sq_to_blocker:
                    min_dist_sq_to_blocker = dist_sq_to_me
                    best_target_defender = opponent

    if is_instance_valid(best_target_defender):
        if current_block_target_node != best_target_defender: 
            if is_instance_valid(current_block_target_node): 
                field_node.remove_target_for_blocker(current_block_target_node) 
            
            current_block_target_node = best_target_defender
            field_node.set_target_for_blocker(current_block_target_node, self)
            ## print_debug("%s: New block target: %s" % [player_name, current_block_target_node.player_name])
    else: 
        if is_instance_valid(current_block_target_node): 
            clear_block_target() 
        ## print_debug("%s: No suitable block target found." % player_name)

func calculate_basic_support_pos(carrier: Node) -> Vector2:
    if not is_instance_valid(carrier): return global_position
    var target_goal = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    var dir_to_goal = (target_goal - carrier.global_position).normalized()
    if dir_to_goal==Vector2.ZERO: dir_to_goal = (target_goal - global_position).normalized() # Fallback to self if carrier is ON goal
    if dir_to_goal==Vector2.ZERO: dir_to_goal = Vector2(1,0) if carrier.team_id==0 else Vector2(-1,0) # Ultimate fallback
    
    var support_pos = carrier.global_position + dir_to_goal * BASIC_SUPPORT_DISTANCE
    var side_dir = Vector2(dir_to_goal.y, -dir_to_goal.x) # Perpendicular
    var side_amt = (hash(player_name) % BASIC_SUPPORT_SIDE_SPREAD_MAX) - BASIC_SUPPORT_SIDE_SPREAD_MID # e.g. range -50 to 49
    support_pos += side_dir * side_amt
    return support_pos

func find_open_route_position(carrier: Node) -> Vector2:
    if not is_instance_valid(carrier): return global_position

    var carrier_target_goal: Vector2 = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    var direction_to_goal = (carrier_target_goal - global_position).normalized()
    if direction_to_goal == Vector2.ZERO: 
        direction_to_goal = (carrier_target_goal - carrier.global_position).normalized() # Fallback to carrier's direction to goal
    if direction_to_goal == Vector2.ZERO: 
        direction_to_goal = Vector2(1, 0) if carrier.team_id == 0 else Vector2(-1, 0) # Ultimate fallback

    var target_direction = direction_to_goal # Base direction

    # --- Spreading Logic for Runners ---
    var all_players = get_all_players()
    var closest_teammate_dist_sq = INF
    var too_close_teammate_vec = Vector2.ZERO

    for tm in all_players:
        if tm.team_id == self.team_id and tm != carrier and tm.player_role != "Blocker": # Consider other non-blocker teammates
            var dist_sq = global_position.distance_squared_to(tm.global_position)
            if dist_sq < TEAMMATE_TOO_CLOSE_RADIUS_SQ and dist_sq < closest_teammate_dist_sq:
                closest_teammate_dist_sq = dist_sq
                too_close_teammate_vec = global_position - tm.global_position # Vector from teammate to me

    if closest_teammate_dist_sq < TEAMMATE_TOO_CLOSE_RADIUS_SQ:
        # If too close to a teammate, try to move away from them.
        # Add a perpendicular component to the direction_to_goal, influenced by vector from teammate
        var nudge_direction = too_close_teammate_vec.normalized().orthogonal() 
        # Ensure the nudge is generally away from the teammate and somewhat forward
        if too_close_teammate_vec.dot(nudge_direction) < 0: # Ensure nudge is generally away
             nudge_direction *= -1.0
        
        var random_sideways_strength = randf_range(RUNNER_SPREAD_NUDGE_MIN_STRENGTH, RUNNER_SPREAD_NUDGE_MAX_STRENGTH) 
        target_direction = (target_direction + nudge_direction * random_sideways_strength).normalized()
    else:
        # Original behavior if not too close to anyone: slight random variation
        target_direction = direction_to_goal.rotated(randf_range(-RUNNER_ROUTE_ANGLE_VARIATION, RUNNER_ROUTE_ANGLE_VARIATION))
    # --- End Spreading Logic ---

    var target_route_pos = global_position + target_direction * RUNNER_ROUTE_DISTANCE
    target_route_pos.x = clamp(target_route_pos.x, -FIELD_HALF_WIDTH + field_margin, FIELD_HALF_WIDTH - field_margin)
    target_route_pos.y = clamp(target_route_pos.y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
    return target_route_pos

func find_passer_support_position(carrier: Node) -> Vector2:
    if not is_instance_valid(carrier): return global_position
    var best_pos = global_position; var max_safety_score = -INF # Initialize best_pos to current to have a fallback
    var carrier_attack_dir = ((TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER) - carrier.global_position ).normalized()
    if carrier_attack_dir == Vector2.ZERO: carrier_attack_dir = Vector2(1,0) if carrier.team_id == 0 else Vector2(-1,0)
    
    var relative_positions = [ 
        carrier_attack_dir.rotated(PASSER_SUPPORT_ROTATION_MAIN) * PASSER_SUPPORT_IDEAL_DISTANCE, 
        carrier_attack_dir.rotated(PASSER_SUPPORT_ROTATION_SIDE_A) * PASSER_SUPPORT_IDEAL_DISTANCE, 
        carrier_attack_dir.rotated(PASSER_SUPPORT_ROTATION_SIDE_B) * PASSER_SUPPORT_IDEAL_DISTANCE, 
        carrier_attack_dir.rotated(PASSER_SUPPORT_ROTATION_LATERAL_A) * PASSER_SUPPORT_IDEAL_DISTANCE * PASSER_SUPPORT_LATERAL_DISTANCE_FACTOR, 
        carrier_attack_dir.rotated(PASSER_SUPPORT_ROTATION_LATERAL_B) * PASSER_SUPPORT_IDEAL_DISTANCE * PASSER_SUPPORT_LATERAL_DISTANCE_FACTOR 
    ]
    var all_players = get_all_players() # Cache this
    for offset in relative_positions:
        var candidate_pos = carrier.global_position + offset
        candidate_pos.x = clamp(candidate_pos.x, -FIELD_HALF_WIDTH+field_margin, FIELD_HALF_WIDTH-field_margin); candidate_pos.y = clamp(candidate_pos.y, -FIELD_HALF_HEIGHT+field_margin, FIELD_HALF_HEIGHT-field_margin)
        var closest_opponent_dist_sq = INF; var open_spot = true
        for p in all_players:
            if p.team_id != self.team_id:
                var dist_to_candidate_sq = candidate_pos.distance_squared_to(p.global_position)
                if dist_to_candidate_sq < closest_opponent_dist_sq: closest_opponent_dist_sq = dist_to_candidate_sq
                if dist_to_candidate_sq < OPEN_RADIUS_SQ: open_spot = false; break
        if open_spot and closest_opponent_dist_sq > max_safety_score: max_safety_score = closest_opponent_dist_sq; best_pos = candidate_pos
    if max_safety_score == -INF:
        var lateral_offset_dir = Vector2(carrier_attack_dir.y, -carrier_attack_dir.x); var side_multiplier = 1.0 if (hash(player_name)%2==0) else -1.0
        best_pos = carrier.global_position + (lateral_offset_dir*ideal_distance_from_carrier*0.7*side_multiplier)
        best_pos.x = clamp(best_pos.x, -FIELD_HALF_WIDTH+field_margin, FIELD_HALF_WIDTH-field_margin); best_pos.y = clamp(best_pos.y, -FIELD_HALF_HEIGHT+field_margin, FIELD_HALF_HEIGHT-field_margin)

    # --- Spreading Logic for Passers ---
    # var players_for_spacing = get_all_players() # Already got all_players
    for tm in all_players: # Use cached all_players
        if tm.team_id == self.team_id and tm != carrier and tm.player_role != "Blocker": # Consider other non-blocker teammates
            if best_pos.distance_squared_to(tm.global_position) < TEAMMATE_TOO_CLOSE_RADIUS_SQ:
                var direction_away_from_teammate = (best_pos - tm.global_position).normalized()
                best_pos += direction_away_from_teammate * PASSER_SPREAD_SHIFT_DISTANCE 
                # Re-clamp to field boundaries
                best_pos.x = clamp(best_pos.x, -FIELD_HALF_WIDTH + field_margin, FIELD_HALF_WIDTH - field_margin)
                best_pos.y = clamp(best_pos.y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
                # Note: This simple shift might make the spot unsafe from opponents.
                # A more complex solution would re-evaluate safety or try multiple adjustment vectors.
                # For now, we prioritize spacing once a "safe enough" spot is found.
                break # Adjusted once, break to avoid over-correction from multiple teammates in one frame
    # --- End Spreading Logic ---
    return best_pos

func find_nearby_offensive_teammate():
    var players = get_all_players(); var closest_tm: Node = null; var min_dist_sq = HANDOFF_RADIUS_SQ
    for tm in players:
        if tm.team_id == self.team_id and tm.has_method("get_is_knocked_down") and not tm.get_is_knocked_down() and tm.has_method("get"):
            var role = tm.get("player_role"); if role == "Runner" or role == "Passer":
                var dist_sq = global_position.distance_squared_to(tm.global_position)
                if dist_sq < min_dist_sq: min_dist_sq = dist_sq; closest_tm = tm
    return closest_tm

# ------------------------------------ BALL HANDLING / STATE CHANGES ------------------------------------
func pickup_ball():
    if not has_ball and not get_is_knocked_down():
        has_ball = true; can_pass_timer = PASS_COOLDOWN; can_kick_timer = KICK_COOLDOWN
        if player_role=="Blocker": blocker_hold_ball_timer=BLOCKER_MAX_HOLD_TIME
        set_state(PlayerState.HAS_BALL)
        # print_debug("%s picked up ball. State: HAS_BALL" % player_name) # Potentially keep

func lose_ball():
    if has_ball:
        has_ball = false
        ## current_block_target_node = null # This is handled by set_state or clear_block_target now
        if is_instance_valid(current_block_target_node): # Ensure it's cleared if player loses ball
             clear_block_target()

        if ball_node and ball_node.current_possessor == null: set_state(PlayerState.PURSUING_BALL)
        elif ball_node and is_instance_valid(ball_node.current_possessor) and ball_node.current_possessor.team_id == self.team_id:
            if player_role == "Blocker": set_state(PlayerState.BLOCKER_ENGAGING)
            else: set_state(PlayerState.SUPPORTING_OFFENSE)
        else: set_state(PlayerState.DEFENDING)
        ## print_debug("%s lost ball. New State: %s" % [player_name, PlayerState.keys()[current_state]])

func initiate_pass(target_teammate: Node, anticipated_target_pos: Vector2): # Added anticipated_target_pos
    if has_ball and ball_node and not get_is_knocked_down() and is_instance_valid(target_teammate):
        ## print_debug("%s calling ball.initiate_pass to %s at %s" % [player_name, target_teammate.player_name, anticipated_target_pos])
        ball_node.initiate_pass(self, target_teammate, anticipated_target_pos) # Pass both node and position

func initiate_kick(target_override: Vector2 = Vector2.INF):
    if has_ball and ball_node and not get_is_knocked_down():
        var kick_target_pos: Vector2 = target_override if target_override != Vector2.INF else (TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER)
        ## print_debug("%s KICK towards %s" % [player_name, str(kick_target_pos.round())])
        ball_node.initiate_kick(self, kick_target_pos)
        can_kick_timer = KICK_COOLDOWN; can_pass_timer = PASS_COOLDOWN

# ------------------------------------ TACKLING & KNOCKDOWN ------------------------------------
func _on_tackle_area_body_entered(body):
    if body.has_method("get_player_name") and body != self and body.team_id != team_id \
    and body.has_method("get_is_knocked_down") and not body.get_is_knocked_down():
        if body.has_ball:
            if tackle_power > body.agility: # Direct stat comparison
                # print_debug("Tackle SUCCEEDED by %s on %s!" % [player_name, body.player_name]) # Keep for now
                if body.has_method("apply_knockdown"): body.apply_knockdown(self)
                if ball_node and ball_node.current_possessor == body:
                    ball_node.set_loose(body.velocity if body.has_method("get") and typeof(body.get("velocity"))==TYPE_VECTOR2 else Vector2.ZERO)

func attempt_aggressive_tackle(target_opponent: Node):
    if not is_instance_valid(target_opponent) or not target_opponent.has_method("get_is_knocked_down") or target_opponent.get_is_knocked_down() or can_aggressive_tackle_timer > 0.0: return
    can_aggressive_tackle_timer = AGGRESSIVE_TACKLE_COOLDOWN
    if self.tackle_power > target_opponent.agility:
        if target_opponent.has_method("apply_knockdown"): target_opponent.apply_knockdown(self)
        if ball_node != null and ball_node.current_possessor == target_opponent:
            if ball_node.has_method("set_loose"): ball_node.set_loose(target_opponent.velocity if target_opponent.has_method("get") and typeof(target_opponent.get("velocity"))==TYPE_VECTOR2 else Vector2.ZERO)

func apply_knockdown(_tackler):
    if not get_is_knocked_down():
        ## print_debug(">>> %s applying knockdown, DISABLING shape: %s" % [player_name, collision_shape.name if collision_shape else "NULL"])
        is_knocked_down = true; knockdown_timer = KNOCKDOWN_DURATION; velocity = Vector2.ZERO
        # Clear block target if this player is knocked down
        if is_instance_valid(current_block_target_node):
            clear_block_target()
        set_state(PlayerState.KNOCKED_DOWN)
        if collision_shape: collision_shape.set_deferred("disabled", true)
        else: printerr("ERROR: Player %s missing collision_shape!" % player_name)

# ------------------------------------ UTILITY / GETTERS / RESET ------------------------------------
func get_player_name() -> String: return str(player_name) if player_name != "" and player_name != "Player" else str(name)
func get_is_knocked_down() -> bool: return is_knocked_down

func clear_block_target():
    if field_node != null and is_instance_valid(current_block_target_node):
        field_node.remove_target_for_blocker(current_block_target_node)
        ## print_debug("%s cleared block target %s" % [player_name, current_block_target_node.player_name if is_instance_valid(current_block_target_node) else "N/A"])
    current_block_target_node = null

func is_target_still_valid(target_node: Node) -> bool:
    if not is_instance_valid(target_node): return false
    if not target_node.has_method("get_is_knocked_down") or target_node.get_is_knocked_down(): return false
    if not target_node.has_method("get_team_id") or target_node.get_team_id() == self.team_id: return false
    # Add any other checks, e.g., if target is too far, off-screen etc. (optional)
    return true

func set_state(new_state: PlayerState):
    if current_state != new_state:
        var old_state = current_state
        ## print_debug("%s: %s -> %s" % [player_name, PlayerState.keys()[current_state], PlayerState.keys()[new_state]]) # Potentially keep if states are tricky
        current_state = new_state

        # Clear block target if transitioning out of an offensive state or into a non-blocking state
        if old_state == PlayerState.BLOCKER_ENGAGING and new_state != PlayerState.BLOCKER_ENGAGING:
            clear_block_target()
        elif new_state == PlayerState.HAS_BALL or \
             new_state == PlayerState.PURSUING_BALL or \
             new_state == PlayerState.KNOCKED_DOWN or \
             (new_state == PlayerState.DEFENDING and player_role != "Blocker"): # Keep target if Blocker is Defending (might want to block for a tackler)
            clear_block_target()
        
        # Specific logic for Blocker role timers
        if player_role == "Blocker":
            if new_state == PlayerState.HAS_BALL:
                blocker_hold_ball_timer = BLOCKER_MAX_HOLD_TIME
            elif old_state == PlayerState.HAS_BALL and new_state != PlayerState.HAS_BALL: # Check old_state as current_state is already new_state
                 blocker_hold_ball_timer = 0.0
        
        # This was the old logic for clearing block target, much of it is now handled by clear_block_target() calls above
        # Ensure it's still cleared if somehow missed by above transitions
        # if new_state != PlayerState.BLOCKER_ENGAGING and \
        #    not (new_state == PlayerState.SUPPORTING_OFFENSE and player_role == "Blocker") and \
        #    not (new_state == PlayerState.IDLE and player_role == "Blocker" and is_instance_valid(ball_node) and is_instance_valid(ball_node.current_possessor) and ball_node.current_possessor.team_id == self.team_id ):
        #     if is_instance_valid(current_block_target_node): # Check before clearing
        #         clear_block_target()


func reset_state(): 
    ## print_debug("Reset state for %s" % player_name)
    is_knocked_down = false; knockdown_timer = 0.0
    has_ball = false; can_pass_timer = 0.0; can_kick_timer = 0.0
    can_aggressive_tackle_timer = 0.0; blocker_hold_ball_timer = 0.0
    current_stamina = max_stamina
    if collision_shape and collision_shape.disabled: collision_shape.set_deferred("disabled", false)
    velocity = Vector2.ZERO
    if is_instance_valid(current_block_target_node): # Ensure cleared on reset
        clear_block_target()
    # current_block_target_node = null # Done by clear_block_target
    set_state(PlayerState.IDLE)
