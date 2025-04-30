extends Node2D # Or Sprite2D if your root is the sprite

# --- Define Field Boundaries and Bounce ---
# Assumes field origin (0,0) is the center
@export var field_half_width : float = 960.0  # Half of your field's total width
@export var field_half_height : float = 540.0 # Half of your field's total height
@export var bounce_radius : float = 60.0    # Max distance ball bounces on tackle (pixels)
@export var bounce_margin : float = 15.0     # Keep ball away from edge after bounce
# --- End Definitions ---

# --- Pass State Variables ---
var is_passing: bool = false       # Is the ball currently mid-pass?
var pass_velocity: Vector2 = Vector2.ZERO # Speed and direction of the current pass
var pass_target_pos: Vector2 = Vector2.ZERO # Where the pass is aimed (might be clamped by range)
@export var pass_speed: float = 500.0    # Speed of the pass (pixels/sec) - Should be faster than players!
@export var max_pass_range: float = 325.0  # Max distance a pass can travel
# --- End Pass State Variables ---

var current_possessor: Node2D = null # Start with no one possessing
var follow_offset = Vector2(0, -20) # Small offset so ball isn't exactly on player center (adjust as needed)

# Inside ball.gd

func _on_area_2d_body_entered(body):
    # Check if ball is free AND the body entering is a Player
    if current_possessor == null and body.is_in_group("players"):
        current_possessor = body
        # --- ADD THIS LINE ---
        print("BALL SCRIPT: Picked up by ", body.name, ". Possessor is now: ", current_possessor)
        # --- END ADDED LINE ---

# Modified physics process to handle passing
func _physics_process(_delta):
    if is_passing:
        # --- Ball is Mid-Pass ---
        # Move the ball along the pass trajectory
        global_position += pass_velocity * _delta

        # Check if pass reached the target vicinity
        var threshold : float = 20.0 # How close to target counts as arrived
        if global_position.distance_squared_to(pass_target_pos) < (threshold * threshold):
            print("BALL SCRIPT: Pass reached vicinity of target.")
            is_passing = false
            pass_velocity = Vector2.ZERO
            # Ball stops here, becomes 'loose' and available for pickup via its Area2D

    elif current_possessor != null:
        # --- Ball is Being Held ---
        if is_instance_valid(current_possessor):
            # Standard logic to follow the possessor
            global_position = current_possessor.global_position + follow_offset
        else:
            # Possessor somehow disappeared (e.g., deleted - unlikely in sim)
            current_possessor = null
            is_passing = false # Ensure passing flag is off
            pass_velocity = Vector2.ZERO
            print("BALL SCRIPT: Possessor became invalid, ball is free (no bounce)")

    # else:
        # --- Ball is Loose AND Not Passing ---
        # Ball just sits still for now.
        # Later, you could add friction or bouncing off walls here.
        pass

# Call this function when a tackle is successful
# Inside ball.gd

# Call this function when a tackle is successful
func set_loose():
    if current_possessor != null:
        print("BALL SCRIPT: ", current_possessor.name, " lost the ball due to tackle! Possessor set to null.")
        var last_carrier_pos = current_possessor.global_position # Store where carrier was
        current_possessor = null # Ball is now loose

        # --- Add Bounce Logic ---
        # Calculate a random direction
        var random_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
        if random_dir.length_squared() > 0: # Avoid zero vector
            random_dir = random_dir.normalized()
        else:
            random_dir = Vector2.RIGHT # Default fallback

        # Calculate a random distance within the bounce radius (but not zero)
        var random_dist = randf_range(bounce_radius * 0.2, bounce_radius) # Bounce at least 20% of radius

        # Calculate the potential new position based on where the carrier was
        var bounce_offset = random_dir * random_dist
        var new_pos = last_carrier_pos + bounce_offset # Apply bounce from carrier's last spot

        # Clamp position to stay within field boundaries (minus a margin)
        new_pos.x = clamp(new_pos.x, -field_half_width + bounce_margin, field_half_width - bounce_margin)
        new_pos.y = clamp(new_pos.y, -field_half_height + bounce_margin, field_half_height - bounce_margin)

        # Set the ball's new position
        global_position = new_pos
        print("BALL SCRIPT: Ball bounced to ", global_position) # Debug new position
        # --- End Bounce Logic ---

    else:
         # Optional: Handle case where set_loose is called but no one had the ball?
         print("BALL SCRIPT: set_loose called but no possessor?")
         pass

# Make sure your _physics_process and _on_area_2d_body_entered functions are still below

# Call this function FROM the player script to start a pass
func initiate_pass(target_destination: Vector2):
    if current_possessor != null: # Must have possession to pass
        print("BALL SCRIPT: ", current_possessor.name, " initiates pass towards ", target_destination)
        var start_pos = global_position # Where the pass starts from

        current_possessor = null # Ball becomes 'loose' immediately (no longer follows player)
        is_passing = true       # Set the passing state flag

        # Calculate direction and potentially clamp distance based on max_pass_range
        var direction_to_target = (target_destination - start_pos)
        var distance_to_target_sq = direction_to_target.length_squared()
        var max_range_sq = max_pass_range * max_pass_range

        if distance_to_target_sq > max_range_sq:
            # Target is too far, calculate position at max range
            pass_target_pos = start_pos + direction_to_target.normalized() * max_pass_range
            print("BALL SCRIPT: Pass target out of range, aiming for max range point.")
        else:
            # Target is within range
            pass_target_pos = target_destination

        # Calculate velocity needed to reach the (potentially clamped) target
        # Avoid division by zero if start/end points are too close
        var vector_to_target = pass_target_pos - start_pos
        if vector_to_target.length_squared() > 1.0: # Check if target is meaningfully different
            pass_velocity = vector_to_target.normalized() * pass_speed
        else:
            # Target is basically current position, treat as failed pass/drop
            print("BALL SCRIPT: Pass target too close, dropping ball.")
            is_passing = false
            pass_velocity = Vector2.ZERO
            # No need to call set_loose() as possessor is already null
            # Ball will just sit here until picked up again
