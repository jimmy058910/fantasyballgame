# field.gd
extends Node2D

# --- ADD/EDIT THESE ARRAY DEFINITIONS BELOW ---
# Define starting positions (!!! EDIT THESE Vector2 coordinates !!!)
# These are just EXAMPLES assuming a 1920x1080 field centered at (0,0)
# Adjust X and Y values based on your actual field size and desired formation.

# Team 0 starts on left half (usually negative X if centered) - 6 positions
var team0_start_positions: Array[Vector2] = [
    Vector2(-300, 0),    # Position 1 for Team 0
    Vector2(-400, -200), # Position 2 for Team 0
    Vector2(-400, 200),  # Position 3 for Team 0
    Vector2(-700, -300), # Position 4 for Team 0
    Vector2(-700, 0),    # Position 5 for Team 0
    Vector2(-700, 300)   # Position 6 for Team 0
]
# Team 1 starts on right half (usually positive X if centered) - 6 positions
var team1_start_positions: Array[Vector2] = [
    Vector2(300, 0),     # Position 1 for Team 1
    Vector2(400, -200),  # Position 2 for Team 1
    Vector2(400, 200),   # Position 3 for Team 1
    Vector2(700, -300),  # Position 4 for Team 1
    Vector2(700, 0),     # Position 5 for Team 1
    Vector2(700, 300)    # Position 6 for Team 1
]
# --- END OF ARRAY DEFINITIONS ---

# Called when the script instance is ready
func _ready():
    randomize() # Keep this line for random numbers

# Function called when something enters Team 0's end zone
func _on_team_0_end_zone_body_entered(body):
    # Check if it's a player node
    if body.is_in_group("players"):
        var ball = get_tree().get_first_node_in_group("ball") # Find the ball node
        if ball != null and ball.has_method("get"): # Check if ball exists and has methods
            var possessor = ball.get("current_possessor")
            # Check if the body entering IS the possessor AND is on Team 1 (scoring on Team 0's goal)
            if is_instance_valid(possessor) and possessor == body:
                var scorer_team = body.get("team_id")
                if scorer_team == 1:
                    print("SCORE TEAM 1!")
                    # TODO: Add score increment variables later
                    reset_play() # Reset positions after score

# Function called when something enters Team 1's end zone
func _on_team_1_end_zone_body_entered(body):
    if body.is_in_group("players"):
        var ball = get_tree().get_first_node_in_group("ball") # Find the ball node
        if ball != null and ball.has_method("get"): # Check if ball exists and has methods
            var possessor = ball.get("current_possessor")
            # Check if the body entering IS the possessor AND is on Team 0 (scoring on Team 1's goal)
            if is_instance_valid(possessor) and possessor == body:
                var scorer_team = body.get("team_id")
                if scorer_team == 0:
                    print("SCORE TEAM 0!")
                    # TODO: Add score increment variables later
                    reset_play() # Reset positions after score

# Function to reset things after a score
func reset_play():
    print("Resetting Play...")
    var ball = get_tree().get_first_node_in_group("ball")
    if ball != null:
        # Make ball loose
        if ball.has_method("set_loose"):
            ball.set_loose()
        else: # Fallback if set_loose doesn't exist
            ball.set("current_possessor", null)
        # Reset ball position (e.g., center field - adjust coords if needed)
        var screen_size = get_viewport_rect().size
        ball.global_position = screen_size / 2.0

    # Reset players
    var players = get_tree().get_nodes_in_group("players")
    var team0_idx = 0
    var team1_idx = 0
    for player in players:
        # Reset to defined starting positions
        if player.has_method("get") and player.get("team_id") == 0:
            if team0_idx < team0_start_positions.size():
                player.global_position = team0_start_positions[team0_idx]
            team0_idx += 1
        elif player.has_method("get"): # Assume Team 1 if not Team 0
             if team1_idx < team1_start_positions.size():
                player.global_position = team1_start_positions[team1_idx]
             team1_idx += 1

        # Reset stamina, stun, and velocity (if methods/properties exist)
        if player.has_method("set"):
            if "max_stamina" in player: # Check if property exists
                player.set("current_stamina", player.get("max_stamina"))
            player.set("stun_timer", 0.0)
            player.set("velocity", Vector2.ZERO) # Crucial to stop movement
