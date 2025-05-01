# ball.gd - Allows pickup while moving, dynamic pass timer, includes debug prints
extends RigidBody2D

# --- Export Variables ---
@export var pass_speed: float = 650.0      # Speed applied as velocity for a pass
@export var max_pass_range: float = 450.0  # Used by player to calculate target before calling initiate_pass
@export var bounce_impulse_strength : float = 100.0 # Force applied on tackle bounce
@export var follow_offset := Vector2(0, -25) # Offset from player center when held

# Define field boundaries (Adjust if needed)
@export var field_half_width : float = 960.0
@export var field_half_height : float = 540.0
@export var field_margin : float = 15.0

# --- Internal State ---
var current_possessor: Node2D = null # Reference to the player holding the ball
var pass_reception_timer: float = 0.0 # Timer for pass reception delay

# --- Node References ---
@onready var pickup_area: Area2D = $PickupArea

# --- Initialization ---
func _ready():
    # Ball starts loose, physics active
    freeze = false
    if pickup_area != null:
        pickup_area.monitoring = true # Start with monitoring ON
        # Ensure signal is connected (MUST also be connected in the Editor for reliability)
        var signal_name = "body_entered"
        var callable_to_check = Callable(self, "_on_pickup_area_body_entered")
        var connections = pickup_area.get_signal_connection_list(signal_name)
        var already_connected = false
        for connection in connections:
            if connection.callable == callable_to_check:
                already_connected = true
                break
        if not already_connected:
            var error_code = pickup_area.connect(signal_name, callable_to_check)
            if error_code != OK:
                printerr("Ball: Failed to connect pickup area signal in _ready! Error code: ", error_code)
            else:
                print_debug("Ball: PickupArea signal connected via script.")
        else:
            print_debug("Ball: PickupArea signal already connected (likely via editor).")
    else:
        printerr("Ball Error: Cannot find child node named 'PickupArea'!")


# --- Physics Update ---
func _physics_process(delta):
    # --- Pass Reception Timer ---
    if pass_reception_timer > 0.0:
        pass_reception_timer -= delta
        # If timer just ran out, enable monitoring
        if pass_reception_timer <= 0.0:
            if pickup_area != null and not pickup_area.monitoring:
                pickup_area.set_deferred("monitoring", true)
                print("BALL SCRIPT: Pass reception timer ended - Monitoring ON (Deferred)")

    if current_possessor != null:
        # --- Ball is HELD ---
        if is_instance_valid(current_possessor):
            if not freeze: # Use direct check, deferred set below
                 set_deferred("freeze", true)
                 linear_velocity = Vector2.ZERO
                 angular_velocity = 0.0
            # Ensure monitoring is off while held (deferred)
            if pickup_area != null and pickup_area.monitoring:
                pickup_area.set_deferred("monitoring", false)
            # Manually set position
            global_position = current_possessor.global_position + follow_offset
        else:
            # Possessor became invalid
            print("BALL SCRIPT: Possessor became invalid while holding, setting loose.")
            set_loose() # Possessor invalid, no velocity to pass
    else:
        # --- Ball is LOOSE ---
        if freeze: set_deferred("freeze", false)

        # Optional: Comment out continuous debug print if too noisy
        # if pickup_area != null:
        #    print_debug("PHYSICS: Ball loose. Monitoring state: %s, Velocity: %.1f" % [pickup_area.monitoring, linear_velocity.length()])

        # Safety check: If ball settles AND pass timer is done, ensure monitoring is on.
        var stop_threshold_sq = 5.0 * 5.0
        if not freeze and pass_reception_timer <= 0.0 and \
           linear_velocity.length_squared() < stop_threshold_sq and abs(angular_velocity) < 0.1:
            linear_velocity = Vector2.ZERO
            angular_velocity = 0.0
            if pickup_area != null and pickup_area.monitoring == false:
                pickup_area.set_deferred("monitoring", true) # Use deferred for safety
                print("BALL SCRIPT: Ball stopped/settled - Monitoring forced ON (Safety Check)")


# --- Signal Handler for Pickup ---
func _on_pickup_area_body_entered(body):
    # Debug prints to see entry state
    print("--- Pickup Area Entered by: ", body.name if body else "Unknown Body", " ---")
    print("State at entry: Possessor=%s, Frozen=%s, Monitoring=%s" % [current_possessor, freeze, str(pickup_area.monitoring) if pickup_area else 'N/A']) # Fixed ternary warning

    # Check player status safely
    var is_player = body.is_in_group("players") if body else false
    var is_knocked = true # Assume knocked down if not a valid player or check fails
    if is_player and body.has_method("get_is_knocked_down"):
        is_knocked = body.get_is_knocked_down()

    # --- COMMENTED OUT Conditions Check ---
    # print("Conditions Check: is_loose=%s, is_unfrozen=%s, is_monitoring=%s, is_player=%s, is_not_knocked=%s" % [
    #        current_possessor == null, not freeze, pickup_area.monitoring if pickup_area else false, is_player, not is_knocked
    # ])
    # --- END COMMENT OUT ---

    # Main Pickup Condition Check
    if current_possessor == null and not freeze and pickup_area != null and pickup_area.monitoring \
       and is_player and not is_knocked:

        print("BALL AREA DEBUG: Pickup conditions MET for ", body.name)
        current_possessor = body

        # Tell player script it has the ball
        if body.has_method("pickup_ball"): body.pickup_ball()
        else: printerr("Ball Error: Player %s missing pickup_ball() method!" % body.name)

        # Turn Monitoring OFF Deferred now that it's picked up
        pickup_area.set_deferred("monitoring", false)
        print("BALL SCRIPT: Pickup successful - Queued monitoring OFF (Deferred)")

        # Freeze ball physics (deferred) and stop movement
        set_deferred("freeze", true)
        linear_velocity = Vector2.ZERO
        angular_velocity = 0.0
        # Snap position right away
        global_position = current_possessor.global_position + follow_offset
        print("BALL SCRIPT: Picked up by ", body.name, ". Possessor is now: ", current_possessor)
    else:
        # Print failure reason if possible
        if current_possessor != null: print("Pickup failed: Ball already possessed.")
        elif freeze: print("Pickup failed: Ball frozen.")
        elif pickup_area == null: print("Pickup failed: PickupArea node missing.")
        elif not pickup_area.monitoring: print("Pickup failed: PickupArea monitoring is OFF.")
        elif not is_player: print("Pickup failed: Body is not in 'players' group.")
        elif is_knocked: print("Pickup failed: Player is knocked down.")
        else: print("Pickup conditions FAILED (Unknown reason).")
        print("------------------------------------")


# --- Function to Make Ball Loose (e.g., after tackle) ---
func set_loose(bounce_dir_velocity: Vector2 = Vector2.ZERO): # Allow passing velocity for bounce direction
    var print_prefix = "BALL SCRIPT: set_loose(): "

    # Tell the player script it lost the ball
    if is_instance_valid(current_possessor):
        print(print_prefix, current_possessor.name, " lost the ball! Telling player.")
        if current_possessor.has_method("lose_ball"): current_possessor.lose_ball()
        else: printerr("Ball Error: Player %s missing lose_ball() method!" % current_possessor.name)

    current_possessor = null
    set_deferred("freeze", false)
    pass_reception_timer = 0.0 # Ensure pass timer is reset if ball knocked loose

    # Ensure pickup monitoring is enabled (deferred) when ball becomes loose
    if pickup_area != null:
        pickup_area.set_deferred("monitoring", true) # Use deferred for moving pickup logic
        print("BALL SCRIPT: set_loose() - Setting monitoring ON (Deferred)")

    # Apply bounce impulse logic...
    var impulse_dir = Vector2.RIGHT
    if bounce_dir_velocity.length_squared() > 1.0:
        impulse_dir = bounce_dir_velocity.normalized() * -1.0
    else:
         impulse_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
         if impulse_dir == Vector2.ZERO: impulse_dir = Vector2.RIGHT
    apply_central_impulse(impulse_dir * bounce_impulse_strength)
    print(print_prefix, "Applied bounce impulse in direction: ", impulse_dir)


# --- Function to Initiate a Pass ---
func initiate_pass(passer: Node, target_destination: Vector2):
    if is_instance_valid(current_possessor) and current_possessor == passer:
        print("BALL SCRIPT: ", current_possessor.name, " initiates pass towards ", target_destination)
        var start_pos = global_position

        # Tell player script it lost the ball
        if is_instance_valid(current_possessor):
            if current_possessor.has_method("lose_ball"): current_possessor.lose_ball()
            else: printerr("Ball Error: Player %s missing lose_ball() method!" % current_possessor.name)

        current_possessor = null
        set_deferred("freeze", false)
        pass_reception_timer = 0.0 # Reset timer before potentially starting it

        # Turn monitoring OFF immediately during pass initiation
        if pickup_area != null:
            pickup_area.monitoring = false
            print("BALL SCRIPT: initiate_pass() - Monitoring forced OFF")

        # Calculate final target position...
        var direction_to_target = (target_destination - start_pos)
        var max_range_sq = max_pass_range * max_pass_range
        var final_target_pos : Vector2
        if direction_to_target.length_squared() > max_range_sq:
            final_target_pos = start_pos + direction_to_target.normalized() * max_pass_range
        else:
            final_target_pos = target_destination
        final_target_pos.x = clamp(final_target_pos.x, -field_half_width + field_margin, field_half_width - field_margin)
        final_target_pos.y = clamp(final_target_pos.y, -field_half_height + field_margin, field_half_height - field_margin)
        print("BALL SCRIPT: Passing towards (clamped): ", final_target_pos)

        # Calculate vector for velocity AFTER clamping target position
        var vector_to_target = final_target_pos - start_pos
        var distance = vector_to_target.length()

        # --- Debug prints (Commented Out) ---
        # print("DEBUG PASS CALC:")
        # print("  Start Pos: ", start_pos)
        # print("  Target Dest (Original): ", target_destination)
        # print("  Final Target Pos (Clamped): ", final_target_pos)
        # print("  Vector To Target: ", vector_to_target)
        # print("  Vector Length^2: ", vector_to_target.length_squared())
        # print("  Distance: ", distance)
        # --- END Debug prints ---

        # Apply velocity
        # REMOVED pass_successful variable declaration and assignment
        if distance > 1.0: # Use distance > threshold
              linear_velocity = vector_to_target.normalized() * pass_speed
              # print("  Applied Velocity: ", linear_velocity) # Comment out?

              # --- Calculate & Start Dynamic Reception Timer ---
              # This block only runs if distance > 1.0 (pass successful)
              if pass_speed > 0: # Avoid division by zero
                  pass_reception_timer = distance / pass_speed
                  print("BALL SCRIPT: initiate_pass() - Pass reception timer started: %.2f sec" % pass_reception_timer)
              else:
                  pass_reception_timer = 0.1 # Default small delay if speed is zero
                  printerr("Pass speed is zero!")
              # --- END TIMER CHANGE ---

        else:
              # Target too close, drop ball
              print("BALL SCRIPT: Pass target too close after clamping, dropping ball.")
              linear_velocity = Vector2.ZERO
              if pickup_area != null:
                  pickup_area.monitoring = true # Turn monitoring ON immediately if pass fails
                  print("BALL SCRIPT: Pass failed - PickupArea monitoring ON")
              # Ensure timer isn't running if pass fails instantly
              pass_reception_timer = 0.0

    # Error condition checks...
    elif not is_instance_valid(current_possessor):
         printerr("Initiate pass called by ", str(passer.name) if passer else "Unknown", " but ball has no valid possessor!") # Fixed ternary warning
    elif current_possessor != passer:
         printerr("Initiate pass called by ", str(passer.name) if passer else "Unknown", " but ", current_possessor.name, " actually has the ball!") # Fixed ternary warning
