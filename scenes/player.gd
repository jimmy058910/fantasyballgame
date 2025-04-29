# player.gd - FINAL CLEAN VERSION (April 27th)
extends CharacterBody2D

# Player Stats (Exported for tweaking in Inspector)
@export var base_speed: float = 150.0 # Speed in pixels per second
@export var max_stamina: float = 100.0 # Maximum stamina value
@export var power: int = 10
@export var agility: int = 10
@export var tackle_range: float = 30.0 # How close to attempt tackle (pixels) - Reset to reasonable default
@export var team_id: int = 0 # 0 for Team A, 1 for Team B

# Internal State Variables
var current_stamina: float # Variable to track current stamina
var ball_node: Node2D = null # Variable to hold a reference to the ball
var stun_timer: float = 0.0 # Time remaining stunned (in seconds)

# Called when the node enters the scene tree for the first time.
func _ready():
    current_stamina = max_stamina # Start with full stamina
    add_to_group("players") # Identify this node as a player

    # Find the ball node (assumes a node named "Ball" exists in the "ball" group)
    ball_node = get_tree().get_first_node_in_group("ball")
    if ball_node == null:
        printerr(self.name, " could not find the ball node!")


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
    var target_position = global_position # Default: stay put if no target found

    if ball_node != null: # Check if we found the ball node in _ready()
        var possessor = ball_node.get("current_possessor") # Safer access

        if possessor != null and is_instance_valid(possessor): # Check if someone has the ball AND the node still exists
            var possessor_team = possessor.get("team_id") # Returns null if no team_id

            if possessor == self:
                # I HAVE THE BALL! Target opponent's goal
                if team_id == 0:
                    direction = Vector2.RIGHT # Team 0 goal is right
                else:
                    direction = Vector2.LEFT  # Team 1 goal is left
            elif possessor_team != null and possessor_team == team_id:
                # My TEAMMATE has the ball - move towards goal (simple for now)
                if team_id == 0:
                    direction = Vector2.RIGHT
                else:
                    direction = Vector2.LEFT
                # TODO: Add more complex logic later (block, get open, etc.)
# ... (elif block for teammate logic ends here) ...
            else: # Opponent has the ball (or possessor has invalid/no team_id)
                # OPPONENT has the ball - target the possessor
                target_position = possessor.global_position

                # --- REMOVED DISTANCE CHECK AND TACKLE LOGIC FROM HERE ---

                # Calculate direction towards the possessor if not already at the target
                if global_position.distance_squared_to(target_position) > 1.0:
                     direction = (target_position - global_position).normalized()

        else: # NO ONE has the ball (ball is loose)
            # Target the ball itself
            target_position = ball_node.global_position
            # Only calculate direction if not already at the target
            if global_position.distance_squared_to(target_position) > 1.0:
                direction = (target_position - global_position).normalized()

    # 4. Set velocity if the player has stamina and a direction to move in
    if current_stamina > 0 and direction != Vector2.ZERO:
        velocity = direction * effective_speed
    else:
        velocity = Vector2.ZERO

    # 5. Move the character
    move_and_slide()

    # 6. Drain stamina if moving
    if velocity.length_squared() > 0:
        var stamina_drain_rate = 10.0 # Adjust as needed
        current_stamina -= stamina_drain_rate * delta
        current_stamina = max(current_stamina, 0.0)
        # print("Stamina: ", current_stamina) # Optional debug

# This function is called automatically when a body enters the TackleArea
# This function is called automatically when a body enters the TackleArea
func _on_tackle_area_body_entered(body):
    # --- Start Debug Version ---
    print(self.name, " tackle area detected BODY: '", body.name, "' IsPlayerGroup? ", body.is_in_group("players")) # Print 1: Did something enter?

    if body == self or not body.is_in_group("players"):
        #print(self.name, " ignoring self or non-player.") # Optional print
        return # Ignore self or non-player bodies

    print(self.name, " passed initial body check for: '", body.name, "'") # Print 2: Was it a valid player?

    if ball_node != null:
        var possessor = ball_node.get("current_possessor")
        print(self.name, " checking possessor. Current possessor is: '", possessor, "'") # Print 3: Who has the ball?

        if possessor == body and is_instance_valid(possessor):
            print(self.name, " confirmed body '", body.name, "' IS the current possessor.") # Print 4: Did the possessor enter?

            var possessor_team = possessor.get("team_id")
            print(self.name, " possessor '", possessor.name,"' team: ", possessor_team, " | My team: ", team_id) # Print 5: What are the teams?

            if possessor_team != null and possessor_team != team_id:
                print(self.name, " OPPONENT possessor '", possessor.name, "' confirmed in my tackle area!") # Print 6: Is it an opponent?

                # --- Perform Tackle Resolution Logic ---
                if stun_timer <= 0: # Check if defender is stunned
                    print(self.name, " NOT stunned, attempting contest.") # Print 7: Am I stunned?

                    var defender_power_roll = power + randi_range(-3, 3)
                    var carrier_agility = possessor.get("agility")

                    if carrier_agility != null:
                        var carrier_agility_roll = carrier_agility + randi_range(-3, 3)
                        # This is the original target print:
                        print("Tackle Contest: ", self.name, "(Pwr:", defender_power_roll, ") vs ", possessor.name, "(Agi:", carrier_agility_roll, ")") # Print 8 (Original)

                        if defender_power_roll >= carrier_agility_roll:
                            print("Tackle SUCCEEDED!") # Print 9
                            if ball_node.has_method("set_loose"):
                                ball_node.set_loose()
                        else:
                            print("Tackle FAILED/Evaded!") # Print 10
                    else:
                        printerr(self.name, " could not get agility for possessor: ", possessor.name) # Print 11 (Error case)
                    # Apply stun AFTER attempt
                    stun_timer = 0.5
                else:
                    print(self.name, " IS stunned (", stun_timer, "), skipping contest.") # Print 12: Reason for no contest
            else:
                 print(self.name, " body '", body.name, "' is possessor, but SAME team or invalid team.") # Print 13: Reason for no contest
        else:
            print(self.name, " body '", body.name, "' is NOT current possessor (or possessor invalid). Possessor is: '", possessor, "'") # Print 14: Reason for no contest
    else:
        print(self.name, " ball_node is null in area check?") # Print 15: Should not happen if ready worked
    # --- End Debug Version ---
