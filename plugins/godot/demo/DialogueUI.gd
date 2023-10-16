extends Control

var options = []

func _ready():
  $Center/VBox/StartButton.pressed.connect(_on_start_button_pressed)
  $Center/VBox/HBox/NextButton.pressed.connect(_on_next_button_pressed)
  $AlternisDialogue.function_called.connect(_on_dialogue_function_called)

func _on_dialogue_function_called(dialogue: Node, function: String):
  match function:
    "ask player name":
      var label = Label.new()
      label.text = "Enter your name:"
      $Center/VBox.add_child(label)

      var input = LineEdit.new()
      $Center/VBox.add_child(input)
      input.text_submitted.connect(
        func(new_text):
          $AlternisDialogue.set_variable_string("name", new_text)
          input.queue_free()
          label.queue_free()
          step()
      )

func step():
  $Center/VBox/Speaker.visible = true
  $Center/VBox/HBox.visible = true

  for cur_opt in options:
    cur_opt.queue_free()

  options = []

  var result = $AlternisDialogue.step()
  print(result)

  if result.has("line"):
    $Center/VBox/Speaker.text = result.line.speaker
    $Center/VBox/HBox/Text.visible = true
    $Center/VBox/HBox/Text.text = result.line.text

  elif result.has("options"):
    $Center/VBox/Speaker.text = result.options.texts[0].speaker

    $Center/VBox/HBox/Text.visible = false

    for i in range(result.options.texts.size()):
      var new_opt = result.options.texts[i]
      var id = result.options.ids[i]
      var opt_btn = Button.new()
      opt_btn.text = new_opt.text
      var on_press = func():
        $AlternisDialogue.reply(id)
        step()
      opt_btn.pressed.connect(on_press)
      # FIXME: this adds them in reverse order which is weird
      $Center/VBox/HBox/Text.add_sibling(opt_btn)
      options.append(opt_btn)

  elif result.has("done"):
    $Center.visible = false

  elif result.has("function_called"):
    $Center/VBox/Speaker.visible = false
    $Center/VBox/HBox.visible = false
  # note that function_called is handled/skipped by the extension and not reachable

func _on_next_button_pressed():
  step()

func _on_start_button_pressed():
  $Center/VBox/StartButton.visible = false
  step()
