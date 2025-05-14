# player.gd - Full Corrected Version with FSM and AI Refinements
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
const AGGRESSIVE_TACKLE_ATTEMPT_RANGE: float = 40.0
const AGGRESSIVE_TACKLE_ATTEMPT_RANGE_SQ: float = AGGRESSIVE_TACKLE_ATTEMPT_RANGE * AGGRESSIVE_TACKLE_ATTEMPT_RANGE


func _ready():
    current_stamina = max_stamina
    ball_node = get_parent().find_child("Ball")
    if ball_node == null: printerr("Player %s couldn't find Ball node!" % player_name)

    if role_indicator:
        if player_role == "Passer": role_indicator.color = Color.YELLOW
        elif player_role == "Runner": role_indicator.color = Color.GREEN
        elif player_role == "Blocker": role_indicator.color = Color.RED
        else: role_indicator.color = Color.GRAY
    else: printerr("Player %s: Cannot find RoleIndicator node! Path used: $Sprite2D/RoleIndicator" % player_name)

    if team_id == 0: # Team 0 (Starts Left)
        if team0_texture: sprite.texture = team0_texture
        else: printerr("Player %s (Team 0) missing team0_texture!" % player_name)
    else: # Team 1 (Starts Right)
        if team1_texture: sprite.texture = team1_texture
        else: printerr("Player %s (Team 1) missing team1_texture!" % player_name)
    sprite.modulate = Color.WHITE

    if player_name == "" or player_name == "Player":
        player_name = name
        push_warning("Player node '%s' player_name property not set in Inspector, using node name." % name)
    
    set_state(PlayerState.IDLE)


func _physics_process(delta):
    # Update Cooldowns
    if can_pass_timer > 0.0: can_pass_timer -= delta
    if can_kick_timer > 0.0: can_kick_timer -= delta
    if can_aggressive_tackle_timer > 0.0: can_aggressive_tackle_timer -= delta
    
    if player_role == "Blocker" and current_state == PlayerState.HAS_BALL and has_ball:
        if blocker_hold_ball_timer > 0.0:
            blocker_hold_ball_timer -= delta

    # Handle current state logic (actions, transitions)
    match current_state:
        PlayerState.IDLE:                  _state_idle(delta)
        PlayerState.PURSUING_BALL:         _state_pursuing_ball(delta)
        PlayerState.SUPPORTING_OFFENSE:    _state_supporting_offense(delta)
        PlayerState.HAS_BALL:              _state_has_ball(delta)
        PlayerState.DEFENDING:             _state_defending(delta)
        PlayerState.KNOCKED_DOWN:          _state_knocked_down(delta)
        PlayerState.BLOCKER_ENGAGING:      _state_blocker_engaging(delta)
        _:
            push_error("Player %s in unknown state: %s" % [player_name, PlayerState.keys()[current_state]])
            set_state(PlayerState.IDLE) # Fallback

    # Common Post-State Logic (Stamina, Movement if not fully handled by state)
    var state_handled_movement = false
    # Check if the current state already fully handled movement and velocity
    if (current_state == PlayerState.HAS_BALL and player_role == "Blocker") or \
       current_state == PlayerState.KNOCKED_DOWN or \
       (current_state == PlayerState.BLOCKER_ENGAGING and is_instance_valid(current_block_target_node) and \
        global_position.distance_squared_to(current_block_target_node.global_position) < AGGRESSIVE_TACKLE_ATTEMPT_RANGE_SQ * 1.1 ): # Blocker is close to engaging
        state_handled_movement = true
    
    # Apply movement if not handled by state
    if not state_handled_movement:
        var stamina_factor = clamp(current_stamina / max_stamina if max_stamina > 0 else 1.0, 0.2, 1.0)
        var effective_speed = base_speed * stamina_factor
        var target_position = determine_target_position()
        var direction = global_position.direction_to(target_position)
        if global_position.distance_squared_to(target_position) > 25: # Threshold to stop jittering
            velocity = direction * effective_speed
        else:
            velocity = Vector2.ZERO
    
    move_and_slide() # Apply calculated or state-set velocity

    # Stamina drain/recovery AFTER movement has been applied
    if velocity.length_squared() > 10: current_stamina -= STAMINA_DRAIN_RATE * delta
    else: current_stamina += STAMINA_RECOVERY_RATE * delta
    current_stamina = clamp(current_stamina, 0.0, max_stamina)

    # Update Sprite Rotation (if moving and not knocked down)
    if velocity.length_squared() > 0 and current_state != PlayerState.KNOCKED_DOWN:
        sprite.rotation = velocity.angle()

# ------------------------------------
# --- STATE UPDATE FUNCTIONS ---
# ------------------------------------
func _state_idle(_delta):
    # print_debug("%s: IDLE state - evaluating..." % player_name)
    if ball_node == null: return

    if get_is_knocked_down(): # Should have been set by apply_knockdown
        set_state(PlayerState.KNOCKED_DOWN); return

    if ball_node.current_possessor == null:
        set_state(PlayerState.PURSUING_BALL)
    elif is_instance_valid(ball_node.current_possessor):
        if ball_node.current_possessor == self: # Should be set by pickup_ball
            set_state(PlayerState.HAS_BALL)
        elif ball_node.current_possessor.team_id == self.team_id: # Teammate has ball
            if player_role == "Blocker": set_state(PlayerState.BLOCKER_ENGAGING)
            else: set_state(PlayerState.SUPPORTING_OFFENSE)
        else: # Opponent has ball
            set_state(PlayerState.DEFENDING)

func _state_pursuing_ball(_delta):
    # print_debug("%s: PURSUING_BALL state" % player_name)
    # Movement driven by determine_target_position targeting the ball.
    # Transition if ball is picked up (by self via pickup_ball, or by other)
    if ball_node and is_instance_valid(ball_node.current_possessor):
        if ball_node.current_possessor == self: # Should have been set by pickup_ball
            set_state(PlayerState.HAS_BALL)
        elif ball_node.current_possessor.team_id == self.team_id:
            if player_role == "Blocker": set_state(PlayerState.BLOCKER_ENGAGING)
            else: set_state(PlayerState.SUPPORTING_OFFENSE)
        else:
            set_state(PlayerState.DEFENDING)

func _state_supporting_offense(_delta):
    # print_debug("%s: SUPPORTING_OFFENSE state" % player_name)
    # Movement driven by determine_target_position (role-specific support).
    # Transition if ball becomes loose or opponent gets it.
    if ball_node == null: return
    if ball_node.current_possessor == null:
        set_state(PlayerState.PURSUING_BALL)
    elif is_instance_valid(ball_node.current_possessor) and ball_node.current_possessor.team_id != self.team_id:
        set_state(PlayerState.DEFENDING)
    elif not is_instance_valid(ball_node.current_possessor): # Should not happen if ball_node is valid
        set_state(PlayerState.PURSUING_BALL)

func _state_has_ball(_delta):
    # print_debug("%s: HAS_BALL state. Role: %s" % [player_name, player_role])
    var attacking_goal_center = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER
    var distance_to_goal_sq = global_position.distance_squared_to(attacking_goal_center)

    if distance_to_goal_sq < SCORE_ATTEMPT_RANGE_SQ:
        # print_debug("%s in scoring range, prioritizing run!" % player_name)
        return # Fall through to movement logic in _physics_process
    
    if player_role == "Blocker":
        var target_for_handoff = find_nearby_offensive_teammate()
        if target_for_handoff != null and can_pass_timer <= 0.0:
            initiate_pass(target_for_handoff); velocity = Vector2.ZERO
        elif blocker_hold_ball_timer <= 0.0:
            # print_debug("Blocker %s held ball too long, desperation kick!" % player_name)
            var forward_direction = (attacking_goal_center - global_position).normalized()
            if forward_direction == Vector2.ZERO: forward_direction = Vector2(1,0) if team_id == 0 else Vector2(-1,0)
            var desperation_target = global_position + forward_direction * 150.0
            initiate_kick(desperation_target); velocity = Vector2.ZERO
        else:
            velocity = Vector2.ZERO # Blocker holds ball and stops
        # Blocker state handles its velocity; movement in _physics_process will use this.
        # No return needed if velocity is set for the main loop's move_and_slide.
        return # Explicitly return to signify this state manages its action/velocity completely

    # --- Non-Blocker Actions (Runner, Passer, Others) ---
    var can_consider_clearing_kick = true
    # Team 0 attacks Right (+X), their defensive half is Left (-X)
    if team_id == 0: if global_position.x > 0: can_consider_clearing_kick = false
    # Team 1 attacks Left (-X), their defensive half is Right (+X)
    elif team_id == 1: if global_position.x < 0: can_consider_clearing_kick = false
    
    if player_role == "Runner":
        if can_kick_timer <= 0.0 and is_in_clearing_zone() and can_consider_clearing_kick:
            initiate_kick(); return # Action taken
        elif can_pass_timer <= 0.0 and is_under_pressure():
            if randf() < 0.1: # Low chance for Runner to pass
                var target_teammate = find_open_teammate()
                if target_teammate != null: initiate_pass(target_teammate); velocity = Vector2.ZERO; return
        return # Runner defaults to running if no kick/rare pass

    # Passer (or other unhandled roles) logic
    if can_kick_timer <= 0.0 and is_in_clearing_zone() and can_consider_clearing_kick:
        initiate_kick(); return
    elif can_pass_timer <= 0.0:
        if is_under_pressure():
            var target_teammate = find_open_teammate()
            if target_teammate != null: initiate_pass(target_teammate); velocity = Vector2.ZERO; return
    # If no action, carrier runs (handled by main movement logic)

func _state_defending(_delta):
    # print_debug("%s: DEFENDING state" % player_name)
    if player_role == "Blocker":
        if ball_node and is_instance_valid(ball_node.current_possessor):
            var carrier = ball_node.current_possessor
            if carrier.team_id != self.team_id: # Opponent has ball
                if global_position.distance_squared_to(carrier.global_position) < AGGRESSIVE_TACKLE_ATTEMPT_RANGE_SQ:
                    attempt_aggressive_tackle(carrier)
    
    if ball_node and ball_node.current_possessor == null: set_state(PlayerState.PURSUING_BALL)
    elif ball_node and is_instance_valid(ball_node.current_possessor) and ball_node.current_possessor.team_id == self.team_id:
        if player_role == "Blocker": set_state(PlayerState.BLOCKER_ENGAGING)
        else: set_state(PlayerState.SUPPORTING_OFFENSE)

func _state_knocked_down(delta):
    # print_debug("%s: KNOCKED_DOWN state, timer: %.1f" % [player_name, knockdown_timer])
    knockdown_timer -= delta
    velocity = Vector2.ZERO # Explicitly stop movement while knocked down
    if knockdown_timer <= 0.0:
        is_knocked_down = false # Clear the underlying flag
        # print_debug("<<< %s getting up, ENABLING shape: %s" % [player_name, collision_shape.name if collision_shape else "NULL"])
        if collision_shape and collision_shape.disabled:
            collision_shape.set_deferred("disabled", false)
        set_state(PlayerState.IDLE) # Transition to IDLE to re-evaluate

func _state_blocker_engaging(_delta):
    # print_debug("%s: BLOCKER_ENGAGING state. Target: %s" % [player_name, current_block_target_node.name if is_instance_valid(current_block_target_node) else "None"])
    if not is_instance_valid(current_block_target_node) or \
       (ball_node and ball_node.current_possessor != null and ball_node.current_possessor.team_id != self.team_id) or \
       (ball_node and ball_node.current_possessor == null): # Target lost, or opponent got ball, or ball loose
        set_state(PlayerState.IDLE) # Re-evaluate
        current_block_target_node = null
        return

    if is_instance_valid(current_block_target_node): # Double check, might have been cleared by above
        var dist_to_block_target_sq = global_position.distance_squared_to(current_block_target_node.global_position)
        if dist_to_block_target_sq < AGGRESSIVE_TACKLE_ATTEMPT_RANGE_SQ:
            attempt_aggressive_tackle(current_block_target_node)
            # Slow down significantly or stop when engaging
            velocity = (current_block_target_node.global_position - global_position).normalized() * (base_speed * 0.05)
        # Else, velocity will be determined by determine_target_position (moving to block target) via main loop.
        # current_block_target_node is used by determine_target_position in this state.
    else: # Should have been caught by first if in this state
        set_state(PlayerState.SUPPORTING_OFFENSE)


# -----------------------------------------------------------------------------
# AI TARGETING AND DECISION MAKING HELPERS
# -----------------------------------------------------------------------------
# Determines WHERE the player should move towards this frame
func determine_target_position() -> Vector2:
    if ball_node == null:
        return global_position # Stay put if no ball

    # Determine which goal THIS player is attacking
    var attacking_goal_center: Vector2 = TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER

    match current_state:
        PlayerState.HAS_BALL:
            # Carrier runs for goal (Blocker exception for setting velocity to ZERO is handled in _state_has_ball)
            return attacking_goal_center
        
        PlayerState.PURSUING_BALL:
            # This state is active when the ball is loose and this player is considering going for it.
            if ball_node.current_possessor != null: # Ball just got picked up by someone
                # State transition will be handled by _state_pursuing_ball, but for this frame,
                # provide a sensible fallback target, perhaps their current position or an idle spot.
                return global_position # Hold until state transition next frame
            
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
                # --- CORRECTED: Non-pursuer on loose ball moves to dynamic defensive hold ---
                # Not one of the designated attackers.
                var defensive_hold_x_pos: float
                if team_id == 0: # Team 0 DEFENDS Left side (-X)
                    defensive_hold_x_pos = -FIELD_HALF_WIDTH * 0.25 
                else: # Team 1 DEFENDS Right side (+X)
                    defensive_hold_x_pos = FIELD_HALF_WIDTH * 0.25

                var target_y = ball_node.global_position.y
                target_y += (hash(player_name) % int(FIELD_HALF_HEIGHT * 0.8)) - (FIELD_HALF_HEIGHT * 0.4)
                target_y = clamp(target_y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
                
                var strategic_target = Vector2(defensive_hold_x_pos, target_y)
                return global_position.lerp(strategic_target, 0.1) # Lerp for smoother adjustment
        
        PlayerState.SUPPORTING_OFFENSE:
            var carrier = ball_node.current_possessor
            if is_instance_valid(carrier) and carrier.team_id == self.team_id:
                # Role-specific support logic (Blocker state actually set to BLOCKER_ENGAGING by _state_idle/_state_pursuing_ball)
                if player_role == "Runner": return find_open_route_position(carrier)
                elif player_role == "Passer": return find_passer_support_position(carrier)
                else: return calculate_basic_support_pos(carrier) # Fallback for other roles in this state
            else: # Teammate lost ball or no carrier
                # State transition will be handled by _state_supporting_offense
                return global_position # Hold until state transition

        PlayerState.BLOCKER_ENGAGING:
            var offensive_carrier = ball_node.current_possessor # Could be null if ball just went loose
            if is_instance_valid(offensive_carrier) and offensive_carrier.team_id == self.team_id:
                if not is_instance_valid(current_block_target_node): # Find a new block target if needed
                    current_block_target_node = find_defender_to_block(offensive_carrier)
                
                if is_instance_valid(current_block_target_node):
                    return current_block_target_node.global_position
                else: # No defender to block, provide basic support for the carrier
                    return calculate_basic_support_pos(offensive_carrier)
            else: # Teammate lost ball or no carrier, Blocker re-evaluates
                # State transition handled by _state_blocker_engaging
                return global_position # Hold until state transition

        PlayerState.DEFENDING:
            if is_instance_valid(ball_node.current_possessor) and ball_node.current_possessor.team_id != self.team_id:
                return ball_node.current_possessor.global_position # Target opponent carrier
            else: # Ball became loose or own team got it
                # State transition handled by _state_defending
                return ball_node.global_position if ball_node.current_possessor == null else global_position

        PlayerState.IDLE:
            # Fallback targeting if still in IDLE state (should be transitioned quickly by _state_idle)
            if ball_node.current_possessor == null: return ball_node.global_position
            elif is_instance_valid(ball_node.current_possessor):
                var L_carrier = ball_node.current_possessor
                if L_carrier.team_id == self.team_id: # Teammate has ball
                    if player_role == "Blocker":
                        var block_target = find_defender_to_block(L_carrier)
                        if is_instance_valid(block_target): return block_target.global_position
                        else: return calculate_basic_support_pos(L_carrier)
                    elif player_role == "Runner": return find_open_route_position(L_carrier)
                    elif player_role == "Passer": return find_passer_support_position(L_carrier)
                    else: return calculate_basic_support_pos(L_carrier)
                else: # Opponent has ball
                    return L_carrier.global_position
            return global_position # Fallback

        PlayerState.KNOCKED_DOWN:
            return global_position # Stay put (velocity is handled by _state_knocked_down)

    return global_position # Ultimate fallback if no state matched or other logic failed

# --- Standard Helper Functions ---
func get_all_players() -> Array[Node]:
    var players: Array[Node] = []
    var parent = get_parent()
    if parent:
        for child in parent.get_children():
            if child.is_in_group("players") and child != self: players.append(child)
    return players

func is_under_pressure() -> bool:
    var all_players = get_all_players()
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if global_position.distance_squared_to(opponent.global_position) < PRESSURE_RADIUS_SQ: return true
    return false

func find_open_teammate():
    var all_players = get_all_players(); var open_runners: Array[Node] = []; var open_passers: Array[Node] = []; var open_others: Array[Node] = []
    for teammate in all_players:
        if teammate.team_id == self.team_id and teammate.has_method("get_is_knocked_down") and not teammate.get_is_knocked_down() and teammate.has_method("get"):
            if is_teammate_open(teammate, all_players):
                var role = teammate.get("player_role")
                if role == "Runner": open_runners.append(teammate)
                elif role == "Passer": open_passers.append(teammate)
                else: open_others.append(teammate)
    var best_target: Node = null; var best_target_x_progress: float = -INF if team_id == 0 else INF # Team 0 attacks Right (+X)
    if not open_runners.is_empty():
        for runner_node in open_runners:
            if team_id == 0: 
                if runner_node.global_position.x > best_target_x_progress: best_target_x_progress = runner_node.global_position.x; best_target = runner_node
            else: # Team 1 attacks Left (-X)
                if runner_node.global_position.x < best_target_x_progress: best_target_x_progress = runner_node.global_position.x; best_target = runner_node
        if best_target: 
            # print_debug("%s found BEST OPEN RUNNER: %s (at X: %.1f)" % [player_name,best_target.player_name, best_target_x_progress])
            return best_target
    best_target = null; best_target_x_progress = -INF if team_id == 0 else INF
    if not open_passers.is_empty():
        for passer_node in open_passers:
            if team_id == 0:
                if passer_node.global_position.x > best_target_x_progress: best_target_x_progress = passer_node.global_position.x; best_target = passer_node
            else:
                if passer_node.global_position.x < best_target_x_progress: best_target_x_progress = passer_node.global_position.x; best_target = passer_node
        if best_target: 
            # print_debug("%s found BEST OPEN PASSER: %s (at X: %.1f)" % [player_name,best_target.player_name, best_target_x_progress])
            return best_target
    if not open_others.is_empty(): 
        # print_debug("%s found OTHER OPEN teammate: %s" % [player_name,open_others[0].player_name])
        return open_others[0]
    return null

func is_teammate_open(teammate_node: Node, all_players: Array[Node]) -> bool:
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            if teammate_node.global_position.distance_squared_to(opponent.global_position) < OPEN_RADIUS_SQ: return false
    return true

func is_in_clearing_zone() -> bool:
    var threshold = FIELD_HALF_WIDTH * 0.4
    if team_id == 0: return global_position.x < -threshold # Team 0 DEFENDS Left (-X)
    elif team_id == 1: return global_position.x > threshold # Team 1 DEFENDS Right (+X)
    return false

func find_defender_to_block(carrier_or_ball: Node) -> Node:
    var all_players = get_all_players(); var target_defender_node: Node = null
    var min_dist_sq_to_blocker = BLOCKING_ENGAGEMENT_RADIUS_SQ 
    if not is_instance_valid(carrier_or_ball): return null
    for opponent in all_players:
        if opponent.team_id != self.team_id and opponent.has_method("get_is_knocked_down") and not opponent.get_is_knocked_down():
            var dist_sq_to_ref_point = carrier_or_ball.global_position.distance_squared_to(opponent.global_position)
            if dist_sq_to_ref_point < BLOCKING_ENGAGEMENT_RADIUS_SQ:
                var dist_sq_to_me = global_position.distance_squared_to(opponent.global_position)
                if dist_sq_to_me < min_dist_sq_to_blocker:
                    min_dist_sq_to_blocker = dist_sq_to_me; target_defender_node = opponent
    return target_defender_node

func calculate_basic_support_pos(carrier: Node) -> Vector2:
    if not is_instance_valid(carrier): return global_position
    var target_goal = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    var dir_to_goal = (target_goal - carrier.global_position).normalized()
    if dir_to_goal==Vector2.ZERO: dir_to_goal = (target_goal - global_position).normalized()
    if dir_to_goal==Vector2.ZERO: dir_to_goal = Vector2(1,0) if carrier.team_id==0 else Vector2(-1,0)
    var support_pos = carrier.global_position + dir_to_goal * 100.0
    var side_dir = Vector2(dir_to_goal.y, -dir_to_goal.x); var side_amt = (hash(player_name)%100-50)
    support_pos += side_dir * side_amt; return support_pos

func find_open_route_position(carrier: Node) -> Vector2:
    if not is_instance_valid(carrier): return global_position
    var carrier_target_goal: Vector2 = TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER
    var direction_to_goal = (carrier_target_goal - global_position).normalized()
    if direction_to_goal == Vector2.ZERO: direction_to_goal = Vector2(1, 0) if carrier.team_id == 0 else Vector2(-1, 0)
    var route_distance = 300.0; var random_angle_variation = randf_range(-PI / 10.0, PI / 10.0)
    var target_direction = direction_to_goal.rotated(random_angle_variation)
    var target_route_pos = global_position + target_direction * route_distance
    target_route_pos.x = clamp(target_route_pos.x, -FIELD_HALF_WIDTH + field_margin, FIELD_HALF_WIDTH - field_margin)
    target_route_pos.y = clamp(target_route_pos.y, -FIELD_HALF_HEIGHT + field_margin, FIELD_HALF_HEIGHT - field_margin)
    return target_route_pos

func find_passer_support_position(carrier: Node) -> Vector2:
    if not is_instance_valid(carrier): return global_position
    var ideal_distance_from_carrier = 150.0; var best_pos = global_position; var max_safety_score = -INF
    var carrier_attack_dir = ((TEAM1_GOAL_CENTER if carrier.team_id == 0 else TEAM0_GOAL_CENTER) - carrier.global_position ).normalized()
    if carrier_attack_dir == Vector2.ZERO: carrier_attack_dir = Vector2(1,0) if carrier.team_id == 0 else Vector2(-1,0)
    var relative_positions = [ carrier_attack_dir.rotated(PI) * ideal_distance_from_carrier, carrier_attack_dir.rotated(PI*0.8)*ideal_distance_from_carrier, carrier_attack_dir.rotated(PI*1.2)*ideal_distance_from_carrier, carrier_attack_dir.rotated(PI*0.5)*ideal_distance_from_carrier*0.7, carrier_attack_dir.rotated(PI*1.5)*ideal_distance_from_carrier*0.7 ]
    var all_players = get_all_players()
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
        print_debug("%s picked up ball. State: HAS_BALL" % player_name)

func lose_ball():
    if has_ball:
        has_ball = false; current_block_target_node = null
        if ball_node and ball_node.current_possessor == null: set_state(PlayerState.PURSUING_BALL)
        elif ball_node and is_instance_valid(ball_node.current_possessor) and ball_node.current_possessor.team_id == self.team_id:
            if player_role == "Blocker": set_state(PlayerState.BLOCKER_ENGAGING)
            else: set_state(PlayerState.SUPPORTING_OFFENSE)
        else: set_state(PlayerState.DEFENDING)
        # print_debug("%s lost ball. New State: %s" % [player_name, PlayerState.keys()[current_state]]) # Reduce noise

func initiate_pass(target_teammate: Node):
    if has_ball and ball_node and not get_is_knocked_down():
        ball_node.initiate_pass(self, target_teammate)
        # State change handled by lose_ball()

func initiate_kick(target_override: Vector2 = Vector2.INF):
    if has_ball and ball_node and not get_is_knocked_down():
        var kick_target_pos: Vector2 = target_override if target_override != Vector2.INF else (TEAM1_GOAL_CENTER if team_id == 0 else TEAM0_GOAL_CENTER)
        # print_debug("%s KICK towards %s" % [player_name, str(kick_target_pos.round())])
        ball_node.initiate_kick(self, kick_target_pos)
        can_kick_timer = KICK_COOLDOWN; can_pass_timer = PASS_COOLDOWN # Reset both cooldowns
        # State change handled by lose_ball()

# ------------------------------------ TACKLING & KNOCKDOWN ------------------------------------
func _on_tackle_area_body_entered(body):
    if body.has_method("get_player_name") and body != self and body.team_id != team_id \
    and body.has_method("get_is_knocked_down") and not body.get_is_knocked_down():
        if body.has_ball: # Check if the body being tackled has the ball
            if tackle_power > body.agility: # Assuming 'body' (the player) has an 'agility' property
                print_debug("Tackle SUCCEEDED by %s on %s!" % [player_name, body.player_name])
                if body.has_method("apply_knockdown"): body.apply_knockdown(self)
                if ball_node and ball_node.current_possessor == body:
                    ball_node.set_loose(body.velocity if body.has_method("get") and typeof(body.get("velocity"))==TYPE_VECTOR2 else Vector2.ZERO)


func attempt_aggressive_tackle(target_opponent: Node):
    if not is_instance_valid(target_opponent) or \
       not target_opponent.has_method("get_is_knocked_down") or \
       target_opponent.get_is_knocked_down() or \
       can_aggressive_tackle_timer > 0.0:
        return

    # print_debug("%s (Blocker) ATTEMPTING AGGRESSIVE TACKLE on %s" % [player_name, target_opponent.player_name])
    can_aggressive_tackle_timer = AGGRESSIVE_TACKLE_COOLDOWN

    if self.tackle_power > target_opponent.agility: # Assuming target has 'agility'
        # print_debug("  AGGRESSIVE TACKLE SUCCEEDED by %s on %s!" % [player_name, target_opponent.player_name])
        if target_opponent.has_method("apply_knockdown"):
            target_opponent.apply_knockdown(self)
        # If they had the ball, it should become loose
        if ball_node != null and ball_node.current_possessor == target_opponent:
            if ball_node.has_method("set_loose"):
                ball_node.set_loose(target_opponent.velocity if target_opponent.has_method("get") and typeof(target_opponent.get("velocity"))==TYPE_VECTOR2 else Vector2.ZERO)
    # else:
        # print_debug("  AGGRESSIVE TACKLE FAILED/EVADED by %s against %s!" % [target_opponent.player_name, player_name])


func apply_knockdown(_tackler):
    if not get_is_knocked_down():
        # print_debug(">>> %s applying knockdown, DISABLING shape: %s" % [player_name, collision_shape.name if collision_shape else "NULL"])
        is_knocked_down = true; knockdown_timer = KNOCKDOWN_DURATION; velocity = Vector2.ZERO
        set_state(PlayerState.KNOCKED_DOWN)
        if collision_shape: collision_shape.set_deferred("disabled", true)
        else: printerr("ERROR: Player %s missing collision_shape for knockdown!" % player_name)

# Note: Original handle_knockdown(delta) function is removed as its logic is now in _state_knocked_down

# ------------------------------------ UTILITY / GETTERS / RESET ------------------------------------
func get_player_name() -> String: return str(player_name) if player_name != "" and player_name != "Player" else str(name)

func get_is_knocked_down() -> bool: return is_knocked_down

func set_state(new_state: PlayerState):
    if current_state != new_state:
        # print_debug("%s: %s -> %s" % [player_name, PlayerState.keys()[current_state], PlayerState.keys()[new_state]]) # Can be very spammy
        current_state = new_state
        # Reset Blocker hold timer when they get the ball, or if they lose it and are no longer in HAS_BALL state
        if (new_state == PlayerState.HAS_BALL and player_role == "Blocker"):
            blocker_hold_ball_timer = BLOCKER_MAX_HOLD_TIME
        elif current_state != PlayerState.HAS_BALL and player_role == "Blocker": # Clear if Blocker no longer has ball
            blocker_hold_ball_timer = 0.0
        
        # Clear block target if not in an engaging or supporting state where it's actively set
        if new_state != PlayerState.BLOCKER_ENGAGING and \
           not (new_state == PlayerState.SUPPORTING_OFFENSE and player_role == "Blocker") and \
           not (new_state == PlayerState.IDLE and player_role == "Blocker" and is_instance_valid(ball_node) and is_instance_valid(ball_node.current_possessor) and ball_node.current_possessor.team_id == self.team_id ): # If IDLE but teammate has ball, Blocker re-evaluates block target
            current_block_target_node = null


func reset_state():
    # print_debug("Reset state for %s" % player_name)
    is_knocked_down = false; knockdown_timer = 0.0
    has_ball = false; can_pass_timer = 0.0; can_kick_timer = 0.0
    can_aggressive_tackle_timer = 0.0; blocker_hold_ball_timer = 0.0
    current_stamina = max_stamina
    if collision_shape and collision_shape.disabled: collision_shape.set_deferred("disabled", false)
    velocity = Vector2.ZERO; current_block_target_node = null
    set_state(PlayerState.IDLE) # Initial state after reset
