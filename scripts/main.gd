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
# (per-side-bet multipliers now come from SIDEBET_DB by level)

# Coin types (driven by equipped coin)
var coin_heads_bias: float = 0.5
var coin_single_mult: float = 2.0

var rng := RandomNumberGenerator.new()

# ==== FEATURE UNLOCKS (keep simple feature gates like before) ====
# These are still purchasable "features" (separate from coins/sidebets).
var unlocks := {
	"streaks": false,
	"multiseq": false,
	"risk": false,
	"jackpot": false
}

const SHOP_ITEMS := [
	{"id":"streaks","name":"Streak Bonuses","price":100,"desc":"Bonus payout on win streaks."},
	{"id":"multiseq","name":"Multi-Flip Predictions","price":200,"desc":"Predict 2–5 flips for higher multipliers."},
	{"id":"risk","name":"Risk-Tier DoN","price":150,"desc":"Unlock 3x and 5x double-or-nothing tiers."},
	{"id":"jackpot","name":"Jackpot","price":250,"desc":"A growing pot that pays on rare feats."}
]

# ==== NEW: COINS & SIDE BETS (unlock + upgrade + equip) ====
# Replace paths with your art; ResourceLoader.exists() checks at runtime.
const COIN_DB := {
	"yellow": {
		"name":"Yellow (Fair)", "unlock":100, "level_max":5,
		"bias":[0.50,0.50,0.50,0.50,0.50],
		"mult":[2.00,2.05,2.10,2.15,2.20],
		"tex_heads":[
			"res://images/siegecoin.png"
		],
		"tex_tails":[
			"res://images/siegecoin_tails.png"
		]
	},
	"lucky": {
		"name":"Lucky (Bias Heads)", "unlock":150, "level_max":5,
		"bias":[0.60,0.62,0.64,0.66,0.68],
		"mult":[1.80,1.85,1.90,1.95,2.00],
		"tex_heads":[
			"res://art/lucky/h1.png","res://art/lucky/h2.png","res://art/lucky/h3.png","res://art/lucky/h4.png","res://art/lucky/h5.png"
		],
		"tex_tails":[
			"res://art/lucky/t1.png","res://art/lucky/t2.png","res://art/lucky/t3.png","res://art/lucky/t4.png","res://art/lucky/t5.png"
		]
	},
	"cursed": {
		"name":"Cursed (Bias Tails)", "unlock":150, "level_max":5,
		"bias":[0.40,0.38,0.36,0.34,0.32],
		"mult":[2.50,2.60,2.70,2.80,2.90],
		"tex_heads":[
			"res://art/cursed/h1.png","res://art/cursed/h2.png","res://art/cursed/h3.png","res://art/cursed/h4.png","res://art/cursed/h5.png"
		],
		"tex_tails":[
			"res://art/cursed/t1.png","res://art/cursed/t2.png","res://art/cursed/t3.png","res://art/cursed/t4.png","res://art/cursed/t5.png"
		]
	}
}

const SIDEBET_DB := {
	"same_last": { # pays if first flip matches last round's final flip
		"name":"Same as Previous Flip (first)", "unlock":120, "level_max":5,
		"mult":[1.60,1.70,1.80,1.90,2.00]
	},
	"same_final": { # pays if final flip matches last round's final flip
		"name":"Same as Previous Flip (final)", "unlock":140, "level_max":5,
		"mult":[1.50,1.60,1.70,1.80,1.90]
	}
}

# Persistent ownership/levels (saved)
var owned_coins : Dictionary = {}     # {"yellow": true, ...}
var coin_level  : Dictionary = {}     # {"yellow": 1..level_max}
var owned_sides : Dictionary = {}     # {"same_last": true, ...}
var side_level  : Dictionary = {}     # {"same_last": 1..level_max}

var active_coin_id : String = ""      # equipped coin
var active_side_id : String = ""      # equipped side bet ("" = none)

const SAVE_PATH := "user://save.cfg"

# ==== NODE REFS ====
@onready var lbl_balance: Label          = $Balance
@onready var lbl_result: Label           = $Result
@onready var lbl_jackpot: Label          = get_node_or_null("Jackpot")

@onready var spin_bet: SpinBox           = $BetModal/BetRow/Bet
@onready var btn_flip: Button            = $BetModal/FlipBtn
@onready var flip_bar: ProgressBar       = get_node_or_null("FlipBar")

@onready var btn_one_bet: Button         = $BetModal/ChoiceRow/OneBtn
@onready var btn_multi_bet: Button       = $BetModal/ChoiceRow/MultiBtn

@onready var btn_heads: TextureButton    = get_node_or_null("BetModal/PickRow/PickHeads")
@onready var btn_tails: TextureButton    = get_node_or_null("BetModal/PickRow/PickTails")

@onready var row_seq: Control            = get_node_or_null("BetModal/SeqRow")
@onready var spin_seq_len: SpinBox       = get_node_or_null("BetModal/SeqRow/SeqLen")
@onready var choices_root: Node          = get_node_or_null("BetModal/SeqRow/Choices")

# Old coin selector row is deprecated (coins are now shop/equip). Hide it.
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

@onready var bailout_btn: Button = $Bailout

@onready var coin: Sprite2D = $Coin
var tex_heads: Texture2D = preload("res://images/siegecoin.png")
var tex_tails: Texture2D = preload("res://images/siegecoin_tails.png")

# Keep references to feature buy buttons
var _shop_buttons := {}   # for simple feature items (not coins/sidebets)

func _ready() -> void:
	var theme_builder := load("res://scripts/ThemeBuilder.gd")
	if theme_builder:
		theme_builder.new().apply(self)
	rng.randomize()
	_wire_base_ui()
	_init_seq_ui()
	_load_progress()

	# Ensure a default coin if none owned
	if owned_coins.size() == 0:
		owned_coins["yellow"] = true
		coin_level["yellow"] = 1
		active_coin_id = "yellow"

	_apply_active_coin_stats()
	_load_coin_textures()

	_update_balance()
	_update_jackpot()
	_apply_unlocks_update_ui()
	_build_shop_ui()
	if lbl_result:
		lbl_result.text = "Set bet, upgrade/equip in the Shop, then Flip."
	if balance == 0:
		bailout_btn.visible = true

# ----------------- INIT / WIRING -----------------
func _wire_base_ui() -> void:
	btn_flip.pressed.connect(_on_flip_pressed)
	btn_cashout.pressed.connect(_on_cashout_pressed)

	if btn_heads:
		btn_heads.pressed.connect(_on_pick_heads_pressed)
	if btn_tails:
		btn_tails.pressed.connect(_on_pick_tails_pressed)

	if btn_double2x:
		btn_double2x.pressed.connect(_on_double2x_pressed)
	if btn_double3x:
		btn_double3x.pressed.connect(_on_double3x_pressed)
	if btn_double5x:
		btn_double5x.pressed.connect(_on_double5x_pressed)

	if btn_shop:
		btn_shop.pressed.connect(_on_shop_open_pressed)
	if btn_shop_close:
		btn_shop_close.pressed.connect(_on_shop_close_pressed)

	if flip_bar:
		flip_bar.visible = false
		flip_bar.value = 0

	btn_one_bet.pressed.connect(_on_one_bet_pressed)
	btn_multi_bet.pressed.connect(_on_multi_bet_pressed)

func _init_seq_ui() -> void:
	if spin_seq_len:
		spin_seq_len.min_value = 1
		spin_seq_len.max_value = 5
		spin_seq_len.value = 1
		spin_seq_len.value_changed.connect(_on_seq_len_changed)
	_ensure_choice_buttons()
	if spin_seq_len:
		_on_seq_len_changed(spin_seq_len.value)
	else:
		_on_seq_len_changed(1.0)

# ----------------- SHOP UI (features + coins + sidebets) -----------------
func _build_shop_ui() -> void:
	if not shop_items_box:
		return
	for c in shop_items_box.get_children():
		c.queue_free()
	_shop_buttons.clear()

	# ---- Feature items (legacy) ----
	var h0 := Label.new()
	h0.text = "Features"
	shop_items_box.add_child(h0)

	for item in SHOP_ITEMS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_label := Label.new()
		name_label.text = str(item["name"], " — ", item["desc"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var price_label := Label.new()
		price_label.text = "🪙" + str(item["price"])
		price_label.custom_minimum_size = Vector2(60, 0)
		row.add_child(price_label)

		var b := Button.new()
		row.add_child(b)
		shop_items_box.add_child(row)

		_shop_buttons[item["id"]] = {"button": b, "price": item["price"]}
		b.pressed.connect(Callable(self, "_on_shop_feature_buy_button_pressed").bind(b))

	# ---- Coins ----
	var h1 := Label.new()
	h1.text = "Coins"
	shop_items_box.add_child(h1)

	for cid in COIN_DB.keys():
		var db = COIN_DB[cid]
		var rowc := HBoxContainer.new()
		rowc.add_theme_constant_override("separation", 8)
		shop_items_box.add_child(rowc)

		var owned = owned_coins.get(cid, false)
		var lv := int(coin_level.get(cid, 0))
		if owned and lv <= 0:
			lv = 1

		var namec := Label.new()
		namec.text = str(db["name"], "  ", "(Lv " + str(lv) + ")" if owned else "(Locked)")
		namec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rowc.add_child(namec)

		# Unlock/Upgrade
		var b1 := Button.new()
		b1.set_meta("kind","coin")
		b1.set_meta("id", cid)
		if not owned:
			var p := int(db["unlock"])
			b1.text = "Unlock (🪙" + str(p) + ")"
			b1.disabled = balance < p
			b1.set_meta("action","unlock")
		else:
			var nxt := lv + 1
			if nxt <= int(db["level_max"]):
				var cost := _coin_upgrade_cost(cid, nxt)
				b1.text = "Upgrade (🪙" + str(cost) + ")"
				b1.disabled = balance < cost
				b1.set_meta("action","upgrade")
			else:
				b1.text = "Maxed"
				b1.disabled = true
				b1.set_meta("action","none")
		rowc.add_child(b1)
		b1.pressed.connect(Callable(self,"_on_shop_btn_pressed").bind(b1))

		# Equip
		var b2 := Button.new()
		b2.set_meta("kind","coin")
		b2.set_meta("id", cid)
		b2.set_meta("action","equip")
		b2.text = "Equipped" if (active_coin_id == cid) else "Equip"
		b2.disabled = not owned
		rowc.add_child(b2)
		b2.pressed.connect(Callable(self,"_on_shop_btn_pressed").bind(b2))

	# ---- Side Bets ----
	var h2 := Label.new()
	h2.text = "Side Bets"
	shop_items_box.add_child(h2)

	for sid in SIDEBET_DB.keys():
		var sdb = SIDEBET_DB[sid]
		var rows := HBoxContainer.new()
		rows.add_theme_constant_override("separation", 8)
		shop_items_box.add_child(rows)

		var owned2 = owned_sides.get(sid, false)
		var lv2 := int(side_level.get(sid, 0))
		if owned2 and lv2 <= 0:
			lv2 = 1

		var names := Label.new()
		names.text = str(sdb["name"], "  ", "(Lv " + str(lv2) + ")" if owned2 else "(Locked)")
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(names)

		var a1 := Button.new()
		a1.set_meta("kind","side")
		a1.set_meta("id", sid)
		if not owned2:
			var p2 := int(sdb["unlock"])
			a1.text = "Unlock (🪙" + str(p2) + ")"
			a1.disabled = balance < p2
			a1.set_meta("action","unlock")
		else:
			var nxt2 := lv2 + 1
			if nxt2 <= int(sdb["level_max"]):
				var cost2 := _side_upgrade_cost(sid, nxt2)
				a1.text = "Upgrade (🪙" + str(cost2) + ")"
				a1.disabled = balance < cost2
				a1.set_meta("action","upgrade")
			else:
				a1.text = "Maxed"
				a1.disabled = true
				a1.set_meta("action","none")
		rows.add_child(a1)
		a1.pressed.connect(Callable(self,"_on_shop_btn_pressed").bind(a1))

		var a2 := Button.new()
		a2.set_meta("kind","side")
		a2.set_meta("id", sid)
		a2.set_meta("action","equip")
		a2.text = "Equipped" if (active_side_id == sid) else "Equip"
		a2.disabled = not owned2
		rows.add_child(a2)
		a2.pressed.connect(Callable(self,"_on_shop_btn_pressed").bind(a2))

	_update_funds_labels()
	_refresh_shop_buttons()

func _on_shop_feature_buy_button_pressed(btn: Button) -> void:
	# Buy from legacy SHOP_ITEMS list
	var id := ""
	for k in _shop_buttons.keys():
		if _shop_buttons[k]["button"] == btn:
			id = String(k)
			break
	if id == "":
		return
	if unlocks.get(id, false):
		return
	var price := int(_shop_buttons[id]["price"])
	if balance < price:
		if lbl_result:
			lbl_result.text = "Not enough balance for " + id + "."
		return
	balance -= price
	if balance == 0: bailout_btn.visible = true
	unlocks[id] = true
	_update_balance()
	_apply_unlocks_update_ui()
	_refresh_shop_buttons()
	_update_funds_labels()
	_save_progress()
	if lbl_result:
		lbl_result.text = "Purchased '" + id + "' for 🪙" + str(price) + "!"

func _refresh_shop_buttons() -> void:
	for id in _shop_buttons.keys():
		var b: Button = _shop_buttons[id]["button"]
		var price := int(_shop_buttons[id]["price"])
		if unlocks.get(id, false):
			b.text = "Owned"
			b.disabled = true
		else:
			b.text = "Buy (🪙" + str(price) + ")"
			b.disabled = balance < price

func _set_shop_visible(v: bool) -> void:
	if not shop_panel: return
	shop_panel.visible = v
	_update_funds_labels()
	_refresh_shop_buttons()

func _on_shop_open_pressed() -> void:
	_set_shop_visible(true)

func _on_shop_close_pressed() -> void:
	_set_shop_visible(false)

# ---- Shop actions for coins / sidebets ----
func _coin_upgrade_cost(id: String, next_level: int) -> int:
	var base := int(COIN_DB[id]["unlock"])
	return int(round(base * max(1, next_level))) # linear

func _side_upgrade_cost(id: String, next_level: int) -> int:
	var base := int(SIDEBET_DB[id]["unlock"])
	return int(round(base * (0.5 + 0.5 * max(1, next_level)))) # gentler

func _on_shop_btn_pressed(btn: Button) -> void:
	var kind := String(btn.get_meta("kind"))
	var id := String(btn.get_meta("id"))
	var action := String(btn.get_meta("action"))

	if kind == "coin":
		if action == "unlock":
			var cost := int(COIN_DB[id]["unlock"])
			if balance < cost: return
			balance -= cost
			if balance == 0: bailout_btn.visible = true
			owned_coins[id] = true
			coin_level[id] = 1
			if active_coin_id == "":
				active_coin_id = id
			_apply_active_coin_stats()
			_load_coin_textures()
		elif action == "upgrade":
			var cur := int(coin_level.get(id, 1))
			var nxt := cur + 1
			if nxt > int(COIN_DB[id]["level_max"]): return
			var cost2 := _coin_upgrade_cost(id, nxt)
			if balance < cost2: return
			balance -= cost2
			if balance == 0: bailout_btn.visible = true
			coin_level[id] = nxt
			if active_coin_id == id:
				_apply_active_coin_stats()
				_load_coin_textures()
		elif action == "equip":
			if owned_coins.get(id, false):
				active_coin_id = id
				_apply_active_coin_stats()
				_load_coin_textures()

	elif kind == "side":
		if action == "unlock":
			var cost3 := int(SIDEBET_DB[id]["unlock"])
			if balance < cost3: return
			balance -= cost3
			if balance == 0: bailout_btn.visible = true
			owned_sides[id] = true
			side_level[id] = 1
			if active_side_id == "":
				active_side_id = id
		elif action == "upgrade":
			var cur2 := int(side_level.get(id, 1))
			var nxt2 := cur2 + 1
			if nxt2 > int(SIDEBET_DB[id]["level_max"]): return
			var cost4 := _side_upgrade_cost(id, nxt2)
			if balance < cost4: return
			balance -= cost4
			if balance == 0: bailout_btn.visible = true
			side_level[id] = nxt2
		elif action == "equip":
			if owned_sides.get(id, false):
				active_side_id = id

	_update_balance()
	_build_shop_ui()
	_refresh_feature_visibility()
	_save_progress()

# ----------------- UNLOCK GATING / VISIBILITY -----------------
func _apply_unlocks_update_ui() -> void:
	# Multi-sequence
	if row_seq: row_seq.visible = unlocks["multiseq"]
	if spin_seq_len:
		if unlocks["multiseq"]:
			spin_seq_len.editable = true
			$BetModal/ChoiceRow.visible = true
			_on_one_bet_pressed()
		else:
			spin_seq_len.value = 1
			spin_seq_len.editable = false
			$BetModal/ChoiceRow.visible = false
	if choices_root: choices_root.visible = unlocks["multiseq"]

	# Old coin row is deprecated: hide & disable
	if row_coin: row_coin.visible = false
	if opt_coin: opt_coin.disabled = true

	# Risk tiers beyond 2x
	if btn_double3x: btn_double3x.visible = unlocks["risk"]
	if btn_double5x: btn_double5x.visible = unlocks["risk"]

	# Jackpot label
	if lbl_jackpot: lbl_jackpot.visible = unlocks["jackpot"]

	_refresh_feature_visibility()

func _refresh_feature_visibility() -> void:
	# Side bet row visible if the player owns at least one side bet
	if row_side:
		row_side.visible = owned_sides.size() > 0

# ----------------- LABEL UPDATES -----------------
func _update_balance() -> void:
	if lbl_balance:
		lbl_balance.text = "🪙" + str(balance)
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
func _on_seq_len_changed(v: float) -> void:
	seq_len = clamp(int(v), 1, 5)
	_ensure_predicted_capacity()
	_sync_choice_buttons()

func _on_pick_heads_pressed() -> void:
	_set_all_choices("heads")

func _on_pick_tails_pressed() -> void:
	_set_all_choices("tails")

func _on_double2x_pressed() -> void:
	_on_double_tier_pressed(2.0, 0.50)

func _on_double3x_pressed() -> void:
	_on_double_tier_pressed(3.0, 0.3333)

func _on_double5x_pressed() -> void:
	_on_double_tier_pressed(5.0, 0.20)

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

	# Side bet (enabled if player owns & equipped something and toggled)
	var side_on := false
	if row_side and chk_side_same and chk_side_same.button_pressed and active_side_id != "":
		side_on = true

	var side_amt := 0
	if side_on and spin_side_amt:
		side_amt = int(spin_side_amt.value)

	var total_required := current_bet
	if side_on:
		total_required += side_amt
	if total_required > balance:
		lbl_result.text = "Not enough balance for bet + side bet."
		return

	# Lock inputs & deduct base bet up front
	balance -= current_bet
	if balance == 0: bailout_btn.visible = true
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

	# Deduct side bet upfront
	if side_on and side_amt > 0:
		balance -= side_amt
		if balance == 0: bailout_btn.visible = true
		_update_balance()

	# Run sequence
	var outcomes: Array[String] = []
	var L := _get_seq_len()
	for i in range(L):
		lbl_result.text = "Flipping " + str(i + 1) + "/" + str(L) + "…"
		var o := _flip_once()
		await _animate_coin_flip_to(o, 2 + rng.randi_range(0, 2), 0.4 + rng.randf()*0.25)
		outcomes.append(o)
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

	# Resolve side bet (rule depends on active_side_id)
	var side_msg := ""
	if side_on:
		if last_outcome == "":
			side_msg = "  (Side bet skipped: no last flip)"
		else:
			var hit := false
			var s_lv := int(side_level.get(active_side_id, 1))
			s_lv = clamp(s_lv, 1, int(SIDEBET_DB[active_side_id]["level_max"]))
			var mult := float(SIDEBET_DB[active_side_id]["mult"][s_lv - 1])

			if active_side_id == "same_last":
				hit = (outcomes[0] == last_outcome)
			elif active_side_id == "same_final":
				hit = (outcomes[L - 1] == last_outcome)

			if hit:
				var side_payout := int(round(side_amt * mult))
				balance += side_payout
				_update_balance()
				side_msg = "  (Side bet hit +🪙" + str(side_payout) + ")"
			else:
				side_msg = "  (Side bet lost -🪙" + str(side_amt) + ")"

	last_outcome = outcomes[-1]

	if won:
		win_streak += 1
		lbl_result.text = "Outcome: " + _seq_to_text(outcomes) + " — You WON 🪙" + str(pending_winnings) + "! Double or Cash Out?" + side_msg
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
		# Lose base bet (already deducted)
		_update_balance()
		lbl_result.text = "Outcome: " + _seq_to_text(outcomes) + " — You LOST 🪙" + str(current_bet) + "." + side_msg
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
	lbl_result.text = "Banked 🪙" + str(pending_winnings) + ". Streak reset."
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
		lbl_result.text = "Success! Winnings now 🪙" + str(pending_winnings) + ". Double again or Cash Out?"

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
		lbl_result.text = "Busted! You lost the 🪙" + str(pending_winnings) + " pot."
		pending_winnings = 0
		don_streak = 0
		state = GameState.READY
		_set_inputs_enabled(true)
	_save_progress()

func _on_one_bet_pressed():
	if row_seq:
		row_seq.visible = false
	var pr := get_node_or_null("BetModal/PickRow")
	if pr:
		pr.visible = true
	if spin_seq_len:
		spin_seq_len.value = 1

func _on_multi_bet_pressed():
	if row_seq:
		row_seq.visible = true
	var pr := get_node_or_null("BetModal/PickRow")
	if pr:
		pr.visible = false

# ----------------- SAVE / LOAD -----------------
func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "balance", balance)
	cfg.set_value("meta", "jackpot", jackpot)

	cfg.set_value("equip", "coin", active_coin_id)
	cfg.set_value("equip", "side", active_side_id)

	cfg.set_value("coins", "owned", owned_coins)
	cfg.set_value("coins", "levels", coin_level)

	cfg.set_value("sides", "owned", owned_sides)
	cfg.set_value("sides", "levels", side_level)

	cfg.set_value("features", "unlocks", unlocks)

	cfg.save(SAVE_PATH)

func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	balance = int(cfg.get_value("meta","balance", balance))
	jackpot = int(cfg.get_value("meta","jackpot", jackpot))

	active_coin_id = String(cfg.get_value("equip","coin", active_coin_id))
	active_side_id = String(cfg.get_value("equip","side", active_side_id))

	var oc = cfg.get_value("coins","owned", owned_coins)
	if oc is Dictionary:
		owned_coins = oc
	var clv = cfg.get_value("coins","levels", coin_level)
	if clv is Dictionary:
		coin_level = clv

	var os = cfg.get_value("sides","owned", owned_sides)
	if os is Dictionary:
		owned_sides = os
	var slv = cfg.get_value("sides","levels", side_level)
	if slv is Dictionary:
		side_level = slv

	var u = cfg.get_value("features","unlocks", unlocks)
	if u is Dictionary:
		unlocks = u

# ----------------- HELPERS -----------------
func _set_inputs_enabled(enabled: bool) -> void:
	btn_flip.disabled = not enabled
	spin_bet.editable = enabled
	if spin_seq_len:
		spin_seq_len.editable = enabled and unlocks["multiseq"]
	if choices_root:
		for c in choices_root.get_children():
			if c is Button:
				(c as Button).disabled = not enabled
	if chk_side_same:
		chk_side_same.disabled = not enabled
	if spin_side_amt:
		spin_side_amt.editable = enabled

func _set_all_choices(val: String) -> void:
	var L := _get_seq_len()
	_ensure_predicted_capacity()
	for i in range(L):
		predicted_seq[i] = val
	_sync_choice_buttons()

func _get_seq_len() -> int:
	if spin_seq_len:
		return int(spin_seq_len.value)
	return seq_len

func _sync_choice_buttons() -> void:
	if not choices_root:
		return
	var L := _get_seq_len()
	var i := 0
	for c in choices_root.get_children():
		if c is Button:
			var b: Button = c
			b.visible = i < L
			if i < L:
				b.text = "         "
				if predicted_seq[i] == "heads":
					b.icon = preload("res://images/siegecoin.png")
				else:
					b.icon = preload("res://images/siegecoin_tails.png")
			i += 1

func _ensure_choice_buttons() -> void:
	if not choices_root:
		return
	var i := 0
	for c in choices_root.get_children():
		if c is Button:
			var idx := i
			(c as Button).pressed.connect(Callable(self,"_on_choice_button_pressed").bind(idx))
			i += 1

func _on_choice_button_pressed(idx: int) -> void:
	_cycle_choice_button(idx)

func _cycle_choice_button(idx: int) -> void:
	_ensure_predicted_capacity()
	if predicted_seq[idx] == "heads":
		predicted_seq[idx] = "tails"
	else:
		predicted_seq[idx] = "heads"
	_sync_choice_buttons()

func _ensure_predicted_capacity() -> void:
	var L := _get_seq_len()
	while predicted_seq.size() < L:
		predicted_seq.append("heads")
	seq_len = L

# --- Coin application / textures ---
func _apply_active_coin_stats() -> void:
	if active_coin_id == "" or not COIN_DB.has(active_coin_id):
		coin_heads_bias = 0.5
		coin_single_mult = 2.0
		return
	var db = COIN_DB[active_coin_id]
	var lv := int(coin_level.get(active_coin_id, 1))
	lv = clamp(lv, 1, int(db["level_max"]))
	coin_heads_bias = float(db["bias"][lv - 1])
	coin_single_mult = float(db["mult"][lv - 1])

func _load_coin_textures() -> void:
	if not coin or active_coin_id == "" or not COIN_DB.has(active_coin_id):
		return
	var db = COIN_DB[active_coin_id]
	#var lv = clamp(int(coin_level.get(active_coin_id,1)), 1, int(db["level_max"]))
	var h_path := String(db["tex_heads"][0])
	var t_path := String(db["tex_tails"][0])
	if ResourceLoader.exists(h_path):
		tex_heads = load(h_path) as Texture2D
	if ResourceLoader.exists(t_path):
		tex_tails = load(t_path) as Texture2D
	if tex_heads and coin.texture == null:
		coin.texture = tex_heads

# --- RNG / matching ---
func _flip_once() -> String:
	if rng.randf() < coin_heads_bias:
		return "heads"
	return "tails"

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

# --- Progress fallback ---
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

# --- Coin flip animation (safe, no lambdas) ---
func _current_coin_face() -> String:
	if not coin or not coin.texture:
		return ""
	if tex_heads and coin.texture == tex_heads:
		return "heads"
	if tex_tails and coin.texture == tex_tails:
		return "tails"
	return ""

func _set_coin_face(face: String) -> void:
	if not coin:
		return
	if face == "heads" and tex_heads:
		coin.texture = tex_heads
	elif face == "tails" and tex_tails:
		coin.texture = tex_tails

func _swap_coin_face() -> void:
	var now := _current_coin_face()
	if now == "heads":
		_set_coin_face("tails")
	else:
		_set_coin_face("heads")

func _animate_coin_flip_to(outcome: String, spins: int = 3, duration: float = 0.6) -> void: 
	if not coin or (not tex_heads) or (not tex_tails): 
		# fallback to old progress bar if textures/sprite missing 
		if flip_bar: 
			await _animate_progress(duration) 
		else: 
			await get_tree().create_timer(duration).timeout 
			_set_coin_face(outcome) 
			return 
	# Ensure we start on a valid face 
	if _current_coin_face() == "": 
		_set_coin_face("heads") 
	var tween := create_tween() 
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT) 
	# We animate scale.x: -> 0 (edge) -> 1 (flat), swapping texture at the edge. 
	# Each “flip” is two halves. We’ll do (spins) full flips + a final half if needed to land on the outcome.
	var half := duration / float(spins * 2 + 1) # +1 reserved for the landing half 
	coin.scale = Vector2(130. / coin.texture.get_width(),120. / coin.texture.get_height()) 
	# Do the showy spins (texture swaps each half) 
	for i in spins: 
		tween.tween_callback(func(): 
		# swap face mid-flip 
			var now := _current_coin_face() 
			_set_coin_face( "tails" if now == "heads" else "heads" )) 
		tween.tween_property(coin, "scale:y", 0.001, half) 
		# squash to edge 
		tween.tween_property(coin, "scale:y", get_coin_dims(outcome).y, half) 
		# back to flat 
		# If the current face isn’t the desired outcome, do one landing half-flip to set it 
	if _current_coin_face() != outcome and spins % 2 == 0 or _current_coin_face() == outcome and spins % 2 == 1: 
		tween.tween_callback(func(): _set_coin_face(outcome)) 
		tween.tween_property(coin, "scale:y", 0.001, half) 
		tween.tween_property(coin, "scale:y", get_coin_dims(outcome).y, half) 
		# Optional: tiny settle bounce 
		#tween.tween_property(coin, "scale:y", 115. / coin.texture.get_height(), 0.06) 
		#tween.play() 
		#await tween.finished 
		#tween.stop() 
		#tween.tween_property(coin, "scale:y", 120. / coin.texture.get_height(), 0.06) 
		#tween.play() 
	await tween.finished 
	tween.kill() 
	
func get_coin_dims(result="tails"): 
	if result == "heads": 
		print("he") 
		return Vector2(130./512, 130./473) 
	else: 
		print("ta") 
		return Vector2(130./512, 130./512)


func _on_bailout_pressed() -> void:
	balance += 1000
	_update_balance()
	bailout_btn.visible = false
	_save_progress()
