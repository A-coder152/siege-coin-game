extends Control

# ==== GAME STATE ====
enum GameState { READY, ANIMATING, DOUBLE_DECISION }

var state: GameState = GameState.READY

var balance: int = 1000
var current_bet: int = 0
var pending_winnings: int = 0

# Core prediction
var seq_len: int = 1                                # number of flips to predict (1..5)
var predicted_seq: Array[String] = ["heads"]        # up to 5, e.g., ["heads","tails","heads"]

# Streaks & jackpot
var win_streak: int = 0                             # base-game wins in a row
var don_streak: int = 0                             # successful Double-or-Nothing chain
var jackpot: int = 0
const JACKPOT_TAX := 0.05                           # 5% of each base bet goes into jackpot

# Side bet (“same as last outcome”)
var last_outcome: String = ""                       # result of the most recent flip
const SIDE_MULT := 1.9                              # payout multiplier for side bet

# Coin types (bias + base payout per single correct flip)
var coin_heads_bias: float = 0.5
var coin_single_mult: float = 2.0                   # fair coin pays 2x per flip; others adjust

var rng := RandomNumberGenerator.new()

# ==== NODE REFS (adjust if your scene differs) ====
@onready var lbl_balance: Label          = $Balance
@onready var lbl_result: Label           = $Result
@onready var lbl_jackpot: Label          = get_node_or_null("Jackpot")

@onready var spin_bet: SpinBox           = $BetRow/Bet
@onready var btn_flip: Button            = $FlipBtn
@onready var flip_bar: ProgressBar       = get_node_or_null("FlipBar")

# Quick pick (optional convenience)
@onready var btn_heads: Button           = get_node_or_null("PickRow/PickHeads")
@onready var btn_tails: Button           = get_node_or_null("PickRow/PickTails")

# Sequence prediction UI
@onready var spin_seq_len: SpinBox       = get_node_or_null("SeqRow/SeqLen")
@onready var choices_root: Node          = get_node_or_null("SeqRow/Choices")  # holds Choice0..Choice4 (Buttons)

# Coin type selector
@onready var opt_coin: OptionButton      = get_node_or_null("CoinRow/CoinType")

# Side bet UI
@onready var chk_side_same: CheckButton  = get_node_or_null("SideRow/SideSameAsLast")
@onready var spin_side_amt: SpinBox      = get_node_or_null("SideRow/SideBetAmount")

# Risk Row (Double-or-Nothing tiers)
@onready var row_risk: Control           = $RiskRow
@onready var btn_double2x: Button        = get_node_or_null("RiskRow/Double2x")
@onready var btn_double3x: Button        = get_node_or_null("RiskRow/Double3x")
@onready var btn_double5x: Button        = get_node_or_null("RiskRow/Double5x")
@onready var btn_cashout: Button         = $RiskRow/CashOutBtn

# Optional reset
@onready var btn_reset: Button           = get_node_or_null("ResetBtn")

func _ready() -> void:
	rng.randomize()
	_update_balance()
	_update_jackpot()
	row_risk.visible = false
	if lbl_result:
		lbl_result.text = "Set bet & prediction, then Flip."
	if flip_bar:
		flip_bar.visible = false
		flip_bar.value = 0

	# Wire default quick pick
	if btn_heads: btn_heads.pressed.connect(func(): _set_all_choices("heads"))
	if btn_tails: btn_tails.pressed.connect(func(): _set_all_choices("tails"))

	# Wire main buttons
	btn_flip.pressed.connect(_on_flip_pressed)
	btn_cashout.pressed.connect(_on_cashout_pressed)
	if btn_double2x: btn_double2x.pressed.connect(func(): _on_double_tier_pressed(2.0, 0.50))
	if btn_double3x: btn_double3x.pressed.connect(func(): _on_double_tier_pressed(3.0, 0.3333))
	if btn_double5x: btn_double5x.pressed.connect(func(): _on_double_tier_pressed(5.0, 0.20))
	if btn_reset: btn_reset.pressed.connect(_on_reset_pressed)

	# Coin type menu (Fair / Lucky / Cursed)
	if opt_coin:
		if opt_coin.item_count == 0:
			opt_coin.add_item("Fair (50/50, 2.0x)", 0)
			opt_coin.add_item("Lucky (60% Heads, 1.8x)", 1)
			opt_coin.add_item("Cursed (40% Heads, 2.5x)", 2)
		opt_coin.item_selected.connect(_on_coin_type_changed)
		_apply_coin_type(opt_coin.get_selected_id())

	# Sequence length and choice buttons
	if spin_seq_len:
		spin_seq_len.min_value = 1
		spin_seq_len.max_value = 5
		spin_seq_len.value = 1
		spin_seq_len.value_changed.connect(func(v): _on_seq_len_changed(int(v)))
	_ensure_choice_buttons()
	_on_seq_len_changed(spin_seq_len.value if spin_seq_len else 1)

# ========== UI HELPERS ==========
func _update_balance() -> void:
	if lbl_balance:
		lbl_balance.text = "Balance: $" + str(balance)

func _update_jackpot() -> void:
	if lbl_jackpot:
		lbl_jackpot.text = "Jackpot: $" + str(jackpot)

func _set_inputs_enabled(enabled: bool) -> void:
	btn_flip.disabled = not enabled
	spin_bet.editable = enabled
	if spin_seq_len: spin_seq_len.editable = enabled
	if choices_root:
		for c in choices_root.get_children():
			if c is Button:
				(c as Button).disabled = not enabled
	if opt_coin: opt_coin.disabled = not enabled
	if chk_side_same: chk_side_same.disabled = not enabled
	if spin_side_amt: spin_side_amt.editable = enabled

func _set_all_choices(val: String) -> void:
	var L := _get_seq_len()
	_ensure_predicted_capacity()
	for i in L:
		predicted_seq[i] = val
	_sync_choice_buttons()

func _get_seq_len() -> int:
	return int(spin_seq_len.value) if spin_seq_len else seq_len

func _sync_choice_buttons() -> void:
	if not choices_root: return
	var L := _get_seq_len()
	var i := 0
	for c in choices_root.get_children():
		if c is Button:
			var b: Button = c
			b.visible = i < L
			if i < L:
				b.text = "H" if predicted_seq[i] == "heads" else "T"
			i += 1

func _ensure_choice_buttons() -> void:
	if not choices_root: return
	# Expect Choice0..Choice4
	if choices_root.get_child_count() == 0:
		return
	var i := 0
	for c in choices_root.get_children():
		if c is Button:
			var idx := i
			(c as Button).pressed.connect(func(): _cycle_choice_button(idx))
			i += 1

func _cycle_choice_button(idx: int) -> void:
	_ensure_predicted_capacity()
	predicted_seq[idx] = ("tails" if predicted_seq[idx] == "heads" else "heads")
	_sync_choice_buttons()

func _ensure_predicted_capacity() -> void:
	var L := _get_seq_len()
	while predicted_seq.size() < L:
		predicted_seq.append("heads")
	seq_len = L

# ========== COIN TYPE ==========
func _on_coin_type_changed(id: int) -> void:
	_apply_coin_type(id)

func _apply_coin_type(id: int) -> void:
	match id:
		0:
			coin_heads_bias = 0.5
			coin_single_mult = 2.0
		1:
			coin_heads_bias = 0.6
			coin_single_mult = 1.8
		2:
			coin_heads_bias = 0.4
			coin_single_mult = 2.5
		_:
			coin_heads_bias = 0.5
			coin_single_mult = 2.0

# ========== BUTTONS ==========
func _on_seq_len_changed(v: int) -> void:
	seq_len = clamp(v, 1, 5)
	_ensure_predicted_capacity()
	_sync_choice_buttons()

func _on_flip_pressed() -> void:
	if state != GameState.READY:
		return

	# Read bets
	current_bet = int(spin_bet.value)
	if current_bet <= 0:
		lbl_result.text = "Bet must be > 0."
		return

	var side_amt := (int(spin_side_amt.value) if spin_side_amt else 0)
	var side_on := (chk_side_same and chk_side_same.button_pressed)
	var total_required := current_bet + (side_amt if side_on else 0)
	if total_required > balance:
		lbl_result.text = "Not enough balance for bet + side bet."
		return

	# Lock inputs & prep
	balance -= current_bet
	_update_balance()
	state = GameState.ANIMATING
	_set_inputs_enabled(false)
	row_risk.visible = false
	lbl_result.text = "Flipping sequence…"
	if flip_bar:
		flip_bar.visible = true
		flip_bar.value = 0

	# Jackpot grows (house tax; not deducted from player separately)
	jackpot += int(round(current_bet * JACKPOT_TAX))
	_update_jackpot()

	# Handle side bet pre-deduction (you pay the side bet; you’ll get SIDE_MULT back if it hits)
	if side_on and side_amt > 0:
		balance -= side_amt
		_update_balance()

	# Run the sequence flips with short delays
	var outcomes: Array[String] = []
	var L := _get_seq_len()
	for i in L:
		lbl_result.text = "Flipping %d/%d…" % [i + 1, L]
		if flip_bar:
			await _animate_progress(0.4)
		var o := _flip_once()
		outcomes.append(o)

	if flip_bar:
		flip_bar.visible = false

	# Resolve base bet
	var won := _sequence_matches(predicted_seq, outcomes, L)
	if won:
		var base_mult := pow(coin_single_mult, L)

		# Streak bonus (based on previous streak before this win)
		var bonus_mult := 1.0
		if win_streak >= 3:
			bonus_mult = 1.5
		elif win_streak == 2:
			bonus_mult = 1.25

		pending_winnings = int(round(current_bet * base_mult * bonus_mult))

	# Resolve side bet (“next flip same as last outcome” → judged on the FIRST flip of this run)
	var side_msg := ""
	if side_on and last_outcome != "" and L > 0:
		var hit := (outcomes[0] == last_outcome)
		if hit:
			var side_payout := int(round(side_amt * SIDE_MULT))
			balance += side_payout
			side_msg = "  (Side bet hit +$%d)" % side_payout
		else:
			side_msg = "  (Side bet lost -$%d)" % side_amt
		_update_balance()
	elif side_on and last_outcome == "":
		side_msg = "  (Side bet skipped: no last flip)"
		# side bet already deducted; treat as a loss for the first round

	# Update last outcome (from the final flip)
	last_outcome = outcomes[-1]

	# Apply base win/lose and advance to DoN or finish
	if won:
		win_streak += 1
		lbl_result.text = "Outcome: %s — You WON $%d! Double or Cash Out?%s" % [
			_seq_to_text(outcomes), pending_winnings, side_msg
		]
		# Jackpot condition: long sequence win awards jackpot
		if L >= 5 and jackpot > 0:
			balance += jackpot
			lbl_result.text += "  JACKPOT +$%d!" % jackpot
			jackpot = 0
			_update_balance()
			_update_jackpot()
		row_risk.visible = true
		state = GameState.DOUBLE_DECISION
	else:
		# Lose base bet
		_update_balance()
		lbl_result.text = "Outcome: %s — You LOST $%d.%s" % [
			_seq_to_text(outcomes), current_bet, side_msg
		]
		win_streak = 0
		don_streak = 0
		pending_winnings = 0
		state = GameState.READY
		_set_inputs_enabled(true)

func _on_cashout_pressed() -> void:
	if state != GameState.DOUBLE_DECISION:
		return
	balance += pending_winnings
	_update_balance()
	lbl_result.text = "Banked $%d. Streak reset." % pending_winnings
	pending_winnings = 0
	row_risk.visible = false
	state = GameState.READY
	win_streak = 0              # per design: cashing out resets base streak
	don_streak = 0
	_set_inputs_enabled(true)

func _on_double_tier_pressed(mult: float, success_prob: float) -> void:
	if state != GameState.DOUBLE_DECISION:
		return
	# Run a quick risk roll (no coin; abstract odds)
	row_risk.visible = false
	state = GameState.ANIMATING
	_set_inputs_enabled(false)
	lbl_result.text = "Risking it…"
	if flip_bar:
		flip_bar.visible = true
		await _animate_progress(0.5)
		flip_bar.visible = false

	var hit := rng.randf() < success_prob
	if hit:
		pending_winnings = int(round(pending_winnings * mult))
		don_streak += 1
		lbl_result.text = "Success! Winnings now $%d. Double again or Cash Out?" % pending_winnings

		# Jackpot for huge DoN streaks
		if don_streak >= 10 and jackpot > 0:
			balance += jackpot
			_update_balance()
			lbl_result.text += "  JACKPOT +$%d!" % jackpot
			jackpot = 0
			_update_jackpot()

		row_risk.visible = true
		state = GameState.DOUBLE_DECISION
	else:
		lbl_result.text = "Busted! You lost the $%d pot." % pending_winnings
		pending_winnings = 0
		don_streak = 0
		state = GameState.READY
		_set_inputs_enabled(true)

func _on_reset_pressed() -> void:
	balance = 1000
	win_streak = 0
	don_streak = 0
	pending_winnings = 0
	lbl_result.text = "Reset to $1000."
	_update_balance()

# ========== CORE LOGIC ==========
func _flip_once() -> String:
	return "heads" if rng.randf() < coin_heads_bias else "tails"

func _sequence_matches(pred: Array[String], outc: Array[String], L: int) -> bool:
	var i := 0
	while i < L:
		if pred[i] != outc[i]:
			return false
		i += 1
	return true

func _seq_to_text(seq: Array[String]) -> String:
	var parts := []
	for s in seq:
		parts.append(s.substr(0,1).to_upper())
	return ", ".join(PackedStringArray(parts))

# Simple progress “animation”
func _animate_progress(duration: float) -> void:
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
