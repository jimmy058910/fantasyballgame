# field.gd - Full version with custom starting positions (May 15th)
extends Node2D

# --- References ---
@onready var Team0_EndZone: Area2D = $Team0_EndZone # User confirmed name
@onready var Team1_EndZone: Area2D = $Team1_EndZone # User confirmed name
@onready var ball = $Ball # Adjust path if needed
@onready var score_label: Label = $CanvasLayer/ScoreLabel # Adjust path if needed

# --- Score Variables ---
var team_0_score: int = 0
var team_1_score: int = 0

# --- START POSITION ARRAYS (User Defined) ---
# Team 0 (Starts Left, assuming Players 1-6)
const TEAM0_DEFAULT_START_POSITIONS: Array[Vector2] = [
    Vector2(-227, 105),  # Player 1
    Vector2(-222, -128), # Player 2
    Vector2(-409, -264), # Player 3
    Vector2(-479, -2),   # Player 4 (Y was -Y -2, assuming -2)
    Vector2(-422, 280),  # Player 5
    Vector2(-612, -2)    # Player 6
]
# Team 1 (Starts Right, assuming Players 7-12)
const TEAM1_DEFAULT_START_POSITIONS: Array[Vector2] = [
    Vector2(53, -87),    # Player 7
    Vector2(154, 92),    # Player 8
    Vector2(412, -343),  # Player 9
    Vector2(401, 310),   # Player 10
    Vector2(431, -2),    # Player 11
    Vector2(320, 0)      # Player 12
]
# --- END POSITION ARRAYS ---

# Fallback starting X if not enough positions in arrays (less critical if arrays are correct size)
const TEAM_0_FALLBACK_START_X: float = -300.0
const TEAM_1_FALLBACK_START_X: float = 300.0
const PLAYER_FALLBACK_Y_SPREAD: float = 100.0

const BALL_START_POS = Vector2.ZERO

# --- Initialization ---

# Dictionary to store targeted defenders: {defender_node: blocker_node}
var currently_targeted_defenders = {}

func get_targeted_defenders() -> Dictionary:
    return currently_targeted_defenders

func set_target_for_blocker(defender: Node, blocker: Node):
    currently_targeted_defenders[defender] = blocker
    # print_debug("Field: Blocker ", blocker.name, " targeted ", defender.name)

func remove_target_for_blocker(defender: Node):
    if currently_targeted_defenders.has(defender):
        # var blocker = currently_targeted_defenders[defender]
        currently_targeted_defenders.erase(defender)
        # print_debug("Field: Blocker ", blocker.name if is_instance_valid(blocker) else "N/A", " UN-targeted ", defender.name)
    # else:
        # print_debug("Field: Attempted to remove non-targeted defender ", defender.name)

func is_defender_targeted(defender: Node) -> bool:
    return currently_targeted_defenders.has(defender)

func get_blocker_for_defender(defender: Node) -> Node:
    if is_defender_targeted(defender):
        return currently_targeted_defenders[defender]
    return null

func _ready():
    # Connect signals from score areas via code
    if Team0_EndZone:
        if not Team0_EndZone.is_connected("body_entered", Callable(self, "_on_score_area_body_entered")):
            Team0_EndZone.body_entered.connect(_on_score_area_body_entered.bind(Team0_EndZone))
            # print_debug("Field: Connected Team0EndZone signal via script.")
        # else:
            # push_warning("Field: Team0EndZone signal already connected (expected disconnection in editor).")
    else:
        printerr("Field Error: Missing Team0EndZone node!")

    if Team1_EndZone:
        if not Team1_EndZone.is_connected("body_entered", Callable(self, "_on_score_area_body_entered")):
            Team1_EndZone.body_entered.connect(_on_score_area_body_entered.bind(Team1_EndZone))
            # print_debug("Field: Connected Team1EndZone signal via script.")
        # else:
            # push_warning("Field: Team1EndZone signal already connected (expected disconnection in editor).")
    else:
        printerr("Field Error: Missing Team1EndZone node!")

    # Initial Setup
    update_score_display()
    reset_play() # Call reset_play on ready if you want players positioned by code at game start


# --- Score Detection ---
func _on_score_area_body_entered(body: Node, area_node: Area2D):
    if not body.is_in_group("players") or not body.has_ball:
        return

    if area_node == Team0_EndZone and body.team_id == 1: # Team 1 scores in Team 0's (Left) zone
        team_1_score += 1
        print("SCORE TEAM 1! Total: ", team_1_score)
    elif area_node == Team1_EndZone and body.team_id == 0: # Team 0 scores in Team 1's (Right) zone
        team_0_score += 1
        print("SCORE TEAM 0! Total: ", team_0_score)
    else:
        return # Not a valid score condition

    update_score_display()
    # print("Resetting Play...") # Reduce noise
    reset_play()

# --- Score Display Update ---
func update_score_display():
    if score_label:
        score_label.text = "Team 0: %d - Team 1: %d" % [team_0_score, team_1_score]
    else:
        printerr("Field Error: ScoreLabel node not found or path incorrect!")


# --- Reset Logic ---
func reset_play():
    # print_debug("Field: Resetting play...") # Reduce noise
    # 1. Make the ball loose BEFORE moving players
    if ball != null and is_instance_valid(ball.current_possessor):
        # print_debug("Field: Forcing ball loose for reset.") # Reduce noise
        ball.set_loose(Vector2.ZERO) 
        await get_tree().physics_frame
    elif ball == null:
        printerr("Field Error: Cannot find ball node in reset_play!")
        return

    # 2. Reset Ball Position & State
    if ball != null:
        ball.freeze = true
        ball.global_position = BALL_START_POS
        ball.linear_velocity = Vector2.ZERO
        ball.angular_velocity = 0.0
        ball.set_deferred("freeze", false)
        ball.pass_reception_timer = 0.0
        ball._is_arriving_from_pass = false
        ball.intended_receiver = null
        if ball.pickup_area:
            ball.pickup_area.set_deferred("monitoring", true)
        # print_debug("Field: Ball reset.") # Reduce noise

    # 3. Reset Players
    var players = get_tree().get_nodes_in_group("players")
    var team0_player_index = 0
    var team1_player_index = 0

    # print_debug("Field: Resetting %d players..." % players.size()) # Reduce noise
    for player_node in players:
        if not is_instance_valid(player_node): continue

        var target_pos: Vector2
        if player_node.team_id == 0: # Team 0 (Starts Left)
            if team0_player_index < TEAM0_DEFAULT_START_POSITIONS.size():
                target_pos = TEAM0_DEFAULT_START_POSITIONS[team0_player_index]
                team0_player_index += 1
            else: 
                printerr("Warning: Not enough start positions defined for Team 0. Using fallback for %s." % player_node.name)
                target_pos = Vector2(TEAM_0_FALLBACK_START_X, (team0_player_index - TEAM0_DEFAULT_START_POSITIONS.size()) * PLAYER_FALLBACK_Y_SPREAD - (PLAYER_FALLBACK_Y_SPREAD * 1.5) )
                team0_player_index += 1 
        elif player_node.team_id == 1: # Team 1 (Starts Right)
            if team1_player_index < TEAM1_DEFAULT_START_POSITIONS.size():
                target_pos = TEAM1_DEFAULT_START_POSITIONS[team1_player_index]
                team1_player_index += 1
            else: 
                printerr("Warning: Not enough start positions defined for Team 1. Using fallback for %s." % player_node.name)
                target_pos = Vector2(TEAM_1_FALLBACK_START_X, (team1_player_index - TEAM1_DEFAULT_START_POSITIONS.size()) * PLAYER_FALLBACK_Y_SPREAD - (PLAYER_FALLBACK_Y_SPREAD * 1.5) )
                team1_player_index += 1
        else: # Should not happen
            printerr("Player %s has invalid team_id %s during reset!" % [player_node.name, player_node.team_id])
            target_pos = player_node.global_position # Keep current position if invalid team
            
        player_node.global_position = target_pos
        player_node.velocity = Vector2.ZERO

        if player_node.has_method("reset_state"):
            player_node.reset_state()
        else:
            printerr("Player %s missing reset_state method!" % player_node.name)

    # print_debug("Field: Player reset complete.") # Reduce noise

    # Ensure currently_targeted_defenders is cleared on reset
    currently_targeted_defenders.clear()
