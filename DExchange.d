module DExchange;

import std.stdio;

import std.math;
import std.algorithm;
import std.typecons;
import std.array;
import std.conv;


struct Trade {
	ulong   timeMilliS;
	uint   qty;
	double price;
	string buyer;
	string seller;
	string cond;
	uint aggressorOrderId;
	uint aggressedOrderId;

	bool timeEqualsMinutePrecision(ulong anotherTimeMilliS) const {
		return abs((timeMilliS/(1000*60)) - (anotherTimeMilliS/(1000*60))) <= 1;
	}
}


class DExchange {

	struct Order {
		uint   orderId;
		uint   quantity;
	}

	struct PriceLevel {
		double  priceLevel;
		Order[] orders;

		/** returns the sum of all 'quantity'ies in 'orders' */
		uint totalQuantity() {
			uint quantityAccumulator = 0;
			foreach (order; orders) {
				quantityAccumulator += order.quantity;
			}
			return quantityAccumulator;
		}

		void enqueueOrder(ref Order order) {
			orders.insertInPlace(orders.length, order);
		}
	}

	// used when placing orders
	string party;

	// callbacks
	alias TOnExecutedOrderCallback = void delegate (uint tradeEventId, uint orderId, ref Trade trade, bool isBuying);
	alias TOnTradeCallback         = void delegate (uint tradeEventId, ref Trade trade, bool isAttackingBids);
	alias TOnBookCallback          = void delegate (immutable PriceBookEntry[]* bidsPriceBook, immutable PriceBookEntry[]* asksPriceBook);
	TOnExecutedOrderCallback  onExecutedOrderCallback;
	static TOnTradeCallback[] onTradeCallbacks;
	// used to control whether to propagate 'onTrade' events to 'this' instance -- 'trade' will not be informed to a party whose
	// order participated on that trade -- for it already got the 'onExecution' event notification.
	TOnTradeCallback          thisOnTradeCallback;
	static TOnBookCallback[]  onBookCallbacks;

	// tracked orders -- all active orders, indexeable by 'internalOrderId' (currently we use 'partyOrderId', trusting it will be unique)
	struct OrderInfo {
		string                   party;
		TOnExecutedOrderCallback onExecutionCallback;
		// necessário apenas para correlacionar trades e executions, de modo a não emitir eventos de trade para quem recebeu evento de executed order.
		// TODO: pensar melhor em como fazer isso.
		TOnTradeCallback         onTradeCallback;
	}
	static OrderInfo[uint] trackedOrders;

	static PriceLevel[double] bids;
	static PriceLevel[double] asks;


	static void resetBooks() {
		bids.clear();
		asks.clear();
	}

	this(string                   party,
		 TOnExecutedOrderCallback onExecutedOrderCallback,
		 TOnTradeCallback         onTradeCallback,
		 TOnBookCallback          onBookCallback) {

		this.party                   = party;
		this.onExecutedOrderCallback = onExecutedOrderCallback;
		this.thisOnTradeCallback     = onTradeCallback;

		// add to the static list
		if (onTradeCallback != null) {
			onTradeCallbacks.insertInPlace(onTradeCallbacks.length, onTradeCallback);
		}
		if (onBookCallback != null) {
			onBookCallbacks.insertInPlace(onBookCallbacks.length,   onBookCallback);
		}
	}

	this(string                   party,
		 TOnExecutedOrderCallback onExecutedOrderCallback,
		 TOnTradeCallback         onTradeCallback) {
		this(party, onExecutedOrderCallback, onTradeCallback, null);
	}

	/** Dispatch 'onTrade' and 'onExecutedOrder' events.
	  * Performs like B3 (to check): parties involved on the trade will not receive the 'onTrade' event
	  * for they already received the 'onExecutedOrder' event for that trade. */
	void dispatchExecutionEvents(uint aggressedOrderId, uint aggressorOrderId, uint quantity, double price, bool isAggressorBuying) {
		static ulong time = 1000000000;
		static uint tradeEventId = 0;
		// get the info to build the 'Trade' object
		OrderInfo* aggressedOrderInfo = aggressedOrderId in trackedOrders;
		OrderInfo* aggressorOrderInfo = aggressorOrderId in trackedOrders;
		Trade trade = Trade(time++, quantity, price,
							isAggressorBuying ? (*aggressorOrderInfo).party : (*aggressedOrderInfo).party,
							isAggressorBuying ? (*aggressedOrderInfo).party : (*aggressorOrderInfo).party, "",
							aggressorOrderId, aggressedOrderId);
		// order execution callbacks
		(*aggressedOrderInfo).onExecutionCallback(tradeEventId, aggressedOrderId, trade, !isAggressorBuying);
		(*aggressorOrderInfo).onExecutionCallback(tradeEventId, aggressorOrderId, trade, isAggressorBuying);
		// trade callbacks -- not for parties whose orders were just executed
		foreach(onTradeCallback; onTradeCallbacks) {
//			writeln("party=",party,"; onTradeCallback=",onTradeCallback,"; aggressorCallback=",(*aggressorOrderInfo).onExecutionCallback,"; aggressedCallback=",(*aggressedOrderInfo).onExecutionCallback);
			if ((*aggressedOrderInfo).onTradeCallback != onTradeCallback &&
				(*aggressorOrderInfo).onTradeCallback != onTradeCallback) {
				onTradeCallback(tradeEventId, trade, !isAggressorBuying);
			}
		}
		tradeEventId++;
	}

	/** builds the price level bids and asks books and dispatch them to the registered 'onBook' callbacks */
	void dispatchBookEvents() {
		static PriceBookEntry[] bidsPriceBook;
		static PriceBookEntry[] asksPriceBook;
		buildPriceBookEntries(&bidsPriceBook, &asksPriceBook);
		foreach (onBookCallback; onBookCallbacks) {
			onBookCallback(cast(immutable)&bidsPriceBook, cast(immutable)&asksPriceBook);
		}
	}


	/** informs what to do if one is to really execute a quantity -- i.e. remove a quantity from an 'Order[]' array */
	struct MatchAnalysis {
		uint fullyExecutableUntilIndex;		// Exclusive. 0 if no order may be fully executed
		uint fullyExecutableQuantity;
		uint partiallyExecutableQuantity;	// if non 0, the order at index 'fullyExecutableUntilIndex' may be subtracted by this amount (for it is bigger than that)
	}
	/** returns what to do if one is to retrieve 'quantity' from the 'orders' array */
	MatchAnalysis matchAnalysis(Order[]* orders, uint quantity) {
		uint quantityAccumulator     = 0;
		uint lastQuantityAccumulator = 0;
		for (uint i=0; i < (*orders).length; i++) {
			uint currentQuantity = (*orders)[i].quantity;
			quantityAccumulator += currentQuantity;
			if (quantityAccumulator == quantity) {
				// may execute 'quantity' by fully executing all orders up to 'i'
				return MatchAnalysis(i+1, quantity, 0);
			}
			if (quantityAccumulator > quantity) {
				// may execute 'quantity' by fully executing all orders up to 'i-1' and
				// by partially executing the order at 'i', which should be subtracted by 'quantity-lastQuantityAccumulator'
				return MatchAnalysis(i, lastQuantityAccumulator, quantity-lastQuantityAccumulator);
			}
			lastQuantityAccumulator = quantityAccumulator;
		}
		if (quantityAccumulator == 0) {
			// nothing may be executed -- there are no orders!?
			return MatchAnalysis(0, 0, 0);
		} else {
			// even traversing through all available 'orders' wasn't enough to executed the wanted 'quantity'
			return MatchAnalysis((*orders).length.to!uint, quantityAccumulator, 0);
		}
	}

	/** takes up to 'quantity' from 'orders', returning how much could be retrieved. Elements from 'orders' are removed if fully taken. */
	uint execute(Order[]* orders, uint quantity, uint aggressorOrderId, double price, bool isAggressorBuying) {
		MatchAnalysis analysis = matchAnalysis(orders, quantity);
		// portion to fully execute
		for (uint i=0; i<analysis.fullyExecutableUntilIndex; i++) {
			//writeln("--> fully executing order #", (*orders)[i].orderId, " in response to agression #", aggressorOrderId);
			dispatchExecutionEvents((*orders)[i].orderId, aggressorOrderId, (*orders)[i].quantity, price, isAggressorBuying);
			// remove the order from the 'onExecution' event notifications control list
			trackedOrders.remove((*orders)[i].orderId);
		}
		// remove all fully executed orders from the price point's order queue
		if (analysis.fullyExecutableUntilIndex > 0) {
			*orders = (*orders).remove(tuple(0, analysis.fullyExecutableUntilIndex));
		}
		// portion to partially execute
		if (analysis.partiallyExecutableQuantity > 0) {
			(*orders)[0].quantity -= analysis.partiallyExecutableQuantity;
			//writeln("--> partially executing order #", (*orders)[0].orderId, " in response to agression #", aggressorOrderId);
			dispatchExecutionEvents((*orders)[0].orderId, aggressorOrderId, analysis.partiallyExecutableQuantity, price, isAggressorBuying);
		}
		return analysis.fullyExecutableQuantity + analysis.partiallyExecutableQuantity;
	}

	bool addOrder(string oppositeBookSortExpr, bool isBuying)
	(PriceLevel[double]* book, PriceLevel[double]* oppositeBook, uint orderId, double limitPrice, uint quantity) {
		// prepare for the 'onExecuted' notifications
		trackedOrders[orderId] = OrderInfo(party, onExecutedOrderCallback, thisOnTradeCallback);
		// attempt to match this order against existing orders on the opposite book
		uint executedQuantity = 0;
		foreach(priceIndex; (*oppositeBook).keys.sort!(oppositeBookSortExpr)) {
			static if (isBuying) {
				if (limitPrice-priceIndex < -0.001) {
					break;
				}
			} else {
				if (priceIndex-limitPrice < -0.001) {
					break;
				}
			}
			PriceLevel* oppositePriceLevel = priceIndex in *oppositeBook;
			executedQuantity += execute(&((*oppositePriceLevel).orders), quantity-executedQuantity, orderId, priceIndex, isBuying);
			if (executedQuantity >= quantity) {
				break;
			}
		}
		// enqueue the order if there is still any non executed quantity
		uint remainingQuantity = quantity-executedQuantity;
		if (remainingQuantity > 0) {
			// get & set the price level to which the order shall be added
			PriceLevel* priceLevel = limitPrice in *book;
			if (priceLevel is null) {
				PriceLevel newPriceLevel = PriceLevel(limitPrice);
				(*book)[limitPrice] = newPriceLevel;
				priceLevel = limitPrice in *book;
			}
			// enqueue the remaining quantity
			Order buyOrder = Order(orderId, remainingQuantity);
			(*priceLevel).enqueueOrder(buyOrder);
			// price book events
			dispatchBookEvents();
			return true;
		} else {
			// remove from the 'onExecuted' notifications, since the order was immediately fully executed
			trackedOrders.remove(orderId);
			// price book events
			if (executedQuantity > 0) {
				dispatchBookEvents();
			}
			return false;
		}
	}

	bool addBuyOrder(uint orderId, double limitPrice, uint quantity) {
		return addOrder!("a < b", true)(&bids, &asks, orderId, limitPrice, quantity);
	}

	bool addSellOrder(uint orderId, double limitPrice, uint quantity) {
		return addOrder!("a > b", false)(&asks, &bids, orderId, limitPrice, quantity);
	}

	struct PriceBookEntry {
		double price;
		uint   quantity;
	}

	void buildPriceBookEntries(PriceBookEntry[]* bidsPriceLevels, PriceBookEntry[]* asksPriceLevels) {
		(*bidsPriceLevels).length = 0;
		foreach(priceIndex; bids.keys.sort!("a > b")) {
			uint totalQuantity = bids[priceIndex].totalQuantity;
			if (totalQuantity > 0) {
				PriceBookEntry entry = PriceBookEntry(priceIndex, totalQuantity);
				(*bidsPriceLevels).insertInPlace((*bidsPriceLevels).length, entry);
			}
		}
		(*asksPriceLevels).length = 0;
		foreach(priceIndex; asks.keys.sort!("a < b")) {
			uint totalQuantity = asks[priceIndex].totalQuantity;
			if (totalQuantity > 0) {
				PriceBookEntry entry = PriceBookEntry(priceIndex, totalQuantity);
				(*asksPriceLevels).insertInPlace((*asksPriceLevels).length, entry);
			}
		}
	}

}

// test methods

void test() {

	uint orderId = 1;

	void onExecutedOrderJohn(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {
		writeln("--> JOHN: my order #",orderId,", attempting to ",isBuying?"BUY":"SELL",", was executed in ",trade.qty," units for $",trade.price," each");
	}
	void onTradeJohn(uint tradeEventId, ref Trade trade, bool isAttackingBids) {
		writeln("--> JOHN: trade #",tradeEventId,": aggressor #",trade.aggressorOrderId," ",isAttackingBids?"SOLD":"BOUGHT", " ",trade.qty," ",isAttackingBids?"to":"from"," order #", trade.aggressedOrderId, " for $",trade.price);
	}

	void onExecutedOrderMary(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {
		writeln("--> MARY: my order #",orderId,", attempting to ",isBuying?"BUY":"SELL",", was executed in ",trade.qty," units for $",trade.price," each");
	}
	void onTradeMary(uint tradeEventId, ref Trade trade, bool isAttackingBids) {
		writeln("--> MARY: trade #",tradeEventId,": aggressor #",trade.aggressorOrderId," ",isAttackingBids?"SOLD":"BOUGHT", " ",trade.qty," ",isAttackingBids?"to":"from"," order #", trade.aggressedOrderId, " for $",trade.price);
	}

	void onExecutedOrderAmelia(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {
		writeln("--> AMELIA: my order #",orderId,", attempting to ",isBuying?"BUY":"SELL",", was executed in ",trade.qty," units for $",trade.price," each");
	}
	void onTradeAmelia(uint tradeEventId, ref Trade trade, bool isAttackingBids) {
		writeln("--> AMELIA: trade #",tradeEventId,
				": aggressor #",trade.aggressorOrderId," (",isAttackingBids?trade.seller:trade.buyer,") ",
				isAttackingBids?"SOLD":"BOUGHT", " ",trade.qty," ",
				isAttackingBids?"to":"from"," order #", trade.aggressedOrderId," (",isAttackingBids?trade.buyer:trade.seller,
				") for $",trade.price);
	}

	void onBookAmelia(immutable DExchange.PriceBookEntry[]* bidsPriceBook, immutable DExchange.PriceBookEntry[]* asksPriceBook) {
		uint i=0;
		write("    BIDS = ");
		foreach(priceBookEntry; *bidsPriceBook) {
			write("(",priceBookEntry.price,", ",priceBookEntry.quantity, "), ");
		}
		write("\n    ASKS = ");
		foreach(priceBookEntry; *asksPriceBook) {
			write("(",priceBookEntry.price,", ",priceBookEntry.quantity, "), ");
		}
		writeln();
	}

	DExchange john = new DExchange("John", &onExecutedOrderJohn, &onTradeJohn);
	DExchange mary = new DExchange("Mary", &onExecutedOrderMary, &onTradeMary);
	DExchange amelia = new DExchange("Amelia", &onExecutedOrderAmelia, &onTradeAmelia, &onBookAmelia);

	writeln();
	DExchange.resetBooks();
	john.addBuyOrder(orderId++, 37.01, 100);
	john.addBuyOrder(orderId++, 37.02, 900);
	john.addBuyOrder(orderId++, 37.03, 800);
	john.addSellOrder(orderId++, 37.04, 200);
	john.addSellOrder(orderId++, 37.05, 600);
	john.addSellOrder(orderId++, 37.06, 700);
	mary.addSellOrder(orderId++, 37.02, 1000);

	writeln();
	DExchange.resetBooks();
	john.addBuyOrder(orderId++, 37.01, 100);
	john.addBuyOrder(orderId++, 37.02, 900);
	john.addBuyOrder(orderId++, 37.03, 800);
	john.addSellOrder(orderId++, 37.04, 200);
	john.addSellOrder(orderId++, 37.05, 600);
	john.addSellOrder(orderId++, 37.06, 700);
	mary.addBuyOrder(orderId++, 37.06, 1000);

	writeln();
	DExchange.resetBooks();
	mary.addBuyOrder(orderId++, 37.01, 100);
	mary.addBuyOrder(orderId++, 37.02, 900);
	mary.addBuyOrder(orderId++, 37.03, 800);
	mary.addSellOrder(orderId++, 37.04, 200);
	mary.addSellOrder(orderId++, 37.05, 600);
	mary.addSellOrder(orderId++, 37.06, 700);
	mary.addBuyOrder(orderId++, 37.01, 100);
	mary.addBuyOrder(orderId++, 37.02, 900);
	mary.addBuyOrder(orderId++, 37.03, 800);
	mary.addSellOrder(orderId++, 37.04, 200);
	mary.addSellOrder(orderId++, 37.05, 600);
	mary.addSellOrder(orderId++, 37.06, 700);
	john.addBuyOrder(orderId++, 37.06, 1000);

}
