module Types;

import std.math;

/** Types that needed to be refactored from DExchange package modules in order to avoid redundant dependencies.
    (otherwise, types must be defined inside the modules they are required) */

enum ETradeSide: uint {BUY, SELL}

struct Trade {
	ulong   timeMilliS;
	uint   qty;
	real   price;
	string buyer;
	string seller;
	string cond;
	uint aggressorOrderId;
	uint aggressedOrderId;

	bool timeEqualsMinutePrecision(ulong anotherTimeMilliS) const {
		return abs((timeMilliS/(1000*60)) - (anotherTimeMilliS/(1000*60))) <= 1;
	}
}

struct PriceBookEntry {
	real price;
	uint quantity;
}
