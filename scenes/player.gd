# player.gd - COMPLETE CLEAN VERSION (April 29th) - Includes Pass Logic
extends CharacterBody2D

@export var team0_texture: Texture2D
@export var team1_texture: Texture2D

# Player Stats (Exported for tweaking in Inspector)
@export var base_speed: float = 150.0 # Speed in pixels per second
@export var max_stamina: float = 300.0 # Maximum stamina value
@export var stamina_recovery_rate: float = 12.0 # Stamina units recovered per second when resting
@export var power: int = 10
@export var agility: int = 10
@export var tackle_range: float = 30.0 # How close to attempt tackle (pixels)
@export var team_id: int = 0 # 0 for Team A, 1 for Team B

@onready var sprite: Sprite2D = $Sprite2D

# Internal State Variables
var current_stamina: float
var ball_node: Node2D = null
var stun_timer: float = 0.0

# Node References (ensure node paths are correct in your scene!)
@onready var tackle_area: Area2D = $TackleArea # Assumes child node is named TackleArea

# Called when the node enters the scene tree for the first time.
func _ready():
    current_stamina = max_stamina
    add_to_group("players")

    ball_node = get_tree().get_first_node_in_group("ball")
    if ball_node == null:
        printerr(self.name, " could not find the ball node!")
    
    # Set the correct texture based on team_id
    if sprite != null: # Safety check: Did we find the sprite node?
        if team_id == 0:
            if team0_texture != null: # Safety check: Was texture assigned in Inspector?
                sprite.texture = team0_texture
            else:
                printerr(self.name, " missing Team 0 Texture assignment in Inspector!")
        elif team_id == 1:
            if team1_texture != null: # Safety check: Was texture assigned in Inspector?
                sprite.texture = team1_texture
            else:
                printerr(self.name, " missing Team 1 Texture assignment in Inspector!")
        else:
            # Handles cases if team_id is not 0 or 1
            printerr(self.name, " has invalid team_id: ", team_id, " - Cannot set texture.")
    else:
        printerr(self.name, " could not find Sprite2D node named 'Sprite2D'!")

# Called every physics frame. 'delta' is the elapsed time since the previous frame.
# Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
    # --- START: Stun Check ---
    if stun_timer > 0:
        stun_timer -= delta # Decrease stun timer
        velocity = Vector2.ZERO # Stop movement if stunned
        move_and_slide() # Apply the stop/resolve collisions even while stunned
        return # Skip the rest of physics processing for this frame
    # --- END: Stun Check ---

    # 1. Calculate stamina ratio (prevent division by zero)
    var stamina_ratio: float = 1.0
    if max_stamina > 0:
        stamina_ratio = max(current_stamina, 0.0) / max_stamina

    # 2. Calculate effective speed based on stamina
    var effective_speed = base_speed * stamina_ratio

    # 3. Determine movement direction based on ball possession
    var direction = Vector2.ZERO
    var target_position = global_position # Default: stay put

    if ball_node != null: # Check if we found the ball node in _ready()
        var possessor = ball_node.get("current_possessor") # Safer access

        if possessor != null and is_instance_valid(possessor): # Check if someone has the ball AND the node still exists
            var possessor_team = possessor.get("team_id") # Returns null if no team_id

            # --- Start of IF/ELIF/ELSE for Possession State ---
            if possessor == self:
                # --- I HAVE THE BALL ---
                var goal_direction = Vector2.RIGHT if team_id == 0 else Vector2.LEFT
                direction = goal_direction # Default action is move

                # Check for pressure to trigger pass
                var opponent_is_close = false
                if tackle_area != null:
                    var bodies_in_zone = tackle_area.get_overlapping_bodies()
                    for body in bodies_in_zone:
                        if body.is_in_group("players") and body.has_method("get"):
                            var body_team_id = body.get("team_id")
                            if body_team_id != null and body_team_id != team_id:
                                opponent_is_close = true
                                break # Found opponent

                if opponent_is_close: # Attempt pass if opponent nearby
                    if ball_node.has_method("initiate_pass"):
                        print(self.name, " passing under pressure!")
                        var pass_range = 600.0 # Default pass range if ball node doesn't have it
                        if "max_pass_range" in ball_node:
                                pass_range = ball_node.get("max_pass_range")
                        var pass_target = global_position + goal_direction * pass_range
                        ball_node.initiate_pass(pass_target)
                        direction = Vector2.ZERO # Stop moving after passing
                        # stun_timer = 0.1 # Optional short stun after pass
                    else:
                        printerr(self.name, " Ball node missing initiate_pass method?")
                # --- End Pass Logic ---

            elif possessor_team != null and possessor_team == team_id:
                # --- TEAMMATE has ball ---
                if team_id == 0:
                    direction = Vector2.RIGHT
                else:
                    direction = Vector2.LEFT
                # TODO: Better teammate AI (spacing, blocking)

            else: # Opponent has the ball (or possessor team invalid)
                # --- OPPONENT has ball ---
                target_position = possessor.global_position

                # Check distance for tackle attempt (via Area2D signal now)
                # We removed the distance check logic from here, signal handles it.

                # Calculate direction towards the possessor
                if global_position.distance_squared_to(target_position) > 1.0:
                        direction = (target_position - global_position).normalized()

            # --- End of IF/ELIF/ELSE for Possession State ---

        else: # Ball is LOOSE
            # --- Ball is LOOSE ---
            target_position = ball_node.global_position
            # Add random offset to target
            var offset_radius = 20.0
            var random_offset = Vector2(randf_range(-offset_radius, offset_radius), randf_range(-offset_radius, offset_radius))
            target_position += random_offset
            # Calculate direction to adjusted target
            if global_position.distance_squared_to(target_position) > 1.0:
                direction = (target_position - global_position).normalized()

    # else: # Optional: Ball node not found
    #	printerr(self.name, " cannot find ball node in physics process.")


    # 4. Set velocity based on direction, speed, and stamina
    if current_stamina > 0 and direction != Vector2.ZERO:
        velocity = direction * effective_speed
    else:
        velocity = Vector2.ZERO # Stop if out of stamina or no direction

    # 5. Move the character
    move_and_slide()

    # 6. Drain or Recover Stamina
    # Define the threshold below which we consider the player stopped (squared value)
    var movement_threshold_sq = 5.0 * 5.0 

    if velocity.length_squared() > movement_threshold_sq:
        # Player is MOVING significantly
        # Use the adjusted lower drain rate (e.g., 2.0 or 4.0 - adjust as needed)
        var stamina_drain_rate = 2.0 # <--- ADJUST THIS RATE IF NEEDED
        current_stamina -= stamina_drain_rate * delta
        current_stamina = max(current_stamina, 0.0) # Clamp stamina >= 0
        # Print stamina value while draining
        print(self.name, " Draining Stamina: ", current_stamina)

    else:
        # Player is STOPPED or moving very slowly
        # Recover stamina using the recovery rate variable (declared at top)
        current_stamina += stamina_recovery_rate * delta
        # Clamp stamina (don't exceed max_stamina)
        current_stamina = min(current_stamina, max_stamina)
        # Optional print for recovery
        # print(self.name, " Recovering Stamina: ", current_stamina)
    # --- End Stamina Logic ---

# --- End of _physics_process function ---

# --- Tackle Area Signal Handler ---
# Called automatically when a body enters the TackleArea
func _on_tackle_area_body_entered(body):
    if body == self or not body.is_in_group("players"):
        return

    if ball_node != null:
        var possessor = ball_node.get("current_possessor")
        if possessor == body and is_instance_valid(possessor):
            var possessor_team = possessor.get("team_id")
            if possessor_team != null and possessor_team != team_id:
                # Opponent possessor detected in tackle range!
                print(self.name, " detected ", possessor.name, " in tackle area.")

                if stun_timer <= 0: # Check if defender is stunned
                    var defender_power_roll = power + randi_range(-3, 3)
                    var carrier_agility = possessor.get("agility")

                    if carrier_agility != null:
                        var carrier_agility_roll = carrier_agility + randi_range(-3, 3)
                        print("Tackle Contest: ", self.name, "(Pwr:", defender_power_roll, ") vs ", possessor.name, "(Agi:", carrier_agility_roll, ")")

                        if defender_power_roll >= carrier_agility_roll:
                            print("Tackle SUCCEEDED!")
                            if ball_node.has_method("set_loose"):
                                ball_node.set_loose()
                        else:
                            print("Tackle FAILED/Evaded!")
                    else:
                        printerr(self.name, " could not get agility for possessor: ", possessor.name)
                    # Apply stun AFTER attempt
                    stun_timer = 0.5
                # else: # Optional: print if stunned
                    # print(self.name, " IS stunned (", stun_timer, "), skipping contest.")
