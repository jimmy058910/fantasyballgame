# name_generator.gd - Autoload Singleton Script
extends Node

# --- Define File Paths ---
const HUMAN_FIRST_NAMES_PATH = "res://data/names/human_first.txt"
const HUMAN_LAST_NAMES_PATH = "res://data/names/human_last.txt"
const SYLVAN_FIRST_NAMES_PATH = "res://data/names/sylvan_first.txt"
const SYLVAN_LAST_NAMES_PATH = "res://data/names/sylvan_last.txt"
const GRYLL_FIRST_NAMES_PATH = "res://data/names/gryll_first.txt"
const GRYLL_LAST_NAMES_PATH = "res://data/names/gryll_last.txt"
const LUMINA_FIRST_NAMES_PATH = "res://data/names/lumina_first.txt"
const LUMINA_LAST_NAMES_PATH = "res://data/names/lumina_last.txt"
const UMBRA_FIRST_NAMES_PATH = "res://data/names/umbra_first.txt"
const UMBRA_LAST_NAMES_PATH = "res://data/names/umbra_last.txt"

# --- Declare Name List Arrays ---
var human_first_names: Array[String]
var human_last_names: Array[String]
var sylvan_first_names: Array[String]
var sylvan_last_names: Array[String]
var gryll_first_names: Array[String]
var gryll_last_names: Array[String]
var lumina_first_names: Array[String]
var lumina_last_names: Array[String]
var umbra_first_names: Array[String]
var umbra_last_names: Array[String]


func _ready():
    # Load all name lists from files when the game starts
    human_first_names = _load_names_from_file(HUMAN_FIRST_NAMES_PATH)
    human_last_names = _load_names_from_file(HUMAN_LAST_NAMES_PATH)
    sylvan_first_names = _load_names_from_file(SYLVAN_FIRST_NAMES_PATH)
    sylvan_last_names = _load_names_from_file(SYLVAN_LAST_NAMES_PATH)
    gryll_first_names = _load_names_from_file(GRYLL_FIRST_NAMES_PATH)
    gryll_last_names = _load_names_from_file(GRYLL_LAST_NAMES_PATH)
    lumina_first_names = _load_names_from_file(LUMINA_FIRST_NAMES_PATH)
    lumina_last_names = _load_names_from_file(LUMINA_LAST_NAMES_PATH)
    umbra_first_names = _load_names_from_file(UMBRA_FIRST_NAMES_PATH)
    umbra_last_names = _load_names_from_file(UMBRA_LAST_NAMES_PATH)

    # Initialize random number generator (important!)
    randomize()

# Helper function to load names from a text file (one name per line)
# (Keep this function exactly the same as before)
func _load_names_from_file(file_path: String) -> Array[String]:
    var names: Array[String] = []
    var file = FileAccess.open(file_path, FileAccess.READ)
    if FileAccess.get_open_error() == OK:
        while not file.eof_reached():
            var line = file.get_line().strip_edges() # Remove leading/trailing whitespace
            if not line.is_empty():
                names.append(line)
        file.close()
    else:
        printerr("Error opening name file: ", file_path)
    return names

# The main function to generate a name based on race
func generate_player_name(race: PlayerData.Race) -> String:
    var first_names: Array[String]
    var last_names: Array[String]

    # Select the correct name lists based on the race enum from PlayerData
    match race:
        PlayerData.Race.HUMAN:
            first_names = human_first_names
            last_names = human_last_names
        PlayerData.Race.SYLVAN:
            first_names = sylvan_first_names
            last_names = sylvan_last_names
        PlayerData.Race.GRYLL:
            first_names = gryll_first_names
            last_names = gryll_last_names
        PlayerData.Race.LUMINA:
            first_names = lumina_first_names
            last_names = lumina_last_names
        PlayerData.Race.UMBRA:
            first_names = umbra_first_names
            last_names = umbra_last_names
        _: # Default case
            printerr("Unknown race provided for name generation: ", race)
            first_names = human_first_names # Fallback to Human
            last_names = human_last_names

    # Ensure lists are not empty before picking
    if first_names.is_empty() or last_names.is_empty():
        var race_name = PlayerData.Race.keys()[race] # Get string name of the race enum
        printerr("Name list empty for race: ", race_name)
        return "Unnamed %s" % race_name # Fallback name includes race

    # Pick one random name from each list
    var first_name = first_names.pick_random()
    var last_name = last_names.pick_random()

    return "%s %s" % [first_name, last_name] # Combine first and last name