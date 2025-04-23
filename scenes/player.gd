extends CharacterBody2D

@export var team_id: int = 0 # 0 for Team A, 1 for Team B

var ball_node: Node2D = null # Variable to hold a reference to the ball

@export var base_speed: float = 150.0 # Speed in pixels per second
@export var max_stamina: float = 100.0 # Maximum stamina value
var current_stamina: float # Variable to track current stamina

# Called when the node enters the scene tree for the first time.
func _ready():
    current_stamina = max_stamina # Start with full stamina
    # Find the first node in the scene tree that's in the "ball" group
    ball_node = get_tree().get_first_node_in_group("ball")
    if ball_node == null:
        printerr("Player could not find the ball node!")
# --- End of code to add for now ---

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
    # --- Start of corrected physics process ---
    # Ensure ALL lines below this are indented ONE level relative to the 'func' line,
    # and nested blocks (like inside 'if') are indented further.

    # 1. Calculate stamina ratio (prevent division by zero)
    var stamina_ratio: float = 1.0
    if max_stamina > 0:
        # Ensure current_stamina doesn't go below 0 for calculation
        stamina_ratio = max(current_stamina, 0.0) / max_stamina

    # 2. Calculate effective speed based on stamina
    var effective_speed = base_speed * stamina_ratio

    # 3. Determine movement direction based on ball possession
    var direction = Vector2.ZERO
    var target_position = global_position # Default: stay put if no target found

    if ball_node != null: # Check if we found the ball node in _ready()
        # Safely get the current possessor from the ball node script
        # Assumes ball_node has a script attached with 'current_possessor' variable
        var possessor = ball_node.get("current_possessor") # Safer access

        if possessor != null and is_instance_valid(possessor): # Check if someone has the ball AND the node still exists
            # Safely get the possessor's team ID (if it exists on that node)
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
            else: # Opponent has the ball (or possessor has invalid/no team_id)
                # OPPONENT has the ball - target the possessor
                target_position = possessor.global_position
                # Only calculate direction if not already at the target
                if global_position.distance_squared_to(target_position) > 1.0:
                     direction = (target_position - global_position).normalized()

        else: # NO ONE has the ball (ball is loose)
            # Target the ball itself
            target_position = ball_node.global_position
            # Only calculate direction if not already at the target
            if global_position.distance_squared_to(target_position) > 1.0:
                direction = (target_position - global_position).normalized()
    # else: # Optional: Handle case where ball_node wasn't found in _ready()
        # print_debug("Player cannot find ball node to determine direction.")
        # direction = Vector2.ZERO # Stay put if no ball found


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

    # --- End of corrected physics process ---
