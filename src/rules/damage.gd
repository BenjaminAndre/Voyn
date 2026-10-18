class_name Damage
extends RefCounted
## Damage, healing and Shield (GDD R7.1-R7.3). Integers only, never dividing a negative number.


## R7.1 Damage = floor(max(0, base x (100 + user power + user damage-dealt % + target damage-taken %)) / 100).
## All modifiers add into one sum, the Blightborn bonus included. Call it on the state as it stands
## when the damage is computed (for Strike, the state at the start of Strike).
static func compute(state: FightState, user: FighterState, target: FighterState, base: int) -> int:
	var percent: int = 100 + user.power
	percent += Statuses.total(user, "damage_dealt_pct")
	percent += Statuses.total(target, "damage_taken_pct")
	if user.has_trait("blightborn") and user.cell >= 0 and state.karma[user.cell] <= Land.CORRUPTED:
		percent += int(state.rules["blightborn_power_pct"])
	var product: int = base * percent
	if product < 0:
		product = 0
	@warning_ignore("integer_division")
	return product / 100


## Deals `amount` to a fighter: Shield first (fixed damage included, R7.3), then HP. Emits `damaged`
## (and `shield_changed`, `status_ended` when the Shield is hit). Does not defeat: callers check
## for fighters at 0 HP at the right checkpoint.
static func apply(state: FightState, fighter: FighterState, amount: int, cause: String, events: Array[Dictionary]) -> void:
	if not fighter.alive:
		return
	var absorbed: int = mini(amount, Statuses.shield_amount(fighter))
	fighter.hp = maxi(0, fighter.hp - (amount - absorbed))
	events.append(Events.damaged(fighter.id, amount, absorbed, cause, fighter.hp))
	if absorbed > 0:
		var i: int = Statuses.index_of(fighter, Statuses.SHIELD)
		var left: int = int(fighter.statuses[i]["magnitude"]) - absorbed
		if left > 0:
			fighter.statuses[i]["magnitude"] = left
			events.append(Events.shield_changed(fighter.id, left))
		else:
			events.append(Events.shield_changed(fighter.id, 0))
			Statuses.remove(fighter, Statuses.SHIELD, events)


## R7.2 Heal restores HP, capped at max_hp. `power` does not affect it.
static func heal(fighter: FighterState, amount: int, cause: String, events: Array[Dictionary]) -> void:
	if not fighter.alive:
		return
	fighter.hp = mini(fighter.max_hp, fighter.hp + amount)
	events.append(Events.healed(fighter.id, amount, cause, fighter.hp))
