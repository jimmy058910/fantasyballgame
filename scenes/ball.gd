# ball.gd - Includes synchronization calls to player.gd
extends RigidBody2D

# --- Export Variables ---
# Gameplay parameters (can be tweaked in Inspector)
@export var pass_speed: float = 650.0      # Speed applied as velocity for a pass
@export var max_pass_range: float = 450.0  # Used by player to calculate target before calling initiate_pass
@export var bounce_impulse_strength : float = 100.0 # Force applied on tackle bounce
@export var follow_offset := Vector2(0, -25) # Offset from player center when held

# Define field boundaries (!!! USER NEEDS TO ADJUST THESE VALUES !!!)
# Assumes field origin (0,0) is the center
@export var field_half_width : float = 960.0
@export var field_half_height : float = 540.0
@export var field_margin : float = 15.0

# --- Internal State ---
var current_possessor: Node2D = null # Reference to the player holding the ball

# --- Node References ---
# IMPORTANT: Assumes the pickup Area2D child node in ball.tscn is named exactly "PickupArea"
@onready var pickup_area: Area2D = $PickupArea

# --- Initialization ---
func _ready():
    # Ball starts loose, physics active
    freeze = false
    # Ensure the pickup area node exists and monitoring is enabled initially
    if pickup_area != null:
        pickup_area.monitoring = true
        # Ensure signal is connected (MUST also be connected in the Editor for reliability)
        # Check if connection ALREADY exists before attempting to connect
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
# Handles freezing/unfreezing and setting position when held
func _physics_process(_delta):
    if current_possessor != null:
        # --- Ball is HELD ---
        if is_instance_valid(current_possessor):
            # If not already frozen, request freeze and stop physics movement/rotation
            if freeze == false:
                 set_deferred("freeze", true) # Use deferred to safely change physics state
                 linear_velocity = Vector2.ZERO # Stop residual movement when freezing
                 angular_velocity = 0.0      # Stop residual spin when freezing
            # Manually set position to follow possessor precisely
            global_position = current_possessor.global_position + follow_offset
        else:
            # Possessor became invalid (e.g., deleted?), make ball loose
            print("BALL SCRIPT: Possessor became invalid while holding, setting loose.")
            # Possessor is already invalid, so no need to call lose_ball() on them
            set_loose() # Use set_loose to handle unfreeze, bounce, and enabling monitoring
    else:
        # --- Ball is LOOSE ---
        # If it was previously frozen (e.g., just became loose), request unfreeze
        if freeze == true:
            set_deferred("freeze", false) # Use deferred to safely change physics state
            # Note: set_loose or initiate_pass should have already re-enabled monitoring

        # Physics engine handles movement when not frozen
        # Check if velocity is very low (ball has settled) and ensure pickup monitoring is on
        var stop_threshold_sq = 5.0 * 5.0 # Squared speed below which ball is considered stopped
        if not freeze and linear_velocity.length_squared() < stop_threshold_sq and abs(angular_velocity) < 0.1:
            # Ball is loose and almost stopped
            linear_velocity = Vector2.ZERO # Ensure it's fully stopped
            angular_velocity = 0.0
            # Ensure monitoring is on when ball is settled and loose
            if pickup_area != null and pickup_area.monitoring == false:
                pickup_area.monitoring = true
                print("BALL SCRIPT: Ball stopped/settled - PickupArea monitoring ON")
        # Let physics engine do its work when loose


# --- Signal Handler for Pickup ---
# CONNECT THIS in the editor: PickupArea -> body_entered -> Ball -> _on_pickup_area_body_entered
func _on_pickup_area_body_entered(body):
    # Check if ball is currently loose (NOT frozen) AND pickup monitoring is ON
    # Also ensure the body entering is a player and isn't knocked down
    if current_possessor == null and not freeze and pickup_area.monitoring \
       and body.is_in_group("players") and not body.get_is_knocked_down():

        print("BALL AREA DEBUG: Pickup conditions met for ", body.name)
        current_possessor = body

        # *** SYNC CHANGE: Tell player script it has the ball ***
        if body.has_method("pickup_ball"):
            body.pickup_ball()
        else:
            printerr("Ball Error: Player %s missing pickup_ball() method!" % body.name)

        set_deferred("freeze", true) # Use deferred set
        linear_velocity = Vector2.ZERO # Stop physics movement AFTER freeze takes effect
        angular_velocity = 0.0
        # Snap position right away
        global_position = current_possessor.global_position + follow_offset
        print("BALL SCRIPT: Picked up by ", body.name, ". Possessor is now: ", current_possessor)


# --- Function to Make Ball Loose (e.g., after tackle) ---
# Accepts optional velocity vector from the player losing the ball/tackler for bounce direction
func set_loose(bounce_dir_velocity: Vector2 = Vector2.ZERO):
    var print_prefix = "BALL SCRIPT: set_loose(): "

    # *** SYNC CHANGE: Tell the player script it lost the ball ***
    if is_instance_valid(current_possessor): # Check if possessor is valid before calling
         print(print_prefix, current_possessor.name, " lost the ball! Telling player.")
         if current_possessor.has_method("lose_ball"):
             current_possessor.lose_ball()
         else:
              printerr("Ball Error: Player %s missing lose_ball() method!" % current_possessor.name)

    current_possessor = null # Set possessor to null AFTER telling them
    set_deferred("freeze", false) # Ensure physics is active

    # Ensure pickup monitoring is enabled when ball becomes loose
    if pickup_area != null:
        pickup_area.monitoring = true
        # print(print_prefix, "PickupArea monitoring ON.") # Optional debug

    # Apply bounce impulse based on passed velocity or random
    var impulse_dir = Vector2.RIGHT # Default
    if bounce_dir_velocity.length_squared() > 1.0:
        # Bounce away from the direction the tackler/loser was moving
        # Using the negative of the provided velocity vector as the impulse direction
        impulse_dir = bounce_dir_velocity.normalized() * -1.0
    else:
        # Random bounce if no velocity provided or it's zero
         impulse_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
         # Ensure we don't get a zero vector if randf happens to hit (0,0)
         if impulse_dir == Vector2.ZERO: impulse_dir = Vector2.RIGHT

    apply_central_impulse(impulse_dir * bounce_impulse_strength)
    print(print_prefix, "Applied bounce impulse in direction: ", impulse_dir)


# --- Function to Initiate a Pass ---
# Call this FROM the player script, passing 'self' as the passer
func initiate_pass(passer: Node, target_destination: Vector2):
    # Check if the node attempting the pass is actually the current possessor
    if is_instance_valid(current_possessor) and current_possessor == passer:
        print("BALL SCRIPT: ", current_possessor.name, " initiates pass towards ", target_destination)
        var start_pos = global_position

        # *** SYNC CHANGE: Tell the player script it lost the ball ***
        if is_instance_valid(current_possessor): # Check again just before call
            if current_possessor.has_method("lose_ball"):
                current_possessor.lose_ball()
            else:
                 printerr("Ball Error: Player %s missing lose_ball() method!" % current_possessor.name)

        current_possessor = null # Set possessor to null AFTER telling them
        set_deferred("freeze", false) # Ensure physics is active for pass

        # --- Disable pickup monitoring DURING pass ---
        if pickup_area != null:
            pickup_area.monitoring = false
            print("BALL SCRIPT: initiate_pass() - PickupArea monitoring OFF")
        # ---

        # Calculate final target pos, clamping for range and field boundaries
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

        # Apply velocity
        var vector_to_target = final_target_pos - start_pos
        if vector_to_target.length_squared() > 1.0: # Check length squared > 1 to avoid normalizing zero vector
              linear_velocity = vector_to_target.normalized() * pass_speed
        else:
              # Target too close, just drop it
              print("BALL SCRIPT: Pass target too close after clamping, dropping ball.")
              linear_velocity = Vector2.ZERO
              # Ball is loose, ensure monitoring is back on if pass fails instantly
              if pickup_area != null:
                  pickup_area.monitoring = true
                  print("BALL SCRIPT: Pass failed - PickupArea monitoring ON")

    elif not is_instance_valid(current_possessor):
         printerr("Initiate pass called by ", passer.name, " but ball has no valid possessor!")
    elif current_possessor != passer:
         printerr("Initiate pass called by ", passer.name, " but ", current_possessor.name, " actually has the ball!")
