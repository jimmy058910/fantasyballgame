extends Node2D # Or Sprite2D if your root is the sprite

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

func _physics_process(_delta):
	if current_possessor != null:
		# Check if possessor still exists (might be deleted)
		if is_instance_valid(current_possessor):
			global_position = current_possessor.global_position + follow_offset
		else:
			# Possessor was removed, ball is free again
			current_possessor = null
			print("Possessor lost, ball is free") # Debug message
	# (Optional: Add code here later for when the ball IS free, e.g., basic physics or staying put)

# Call this function when a tackle is successful
# Inside ball.gd

func set_loose():
	if current_possessor != null:
		# Ensure this print exists
		print("BALL SCRIPT: ", current_possessor.name, " lost the ball due to tackle! Possessor set to null.")
		current_possessor = null
