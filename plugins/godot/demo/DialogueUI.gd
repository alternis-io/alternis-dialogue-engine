extends Control

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.
	$Button.pressed.connect(_on_button_pressed)

func _on_button_pressed():
	var line = $AlternisDialogue.step()
	print(line)
	$Speaker.text = line.line.speaker
	$Text.text = line.line.text
