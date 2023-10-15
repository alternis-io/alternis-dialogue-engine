extends Control

func _ready():
  $Center/VBox/HBox/NextButton.pressed.connect(_on_button_pressed)

var options = []

func _on_button_pressed():
  step()

func step():
  for cur_opt in options:
    cur_opt.queue_free()

  options = []

  var result = $AlternisDialogue.step()
  print(result)

  if result.has("line"):
    $Center/VBox/Speaker.text = result.line.speaker
    $Center/VBox/HBox/Text.visible = true;
    $Center/VBox/HBox/Text.text = result.line.text

  elif result.has("options"):
    $Center/VBox/Speaker.text = result.options.texts[0].speaker

    $Center/VBox/HBox/Text.visible = false;

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

  elif result.has("function_called"):
    pass

  elif result.has("done"):
    pass
