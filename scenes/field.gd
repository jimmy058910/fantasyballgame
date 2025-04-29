# field.gd - Complete version with scoring logic (April 29th)
extends Node2D

# --- START POSITION ARRAYS ---
# Define starting positions (!!! USER NEEDS TO EDIT THESE Vector2 COORDINATES !!!)
# Example assumes field is 1920x1080 centered at (0,0)
var team0_start_positions: Array[Vector2] = [
    Vector2(-300, 0), Vector2(-400, -200), Vector2(-400, 200),
    Vector2(-700, -300), Vector2(-700, 0), Vector2(-700, 300)
]
var team1_start_positions: Array[Vector2] = [
    Vector2(300, 0), Vector2(400, -200), Vector2(400, 200),
    Vector2(700, -300), Vector2(700, 0), Vector2(700, 300)
]
# --- END POSITION ARRAYS ---


# Called when the script instance is ready
func _ready():
    randomize() # Initialize the random number generator


# --- START SIGNAL HANDLERS AND RESET FUNCTION ---
# Function called when something enters Team 0's end zone (Goal for Team 1)
func _on_team_0_end_zone_body_entered(body):
    # Check if it's a player node that entered
    if body.is_in_group("players"):
        var ball = get_tree().get_first_node_in_group("ball") # Find the ball node
        # Ensure ball exists and has the necessary property/method access
        if ball != null and ball.has_method("get"):
            var possessor = ball.get("current_possessor")
            # Check if the body entering IS the current possessor AND is on Team 1
            if is_instance_valid(possessor) and possessor == body:
                var scorer_team = body.get("team_id")
                if scorer_team == 1:
                    print("SCORE TEAM 1!")
                    # TODO: Add score increment variables later
                    reset_play() # Reset positions after score

# Function called when something enters Team 1's end zone (Goal for Team 0)
func _on_team_1_end_zone_body_entered(body):
    # Check if it's a player node that entered
    if body.is_in_group("players"):
        var ball = get_tree().get_first_node_in_group("ball") # Find the ball node
        # Ensure ball exists and has the necessary property/method access
        if ball != null and ball.has_method("get"):
            var possessor = ball.get("current_possessor")
            # Check if the body entering IS the current possessor AND is on Team 0
            if is_instance_valid(possessor) and possessor == body:
                var scorer_team = body.get("team_id")
                if scorer_team == 0:
                    print("SCORE TEAM 0!")
                    # TODO: Add score increment variables later
                    reset_play() # Reset positions after score

# Basic function to reset things after a score
func reset_play():
    print("Resetting Play...")
    var ball = get_tree().get_first_node_in_group("ball")
    if ball != null:
        # Make ball loose
        if ball.has_method("set_loose"):
            ball.set_loose()
        elif ball.has_method("set"): # Fallback if set_loose method missing
            ball.set("current_possessor", null)

        # Reset ball position to center of the field (adjust if your field isn't centered at 0,0)
        ball.global_position = Vector2.ZERO

    # Reset players
    var players = get_tree().get_nodes_in_group("players")
    var team0_idx = 0
    var team1_idx = 0
    for player in players:
        # Ensure player node is valid and has expected methods/properties before accessing
        if not is_instance_valid(player) or not player.has_method("get") or not player.has_method("set"):
            printerr("Invalid player node found during reset: ", player)
            continue # Skip this invalid player

        var player_team_id = player.get("team_id")

        # Reset to defined starting positions
        if player_team_id == 0:
            if team0_idx < team0_start_positions.size():
                player.global_position = team0_start_positions[team0_idx]
            else: # Fallback if not enough positions defined
                player.global_position = Vector2(-200, randi_range(-200, 200))
                printerr("Not enough start positions defined for Team 0 player: ", player.name)
            team0_idx += 1
        elif player_team_id == 1: # Explicitly check for team 1
             if team1_idx < team1_start_positions.size():
                player.global_position = team1_start_positions[team1_idx]
             else: # Fallback
                 player.global_position = Vector2(200, randi_range(-200, 200))
                 printerr("Not enough start positions defined for Team 1 player: ", player.name)
             team1_idx += 1
        # else: # Optional: Handle players with unexpected team IDs?
        #    printerr("Player with unexpected team ID found during reset: ", player.name, " Team: ", player_team_id)


        # Reset stamina, stun, and velocity safely
        # Check if property exists before getting/setting, using 'in' operator
        if "max_stamina" in player and "current_stamina" in player: 
            player.set("current_stamina", player.get("max_stamina"))
        else:
            printerr("Player missing stamina properties: ", player.name)

        if "stun_timer" in player:
            player.set("stun_timer", 0.0)
        else:
            printerr("Player missing stun_timer property: ", player.name)

        if "velocity" in player:
            player.set("velocity", Vector2.ZERO) # Crucial to stop movement
        else:
            printerr("Player missing velocity property: ", player.name)

# --- End of field.gd ---
