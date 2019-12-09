module Types;

import std.math;
import std.conv;
import std.typecons;


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

struct SecurityInfo {
	/** the ID used to directly reference this security in the 'securityInfos[securityId]' array */
	uint securityId;
	/** symbol: the security name */
	string symbol;
	/** prices in orders are multiplied by this amount in order to be representable by ints */
	real faceToExchangeFactor;
	// bandas, horários de negociação, lote mínimo, faceToPrice factor (ex: mini-indice bovespa tem price = 20%*face), etc.

	/** routine to convert from the 'faceValue' (real) to the 'exchangeValue' (uint) -- the value best manipulated by the exchange */
	uint faceValueToExchangeValue(real faceValue) {
		return round(faceValue * faceToExchangeFactor).to!uint;
	}

	/** routine to convert from the 'exchangeValue' (uint) to the 'faceValue' (real) -- the value the user expects to see */
	real exchangeValueToFaceValue(uint exchangeValue) {
		return exchangeValue.to!real / faceToExchangeFactor;
	}
}

static uint[string] securityNamesToIDs;		// securityNamesToIDs := { [(string)symbol] = securityId, ... }
													
static SecurityInfo[1] securityInfos;		// securityInfos := { [(uint)securityId] = SecurityInfo, ... }
static this() {
	alias SecurityDatum = Tuple!(uint, string, real);
	SecurityDatum[] securityData = [
		SecurityDatum(0, "PETR4", 100.0.to!real),
	];
	securityNamesToIDs["PETR4"] = 0;
	securityInfos[securityNamesToIDs["PETR4"]] = SecurityInfo(0, "PETR4", 100.0.to!real);	// c++ requires "long double" and prices must be set as long double literals -- 37.05l
}

struct Order {
	uint       orderId;
	ETradeSide side;
	uint       exchangeValue;
	uint       quantity;
}

/** operations */
struct PriceLevel {

	Order[] orders;
	uint totalQuantity = 0;

	// operations on the 'PriceLevel' objects are moved to the 'AbstractDExchange' and derived classes,
	// for they change as the purpose of the '*DExchange' specialization.
	// They should, however, respect:
	//   1) the 'orders' array should behave like a queue: new orders go to the tail.
	//   2) editions to a member of 'orders' cause the edited member to go to the tail
	//   3) 'totalQuantity' must be updated appropriately, on enqueueing, cancelling and updating
	//   4) if 'trackedOrders' is used, the cancel methods must remove the orders also from theere

	/*
	void enqueueOrder(ref Order order) {
	orders ~= order;
	totalQuantity += order.quantity;
	// dispatch to everyone, even to the order creator
	foreach(session; onAdditionAndCancellationSessions) {
	session.onAddition(order.orderId, order.side, info.exchangeValueToFaceValue(order.exchangeValue), order.quantity);
	}
	}

	bool _cancelOrderFromId(uint orderId) {
	for (uint i=0; i<orders.length; i++) {
	if (orders[i].orderId == orderId) {
	// dispatch to everyone, even to the order canceller
	foreach(session; onAdditionAndCancellationSessions) {
	session.onCancellation(orders[i].orderId, orders[i].side, info.exchangeValueToFaceValue(orders[i].exchangeValue), orders[i].quantity);
	}
	totalQuantity -= orders[i].quantity;
	trackedOrders.remove(orders[i].orderId);
	orders = orders.remove(i);
	return true;
	}
	}
	return false;
	}

	bool _cancelOrderFromIndex(uint index) {
	// dispatch to everyone, even to the order canceller
	foreach(session; onAdditionAndCancellationSessions) {
	session.onCancellation(orders[index].orderId, orders[index].side, info.exchangeValueToFaceValue(orders[index].exchangeValue), orders[index].quantity);
	}
	totalQuantity -= orders[index].quantity;
	trackedOrders.remove(orders[index].orderId);
	orders = orders.remove(index);
	return true;
	}

	void cancelAllOrders() {
	foreach(ref order; orders) {
	// dispatch to everyone, even to the order canceller
	foreach(session; onAdditionAndCancellationSessions) {
	session.onCancellation(order.orderId, order.side, info.exchangeValueToFaceValue(order.exchangeValue), order.quantity);
	}
	trackedOrders.remove(order.orderId);
	}
	orders = orders.remove(tuple(0, orders.length));
	totalQuantity = 0;
	}*/
}
