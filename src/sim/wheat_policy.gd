class_name WheatPolicy
extends RefCounted

# Purchase policy of the wharf (issue #41). accumulate_price OFF means "do not stockpile"; max_price
# NO_LIMIT means "no limit" (it must not depend on the market's own top price, which a role may move).
# Both sentinels lie outside the price domain: a market can have a price of 0, so 0 is a real price.
const OFF: int = -1
const NO_LIMIT: int = -1
# Safety reserve, in minutes of mill consumption: below it the maximum price stops applying.
const MAX_RESERVE_MINUTES: int = 10


# Empty string when the combination is valid. Shared by Params, DataLoader and SetWheatPolicyCommand.
static func validation_error(accumulate_price: int, max_price: int, target_stock: int,
		reserve_minutes: int, storage_capacity: int, min_price: int, market_max_price: int) -> String:
	if accumulate_price < OFF or max_price < NO_LIMIT or target_stock < 0:
		return "wheat policy values cannot be negative"
	if reserve_minutes < 0 or reserve_minutes > MAX_RESERVE_MINUTES:
		return "safety reserve must be between 0 and %d minutes of mill" % MAX_RESERVE_MINUTES
	if accumulate_price > market_max_price:
		return "accumulate price is above the market's maximum price"
	if max_price != NO_LIMIT and (max_price < min_price or max_price > market_max_price):
		return "maximum price must be %d (no limit) or inside the market's price range" % NO_LIMIT
	if max_price != NO_LIMIT and accumulate_price > max_price:
		return "accumulate price cannot be above the maximum price"
	if target_stock > storage_capacity:
		return "target stock cannot exceed the storage capacity"
	return ""
