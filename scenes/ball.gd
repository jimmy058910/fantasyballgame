# ball.gd - Adjusted Pass/Kick Reception Timer, includes Kicking, Catching Stat, Target Locking Lite, Fixes
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

# --- Internal State ---
var current_possessor: Node2D = null
var pass_reception_timer: float = 0.0 # Used for both pass and kick reception
var _is_arriving_from_pass: bool = false # Flag for catch check (applies to kicks too now)
var intended_receiver: Node = null # Stores the target of the last pass/kick

# --- Node References ---
@onready var pickup_area: Area2D = $PickupArea

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
            else: print_debug("Ball: PickupArea signal connected via script.")
        else: print_debug("Ball: PickupArea signal already connected.")
    else: printerr("Ball Error: Cannot find child node named 'PickupArea'!")


# --- Physics Update ---
func _physics_process(delta):
    # --- Pass/Kick Reception Timer ---
    if pass_reception_timer > 0.0:
        pass_reception_timer -= delta
        # If timer just ran out THIS FRAME
        if pass_reception_timer <= 0.0:
            _is_arriving_from_pass = true # Set flag
            if pickup_area != null and not pickup_area.monitoring:
                pickup_area.set_deferred("monitoring", true)
                print("BALL SCRIPT: Pass/Kick reception timer ended - Monitoring ON (Deferred)")

    if current_possessor != null: # Ball Held
        if is_instance_valid(current_possessor):
            if not freeze: set_deferred("freeze", true); linear_velocity=Vector2.ZERO; angular_velocity=0.0
            if pickup_area != null and pickup_area.monitoring: pickup_area.set_deferred("monitoring", false)
            global_position = current_possessor.global_position + follow_offset
        else: print("BALL SCRIPT: Possessor invalid, setting loose."); set_loose()
    else: # Ball Loose
        if freeze: set_deferred("freeze", false)
        var stop_threshold_sq = 5.0*5.0
        if not freeze and pass_reception_timer <= 0.0 and \
           linear_velocity.length_squared() < stop_threshold_sq and abs(angular_velocity) < 0.1:
            linear_velocity = Vector2.ZERO; angular_velocity = 0.0
            if pickup_area != null and not pickup_area.monitoring:
                pickup_area.set_deferred("monitoring", true)
                print("BALL SCRIPT: Ball stopped/settled - Monitoring ON (Safety Check)")


# --- Signal Handler for Pickup ---
func _on_pickup_area_body_entered(body: Node):
    # Ignore if ball is "in the air" (reception timer active)
    if pass_reception_timer > 0.0:
        return

    # Basic validity checks
    if not body or not pickup_area or not body.is_in_group("players"):
        if _is_arriving_from_pass: _is_arriving_from_pass = false
        return

    print("--- Pickup Area Entered by: ", body.name, " ---")
    print("State at entry: Possessor=%s, Frozen=%s, Monitoring=%s, ArrivingPass=%s" % [current_possessor, freeze, str(pickup_area.monitoring), _is_arriving_from_pass])

    var is_player = true
    var is_knocked = body.get_is_knocked_down() if body.has_method("get_is_knocked_down") else true

    var can_attempt_pickup = (current_possessor == null and not freeze and pickup_area.monitoring and not is_knocked)

    if not can_attempt_pickup:
        # ... (Log failure reasons) ...
        if _is_arriving_from_pass: _is_arriving_from_pass = false
        return

    var pickup_allowed = false
    if _is_arriving_from_pass:
        # --- This is a PASS/KICK RECEPTION attempt ---
        print_debug("Attempting pass/kick reception for %s" % body.name)
        _is_arriving_from_pass = false

        # Get catching stat
        var catcher_catching_stat : int = 1
        if body.has_method("get"): var cv=body.get("catching"); if typeof(cv)==TYPE_INT: catcher_catching_stat=clamp(cv,1,MAX_CATCHING_STAT)
        var norm_catch = float(catcher_catching_stat - 1) / float(MAX_CATCHING_STAT - 1) if MAX_CATCHING_STAT > 1 else 1.0
        var catch_chance = lerp(BASE_CATCH_CHANCE, MAX_CATCH_CHANCE, norm_catch)

        # Adjust chance based on intended receiver
        var adjustment = 0.0
        if is_instance_valid(intended_receiver):
            if body == intended_receiver:
                adjustment = 0.10 # Keep bonus at 10% for now (tune later)
                print_debug("  - Target Match! Applying catch bonus.")
            else:
                adjustment = -0.10 # Keep penalty at 10% for now (tune later)
                print_debug("  - Interception attempt! Applying catch penalty.")
            catch_chance = clamp(catch_chance + adjustment, 0.0, 1.0)

        print_debug("  - Catching: %d -> Norm: %.2f -> Final Chance: %.2f" % [catcher_catching_stat, norm_catch, catch_chance])

        if randf() < catch_chance: # Catch roll
            print("Catch Successful!"); pickup_allowed = true
        else: # Catch Fail
            print("Catch FAILED! Dropped by %s." % body.name); var bv = body.velocity * -0.3 + Vector2(randf_range(-30,30), randf_range(-30,-100)); set_loose(bv); pickup_allowed = false; print("------------------------------------"); return

        intended_receiver = null # Clear receiver after attempt

    else: # Loose ball pickup
        print_debug("Attempting loose ball pickup for %s" % body.name)
        pickup_allowed = true
        intended_receiver = null

    # --- Proceed with actual pickup IF allowed and STILL possible ---
    if pickup_allowed and current_possessor == null and not freeze and pickup_area.monitoring and is_player and not is_knocked:
        print("BALL AREA DEBUG: Pickup conditions MET for ", body.name)
        current_possessor = body
        if body.has_method("pickup_ball"): body.pickup_ball()
        else: printerr("Ball Error: Player %s missing pickup_ball() method!" % body.name)
        pickup_area.set_deferred("monitoring", false)
        print("BALL SCRIPT: Pickup successful - Queued monitoring OFF (Deferred)")
        set_deferred("freeze", true)
        linear_velocity = Vector2.ZERO; angular_velocity = 0.0
        global_position = current_possessor.global_position + follow_offset
        print("BALL SCRIPT: Picked up by ", body.name, ". Possessor is now: ", current_possessor)
    else:
        if pickup_allowed: print("Pickup conditions FAILED (Final check). Possessor=%s, Frozen=%s, Monitoring=%s, is_player=%s, not_knocked=%s" % [current_possessor, freeze, pickup_area.monitoring, is_player, not is_knocked]); print("------------------------------------")


# --- Function to Make Ball Loose ---
func set_loose(bounce_dir_velocity: Vector2 = Vector2.ZERO):
    var print_prefix = "BALL SCRIPT: set_loose(): "
    if is_instance_valid(current_possessor):
        print(print_prefix, current_possessor.name, " lost the ball! Telling player.")
        if current_possessor.has_method("lose_ball"): current_possessor.lose_ball()
        else: printerr("...") # Error handling
    current_possessor = null
    intended_receiver = null # Clear intended receiver
    set_deferred("freeze", false)
    pass_reception_timer = 0.0 # Reset timer
    if pickup_area != null:
        pickup_area.set_deferred("monitoring", true)
        print("BALL SCRIPT: set_loose() - Setting monitoring ON (Deferred)")
    var impulse_dir = Vector2.RIGHT
    if bounce_dir_velocity.length_squared() > 1.0: impulse_dir = bounce_dir_velocity.normalized() * -1.0
    else: impulse_dir = Vector2(randf_range(-1,1), randf_range(-1,1)).normalized(); if impulse_dir == Vector2.ZERO: impulse_dir = Vector2.RIGHT
    apply_central_impulse(impulse_dir * bounce_impulse_strength)
    print(print_prefix, "Applied bounce impulse in direction: ", impulse_dir)


# --- Function to Initiate a Pass ---
func initiate_pass(passer: Node, target_teammate: Node):
    if not is_instance_valid(passer) or not passer.has_method("get_player_name"): printerr("Invalid passer!"); return
    if not is_instance_valid(current_possessor) or current_possessor != passer: printerr("Passer mismatch!"); return
    if not is_instance_valid(target_teammate): printerr("Invalid target_teammate!"); return

    self.intended_receiver = target_teammate
    var target_destination = intended_receiver.global_position
    print("BALL SCRIPT: %s initiates pass towards %s (%s)" % [current_possessor.name, intended_receiver.player_name, str(target_destination.round())])
    var start_pos = global_position
    var passer_throwing_stat: int = 1; if passer.has_method("get"): var tv=passer.get("throwing"); if typeof(tv)==TYPE_INT: passer_throwing_stat=clamp(tv,1,MAX_THROWING_STAT)
    if current_possessor.has_method("lose_ball"): current_possessor.lose_ball()
    current_possessor = null; set_deferred("freeze", false); pass_reception_timer = 0.0
    if pickup_area != null: pickup_area.monitoring = false; print("BALL SCRIPT: initiate_pass() - Monitoring forced OFF")
    var dir = (target_destination - start_pos); var max_r_sq = max_pass_range*max_pass_range
    var final_target_pos: Vector2 = start_pos + dir.normalized()*max_pass_range if dir.length_squared() > max_r_sq else target_destination
    final_target_pos.x = clamp(final_target_pos.x, -field_half_width+field_margin, field_half_width-field_margin)
    final_target_pos.y = clamp(final_target_pos.y, -field_half_height+field_margin, field_half_height-field_margin)
    print("BALL SCRIPT: Passing towards (clamped): %s" % str(final_target_pos))
    var vector_to_target = final_target_pos - start_pos; var distance = vector_to_target.length()
    var pass_successful = false
    if distance > 1.0:
        var norm_throw = float(passer_throwing_stat-1)/float(MAX_THROWING_STAT-1) if MAX_THROWING_STAT>1 else 1.0
        var eff_speed = lerp(BASE_PASS_SPEED, MAX_PASS_SPEED, norm_throw)
        var max_dev = lerp(BASE_INACCURACY_ANGLE, MIN_INACCURACY_ANGLE, norm_throw)
        var rand_dev = randf_range(-max_dev, max_dev)
        var actual_dir = vector_to_target.normalized().rotated(rand_dev)
        linear_velocity = actual_dir * eff_speed
        pass_successful = true
        if eff_speed > 0:
            # --- UPDATED TIMER CALCULATION ---
            pass_reception_timer = (distance / eff_speed) * 1.05 + 0.05
            # ---
            print("BALL SCRIPT: initiate_pass() - Pass reception timer started: %.2f sec" % pass_reception_timer)
        else: pass_reception_timer = 0.1; printerr("Pass speed zero!")
    else:
        print("BALL SCRIPT: Pass target too close..."); linear_velocity = Vector2.ZERO
        if pickup_area != null: pickup_area.monitoring = true; print("BALL SCRIPT: Pass failed - Monitor ON")
        pass_reception_timer = 0.0; intended_receiver = null

    if pass_successful: call_deferred("_clear_intended_receiver")


# --- Function to Initiate a Kick ---
func initiate_kick(kicker: Node, target_destination: Vector2):
    if not is_instance_valid(kicker) or not kicker.has_method("get_player_name"): printerr("Invalid kicker!"); return
    if not is_instance_valid(current_possessor) or current_possessor != kicker: printerr("Kicker mismatch!"); return
    print("BALL SCRIPT: %s initiates KICK towards %s" % [current_possessor.name, str(target_destination)])
    var start_pos = global_position
    var kicker_kicking_stat: int = 1; if kicker.has_method("get"): var kv=kicker.get("kicking"); if typeof(kv)==TYPE_INT: kicker_kicking_stat=clamp(kv,1,MAX_KICKING_STAT)
    if current_possessor.has_method("lose_ball"): current_possessor.lose_ball()
    current_possessor = null; set_deferred("freeze", false); pass_reception_timer = 0.0
    intended_receiver = null # Kicks don't have an intended receiver
    if pickup_area != null: pickup_area.monitoring = false; print("BALL SCRIPT: initiate_kick() - Monitoring forced OFF")
    var final_target_pos = target_destination
    final_target_pos.x = clamp(final_target_pos.x, -field_half_width+field_margin, field_half_width-field_margin)
    final_target_pos.y = clamp(final_target_pos.y, -field_half_height+field_margin, field_half_height-field_margin)
    print("BALL SCRIPT: Kicking towards (clamped): %s" % str(final_target_pos))
    var vector_to_target = final_target_pos - start_pos; var distance = vector_to_target.length()
    var kick_successful = false # Track kick success
    if distance > 1.0:
        var norm_kick = float(kicker_kicking_stat-1)/float(MAX_KICKING_STAT-1) if MAX_KICKING_STAT>1 else 1.0
        var eff_speed = lerp(BASE_KICK_SPEED, MAX_KICK_SPEED, norm_kick)
        var max_dev = lerp(BASE_KICK_INACCURACY_ANGLE, MIN_KICK_INACCURACY_ANGLE, norm_kick)
        var rand_dev = randf_range(-max_dev, max_dev)
        var actual_dir = vector_to_target.normalized().rotated(rand_dev)
        linear_velocity = actual_dir * eff_speed
        kick_successful = true # Mark kick successful
        if eff_speed > 0:
            # --- UPDATED TIMER CALCULATION ---
            pass_reception_timer = (distance / eff_speed) * 1.05 + 0.05 # Apply same buffer logic to kicks
            # ---
            print("BALL SCRIPT: initiate_kick() - Kick reception timer started: %.2f sec" % pass_reception_timer)
        else: pass_reception_timer = 0.1; printerr("Kick speed zero!")
    else:
        print("BALL SCRIPT: Kick target too close..."); linear_velocity = Vector2.ZERO
        if pickup_area != null: pickup_area.monitoring = true; print("BALL SCRIPT: Kick failed - Monitor ON")
        pass_reception_timer = 0.0

    # Reset intended_receiver DEFERRED (already null, but good practice)
    if kick_successful: # Only queue clear if kick was successful
        call_deferred("_clear_intended_receiver")

# --- Helper Function to Clear Receiver ---
func _clear_intended_receiver():
    intended_receiver = null
    #print_debug("Intended receiver cleared.")
