# ball.gd - Full Version (May 14th) - Fixes visual scale, ternary warnings, includes all features
extends RigidBody2D

# --- Export Variables ---
@export var pass_speed: float = 650.0      # Base speed, modified by Throwing
@export var max_pass_range: float = 450.0  # Only used for PASSES now
@export var bounce_impulse_strength : float = 100.0
@export var follow_offset := Vector2(0, -25)

# Field boundaries (Adjust if needed)
@export var field_half_width : float = 960.0
@export var field_half_height : float = 540.0
@export var field_margin : float = 15.0

# --- Constants for Stat-Based Passing ---
const BASE_PASS_SPEED: float = 400.0
const MAX_PASS_SPEED: float = 900.0
const MAX_THROWING_STAT: int = 40
const BASE_INACCURACY_ANGLE: float = PI / 6.0 # ~30 deg
const MIN_INACCURACY_ANGLE: float = PI / 64.0 # ~3 deg

# --- Constants for Stat-Based Kicking ---
const BASE_KICK_SPEED: float = 600.0
const MAX_KICK_SPEED: float = 1100.0
const MAX_KICKING_STAT: int = 40
const BASE_KICK_INACCURACY_ANGLE: float = PI / 4.0 # 45 deg
const MIN_KICK_INACCURACY_ANGLE: float = PI / 16.0 # ~11 deg

# --- Constants for Stat-Based Catching ---
const MAX_CATCHING_STAT: int = 40
const BASE_CATCH_CHANCE: float = 0.60   # 60% base chance
const MAX_CATCH_CHANCE: float = 0.98   # ~98% max chance

# --- Constant for Pass/Kick Air Time ---
const MIN_AIR_TIME_BUFFER: float = 0.2 # Minimum "in air" uncatchable time (tune this)

# --- Constants for Visual Effect ---
const AIR_SCALE_MULTIPLIER: float = 1.15 # How much bigger ball gets "in air"
const MODULATE_GROUND: Color = Color(1.0, 1.0, 1.0, 1.0)
const MODULATE_AIR: Color = Color(0.9, 0.9, 0.9, 1.0) # Slightly desaturated/different tint
const SHADOW_OFFSET_GROUND: Vector2 = Vector2(3, 5)
const SHADOW_OFFSET_AIR: Vector2 = Vector2(8, 12)
const SHADOW_SCALE_GROUND: Vector2 = Vector2(1.0, 1.0) # Relative to ShadowSprite's initial scale
const SHADOW_SCALE_AIR: Vector2 = Vector2(1.2, 1.2)   # Shadow gets bigger/diffused
const SHADOW_ALPHA_GROUND: float = 0.3
const SHADOW_ALPHA_AIR: float = 0.5

# --- Gameplay Constants ---
const BALL_STOP_THRESHOLD_SQ: float = 5.0 * 5.0          # Velocity squared, below which ball is considered stopped
const BALL_ANGULAR_VELOCITY_STOP_THRESHOLD: float = 0.1 # Angular velocity, below which ball is considered stopped rotationally
const CATCH_CHANCE_TARGET_MATCH_BONUS: float = 0.10
const CATCH_CHANCE_INTERCEPTION_PENALTY: float = -0.10 # Note: This is negative
const FAILED_CATCH_BOUNCE_VELOCITY_MULTIPLIER: float = -0.3
const FAILED_CATCH_BOUNCE_RANDOM_X_MIN: float = -30.0
const FAILED_CATCH_BOUNCE_RANDOM_X_MAX: float = 30.0
const FAILED_CATCH_BOUNCE_RANDOM_Y_MIN: float = -30.0
const FAILED_CATCH_BOUNCE_RANDOM_Y_MAX: float = -100.0 # More downward
const SET_LOOSE_BOBBLE_TIMER_FACTOR: float = 0.75     # Multiplier for MIN_AIR_TIME_BUFFER on set_loose
const SET_LOOSE_NO_BOUNCE_THRESHOLD_SQ: float = 0.01 * 0.01 # If bounce_dir_velocity is very small
const PASS_KICK_MIN_DISTANCE_THRESHOLD: float = 1.0   # Min distance for a pass/kick to not be considered too close
const PASS_KICK_RECEPTION_TIMER_SPEED_FACTOR: float = 1.05 # Factor for speed component of air time
const PASS_KICK_RECEPTION_TIMER_FLAT_BONUS: float = 0.05   # Flat time bonus to air time
const PASS_KICK_FAIL_MIN_AIR_TIME_BUFFER: float = 0.1    # Min air time if pass/kick speed is somehow zero

# --- Internal State ---
var current_possessor: Node2D = null
var pass_reception_timer: float = 0.0
var _is_arriving_from_pass: bool = false
var intended_receiver: Node = null
var initial_ball_scale: Vector2 = Vector2(1.0, 1.0) # Store editor scale for ball_sprite
var initial_shadow_scale: Vector2 = Vector2(1.0, 1.0) # Store editor scale for shadow_sprite

# --- Node References ---
@onready var pickup_area: Area2D = $PickupArea
@onready var ball_sprite: Sprite2D = $Sprite2D # Main ball visual
@onready var shadow_sprite: Sprite2D = $ShadowSprite # Shadow visual

# --- Initialization ---
func _ready():
    freeze = false
    if pickup_area != null:
        pickup_area.monitoring = true
        var signal_name = "body_entered"
        var callable_to_check = Callable(self, "_on_pickup_area_body_entered")
        var connections = pickup_area.get_signal_connection_list(signal_name)
        var already_connected = false
        for connection in connections:
            if connection.callable.get_method() == callable_to_check.get_method():
                already_connected = true; break
        if not already_connected:
            var error_code = pickup_area.connect(signal_name, callable_to_check)
            if error_code != OK: printerr("Ball: Failed to connect pickup area signal! Error: %s" % error_code)
        ## else: print_debug("Ball: PickupArea signal already connected.") 
    else: printerr("Ball Error: Cannot find child node named 'PickupArea'!")

    # Store initial scales set in the editor
    if is_instance_valid(ball_sprite):
        initial_ball_scale = ball_sprite.scale
    else:
        printerr("Ball Error: ball_sprite node not found in _ready! Ensure path is correct.")
    
    if is_instance_valid(shadow_sprite):
        initial_shadow_scale = shadow_sprite.scale
    else:
        printerr("Ball Error: shadow_sprite node not found in _ready! Ensure path is correct.")


# --- Physics Update ---
func _physics_process(delta):
    # --- Visual Cue for "In Air" ---
    if is_instance_valid(ball_sprite) and is_instance_valid(shadow_sprite): # Safety check
        if pass_reception_timer > 0.0: # Ball is "in the air"
            ball_sprite.scale = initial_ball_scale * AIR_SCALE_MULTIPLIER # Ball gets slightly bigger
            ball_sprite.modulate = MODULATE_AIR
            
            shadow_sprite.visible = true # Make shadow visible
            shadow_sprite.position = SHADOW_OFFSET_AIR
            shadow_sprite.scale = initial_shadow_scale * SHADOW_SCALE_AIR # Adjust SHADOW_SCALE_AIR constant if needed
            shadow_sprite.modulate.a = SHADOW_ALPHA_AIR
        else: # Ball is "on the ground"
            ball_sprite.scale = initial_ball_scale # Ball returns to normal editor-set scale
            ball_sprite.modulate = MODULATE_GROUND
            
            shadow_sprite.visible = false # Hide shadow when on the ground
            # Optionally reset other shadow properties if you like, though visibility is key
            # shadow_sprite.position = SHADOW_OFFSET_GROUND
            # shadow_sprite.scale = initial_shadow_scale
            # shadow_sprite.modulate.a = SHADOW_ALPHA_GROUND
            
        shadow_sprite.global_rotation = 0 # Force shadow to have no world rotation
    
    # Pass/Kick Reception Timer
    if pass_reception_timer > 0.0:
        pass_reception_timer -= delta
        if pass_reception_timer <= 0.0:
            _is_arriving_from_pass = true
            if pickup_area != null and not pickup_area.monitoring:
                pickup_area.set_deferred("monitoring", true)
                ## print("BALL SCRIPT: Pass/Kick reception timer ended - Monitoring ON (Deferred)")

    # Visual Cue for "In Air"
    if is_instance_valid(ball_sprite) and is_instance_valid(shadow_sprite):
        if pass_reception_timer > 0.0: # Ball is "in the air"
            ball_sprite.scale = initial_ball_scale * AIR_SCALE_MULTIPLIER
            ball_sprite.modulate = MODULATE_AIR
            shadow_sprite.position = SHADOW_OFFSET_AIR
            shadow_sprite.scale = initial_shadow_scale * SHADOW_SCALE_AIR # Scale shadow relative to its initial
            shadow_sprite.modulate.a = SHADOW_ALPHA_AIR
        else: # Ball is "on the ground"
            ball_sprite.scale = initial_ball_scale
            ball_sprite.modulate = MODULATE_GROUND
            shadow_sprite.position = SHADOW_OFFSET_GROUND
            shadow_sprite.scale = initial_shadow_scale # Revert shadow to its initial scale
            shadow_sprite.modulate.a = SHADOW_ALPHA_GROUND

    # Ball Possession Logic
    if current_possessor != null: # Ball Held
        if is_instance_valid(current_possessor):
            if not freeze: set_deferred("freeze", true); linear_velocity=Vector2.ZERO; angular_velocity=0.0
            if pickup_area != null and pickup_area.monitoring: pickup_area.set_deferred("monitoring", false)
            global_position = current_possessor.global_position + follow_offset
        else: 
            print("BALL SCRIPT: Possessor invalid, setting loose.") # Keep this critical message
            set_loose()
    else: # Ball is LOOSE
        if freeze: set_deferred("freeze", false)
        if pickup_area != null and not pickup_area.monitoring and pass_reception_timer <= 0.0:
            pickup_area.set_deferred("monitoring", true)
            ## print_debug("BALL PHYSICS (Loose & Timer Done): Forcing monitoring ON.")
        
        if not freeze and pass_reception_timer <= 0.0 and \
           linear_velocity.length_squared() < BALL_STOP_THRESHOLD_SQ and abs(angular_velocity) < BALL_ANGULAR_VELOCITY_STOP_THRESHOLD:
            linear_velocity = Vector2.ZERO; angular_velocity = 0.0
            if pickup_area != null and not pickup_area.monitoring:
                 pickup_area.set_deferred("monitoring", true)
                ## print("BALL SCRIPT: Ball stopped/settled - Monitoring FORCED ON (Safety Check - RARE)")
            ## else:
                ## print("BALL SCRIPT: Ball stopped/settled.")


# --- Signal Handler for Pickup ---
func _on_pickup_area_body_entered(body: Node):
    if pass_reception_timer > 0.0: return
    if not body or not pickup_area or not body.is_in_group("players"):
        if _is_arriving_from_pass: _is_arriving_from_pass = false # Reset flag if non-player "consumes" it
        return
    
    ## print("--- Pickup Area Entered by: ", body.name, " ---") 
    ## print("State at entry: Possessor=%s, Frozen=%s, Monitoring=%s, ArrivingPass=%s" % [current_possessor, freeze, str(pickup_area.monitoring), _is_arriving_from_pass])

    var is_player = true # Assumed since it's in "players" group, but can be checked more robustly if needed
    var is_knocked = body.get_is_knocked_down() if body.has_method("get_is_knocked_down") else true # Default to true if method missing
    var can_attempt_pickup = (current_possessor == null and not freeze and pickup_area.monitoring and not is_knocked)

    if not can_attempt_pickup:
        if _is_arriving_from_pass: _is_arriving_from_pass = false # Reset flag if pickup is not possible
        return

    var pickup_allowed = false
    if _is_arriving_from_pass:
        ## print_debug("Attempting pass/kick reception for %s" % body.name) 
        _is_arriving_from_pass = false # Consume the flag
        var catcher_catching_stat : int = 1
        if body.has_method("get"): var cv=body.get("catching"); if typeof(cv)==TYPE_INT: catcher_catching_stat=clamp(cv,1,MAX_CATCHING_STAT)
        
        var norm_catch = float(catcher_catching_stat - 1) / float(MAX_CATCHING_STAT - 1) if MAX_CATCHING_STAT > 1 else float(1.0)
        var catch_chance = lerp(BASE_CATCH_CHANCE, MAX_CATCH_CHANCE, norm_catch)
        
        var adjustment = 0.0
        if is_instance_valid(intended_receiver):
            if body == intended_receiver: adjustment = CATCH_CHANCE_TARGET_MATCH_BONUS ## print_debug("  - Target Match! Applying catch bonus.")
            else: adjustment = CATCH_CHANCE_INTERCEPTION_PENALTY ## print_debug("  - Interception attempt! Applying catch penalty.")
            catch_chance = clamp(catch_chance + adjustment, 0.0, 1.0)
            
        ## print_debug("  - Catching: %d -> Norm: %.2f -> Final Chance: %.2f" % [catcher_catching_stat, norm_catch, catch_chance]) 
        if randf() < catch_chance: 
            # print_debug("Catch Successful by %s!" % body.name) # Keep for now
            pickup_allowed = true
        else: 
            # print_debug("Catch FAILED! Dropped by %s." % body.name) # Keep for now
            var bounce_random_x = randf_range(FAILED_CATCH_BOUNCE_RANDOM_X_MIN, FAILED_CATCH_BOUNCE_RANDOM_X_MAX)
            var bounce_random_y = randf_range(FAILED_CATCH_BOUNCE_RANDOM_Y_MIN, FAILED_CATCH_BOUNCE_RANDOM_Y_MAX)
            var bounce_vec = body.velocity * FAILED_CATCH_BOUNCE_VELOCITY_MULTIPLIER + Vector2(bounce_random_x, bounce_random_y)
            call_deferred("set_loose", bounce_vec)
            pickup_allowed=false
            return # Explicit return after failed catch
        intended_receiver = null # Clear after successful or failed attempt if it was a pass
    else: # Loose ball pickup attempt
        ## print_debug("Attempting loose ball pickup for %s" % body.name) 
        pickup_allowed = true
        intended_receiver = null # Should be null anyway for loose balls

    if pickup_allowed and current_possessor == null and not freeze and pickup_area.monitoring and is_player and not is_knocked:
        ## print_debug("BALL AREA DEBUG: Pickup conditions MET for %s" % body.name) 
        current_possessor = body
        if body.has_method("pickup_ball"): body.pickup_ball()
        else: printerr("Ball Error: Player %s missing pickup_ball() method!" % body.name)
        
        pickup_area.set_deferred("monitoring", false)
        # print("BALL SCRIPT: Picked up by %s." % body.name) # Keep this key event
        set_deferred("freeze", true); linear_velocity = Vector2.ZERO; angular_velocity = 0.0
        global_position = current_possessor.global_position + follow_offset
    ## else: # For debugging failed pickups if needed later
        ## if pickup_allowed: print("Pickup conditions FAILED (Final check)...")


# --- Function to Make Ball Loose ---
func set_loose(bounce_dir_velocity: Vector2 = Vector2.ZERO):
    if is_instance_valid(current_possessor):
        if current_possessor.has_method("lose_ball"): current_possessor.lose_ball()
    current_possessor = null
    intended_receiver = null # Always clear intended receiver when ball becomes loose
    set_deferred("freeze", false)
    pass_reception_timer = MIN_AIR_TIME_BUFFER * SET_LOOSE_BOBBLE_TIMER_FACTOR 
    _is_arriving_from_pass = true # Treat a fumbled loose ball like a short "pass" for pickup logic
    ## print_debug("BALL SCRIPT: set_loose() - Initiating brief 'bobble' (%.2f sec)" % pass_reception_timer) 
    
    if pickup_area != null: # Ensure pickup area can be re-enabled
        if pickup_area.monitoring: pickup_area.set_deferred("monitoring", false) # Disable briefly if it was on
        # It will be re-enabled once pass_reception_timer (bobble) ends or ball stops.

    var impulse_dir = Vector2.RIGHT # Default impulse if no bounce_dir_velocity
    if bounce_dir_velocity.length_squared() > SET_LOOSE_NO_BOUNCE_THRESHOLD_SQ: 
        impulse_dir = bounce_dir_velocity.normalized() * -1.0 # Bounce away from impact
    else: 
        impulse_dir = Vector2(randf_range(-1.0,1.0), randf_range(-1.0,1.0)).normalized()
        if impulse_dir == Vector2.ZERO: impulse_dir = Vector2.RIGHT # Ensure non-zero
    apply_central_impulse(impulse_dir * bounce_impulse_strength)


# --- Function to Initiate a Pass ---
func initiate_pass(passer: Node, target_teammate: Node, target_destination_pos: Vector2): # Added target_destination_pos
    # Basic validity checks
    if not is_instance_valid(passer) or not passer.has_method("get_player_name"):
        printerr("Ball Error: Initiate pass called with invalid passer node!")
        return
    if not is_instance_valid(current_possessor) or current_possessor != passer:
        printerr("Ball Error: Initiate pass called by %s but %s has the ball (or ball is loose)!" % [passer.get_player_name(), str(current_possessor.get_player_name() if is_instance_valid(current_possessor) else "no one")])
        return
    if not is_instance_valid(target_teammate): 
        printerr("Ball Error: Initiate pass called with invalid target_teammate node!")
        return

    # Store the intended receiver (the node)
    self.intended_receiver = target_teammate
    # The target_destination is now the passed-in anticipated position
    var target_destination = target_destination_pos 

    # print("BALL SCRIPT: %s initiates pass towards %s (Node: %s, Aim Pos: %s)" % [current_possessor.name, intended_receiver.player_name, intended_receiver.name, str(target_destination.round())]) # Keep
    var start_pos = global_position

    # Get Passer's Throwing Stat
    var passer_throwing_stat : int = 1
    if passer.has_method("get"): 
        var throwing_val = passer.get("throwing")
        if typeof(throwing_val) == TYPE_INT: 
            passer_throwing_stat = clamp(throwing_val, 1, MAX_THROWING_STAT)

    # Tell player script it lost the ball
    if current_possessor.has_method("lose_ball"): 
        current_possessor.lose_ball()
    else: 
        printerr("Ball Error: Player %s missing lose_ball() method!" % current_possessor.name)

    current_possessor = null
    set_deferred("freeze", false)
    pass_reception_timer = 0.0 # Reset timer

    # Turn monitoring OFF immediately
    if pickup_area != null:
        pickup_area.monitoring = false
        ## print_debug("BALL SCRIPT: initiate_pass() - Monitoring forced OFF")
    
    # Calculate final target position (Clamped to field, uses max_pass_range)
    var direction_to_target_vector = (target_destination - start_pos)
    var max_range_sq = max_pass_range * max_pass_range
    var final_target_pos : Vector2
    if direction_to_target_vector.length_squared() > max_range_sq:
        final_target_pos = start_pos + direction_to_target_vector.normalized() * max_pass_range
    else:
        final_target_pos = target_destination
    final_target_pos.x = clamp(final_target_pos.x, -field_half_width + field_margin, field_half_width - field_margin)
    final_target_pos.y = clamp(final_target_pos.y, -field_half_height + field_margin, field_half_height - field_margin)
    ## print("BALL SCRIPT: Passing towards (clamped): %s" % str(final_target_pos.round())) 

    # Calculate Vector and Distance
    var vector_to_target = final_target_pos - start_pos
    var distance = vector_to_target.length()

    # Apply Velocity (Stat-Based)
    var pass_successful = false # Track if velocity applied
    if distance > PASS_KICK_MIN_DISTANCE_THRESHOLD: 
        # --- MODIFIED TERNARY TO IF/ELSE for norm_throw ---
        var norm_throw: float
        if MAX_THROWING_STAT > 1:
            norm_throw = float(passer_throwing_stat - 1) / float(MAX_THROWING_STAT - 1)
        else:
            norm_throw = 1.0
        # --- END MODIFICATION ---
        
        var effective_pass_speed = lerp(BASE_PASS_SPEED, MAX_PASS_SPEED, norm_throw)
        ##print_debug("  - Throwing: %d -> Norm: %.2f -> Speed: %.1f" % [passer_throwing_stat, normalized_throwing, effective_pass_speed])
        
        var max_deviation_angle = lerp(BASE_INACCURACY_ANGLE, MIN_INACCURACY_ANGLE, norm_throw)
        var random_deviation = randf_range(-max_deviation_angle, max_deviation_angle)
        ##print_debug("  - Max Pass Dev: %.3f rad -> Actual Deviation: %.3f rad" % [max_deviation_angle, random_deviation])
        
        var actual_dir = vector_to_target.normalized().rotated(random_deviation)
        linear_velocity = actual_dir * effective_pass_speed
        pass_successful = true # Mark as successful

        # Calculate & Start Reception Timer (Using effective speed + buffer)
        if effective_pass_speed > 0:
            pass_reception_timer = MIN_AIR_TIME_BUFFER + ((distance / effective_pass_speed) * PASS_KICK_RECEPTION_TIMER_SPEED_FACTOR + PASS_KICK_RECEPTION_TIMER_FLAT_BONUS)
            # print("BALL SCRIPT: initiate_pass() - Reception timer: %.2f sec" % pass_reception_timer) # Keep
        else:
            pass_reception_timer = MIN_AIR_TIME_BUFFER + PASS_KICK_FAIL_MIN_AIR_TIME_BUFFER 
            printerr("Ball Error: Effective pass speed is zero!")
    else:
        # Target too close, drop ball
        # print("BALL SCRIPT: Pass target too close after clamping, dropping ball.") # Keep
        linear_velocity = Vector2.ZERO
        if pickup_area != null: 
            pickup_area.monitoring = true # Turn monitoring ON immediately if pass fails right away
            # print("BALL SCRIPT: Pass failed (too close) - PickupArea monitoring ON") # Keep
        pass_reception_timer = 0.0 # No air time
        intended_receiver = null # Clear receiver if pass fails instantly

    # Reset intended_receiver DEFERRED *if* pass was successful (i.e., had some air time)
    if pass_successful:
        call_deferred("_clear_intended_receiver")

# --- Function to Initiate a Kick ---
func initiate_kick(kicker: Node, target_destination: Vector2):
    # Basic validity checks
    if not is_instance_valid(kicker) or not kicker.has_method("get_player_name"): 
        printerr("Ball Error: Initiate kick called with invalid kicker node!")
        return
    if not is_instance_valid(current_possessor) or current_possessor != kicker: 
        printerr("Ball Error: Initiate kick called by %s but %s has the ball (or ball is loose)!" % [kicker.get_player_name(), str(current_possessor.get_player_name() if is_instance_valid(current_possessor) else "no one")])
        return

    print("BALL SCRIPT: %s initiates KICK towards %s" % [current_possessor.name, str(target_destination.round())])
    var start_pos = global_position

    # Get Kicker's Kicking Stat
    var kicker_kicking_stat : int = 1
    if kicker.has_method("get"): 
        var kicking_val = kicker.get("kicking")
        if typeof(kicking_val) == TYPE_INT: 
            kicker_kicking_stat = clamp(kicking_val, 1, MAX_KICKING_STAT)
    
    # Tell player script it lost the ball
    if current_possessor.has_method("lose_ball"): 
        current_possessor.lose_ball()
    else: 
        printerr("Ball Error: Player %s missing lose_ball() method!" % current_possessor.name)

    current_possessor = null
    set_deferred("freeze", false)
    pass_reception_timer = 0.0 # Reset timer
    intended_receiver = null # Kicks don't have an intended receiver for catch bonus logic

    # Turn monitoring OFF immediately
    if pickup_area != null:
        pickup_area.monitoring = false
        ## print_debug("BALL SCRIPT: initiate_kick() - Monitoring forced OFF") 
    
    # Kicks generally ignore max_pass_range and aim directly for target (still clamp to field)
    var final_target_pos = target_destination
    final_target_pos.x = clamp(final_target_pos.x, -field_half_width + field_margin, field_half_width - field_margin)
    final_target_pos.y = clamp(final_target_pos.y, -field_half_height + field_margin, field_half_height - field_margin)
    ## print("BALL SCRIPT: Kicking towards (clamped): %s" % str(final_target_pos.round())) 

    # Calculate Vector and Distance
    var vector_to_target = final_target_pos - start_pos
    var distance = vector_to_target.length()

    # Apply Velocity (Stat-Based for Kicking)
    var kick_successful = false # Track if velocity applied
    if distance > PASS_KICK_MIN_DISTANCE_THRESHOLD:
        # --- MODIFIED TERNARY TO IF/ELSE for norm_kick ---
        var norm_kick: float
        if MAX_KICKING_STAT > 1:
            norm_kick = float(kicker_kicking_stat - 1) / float(MAX_KICKING_STAT - 1)
        else:
            norm_kick = 1.0
        # --- END MODIFICATION ---
        
        var effective_kick_speed = lerp(BASE_KICK_SPEED, MAX_KICK_SPEED, norm_kick)
        ##print_debug("  - Kicking: %d -> Norm: %.2f -> Speed: %.1f" % [kicker_kicking_stat, normalized_kicking, effective_kick_speed])
        
        var max_deviation_angle = lerp(BASE_KICK_INACCURACY_ANGLE, MIN_KICK_INACCURACY_ANGLE, norm_kick)
        var random_deviation = randf_range(-max_deviation_angle, max_deviation_angle)
        ##print_debug("  - Max Kick Dev: %.3f rad -> Actual Dev: %.3f rad" % [max_deviation_angle, random_deviation])
        
        var actual_dir = vector_to_target.normalized().rotated(random_deviation)
        linear_velocity = actual_dir * effective_kick_speed
        kick_successful = true

        # Calculate & Start Reception Timer (Using effective KICK speed + buffer)
        if effective_kick_speed > 0:
            pass_reception_timer = MIN_AIR_TIME_BUFFER + ((distance / effective_kick_speed) * PASS_KICK_RECEPTION_TIMER_SPEED_FACTOR + PASS_KICK_RECEPTION_TIMER_FLAT_BONUS)
            # print("BALL SCRIPT: initiate_kick() - Reception timer: %.2f sec" % pass_reception_timer) # Keep
        else:
            pass_reception_timer = MIN_AIR_TIME_BUFFER + PASS_KICK_FAIL_MIN_AIR_TIME_BUFFER 
            printerr("Ball Error: Effective kick speed is zero!")
    else:
        # Target too close, just drop it
        # print("BALL SCRIPT: Kick target too close after clamping, dropping ball.") # Keep
        linear_velocity = Vector2.ZERO
        if pickup_area != null: 
            pickup_area.monitoring = true
            # print("BALL SCRIPT: Kick failed (too close) - PickupArea monitoring ON") # Keep
        pass_reception_timer = 0.0
    
    # Reset intended_receiver DEFERRED (already null for kicks, but good practice for consistency)
    if kick_successful:
        call_deferred("_clear_intended_receiver") # This will clear the (already null) intended_receiver
# --- Helper Function to Clear Receiver ---
func _clear_intended_receiver():
    intended_receiver = null
    ##print_debug("Ball: Intended receiver cleared.")
