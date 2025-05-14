# field.gd (Attach to the parent Field Node2D)
extends Node2D

# --- References ---
# Variable names now match the node names exactly
@onready var Team0_EndZone: Area2D = $Team0_EndZone
@onready var Team1_EndZone: Area2D = $Team1_EndZone
@onready var ball = $Ball # Adjust path if needed
@onready var score_label: Label = $CanvasLayer/ScoreLabel # Adjust path if needed

# --- Score Variables ---
var team_0_score: int = 0
var team_1_score: int = 0

# --- Starting Positions (EXAMPLE - Adjust as needed!) ---
const TEAM_0_START_X: float = -300.0  # Left side
const TEAM_1_START_X: float = 300.0 # Right side
const PLAYER_START_Y_OFFSET: float = 150.0 # How far players spread vertically
const BALL_START_POS = Vector2.ZERO

# --- Initialization ---
func _ready():
	# Connect signals from score areas via code
	# Uses bind() to pass the specific area node to the handler
	if Team0_EndZone: # Use correct variable name
		# Check if ALREADY connected (e.g. from editor) before connecting in code
		if not Team0_EndZone.is_connected("body_entered", Callable(self, "_on_score_area_body_entered")): # Use correct variable name
			# Connect Team 0 Zone signal, bind the node itself as an argument
			Team0_EndZone.body_entered.connect(_on_score_area_body_entered.bind(Team0_EndZone)) # Use correct variable name
			print_debug("Field: Connected Team0EndZone signal via script.")
		else:
			push_warning("Field: Team0EndZone signal already connected (expected disconnection in editor).")
	else:
		printerr("Field Error: Missing Team0EndZone node!")

	if Team1_EndZone: # Use correct variable name
		if not Team1_EndZone.is_connected("body_entered", Callable(self, "_on_score_area_body_entered")): # Use correct variable name
			# Connect Team 1 Zone signal, bind the node itself as an argument
			Team1_EndZone.body_entered.connect(_on_score_area_body_entered.bind(Team1_EndZone)) # Use correct variable name
			print_debug("Field: Connected Team1EndZone signal via script.")
		else:
			push_warning("Field: Team1EndZone signal already connected (expected disconnection in editor).")
	else:
		printerr("Field Error: Missing Team1EndZone node!")

	# Initial Setup
	update_score_display()

# --- Score Detection ---
# SINGLE handler function for BOTH score areas
# 'area_node' argument tells us which specific Area2D triggered the signal
func _on_score_area_body_entered(body: Node, area_node: Area2D):
	# Check if the body is a player, has the ball
	if not body.is_in_group("players") or not body.has_ball:
		return # Exit if not a player with the ball

	# REMOVED var scoring_team_id = -1

	# Check which zone was entered and if the entering player is on the opposing team
	if area_node == Team0_EndZone and body.team_id == 1:
		# Team 1 scored in Team 0's zone (X = -750)
		# REMOVED scoring_team_id = 1
		team_1_score += 1
		print("SCORE TEAM 1! Total: ", team_1_score)

	elif area_node == Team1_EndZone and body.team_id == 0:
		# Team 0 scored in Team 1's zone (X = 750)
		# REMOVED scoring_team_id = 0
		team_0_score += 1
		print("SCORE TEAM 0! Total: ", team_0_score)
	else:
		# Player entered own score zone or invalid team ID somehow
		return # Exit if not a valid score condition

	# If we reach here, a valid score occurred
	update_score_display()
	print("Resetting Play...")
	reset_play()

# --- Score Display Update ---
func update_score_display():
	if score_label:
		score_label.text = "Team 0: %d - Team 1: %d" % [team_0_score, team_1_score]
	else:
		printerr("Field Error: ScoreLabel node not found or path incorrect!")

# --- Reset Logic ---
func reset_play():
	print_debug("Field: Resetting play...")
	# 1. Make the ball loose BEFORE moving players
	if ball != null and is_instance_valid(ball.current_possessor):
		print_debug("Field: Forcing ball loose for reset.")
		ball.set_loose(Vector2.ZERO) # Pass zero velocity for a neutral drop/bounce
		# Wait one physics frame to allow deferred calls in set_loose to process
		await get_tree().physics_frame # Make sure this line is present
	elif ball == null:
		printerr("Field Error: Cannot find ball node in reset_play!")
		return # Cannot proceed without ball

	# 2. Reset Ball Position & State
	if ball != null: # Check again in case it became null somehow (unlikely)
		ball.freeze = true # Freeze immediately before setting position
		ball.global_position = BALL_START_POS
		ball.linear_velocity = Vector2.ZERO
		ball.angular_velocity = 0.0
		ball.set_deferred("freeze", false) # Unfreeze deferred
		ball.pass_reception_timer = 0.0 # Reset pass timer
		ball._is_arriving_from_pass = false # Reset pass arrival flag
		ball.intended_receiver = null # Reset intended receiver
		if ball.pickup_area: # Ensure monitoring is on after reset
			ball.pickup_area.set_deferred("monitoring", true)
		print_debug("Field: Ball reset.")

	# 3. Reset Players
	var players = get_tree().get_nodes_in_group("players")
	var team_0_count = 0
	var team_1_count = 0
	var num_players_per_team = players.size() / 2.0 # Use float for division

	print_debug("Field: Resetting %d players..." % players.size())
	for player_node in players: # Using player_node here
		if not is_instance_valid(player_node): continue

		# Simple reset positioning - arrange in columns on their side
		var start_x_base = TEAM_0_START_X if player_node.team_id == 0 else TEAM_1_START_X # Team 0 Left, Team 1 Right
		var player_index_in_team = 0
		if player_node.team_id == 0:
			player_index_in_team = team_0_count
			team_0_count += 1
		else: # Assuming team_id == 1
			player_index_in_team = team_1_count
			team_1_count += 1

		# Example layout: Spread players vertically, centered around Y=0
		var y_pos = (player_index_in_team - (num_players_per_team / 2.0) + 0.5) * PLAYER_START_Y_OFFSET
		player_node.global_position = Vector2(start_x_base, y_pos)
		player_node.velocity = Vector2.ZERO # Reset velocity

		# Call reset function on the player script
		# player_node.reset_state() ALREADY sets the player's state internally.
		if player_node.has_method("reset_state"):
			player_node.reset_state()
		else:
			printerr("Player %s missing reset_state method!" % player_node.name)
		
		# --- REMOVE THE FOLLOWING LINES THAT CAUSE ERRORS ---
		# if player_node.has_method("set_state"): # This was redundant
		#     player_node.set_state(PlayerState.IDLE) # PlayerState not known here
		# else:
		#     player_node.current_state = PlayerState.IDLE # PlayerState not known here
		# ---

	print_debug("Field: Player reset complete.")
