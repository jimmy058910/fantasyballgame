# Defines the data structure for a single player in the game.
# Using Resource allows easy saving, loading, and management.
extends Resource
class_name PlayerData

# --- Basic Identification ---
@export var player_name: String = "New Player"
@export var age: int = 18
# Consider adding a unique ID later if needed, e.g.:
# var player_id: String = "" # Generate this uniquely when created

# --- Race ---
# Using an Enum is cleaner than just a string for predefined races
enum Race { GRYLL, HUMAN, SYLVAN, LUMINA, UMBRA } # Add all your planned races here!
@export var race: Race = Race.HUMAN

# --- Core Attributes (Scale 1-40) ---
@export_group("Attributes") # Groups fields in the Godot Inspector
@export_range(1, 40) var speed: int = 10
@export_range(1, 40) var power: int = 10
@export_range(1, 40) var throwing: int = 10
@export_range(1, 40) var catching: int = 10
@export_range(1, 40) var kicking: int = 10 # Define what this impacts (kickoffs? field goals?)
@export_range(1, 40) var stamina: int = 10 # Max stamina attribute
@export_range(1, 40) var leadership: int = 10
@export_range(1, 40) var awareness: int = 10
@export_range(1, 40) var agility: int = 10

# --- Potential (Scale 0.0 - 5.0, with 0.5 steps for half-stars) ---
# Decide which attributes have a potential rating
@export_group("Potential")
@export_range(0.0, 5.0, 0.5) var speed_potential: float = 2.5
@export_range(0.0, 5.0, 0.5) var power_potential: float = 2.5
# ... Add potential ratings for other relevant attributes ...
@export_range(0.0, 5.0, 0.5) var agility_potential: float = 2.5

# --- Status & Contract ---
@export_group("Status")
@export var current_stamina_level: int = 100 # Current % or absolute value? Define max based on stamina attr?
@export var salary: int = 1000 # Credits per season?
@export var is_injured: bool = false
@export var injury_days_remaining: int = 0 # Or store injury type resource?

# --- Inventory Slots (Helmet, Chest, Shoes, Gloves) ---
# These will likely hold references to ItemData resources later.
# For now, we can define them, maybe exporting temporarily as placeholders.
@export_group("Equipment")
@export var equipped_helmet = null # : ItemData # Add type hint later
@export var equipped_chest = null # : ItemData
@export var equipped_shoes = null # : ItemData
@export var equipped_gloves = null # : ItemData

# --- Abilities (Max 3) ---
# This will hold references to AbilityData resources later.
@export_group("Abilities")
# This line is likely okay because 'Array' is a valid type provided.
@export var learned_abilities: Array # [AbilityData] # Add type hint later

# --- Career / Stats (Optional here, maybe separate object?) ---
# Could add vars like games_played, total_scores, awards_won etc.


# --- Initialization Function (Optional) ---
# You might want a function to set initial values, especially non-exported ones
# func _init(p_name = "New Player", p_age = 18, ...):
#     player_name = p_name
#     age = p_age
#     # ... set other defaults ...
#     player_id = generate_unique_id() # Need a helper function for this

# --- Future Functions ---
# placeholder for functions like: age_player(), apply_training(), calculate_market_value(), etc.