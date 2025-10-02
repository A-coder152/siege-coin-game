extends Node

enum GameState { READY, ANIMATING, DOUBLE_DECISION }

# --- Game state ---
var state: GameState = GameState.READY
var balance: int = 1000
var current_bet: int = 0
var choice: String = ""                # "heads" or "tails"
var pending_winnings: int = 0          # held while player decides DoN

var rng := RandomNumberGenerator.new()

# --- Node refs (adjust paths if your scene differs) ---
@onready var lbl_balance: Label       = $"UI/Root/Balance"
@onready var spin_bet: SpinBox        = $"UI/Root/BetRow/Bet"
@onready var btn_heads: Button        = $"UI/Root/PickRow/PickHeads"
@onready var btn_tails: Button        = $"UI/Root/PickRow/PickTails"
@onready var btn_flip: Button         = $"UI/Root/FlipBtn"
@onready var row_risk: Control        = $"UI/Root/RiskRow"
@onready var btn_double: Button       = $"UI/Root/RiskRow/DoubleBtn"
@onready var btn_cashout: Button      = $"UI/Root/RiskRow/CashOutBtn"
@onready var lbl_result: Label        = $"UI/Root/Result"
@onready var flip_bar: ProgressBar    = get_node_or_null("UI/Root/FlipBar") # optional

func _ready() -> void:
	rng.randomize()
	_update_balance_label()
	row_risk.visible = false
	lbl_result.text = "Pick Heads or Tails, set a bet, then Flip."
	_set_choice("")  # no selection yet
	# Wire signals in code so you don't have to connect in the editor
	btn_heads.pressed.connect(_on_pick_heads_pressed)
	btn_tails.pressed.connect(_on_pick_tails_pressed)
	btn_flip.pressed.connect(_on_flip_pressed)
	btn_double.pressed.connect(_on_double_pressed)
	btn_cashout.pressed.connect(_on_cashout_pressed)
	if flip_bar:
		flip_bar.visible = false
		flip_bar.value = 0

# --- UI helpers ---
func _update_balance_label() -> void:
	lbl_balance.text = "Balance: $" + str(balance)

func _set_choice(new_choice: String) -> void:
	choice = new_choice
	# Simple visual toggle: disable the unpicked button, enable the picked
	if new_choice == "heads":
		btn_heads.disabled = false
		btn_tails.disabled = true
	elif new_choice == "tails":
		btn_heads.disabled = true
		btn_tails.disabled = false
	else:
		btn_heads.disabled = false
		btn_tails.disabled = false

func _set_inputs_enabled(enabled: bool) -> void:
	btn_flip.disabled = not enabled
	btn_heads.disabled = not enabled if choice == "" else btn_heads.disabled
	btn_tails.disabled = not enabled if choice == "" else btn_tails.disabled
	spin_bet.editable = enabled

# --- Button callbacks ---
func _on_pick_heads_pressed() -> void:
	if state != GameState.READY:
		return
	_set_choice("heads")
	lbl_result.text = "Chosen: Heads."

func _on_pick_tails_pressed() -> void:
	if state != GameState.READY:
		return
	_set_choice("tails")
	lbl_result.text = "Chosen: Tails."

func _on_flip_pressed() -> void:
	if state != GameState.READY:
		return
	if choice == "":
		lbl_result.text = "Pick Heads or Tails first."
		return
	current_bet = int(spin_bet.value)
	if current_bet <= 0:
		lbl_result.text = "Bet must be > 0."
		return
	if current_bet > balance:
		lbl_result.text = "Bet exceeds balance."
		return
	
	balance -= current_bet
	_update_balance_label()

	# Start flip "animation"
	state = GameState.ANIMATING
	_set_inputs_enabled(false)
	row_risk.visible = false
	lbl_result.text = "Flipping…"
	if flip_bar:
		flip_bar.value = 0
		flip_bar.visible = true
		await _animate_progress(0.55) # ~0.55s fill

	# Resolve result
	var outcome: String = "heads" if (rng.randf() < 0.5) else "tails"
	if flip_bar:
		flip_bar.visible = false

	if outcome == choice:
		# Win → stash in pending_winnings; offer DoN
		pending_winnings = current_bet * 2
		lbl_result.text = "%s — You won $%d! Double or Cash Out?" % [outcome.capitalize(), pending_winnings]
		row_risk.visible = true
		state = GameState.DOUBLE_DECISION
	else:
		# Lose → deduct immediately
		_update_balance_label()
		lbl_result.text = "%s — You lost $%d." % [outcome.capitalize(), current_bet]
		state = GameState.READY
		choice = ""
		_set_inputs_enabled(true)

func _on_cashout_pressed() -> void:
	if state != GameState.DOUBLE_DECISION:
		return
	balance += pending_winnings
	_update_balance_label()
	lbl_result.text = "Banked $%d. Nice!" % pending_winnings
	pending_winnings = 0
	row_risk.visible = false
	state = GameState.READY
	choice = ""
	_set_inputs_enabled(true)

func _on_double_pressed() -> void:
	if state != GameState.DOUBLE_DECISION:
		return
	# Hide risk row during the double flip to prevent double-click spam
	row_risk.visible = false
	lbl_result.text = "Double or Nothing… flipping…"
	_set_inputs_enabled(false)
	state = GameState.ANIMATING

	if flip_bar:
		flip_bar.value = 0
		flip_bar.visible = true
		await _animate_progress(0.55)
		flip_bar.visible = false

	var outcome: String = "heads" if (rng.randf() < 0.5) else "tails"
	# For Double-or-Nothing, the player must match the ORIGINAL choice
	if outcome == choice:
		pending_winnings *= 2
		lbl_result.text = "%s — Success! Winnings now $%d. Double again or Cash Out?" % [
			outcome.capitalize(), pending_winnings
		]
		row_risk.visible = true
		state = GameState.DOUBLE_DECISION
		# Stay with inputs disabled except risk row; Flip remains disabled until DONE
		_set_inputs_enabled(false)
	else:
		lbl_result.text = "%s — Busted! You lost it all." % outcome.capitalize()
		pending_winnings = 0
		state = GameState.READY
		choice = ""
		_set_inputs_enabled(true)

# --- Utility animation (fake progress fill) ---
func _animate_progress(duration: float) -> void:
	# Simple time-based fill without Tween to keep it self-contained
	var t := 0.0
	var last := Time.get_ticks_msec()
	while t < duration:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		var dt := float(now - last) / 1000.0
		last = now
		t += dt
		if flip_bar:
			flip_bar.value = clamp((t / duration) * flip_bar.max_value, 0.0, flip_bar.max_value)
