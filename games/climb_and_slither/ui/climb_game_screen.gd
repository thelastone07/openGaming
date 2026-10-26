class_name ClimbGameScreen
extends Control
## The Climb and Slither game screen: board on the left, players and controls on the right.
## It shows what the controller tells it and sends the player's actions back (rule 12): it
## contains no game rules. Every batch goes through an EventTimeline, so animations never
## overlap and the screen always ends on the true state.
##
## Scene contract for every game's ui_scene: the root has `setup(controller, players)` (players
## are [{player_id, name}] in seat order) and the signal `leave_requested`.

signal leave_requested
## The host sent everyone back to the lobby (networked games).
signal game_ended

const BANNER_FADE: float = 0.25

var controller: GameController
var timeline: EventTimeline = EventTimeline.new()
var board_view: ClimbBoardView
var dice_view: ClimbDiceView
var roll_button: Button
var leaf_border: LeafBorder
var side_card: PaperCard
var menu_button: Button
var banner: Label
var presence_overlay: PresenceOverlay
var overlay: Control
var overlay_title: Label
var rematch_button: Button
var lobby_button: Button
var overlay_wait_label: Label
var overlay_menu_button: Button
var medallion: PawnMedallion
var confetti: Confetti
var player_rows: Dictionary = {}  # player_id -> {panel, square}

## Animation speed multiplier: always 1 in play. set_speed_by_label() exists for tests and tools.
var speed: float = 1.0
var names: Dictionary = {}
var _player_ids: Array[String] = []
var _view: Dictionary = {}
var _steps: Array[Dictionary] = []
var _step_index: int = 0
var _run_id: int = 0
var _ready_built: bool = false
var _pending_setup: bool = false
var _last_error: String = ""
var _players_box: VBoxContainer
var _margin: MarginContainer
var _row: HBoxContainer


func _ready() -> void:
	_build()
	_ready_built = true
	if _pending_setup:
		_connect_controller()


## Connects the screen to a game. `players` are [{player_id, name}] in seat order.
func setup(game_controller: GameController, players: Array) -> void:
	controller = game_controller
	_player_ids.clear()
	names.clear()
	for entry: Dictionary in players:
		_player_ids.append(entry["player_id"])
		names[entry["player_id"]] = str(entry["name"])
	if _ready_built:
		_connect_controller()
	else:
		_pending_setup = true


## The last error text the controller reported (for the player to read), or "".
func last_error() -> String:
	return _last_error


func current_view() -> Dictionary:
	return _view


# --- building the screen ------------------------------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back: ColorRect = ColorRect.new()
	back.color = Tokens.PAPER_CREAM
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	leaf_border = LeafBorder.new()
	add_child(leaf_border)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", Tokens.SPACE_L)
	_margin.add_child(_row)

	board_view = ClimbBoardView.new()
	board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board_view.custom_minimum_size = Vector2(320, 300)
	_row.add_child(board_view)

	banner = Label.new()
	banner.visible = false
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
	banner.add_theme_color_override("font_color", Tokens.PAPER_CREAM)
	var banner_style: StyleBoxFlat = StyleBoxFlat.new()
	banner_style.bg_color = Tokens.INDIGO
	banner_style.set_corner_radius_all(Tokens.RADIUS)
	banner_style.set_content_margin_all(Tokens.SPACE_M)
	banner_style.shadow_color = Color(Tokens.INK, 0.3)
	banner_style.shadow_size = 4
	banner_style.shadow_offset = Vector2(2, 4)
	banner.add_theme_stylebox_override("normal", banner_style)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_view.add_child(banner)

	side_card = PaperCard.new()
	side_card.back_color = Tokens.DEEP_TEAL
	side_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	side_card.custom_minimum_size = Vector2(280, 0)
	_row.add_child(side_card)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", Tokens.SPACE_S)
	side_card.add_child(column)

	var title: Label = Label.new()
	title.text = "Climb and Slither"
	title.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", Tokens.INDIGO)
	column.add_child(title)

	var players_box: VBoxContainer = VBoxContainer.new()
	players_box.name = "Players"
	players_box.add_theme_constant_override("separation", 4)
	column.add_child(players_box)
	_players_box = players_box

	dice_view = ClimbDiceView.new()
	dice_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(dice_view)

	roll_button = Button.new()
	roll_button.text = "Roll"
	roll_button.theme_type_variation = "PrimaryButton"
	roll_button.custom_minimum_size = Vector2(0, 52)
	roll_button.pressed.connect(_on_roll_pressed)
	column.add_child(roll_button)

	menu_button = Button.new()
	menu_button.text = "Back to menu"
	menu_button.theme_type_variation = "CreamButton"
	menu_button.pressed.connect(_on_menu_pressed)
	column.add_child(menu_button)

	presence_overlay = PresenceOverlay.new()
	presence_overlay.leave_requested.connect(func() -> void: leave_requested.emit())
	add_child(presence_overlay)
	_build_overlay()
	resized.connect(_fit)
	_fit()
	_update_controls()


## The board takes all the height it can and only the width it needs, and the side card sits right
## next to it, so there is no empty room between them. The margin keeps content clear of the leaves.
func _fit() -> void:
	if _margin == null or board_view == null:
		return
	var short_side: float = minf(size.x, size.y)
	var edge: int = roundi(clampf(short_side * 0.05, 20.0, 56.0))
	for side: String in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, edge)
	var height: float = maxf(300.0, size.y - 2.0 * edge)
	var layout: ClimbBoardLayout = board_view.layout if board_view.layout != null else ClimbBoardLayout.new(100, 10, ClimbBoardView.STRIP_GAP_CELLS)
	var wanted: float = height * layout.aspect(ClimbBoardView.FRAME_CELLS) + 2.0 * ClimbBoardView.MARGIN
	var room: float = size.x - 2.0 * edge - side_card.get_combined_minimum_size().x - float(Tokens.SPACE_L)
	board_view.custom_minimum_size.x = clampf(wanted, 320.0, maxf(320.0, room))


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(Tokens.INK, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	confetti = Confetti.new()
	confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(confetti)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card: PaperCard = PaperCard.new()
	card.back_color = Tokens.FOREST_GREEN
	card.back_offset = Vector2(10, 12)
	center.add_child(card)
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var caption: Label = Label.new()
	caption.text = "Game over"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE)
	caption.add_theme_color_override("font_color", Tokens.INDIGO)
	box.add_child(caption)
	medallion = PawnMedallion.new()
	medallion.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(medallion)
	overlay_title = Label.new()
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_title.add_theme_font_size_override("font_size", Tokens.FONT_SIZE_TITLE - 2)
	overlay_title.add_theme_color_override("font_color", Tokens.INDIGO)
	box.add_child(overlay_title)
	rematch_button = Button.new()
	rematch_button.text = "Play again"
	rematch_button.theme_type_variation = "PrimaryButton"
	rematch_button.pressed.connect(_on_rematch_pressed)
	box.add_child(rematch_button)
	lobby_button = Button.new()
	lobby_button.text = "Back to lobby"
	lobby_button.pressed.connect(func() -> void: controller.end_game())
	box.add_child(lobby_button)
	overlay_wait_label = Label.new()
	overlay_wait_label.text = "Waiting for the host..."
	overlay_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(overlay_wait_label)
	overlay_menu_button = Button.new()
	overlay_menu_button.text = "Back to menu"
	overlay_menu_button.theme_type_variation = "CreamButton"
	overlay_menu_button.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(overlay_menu_button)
	add_child(overlay)


## The player's colour as the paper-cut palette has it.
static func _tint_of(view: Dictionary, player_id: String) -> Color:
	for entry: Dictionary in view.get("players", []):
		if entry["player_id"] == player_id:
			match str(entry["color"]):
				"red":
					return Tokens.PLAYER_RED
				"blue":
					return Tokens.PLAYER_BLUE
				"green":
					return Tokens.PLAYER_GREEN
				"yellow":
					return Tokens.PLAYER_YELLOW
	return Tokens.SAFFRON


# --- connecting to the game --------------------------------------------------------------------------

func _connect_controller() -> void:
	_pending_setup = false
	controller.batch_ready.connect(timeline.push)
	controller.action_rejected.connect(_on_rejected)
	controller.ended.connect(func() -> void: game_ended.emit())
	controller.presence_changed.connect(func(_info: Dictionary) -> void: _update_controls())
	presence_overlay.setup(controller)
	timeline.event_started.connect(_on_event_started)
	timeline.settled.connect(_on_settled)
	timeline.snapped.connect(_on_snapped)
	var existing: Dictionary = controller.latest_view()
	if not existing.is_empty():
		_on_snapped(existing)


func _on_event_started(event: Dictionary, _shown: Dictionary) -> void:
	_steps = ClimbAnimationPlan.steps_for(event, names)
	_step_index = 0
	_run_id += 1
	_run_next(_run_id)


func _run_next(run_id: int) -> void:
	if run_id != _run_id:
		return
	if _step_index >= _steps.size():
		timeline.event_finished()
		return
	var step: Dictionary = _steps[_step_index]
	_step_index += 1
	var advance: Callable = func() -> void:
		_refresh_squares()
		_run_next(run_id)
	var seconds: float = 0.0 if speed <= 0.0 else float(step["duration"]) / speed
	match str(step["op"]):
		"dice":
			dice_view.tumble(step["dice"], seconds, advance)
		"banner":
			_show_banner(str(step["text"]), seconds, advance)
		"turn":
			_highlight_turn(str(step["player_id"]))
			advance.call()
		_:
			board_view.animate(step, speed, advance)


func _on_settled(view: Dictionary) -> void:
	_show_view(view)


func _on_snapped(view: Dictionary) -> void:
	_run_id += 1  # whatever was half-played is dropped; late callbacks are ignored
	board_view.cancel_animation()
	banner.visible = false
	dice_view.show_faces(_roll_dice(view))
	_show_view(view)


func _on_rejected(error: Dictionary) -> void:
	_last_error = str(error.get("message", error.get("code", "")))
	_update_controls()


# --- showing a view ---------------------------------------------------------------------------------------

func _show_view(view: Dictionary) -> void:
	_view = view
	_last_error = ""
	if not _view.is_empty():
		_ensure_board(view)
		board_view.set_positions(view["positions"])
		_rebuild_rows(view)
	_highlight_turn(controller.rules().current_player(view) if not view.is_empty() else "")
	_refresh_squares()
	_update_controls()
	_update_overlay()


func _ensure_board(view: Dictionary) -> void:
	if board_view.board.is_empty() or board_view.board != view["board"] or _colors_changed(view):
		board_view.setup(view["board"], view["players"], view["positions"])
		_fit()


func _colors_changed(view: Dictionary) -> bool:
	return board_view.pawn_sprites.size() != (view["players"] as Array).size()


func _rebuild_rows(view: Dictionary) -> void:
	if player_rows.size() == (view["players"] as Array).size():
		return
	for child: Node in _players_box.get_children():
		_players_box.remove_child(child)
		child.queue_free()
	player_rows.clear()
	for entry: Dictionary in view["players"]:
		var id: String = entry["player_id"]
		var panel: PanelContainer = PanelContainer.new()
		var row: HBoxContainer = HBoxContainer.new()
		panel.add_child(row)
		var pawn: TextureRect = TextureRect.new()
		pawn.texture = load(ClimbArt.pawn_path(entry["color"]))
		pawn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pawn.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pawn.custom_minimum_size = Vector2(32, 40)
		row.add_child(pawn)
		var name_label: Label = Label.new()
		name_label.text = str(names.get(id, id))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size.x = 0.0
		row.add_child(name_label)
		# Fixed width sized for the longest text, so "Start" -> "Square 100" never resizes the card
		# (and with it the board).
		var square: Label = Label.new()
		square.text = "Square 100"
		square.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		square.custom_minimum_size.x = square.get_minimum_size().x
		square.text = ""
		row.add_child(square)
		_players_box.add_child(panel)
		player_rows[id] = {"panel": panel, "square": square}


func _refresh_squares() -> void:
	for id: String in player_rows:
		var square: int = int(board_view.square_of(id))
		(player_rows[id]["square"] as Label).text = "Start" if square == 0 else "Square %d" % square


func _highlight_turn(player_id: String) -> void:
	for id: String in player_rows:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Tokens.SAFFRON.lerp(Tokens.PAPER_CREAM, 0.4) if id == player_id else Color(0, 0, 0, 0)
		style.set_corner_radius_all(Tokens.RADIUS)
		style.set_content_margin_all(4)
		(player_rows[id]["panel"] as PanelContainer).add_theme_stylebox_override("panel", style)


func _roll_dice(view: Dictionary) -> Array:
	var last: Dictionary = view.get("last_roll", {})
	return last.get("dice", []) if not last.is_empty() else []


# --- controls -------------------------------------------------------------------------------------------------

## True when the roll button should work: a game is on, nothing is animating, it is not over.
func can_roll() -> bool:
	if controller == null or _view.is_empty() or controller.rules().is_finished(_view) or timeline.is_busy():
		return false
	if bool(controller.presence()["paused"]):
		return false  # the host is waiting for someone
	var me: String = controller.local_player_id()  # "" on a hot-seat computer: everyone plays here
	return me == "" or me == controller.rules().current_player(_view)


func _update_controls() -> void:
	if roll_button == null:
		return
	var who: String = controller.rules().current_player(_view) if controller != null and not _view.is_empty() else ""
	roll_button.disabled = not can_roll()
	var me: String = controller.local_player_id() if controller != null else ""
	if who == "":
		roll_button.text = "Roll"
	elif me == "" or me == who:
		roll_button.text = "Roll for %s" % str(names.get(who, who)) if me == "" else "Your turn: roll"
	else:
		roll_button.text = "%s is rolling..." % str(names.get(who, who))


func _update_overlay() -> void:
	var finished: bool = controller != null and not _view.is_empty() and controller.rules().is_finished(_view) and not timeline.is_busy()
	overlay.visible = finished
	if finished:
		var winner: String = controller.rules().winner(_view)
		overlay_title.text = "%s wins!" % str(names.get(winner, winner))
		medallion.color = _tint_of(_view, winner)
		confetti.reseed(hash(winner) & 0xFFFF)
		var hotseat: bool = controller.local_player_id() == ""
		var is_host: bool = controller.can_rematch()
		rematch_button.visible = is_host
		lobby_button.visible = is_host and not hotseat
		overlay_wait_label.visible = not hotseat and not is_host
		overlay_menu_button.visible = hotseat
		if is_host:
			rematch_button.grab_focus()


func _on_roll_pressed() -> void:
	if can_roll():
		controller.submit_action({"type": "roll"})
		_update_controls()


## Shows the true state now, dropping any animation that is playing.
func skip() -> void:
	timeline.skip()


func set_speed_by_label(label: String) -> void:
	speed = float(ClimbAnimationPlan.SPEEDS.get(label, 1.0))
	if speed <= 0.0 and timeline.is_busy():
		skip()


## The menu button asks first while a game is running (design section 13); a finished game just leaves.
func _on_menu_pressed() -> void:
	if _view.is_empty() or controller.rules().is_finished(_view):
		leave_requested.emit()
		return
	var hotseat: bool = controller.local_player_id() == ""
	var host: bool = not hotseat and controller.can_rematch()
	var question: Dictionary = ConfirmDialog.leave_hotseat() if hotseat else (ConfirmDialog.end_game_for_all() if host else ConfirmDialog.leave_game())
	ConfirmDialog.ask(self, question, _on_leave_choice)


func _on_leave_choice(id: String) -> void:
	if id == "lobby":
		controller.end_game()
	elif id == "leave" or id == "close":
		leave_requested.emit()


func _on_rematch_pressed() -> void:
	if controller.can_rematch():
		controller.rematch()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
		if can_roll():
			_on_roll_pressed()
		elif timeline.is_busy():
			skip()
		get_viewport().set_input_as_handled()


func _show_banner(text: String, seconds: float, done: Callable) -> void:
	if seconds <= 0.0 or not is_inside_tree():
		done.call()
		return
	banner.text = text
	banner.visible = true
	banner.reset_size()
	banner.position = Vector2((board_view.size.x - banner.size.x) / 2.0, board_view.size.y * 0.06)
	var run_id: int = _run_id
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if run_id == _run_id:
			banner.visible = false
			done.call())
