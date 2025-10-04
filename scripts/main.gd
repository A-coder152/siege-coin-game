extends Control

# ==== GAME STATE ====
enum GameState { READY, ANIMATING, DOUBLE_DECISION }

var state: GameState = GameState.READY

var balance: int = 1000
var current_bet: int = 0
var pending_winnings: int = 0

# Core prediction
var seq_len: int = 1
var predicted_seq: Array[String] = ["heads"]

# Streaks & jackpot
var win_streak: int = 0
var don_streak: int = 0
var jackpot: int = 0
const JACKPOT_TAX := 0.05  # grows the jackpot; does NOT charge the player

# Side bet
var last_outcome: String = ""
const SIDE_MULT := 1.9

# Coin types
var coin_heads_bias: float = 0.5
var coin_single_mult: float = 2.0

var rng := RandomNumberGenerator.new()

# ==== UNLOCKS & SHOP ====
# All are locked at first; players buy with balance to unlock.
var unlocks := {
	"streaks": false,
	"multiseq": false,
	"biased": false,
	"risk": false,
	"side": false,
	"jackpot": false
}

const SHOP_ITEMS := [
	{"id":"streaks","name":"Streak Bonuses","price":100,"desc":"Bonus payout on win streaks."},
	{"id":"multiseq","name":"Multi-Flip Predictions","price":200,"desc":"Predict 2–5 flips for higher multipliers."},
	{"id":"biased","name":"Biased Coins","price":150,"desc":"Lucky/Cursed coin types with different odds & payouts."},
	{"id":"risk","name":"Risk-Tier DoN","price":150,"desc":"Unlock 3x and 5x double-or-nothing tiers."},
	{"id":"side","name":"Side Bets","price":120,"desc":"Meta bet: 'next flip = last'."},
	{"id":"jackpot","name":"Jackpot","price":250,"desc":"A growing pot that pays on rare feats."}
]

const SAVE_PATH := "user://save.cfg"

# ==== NODE REFS ====
@onready var lbl_balance: Label          = $Balance
@onready var lbl_result: Label           = $Result
@onready var lbl_jackpot: Label          = get_node_or_null("Jackpot")

@onready var spin_bet: SpinBox           = $BetModal/BetRow/Bet
@onready var btn_flip: Button            = $BetModal/FlipBtn
@onready var flip_bar: ProgressBar       = get_node_or_null("FlipBar")

@onready var btn_heads: Button           = get_node_or_null("BetModal/PickRow/PickHeads")
@onready var btn_tails: Button           = get_node_or_null("BetModal/PickRow/PickTails")

@onready var row_seq: Control            = get_node_or_null("BetModal/SeqRow")
@onready var spin_seq_len: SpinBox       = get_node_or_null("BetModal/SeqRow/SeqLen")
@onready var choices_root: Node          = get_node_or_null("BetModal/SeqRow/Choices")

@onready var row_coin: Control           = get_node_or_null("CoinRow")
@onready var opt_coin: OptionButton      = get_node_or_null("CoinRow/CoinType")

@onready var row_side: Control           = get_node_or_null("SideRow")
@onready var chk_side_same: CheckButton  = get_node_or_null("SideRow/SideSameAsLast")
@onready var spin_side_amt: SpinBox      = get_node_or_null("SideRow/SideBetAmount")

@onready var row_risk: Control           = $RiskRow
@onready var btn_double2x: Button        = get_node_or_null("RiskRow/Double2x")
@onready var btn_double3x: Button        = get_node_or_null("RiskRow/Double3x")
@onready var btn_double5x: Button        = get_node_or_null("RiskRow/Double5x")
@onready var btn_cashout: Button         = $RiskRow/CashOutBtn

# Shop UI
@onready var toprow: Control                 = get_node_or_null("TopRow")
@onready var btn_shop: Button                = get_node_or_null("TopRow/ShopBtn")

@onready var shop_panel: Panel               = get_node_or_null("Shop")
@onready var shop_items_box: VBoxContainer   = get_node_or_null("Shop/ItemsBox")
@onready var lbl_funds_shop: Label           = get_node_or_null("Shop/FundsLabel")
@onready var btn_shop_close: Button          = get_node_or_null("Shop/CloseBtn")

# Keep references to buy buttons to update state
var _shop_buttons := {}

func _ready() -> void:
	ConfigFile.new().save(SAVE_PATH)
	rng.randomize()
	_wire_base_ui()
	_init_coin_menu()
	_init_seq_ui()
	_load_progress()
	_update_balance()
	_update_jackpot()
	_apply_unlocks_update_ui()
	_build_shop_ui()
	if lbl_result:
		lbl_result.text = "Set bet, (optionally) buy unlocks with your balance, then Flip."

# ----------------- INIT / WIRING -----------------
func _wire_base_ui() -> void:
	btn_flip.pressed.connect(_on_flip_pressed)
	btn_cashout.pressed.connect(_on_cashout_pressed)
	if btn_heads: btn_heads.pressed.connect(func(): _set_all_choices("heads"))
	if btn_tails: btn_tails.pressed.connect(func(): _set_all_choices("tails"))

	if btn_double2x: btn_double2x.pressed.connect(func(): _on_double_tier_pressed(2.0, 0.50))
	if btn_double3x: btn_double3x.pressed.connect(func(): _on_double_tier_pressed(3.0, 0.3333))
	if btn_double5x: btn_double5x.pressed.connect(func(): _on_double_tier_pressed(5.0, 0.20))

	if btn_shop: btn_shop.pressed.connect(func(): _set_shop_visible(true))
	if btn_shop_close: btn_shop_close.pressed.connect(func(): _set_shop_visible(false))

	if flip_bar:
		flip_bar.visible = false
		flip_bar.value = 0

func _init_coin_menu() -> void:
	if not opt_coin: return
	if opt_coin.item_count == 0:
		opt_coin.add_item("Fair (50/50, 2.0x)", 0)
		opt_coin.add_item("Lucky (60% Heads, 1.8x)", 1)
		opt_coin.add_item("Cursed (40% Heads, 2.5x)", 2)
	opt_coin.item_selected.connect(_on_coin_type_changed)
	_apply_coin_type(0)

func _init_seq_ui() -> void:
	if spin_seq_len:
		spin_seq_len.min_value = 1
		spin_seq_len.max_value = 5
		spin_seq_len.value = 1
		spin_seq_len.value_changed.connect(func(v): _on_seq_len_changed(int(v)))
	_ensure_choice_buttons()
	_on_seq_len_changed(spin_seq_len.value if spin_seq_len else 1)

# ----------------- SHOP UI -----------------
func _build_shop_ui() -> void:
	if not shop_items_box:
		return
	# clear children
	for c in shop_items_box.get_children():
		c.queue_free()
	_shop_buttons.clear()

	for item in SHOP_ITEMS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_label := Label.new()
		name_label.text = "%s — %s" % [item.name, item.desc]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var price_label := Label.new()
		price_label.text = "🪙%d" % item.price
		price_label.custom_minimum_size = Vector2(60, 0)
		row.add_child(price_label)

		var b := Button.new()
		row.add_child(b)
		shop_items_box.add_child(row)

		_shop_buttons[item.id] = {"button": b, "price": item.price}
		b.pressed.connect(func(id = item.id): _try_buy_item(id))

	_update_funds_labels()
	_refresh_shop_buttons()

func _refresh_shop_buttons() -> void:
	for id in _shop_buttons.keys():
		var b: Button = _shop_buttons[id]["button"]
		var price := int(_shop_buttons[id]["price"])
		if unlocks.get(id, false):
			b.text = "Owned"
			b.disabled = true
		else:
			b.text = "Buy (🪙%d)" % price
			b.disabled = balance < price

func _set_shop_visible(v: bool) -> void:
	if not shop_panel: return
	shop_panel.visible = v
	_update_funds_labels()
	_refresh_shop_buttons()

func _try_buy_item(id: String) -> void:
	if unlocks.get(id, false):
		return
	var price := int(_shop_buttons[id]["price"])
	if balance < price:
		if lbl_result:
			lbl_result.text = "Not enough balance for %s." % id
		return
	balance -= price
	unlocks[id] = true
	_update_balance()
	_apply_unlocks_update_ui()
	_refresh_shop_buttons()
	_update_funds_labels()
	_save_progress()
	if lbl_result:
		lbl_result.text = "Purchased '%s' for 🪙%d!" % [id, price]

# ----------------- UNLOCK GATING -----------------
func _apply_unlocks_update_ui() -> void:
	# Multi-sequence
	if row_seq: row_seq.visible = unlocks["multiseq"]
	if spin_seq_len:
		if unlocks["multiseq"]:
			spin_seq_len.editable = true
		else:
			spin_seq_len.value = 1
			spin_seq_len.editable = false
	if choices_root: choices_root.visible = unlocks["multiseq"]

	# Biased coins
	if row_coin: row_coin.visible = unlocks["biased"]
	if opt_coin: opt_coin.disabled = not unlocks["biased"]
	if not unlocks["biased"]:
		_apply_coin_type(0)  # force Fair

	# Side bets
	if row_side: row_side.visible = unlocks["side"]

	# Risk tiers beyond 2x
	if btn_double3x: btn_double3x.visible = unlocks["risk"]
	if btn_double5x: btn_double5x.visible = unlocks["risk"]

	# Jackpot label
	if lbl_jackpot: lbl_jackpot.visible = unlocks["jackpot"]

# ----------------- LABEL UPDATES -----------------
func _update_balance() -> void:
	if lbl_balance:
		lbl_balance.text = "🪙" + str(balance)
	# Keep shop buttons accurate if shop is open
	if shop_panel and shop_panel.visible:
		_refresh_shop_buttons()
	_update_funds_labels()

func _update_funds_labels() -> void:
	if lbl_funds_shop:
		lbl_funds_shop.text = "🪙" + str(balance)

func _update_jackpot() -> void:
	if lbl_jackpot:
		lbl_jackpot.text = "Jackpot: 🪙" + str(jackpot)

# ----------------- BUTTONS & CORE FLOW -----------------
func _on_seq_len_changed(v: int) -> void:
	seq_len = clamp(v, 1, 5)
	_ensure_predicted_capacity()
	_sync_choice_buttons()

func _on_flip_pressed() -> void:
	if state != GameState.READY:
		return

	# Base bet
	current_bet = int(spin_bet.value)
	if current_bet <= 0:
		lbl_result.text = "Bet must be > 0."
		return
	if current_bet > balance:
		lbl_result.text = "Bet exceeds balance."
		return

	# Side bet (only if unlocked)
	
	var side_on = unlocks["side"] and chk_side_same and chk_side_same.button_pressed
	var side_amt := (int(spin_side_amt.value) if (unlocks["side"] and spin_side_amt) else 0)
	var total_required := current_bet + (side_amt if side_on else 0)
	if total_required > balance:
		lbl_result.text = "Not enough balance for bet + side bet."
		return

	# Lock inputs
	balance -= current_bet
	_update_balance()
	state = GameState.ANIMATING
	_set_inputs_enabled(false)
	row_risk.visible = false
	lbl_result.text = "Flipping sequence…"
	if flip_bar:
		flip_bar.visible = true
		flip_bar.value = 0

	# Grow jackpot only if unlocked
	if unlocks["jackpot"]:
		jackpot += int(round(current_bet * JACKPOT_TAX))
		_update_jackpot()

	# Deduct side bet upfront (if used)
	if side_on and side_amt > 0:
		balance -= side_amt
		_update_balance()

	# Run sequence
	var outcomes: Array[String] = []
	var L := _get_seq_len()
	for i in L:
		lbl_result.text = "Flipping %d/%d…" % [i + 1, L]
		if flip_bar:
			await _animate_progress(0.4)
		outcomes.append(_flip_once())
	if flip_bar:
		flip_bar.visible = false

	# Resolve base bet (with optional streak bonus)
	var won := _sequence_matches(predicted_seq, outcomes, L)
	if won:
		var base_mult := pow(coin_single_mult, L)
		var bonus_mult := 1.0
		if unlocks["streaks"]:
			if win_streak >= 3:
				bonus_mult = 1.5
			elif win_streak == 2:
				bonus_mult = 1.25
		pending_winnings = int(round(current_bet * base_mult * bonus_mult))

	# Resolve side bet (judged on the FIRST flip of this run)
	var side_msg := ""
	if side_on and last_outcome != "" and L > 0:
		var hit := (outcomes[0] == last_outcome)
		if hit:
			var side_payout := int(round(side_amt * SIDE_MULT))
			balance += side_payout
			side_msg = "  (Side bet hit +🪙%d)" % side_payout
		else:
			side_msg = "  (Side bet lost -🪙%d)" % side_amt
		_update_balance()
	elif side_on and last_outcome == "":
		side_msg = "  (Side bet skipped: no last flip)"

	last_outcome = outcomes[-1]

	if won:
		win_streak += 1
		lbl_result.text = "Outcome: %s — You WON 🪙%d! Double or Cash Out?%s" % [
			_seq_to_text(outcomes), pending_winnings, side_msg
		]
		# Jackpot payouts (only if unlocked)
		if unlocks["jackpot"]:
			if L >= 5 and jackpot > 0:
				balance += jackpot
				jackpot = 0
				_update_balance()
				_update_jackpot()
				lbl_result.text += "  JACKPOT WON!"
		row_risk.visible = true
		state = GameState.DOUBLE_DECISION
	else:
		# Lose base bet
		_update_balance()
		lbl_result.text = "Outcome: %s — You LOST 🪙%d.%s" % [
			_seq_to_text(outcomes), current_bet, side_msg
		]
		win_streak = 0
		don_streak = 0
		pending_winnings = 0
		state = GameState.READY
		_set_inputs_enabled(true)
	_save_progress()

func _on_cashout_pressed() -> void:
	if state != GameState.DOUBLE_DECISION:
		return
	balance += pending_winnings
	_update_balance()
	lbl_result.text = "Banked 🪙%d. Streak reset." % pending_winnings
	pending_winnings = 0
	row_risk.visible = false
	state = GameState.READY
	win_streak = 0
	don_streak = 0
	_set_inputs_enabled(true)
	_save_progress()

func _on_double_tier_pressed(mult: float, success_prob: float) -> void:
	if state != GameState.DOUBLE_DECISION:
		return
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
		lbl_result.text = "Success! Winnings now 🪙%d. Double again or Cash Out?" % pending_winnings

		# Jackpot for huge DoN streaks (only if unlocked)
		if unlocks["jackpot"] and don_streak >= 10 and jackpot > 0:
			balance += jackpot
			jackpot = 0
			_update_balance()
			_update_jackpot()
			lbl_result.text += "  JACKPOT WON!"

		row_risk.visible = true
		state = GameState.DOUBLE_DECISION
	else:
		lbl_result.text = "Busted! You lost the 🪙%d pot." % pending_winnings
		pending_winnings = 0
		don_streak = 0
		state = GameState.READY
		_set_inputs_enabled(true)
	_save_progress()

# ----------------- SAVE / LOAD -----------------
func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "balance", balance)
	cfg.set_value("meta", "jackpot", jackpot)
	for item in SHOP_ITEMS:
		cfg.set_value("unlocks", item.id, unlocks[item.id])
	cfg.save(SAVE_PATH)

func _load_progress() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	balance = int(cfg.get_value("meta","balance", balance))
	jackpot = int(cfg.get_value("meta","jackpot", jackpot))
	for item in SHOP_ITEMS:
		unlocks[item.id] = bool(cfg.get_value("unlocks", item.id, unlocks[item.id]))

# ----------------- HELPERS -----------------
func _set_inputs_enabled(enabled: bool) -> void:
	btn_flip.disabled = not enabled
	spin_bet.editable = enabled
	if spin_seq_len: spin_seq_len.editable = enabled and unlocks["multiseq"]
	if choices_root:
		for c in choices_root.get_children():
			if c is Button:
				(c as Button).disabled = not enabled
	if opt_coin: opt_coin.disabled = (not unlocks["biased"]) or (not enabled)
	if chk_side_same: chk_side_same.disabled = (not unlocks["side"]) or (not enabled)
	if spin_side_amt: spin_side_amt.editable = enabled and unlocks["side"]

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
				b.text = "	   " if predicted_seq[i] == "heads" else "🪙"
				b.icon = preload("res://images/siegecoin.png") if predicted_seq[i] == "heads" else null
			i += 1

func _ensure_choice_buttons() -> void:
	if not choices_root: return
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

func _flip_once() -> String:
	return "heads" if rng.randf() < coin_heads_bias else "tails"

func _sequence_matches(pred: Array[String], outc: Array[String], L: int) -> bool:
	for i in range(L):
		if pred[i] != outc[i]:
			return false
	return true

func _seq_to_text(seq: Array[String]) -> String:
	var parts := []
	for s in seq:
		parts.append(s.substr(0,1).to_upper())
	return ", ".join(PackedStringArray(parts))

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
