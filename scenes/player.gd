# player.gd - Full Version with Passer Support AI & Role-Prioritized Pass Targeting
extends CharacterBody2D

enum PlayerState {
    IDLE,                   # (Placeholder for now, e.g., pre-game or if truly doing nothing)
    PURSUING_BALL,          # Actively trying to get a loose ball
    SUPPORTING_OFFENSE,     # Teammate has the ball, player is supporting
    HAS_BALL,               # Player is the current ball carrier
    DEFENDING,              # Opponent has the ball
    KNOCKED_DOWN,
    BLOCKER_ENGAGING        # Blocker specific: moving to or engaging a block target
}
var current_state: PlayerState = PlayerState.IDLE # Initial state

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
var current_block_target_node: Node = null
const KNOCKDOWN_DURATION: float = 1.5
var can_pass_timer: float = 0.0
const PASS_COOLDOWN: float = 0.5
var can_kick_timer: float = 0.0
var blocker_hold_ball_timer: float = 0.0
const BLOCKER_MAX_HOLD_TIME: float = 2.0
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
    current_state = PlayerState.IDLE # Or PURSUING_BALL if appropriate for game start
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
    if team_id == 0: # Team 0 (Starts Left)
        if team0_texture: sprite.texture = team0_texture
        else: printerr("Player %s (Team 0) missing team0_texture!" % player_name)
        sprite.modulate = Color.WHITE
    else: # Team 1 (Starts Right)
        if team1_texture: sprite.texture = team1_texture
        else: printerr("Player %s (Team 1) missing team1_texture!" % player_name)
        sprite.modulate = Color.WHITE

    # Fallback for player_name property
    if player_name == "" or player_name == "Player":
        player_name = name
        push_warning("Player node '%s' player_name property not set in Inspector, using node name." % name)

func _physics_process(delta):
    # --- Update Cooldown Timers ---
    if can_pass_timer > 0.0:
        can_pass_timer -= delta
    if can_kick_timer > 0.0:
        can_kick_timer -= delta
    
    # Blocker specific: Update timer for holding the ball
    if player_role == "Blocker" and has_ball and current_state == PlayerState.HAS_BALL: # Check state too
        if blocker_hold_ball_timer > 0.0:
            blocker_hold_ball_timer -= delta

    # --- State-Specific Logic & Action Decisions ---
    # (This 'match current_state:' block should already be in your script from Turn 129/131)
    match current_state:
        PlayerState.IDLE:                  _state_idle(delta)
        PlayerState.PURSUING_BALL:         _state_pursuing_ball(delta)
        PlayerState.SUPPORTING_OFFENSE:    _state_supporting_offense(delta)
        PlayerState.HAS_BALL:              _state_has_ball(delta) # Contains Blocker logic, kick, pass
        PlayerState.DEFENDING:             _state_defending(delta)
        PlayerState.KNOCKED_DOWN:          _state_knocked_down(delta)
        PlayerState.BLOCKER_ENGAGING:      _state_blocker_engaging(delta)
        _:
            push_error("Player %s in unknown state: %s" % [player_name, PlayerState.keys()[current_state]])
            set_state(PlayerState.IDLE) # Fallback

    # --- Common Post-State Logic (Stamina, Movement) ---
    # This logic runs AFTER the state has potentially decided an action or set velocity
    if current_state != PlayerState.KNOCKED_DOWN: # Knocked down state handles its own minimal movement
        
        var state_handled_movement = false 
        # Check if the current state already fully handled movement and velocity
        if (current_state == PlayerState.HAS_BALL and player_role == "Blocker") or \
           (current_state == PlayerState.BLOCKER_ENGAGING and is_instance_valid(current_block_target_node) and \
            global_position.distance_squared_to(current_block_target_node.global_position) < (30.0*30.0) ):
            state_handled_movement = true
        # Add other states here if they fully manage their own velocity and move_and_slide

        if not state_handled_movement:
            # Stamina calculation
            var stamina_factor = clamp(current_stamina / max_stamina if max_stamina > 0 else 1.0, 0.2, 1.0)
            var effective_speed = base_speed * stamina_factor

            var target_position = determine_target_position()
            var direction = global_position.direction_to(target_position)
            
            if global_position.distance_squared_to(target_position) > 25:
                velocity = direction * effective_speed
            else:
                velocity = Vector2.ZERO
        
        move_and_slide() # Apply calculated or state-set velocity

        # Stamina drain/recovery AFTER movement has been applied
        if velocity.length_squared() > 10: current_stamina -= STAMINA_DRAIN_RATE * delta
        else: current_stamina += STAMINA_RECOVERY_RATE * delta
        current_stamina = clamp(current_stamina, 0.0, max_stamina)

        # Update Sprite Rotation (if moving)
        if velocity.length_squared() > 0:
            sprite.rotation = velocity.angle()

# -----------------------------------------------------------------------------
# AI TARGETING AND DECISION MAKING HELPERS
# -----------------------------------------------------------------------------
# Determines WHERE the player should move towards this frame
func determine_target_position() -> Vector2:
    if ball_node == null:
        # printerr("Player %s cannot find ball node in determine_target_position!" % player_name)
        return global_position # Stay put if no ball

    # Determine which goal this player is attacking (the one they score in)
    # User confirmed: Team 0 (Starts Left) attacks TEAM1_GOAL_CENTER (Right, +X).
    # User confirmed: Team 1 (Starts Right) attacks TEAM0_GOAL_CENTER (Left, -X).
    var target_goal_center: Vector2 = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER

    if has_ball:
        # --- Offensive AI (Ball Carrier) ---
        # This logic is primarily for Runners/Passers if they have the ball.
        # Blocker ball-carrying logic is handled directly in _physics_process and usually returns early.
        # If a Blocker somehow reaches here with the ball (e.g., couldn't pass and didn't hit desperation timer),
        # they'll run towards the goal (which is an acceptable fallback for now).
        return target_goal_center

    elif ball_node.current_possessor == null:
        # --- Ball is loose ---
        var players = get_all_players() # Assumes this function is defined
        var my_dist_sq = global_position.distance_squared_to(ball_node.global_position)
        var players_closer_count = 0
        # const MAX_LOOSE_BALL_ATTACKERS = 2 # Defined at top of script

        for p in players: # Check all OTHER players
            if p.global_position.distance_squared_to(ball_node.global_position) < my_dist_sq:
                players_closer_count += 1
        
        if players_closer_count < MAX_LOOSE_BALL_ATTACKERS:
            # This player IS one of the closest designated attackers, go for the ball.
            # print_debug("%s (%s) is one of %d closest, going for loose ball." % [player_name, player_role, MAX_LOOSE_BALL_ATTACKERS])
            self.current_block_target_node = null # Clear any previous blocking target
            return ball_node.global_position
        else:
            # --- Not one of the designated attackers for loose ball. ---
            # --- ROLE-BASED BEHAVIOR for non-pursuers on loose ball ---
            if player_role == "Blocker":
                # Blocker looks for an opponent near the loose ball to engage.
                # print_debug("%s (Blocker, loose ball non-attacker) looking for opponent near ball." % player_name)
                self.current_block_target_node = find_defender_to_block(ball_node) # Pass ball_node as "carrier" for context
                if is_instance_valid(self.current_block_target_node):
                    return self.current_block_target_node.global_position
                else: 
                    # No defender to block near ball, Blocker holds a defensive position
                    var defensive_hold_x_pos = -FIELD_HALF_WIDTH * 0.25 if team_id == 0 else FIELD_HALF_WIDTH * 0.25
                    var target_y = ball_node.global_position.y + ((hash(player_name) % int(FIELD_HALF_HEIGHT * 0.8)) - (FIELD_HALF_HEIGHT * 0.4))
                    target_y = clamp(target_y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT + field_margin)
                    return global_position.lerp(Vector2(defensive_hold_x_pos, target_y), 0.1)
            else: # Runners and Passers (non-attackers on loose ball)
                # Move to a cautious defensive/neutral position on own side of midfield.
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
            # --- END REFINED LOGIC for Non-Attackers on Loose Ball ---

    else: # Ball is held by someone else
        var carrier = ball_node.current_possessor
        # Check if carrier node is still valid
        if not is_instance_valid(carrier):
             # printerr("Player %s found invalid carrier node!" % player_name)
             self.current_block_target_node = null # Clear block target
             return ball_node.global_position # Target ball if carrier invalid

        # --- Determine if carrier is teammate or opponent ---
        if carrier.team_id != self.team_id:
            # --- Defensive AI ---
            # Move towards the opponent ball carrier
            self.current_block_target_node = null # Clear block target
            return carrier.global_position
        else:
            # --- Offensive AI (Teammate Support) --- ROLE BASED ---
            # Teammate has the ball, determine action based on this player's role
            if player_role == "Blocker":
                # Blocker targets the nearest relevant defender
                self.current_block_target_node = find_defender_to_block(carrier) # Store target
                if is_instance_valid(self.current_block_target_node):
                    return self.current_block_target_node.global_position
                else: # Fallback if no defender found by find_defender_to_block
                    return calculate_basic_support_pos(carrier)

            elif player_role == "Runner":
                self.current_block_target_node = null # Clear block target
                return find_open_route_position(carrier)

            elif player_role == "Passer":
                self.current_block_target_node = null # Clear block target
                return find_passer_support_position(carrier)

            else: # Default/Unknown role - use basic support as fallback
                self.current_block_target_node = null # Clear block target
                push_warning("Player %s has unknown role '%s', using default offensive support." % [player_name, player_role])
                return calculate_basic_support_pos(carrier)
                
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

func find_open_teammate():
    var all_players = get_all_players()
    var open_runners: Array[Node] = []
    var open_passers: Array[Node] = []
    var open_others: Array[Node] = []

    for teammate in all_players:
        if teammate.team_id == self.team_id and \
           teammate.has_method("get_is_knocked_down") and not teammate.get_is_knocked_down() and \
           teammate.has_method("get"): # Ensure it's a player with roles

            if is_teammate_open(teammate, all_players):
                var role = teammate.get("player_role")
                if role == "Runner":
                    open_runners.append(teammate)
                elif role == "Passer":
                    open_passers.append(teammate)
                else: # Blockers or unknown roles
                    open_others.append(teammate)

    var best_target: Node = null
    var best_target_x_progress: float = -INF if team_id == 0 else INF # Team 0 attacks Right (+X), Team 1 attacks Left (-X)

    # Prioritize Runners, pick the one furthest downfield
    if not open_runners.is_empty():
        for runner_node in open_runners:
            if team_id == 0: # Attacking Right (+X), so higher X is better
                if runner_node.global_position.x > best_target_x_progress:
                    best_target_x_progress = runner_node.global_position.x
                    best_target = runner_node
            else: # Attacking Left (-X), so lower X is better
                if runner_node.global_position.x < best_target_x_progress:
                    best_target_x_progress = runner_node.global_position.x
                    best_target = runner_node
        if best_target:
            print_debug("%s found BEST OPEN RUNNER: %s (at X: %.1f)" % [player_name, best_target.player_name, best_target_x_progress])
            return best_target

    # If no suitable Runner, prioritize Passers, pick the one furthest downfield
    best_target_x_progress = -INF if team_id == 0 else INF # Reset for Passers
    if not open_passers.is_empty():
        for passer_node in open_passers:
            if team_id == 0: # Attacking Right (+X)
                if passer_node.global_position.x > best_target_x_progress:
                    best_target_x_progress = passer_node.global_position.x
                    best_target = passer_node
            else: # Attacking Left (-X)
                if passer_node.global_position.x < best_target_x_progress:
                    best_target_x_progress = passer_node.global_position.x
                    best_target = passer_node
        if best_target:
            print_debug("%s found BEST OPEN PASSER: %s (at X: %.1f)" % [player_name, best_target.player_name, best_target_x_progress])
            return best_target

    # If no suitable Runner or Passer, check Others (less ideal targets)
    # For "Others" (e.g., Blockers), just picking the first open one might be fine for now.
    if not open_others.is_empty():
        print_debug("%s found OTHER OPEN teammate: %s" % [player_name, open_others[0].player_name])
        return open_others[0]

    return null
    
func is_teammate_open(teammate_node: Node, all_players: Array[Node]) -> bool:
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if teammate_node.global_position.distance_squared_to(opponent.global_position) < OPEN_RADIUS_SQ:
                return false
    return true

func is_in_clearing_zone() -> bool:
    var threshold = FIELD_HALF_WIDTH * 0.25 # Example: Own 25% of field
    if team_id == 0: # Team 0 DEFENDS Left (-X) side
        return global_position.x < -threshold
    elif team_id == 1: # Team 1 DEFENDS Right (+X) side
        return global_position.x > threshold
    return false

# Finds the best opponent defender near the carrier for a Blocker to target
# MODIFIED: Returns the Node of the target defender, or null
func find_defender_to_block(carrier: Node) -> Node: # Return type is Node
    var all_players = get_all_players()
    var target_defender_node: Node = null # Store the node
    var min_dist_sq_to_blocker = BLOCKING_ENGAGEMENT_RADIUS_SQ 

    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            var dist_sq_to_carrier = carrier.global_position.distance_squared_to(opponent.global_position)
            if dist_sq_to_carrier < BLOCKING_ENGAGEMENT_RADIUS_SQ: # Check if opponent is near the carrier
                var dist_sq_to_me = global_position.distance_squared_to(opponent.global_position)
                if dist_sq_to_me < min_dist_sq_to_blocker: # And if they are the closest to ME (the blocker)
                    min_dist_sq_to_blocker = dist_sq_to_me
                    target_defender_node = opponent # Store the actual node
        
    return target_defender_node # Return the node (or null if none found)

func calculate_basic_support_pos(carrier: Node) -> Vector2:
    var target_goal = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    var dir_to_goal = (target_goal - carrier.global_position).normalized()
    if dir_to_goal==Vector2.ZERO: dir_to_goal = (target_goal - global_position).normalized()
    if dir_to_goal==Vector2.ZERO: dir_to_goal = Vector2(1,0) if carrier.team_id==0 else Vector2(-1,0)
    var support_pos = carrier.global_position + dir_to_goal * 100.0
    var side_dir = Vector2(dir_to_goal.y, -dir_to_goal.x); var side_amt = (hash(player_name)%100-50)
    support_pos += side_dir * side_amt; return support_pos

# Calculates a target point downfield for Runners supporting the carrier
# Calculates a target point downfield for Runners supporting the carrier
func find_open_route_position(carrier: Node) -> Vector2:
    # Determine the goal the CARRIER's team is attacking
    var carrier_target_goal: Vector2 = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    
    var direction_to_goal = (carrier_target_goal - global_position).normalized()

    if direction_to_goal == Vector2.ZERO:
        direction_to_goal = Vector2(1, 0) if carrier.team_id == 0 else Vector2(-1, 0)

    var route_distance = 300.0
    # var lateral_spread_strength = 150.0 # <--- THIS LINE WAS REMOVED
    
    var hash_value = hash(player_name)
    var lateral_offset_factor = 0.0
    if hash_value % 3 == 0:
        lateral_offset_factor = 0.0
    elif hash_value % 3 == 1:
        lateral_offset_factor = 0.75
    else: # hash_value % 3 == 2
        lateral_offset_factor = -0.75

    var perpendicular_direction = direction_to_goal.orthogonal() # Use base_direction_to_goal here
    
    # The lateral offset is applied, then normalized with the forward direction
    var final_target_direction = (direction_to_goal + perpendicular_direction * lateral_offset_factor).normalized()
    
    var random_angle_variation = randf_range(-PI / 10.0, PI / 10.0)
    final_target_direction = final_target_direction.rotated(random_angle_variation)

    var target_route_pos = global_position + final_target_direction * route_distance

    target_route_pos.x = clamp(target_route_pos.x, -FIELD_HALF_WIDTH + field_margin, FIELD_HALF_WIDTH - field_margin)
    target_route_pos.y = clamp(target_route_pos.y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
    
    return target_route_pos

# --- NEW FUNCTION for Passer Support ---
func find_passer_support_position(carrier: Node) -> Vector2:
    var ideal_distance_from_carrier = 150.0
    var best_pos = global_position
    var max_safety_score = -INF
    var carrier_attack_dir = ( (TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER) - carrier.global_position ).normalized()
    if carrier_attack_dir == Vector2.ZERO: carrier_attack_dir = Vector2(1,0) if carrier.team_id == 0 else Vector2(-1,0)

    var relative_positions = [
        carrier_attack_dir.rotated(PI) * ideal_distance_from_carrier,             # Directly behind
        carrier_attack_dir.rotated(PI * 0.8) * ideal_distance_from_carrier,       # Angled behind left
        carrier_attack_dir.rotated(PI * 1.2) * ideal_distance_from_carrier,       # Angled behind right
        carrier_attack_dir.rotated(PI * 0.5) * ideal_distance_from_carrier * 0.7, # Lateral left
        carrier_attack_dir.rotated(PI * 1.5) * ideal_distance_from_carrier * 0.7  # Lateral right
    ]
    var all_players = get_all_players()
    for offset in relative_positions:
        var candidate_pos = carrier.global_position + offset
        candidate_pos.x = clamp(candidate_pos.x, -FIELD_HALF_WIDTH + field_margin, FIELD_HALF_WIDTH - field_margin)
        candidate_pos.y = clamp(candidate_pos.y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
        var closest_opponent_dist_sq = INF; var open_spot = true
        for p in all_players:
            if p.team_id != self.team_id:
                var dist_to_candidate_sq = candidate_pos.distance_squared_to(p.global_position)
                if dist_to_candidate_sq < closest_opponent_dist_sq: closest_opponent_dist_sq = dist_to_candidate_sq
                if dist_to_candidate_sq < OPEN_RADIUS_SQ: open_spot = false; break
        if open_spot and closest_opponent_dist_sq > max_safety_score:
            max_safety_score = closest_opponent_dist_sq; best_pos = candidate_pos
    if max_safety_score == -INF:
        var lateral_offset_dir = Vector2(carrier_attack_dir.y, -carrier_attack_dir.x)
        var side_multiplier = 1.0 if (hash(player_name) % 2 == 0) else -1.0
        best_pos = carrier.global_position + (lateral_offset_dir * ideal_distance_from_carrier * 0.7 * side_multiplier)
        best_pos.x = clamp(best_pos.x, -FIELD_HALF_WIDTH + field_margin, FIELD_HALF_WIDTH - field_margin)
        best_pos.y = clamp(best_pos.y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
    return best_pos

func find_nearby_offensive_teammate():
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
    if not has_ball and not get_is_knocked_down():
        has_ball = true
        can_pass_timer = PASS_COOLDOWN
        can_kick_timer = KICK_COOLDOWN
        if player_role == "Blocker":
            blocker_hold_ball_timer = BLOCKER_MAX_HOLD_TIME

        current_state = PlayerState.HAS_BALL # <<< SET STATE
        print_debug("%s picked up ball. State: HAS_BALL" % player_name)

func lose_ball():
    if has_ball:
        has_ball = false
        current_block_target_node = null # Clear block target if had one
        # Decide next state: if ball is now loose, pursue it.
        # More nuanced transitions can be added later (e.g., if pass was complete to teammate)
        current_state = PlayerState.PURSUING_BALL # <<< SET STATE
        print_debug("%s lost ball. State: PURSUING_BALL" % player_name)

func initiate_pass(target_teammate: Node):
    if has_ball and ball_node and not get_is_knocked_down():
        ball_node.initiate_pass(self, target_teammate)

func initiate_kick(target_override: Vector2 = Vector2.INF): # Add optional target_override
    if has_ball and ball_node and not get_is_knocked_down():
        var kick_target_pos: Vector2

        if target_override != Vector2.INF: # Check if a specific target was provided
            kick_target_pos = target_override
            print_debug("%s KICK towards OVERRIDE target %s" % [player_name, str(kick_target_pos.round())])
        else: # No override, use default clearing kick target
            kick_target_pos = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER # Default: opponent's goal
            print_debug("%s KICK towards default target %s" % [player_name, str(kick_target_pos.round())])

        ball_node.initiate_kick(self, kick_target_pos) # Call ball's kick function
        can_kick_timer = KICK_COOLDOWN
        can_pass_timer = PASS_COOLDOWN # Reset both cooldowns

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
func apply_knockdown(_tackler): # _tackler parameter is present but not used in this version
    # Only apply if not already knocked down
    if not get_is_knocked_down(): # Use getter function
        print_debug(">>> %s applying knockdown, DISABLING shape: %s" % [player_name, collision_shape.name if collision_shape else "NULL"])
        
        is_knocked_down = true      # Set the boolean state variable
        knockdown_timer = KNOCKDOWN_DURATION # Start the timer
        velocity = Vector2.ZERO     # Stop all movement immediately
        
        # --- Transition State ---
        set_state(PlayerState.KNOCKED_DOWN) # Set the FSM state
        # ---

        # Disable collision shape safely
        if collision_shape:
            collision_shape.set_deferred("disabled", true)
        else:
            # Error if shape node not found
            printerr("ERROR in apply_knockdown for %s: Cannot find collision_shape node to disable!" % player_name)

func handle_knockdown(delta):
    knockdown_timer -= delta; velocity = velocity.move_toward(Vector2.ZERO, 300 * delta); move_and_slide()
    if knockdown_timer <= 0:
        is_knocked_down = false
        print_debug("<<< %s getting up, ENABLING shape: %s" % [player_name, collision_shape.name if collision_shape else "NULL"])
        if collision_shape and collision_shape.disabled: collision_shape.set_deferred("disabled", false)

# ------------------------------------ UTILITY / GETTERS / RESET ------------------------------------
func set_state(new_state: PlayerState):
    if current_state != new_state:
        print_debug("%s changing state from %s to %s" % [player_name, PlayerState.keys()[current_state], PlayerState.keys()[new_state]])
        current_state = new_state
        # TODO: Could add on_enter_state / on_exit_state logic here later

func get_player_name() -> String: return str(player_name) if player_name != "" and player_name != "Player" else str(name)
func get_is_knocked_down() -> bool: return is_knocked_down
func reset_state(): print_debug("Reset state for %s" % player_name); is_knocked_down = false; knockdown_timer = 0.0; has_ball = false; can_pass_timer = 0.0; can_kick_timer = 0.0; current_stamina = max_stamina; if collision_shape and collision_shape.disabled: collision_shape.set_deferred("disabled", false); velocity = Vector2.ZERO

func _state_idle(_delta):
    # print_debug("%s is IDLE" % player_name) # For debugging
    # For now, an idle player does nothing, movement will be zero based on target=self
    # Target will be set by determine_target_position based on context
    pass

func _state_pursuing_ball(_delta):
    # Logic for when actively going for a loose ball.
    # Mainly driven by determine_target_position returning ball_node.global_position.
    # Action decisions (like dive for ball?) could go here later.
    # print_debug("%s is PURSUING_BALL" % player_name)
    pass

func _state_supporting_offense(_delta):
    # Logic for when supporting a teammate who has the ball.
    # Mainly driven by determine_target_position returning a support spot.
    # print_debug("%s is SUPPORTING_OFFENSE" % player_name)
    pass

func _state_has_ball(_delta):
    # print_debug("%s: HAS_BALL state" % player_name)
    var attacking_goal_center = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER
    var distance_to_goal_sq = global_position.distance_squared_to(attacking_goal_center)

    # PRIORITY 1: If very close to scoring, just try to run
    if distance_to_goal_sq < SCORE_ATTEMPT_RANGE_SQ:
        # print_debug("%s is in scoring range (%s), prioritizing run!" % [player_name, str(global_position.round())])
        # No specific action here, velocity will be set by main movement logic targeting the goal
        return 
    
    # PRIORITY 2: Blocker with the ball has special handling
    # (This logic block for Blockers should already be here from Turn 129)
    if player_role == "Blocker":
        var target_for_handoff = find_nearby_offensive_teammate()
        if target_for_handoff != null and can_pass_timer <= 0.0:
            initiate_pass(target_for_handoff)
            velocity = Vector2.ZERO 
        elif blocker_hold_ball_timer <= 0.0:
            # print_debug("Blocker %s held ball too long, desperation kick!" % player_name)
            var forward_direction = (attacking_goal_center - global_position).normalized()
            if forward_direction == Vector2.ZERO: forward_direction = Vector2(1,0) if team_id == 0 else Vector2(-1,0)
            var desperation_target = global_position + forward_direction * 150.0
            initiate_kick(desperation_target) 
            velocity = Vector2.ZERO
        else:
            velocity = Vector2.ZERO
        # Blocker state handles its velocity directly, no fall-through to general movement targeting for carrier
        # move_and_slide() is handled by the main _physics_process loop
        return # Indicate Blocker has handled its action for this frame (even if it's just stopping)

    # PRIORITY 3: Non-Blocker Actions (Kick/Pass)
    # These only run if the player has the ball, IS NOT a Blocker, AND is NOT in immediate scoring range.
    
    # --- NEW: Check if player should even consider a clearing kick ---
    var can_consider_clearing_kick = true
    # Team 0 defends Left (-X), Team 1 defends Right (+X)
    # Don't clear kick if in opponent's half
    if team_id == 0: # Attacking Right (+X)
        if global_position.x > 0: # Player is on opponent's (Right) side of field
            can_consider_clearing_kick = false
    elif team_id == 1: # Attacking Left (-X)
        if global_position.x < 0: # Player is on opponent's (Left) side of field
            can_consider_clearing_kick = false
    # --- END NEW CHECK ---

    if can_kick_timer <= 0.0 and is_in_clearing_zone() and can_consider_clearing_kick: # ADDED can_consider_clearing_kick
        # print_debug("%s is in clearing zone (%s) and can consider kick, attempting." % [player_name, str(global_position.round())])
        initiate_kick() # Uses default target (opponent goal center)
        # After initiate_kick, has_ball becomes false.
        # The player will continue to the main movement logic at the end of _physics_process,
        # now acting as a non-carrier, and their state will update via lose_ball().
        return # Action taken for this frame's decision making
    
    elif can_pass_timer <= 0.0: # Check for Passing (if didn't kick and pass cooldown ready)
        if is_under_pressure():
            var target_teammate = find_open_teammate() # This prioritizes by role
            if target_teammate != null:
                # print_debug("%s passing under pressure to OPEN teammate %s!" % [player_name, target_teammate.player_name])
                initiate_pass(target_teammate)
                velocity = Vector2.ZERO # Stop moving immediately after initiating pass
                # No move_and_slide() here, main loop will do it. has_ball will be false.
                return # Action taken
    
    # If no specific action (kick/pass/blocker_action) was taken by the carrier in this state,
    # they will default to running, handled by the main movement logic using determine_target_position.

func _state_defending(_delta):
    # Logic for when opponent has the ball.
    # Mainly driven by determine_target_position returning opponent carrier.
    # Action decisions (like attempt tackle if close?) could go here.
    # print_debug("%s is DEFENDING" % player_name)
    pass

func _state_knocked_down(delta):
    # Replaces direct call to handle_knockdown from _physics_process
    knockdown_timer -= delta
    velocity = velocity.move_toward(Vector2.ZERO, 300 * delta) # Still manage own velocity
    # move_and_slide() is done in main loop, but this state directly sets velocity
    
    if knockdown_timer <= 0.0:
        is_knocked_down = false
        print_debug("<<< %s getting up, ENABLING shape: %s" % [player_name, collision_shape.name if collision_shape else "NULL"])
        if collision_shape and collision_shape.disabled:
            collision_shape.set_deferred("disabled", false)
        # --- Transition State ---
        current_state = PlayerState.PURSUING_BALL # Default state after getting up
        print_debug("%s transitioned to PURSUING_BALL after knockdown" % player_name)

func _state_blocker_engaging(_delta):
    # Logic for Blocker moving to engage an opponent when teammate has ball.
    # Movement driven by determine_target_position (which gets current_block_target_node.global_position).
    # This state would handle the "stop/slow down/orient" when close to target.
    if is_instance_valid(current_block_target_node):
        var dist_to_block_target_sq = global_position.distance_squared_to(current_block_target_node.global_position)
        var engagement_distance = 30.0 
        if dist_to_block_target_sq < engagement_distance * engagement_distance:
            velocity = (current_block_target_node.global_position - global_position).normalized() * (base_speed * 0.1)
            if velocity.length_squared() > 0: sprite.rotation = velocity.angle()
        # Else, velocity will be determined by determine_target_position to move towards block target
    else:
        # No block target, maybe transition back to general support?
        current_state = PlayerState.SUPPORTING_OFFENSE
        # print_debug("%s (Blocker) lost block target, returning to SUPPORTING_OFFENSE" % player_name)
