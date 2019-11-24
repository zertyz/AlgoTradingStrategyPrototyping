module DExchange;

// develop with: d="DExchange"; while sleep 1; do for f in *.d; do if [ "$f" -nt "$d" ]; then echo -en "`date`: COMPILING..."; /c/D/dmd-2.089.0/windows/bin/dmd.exe -release -O -mcpu=native -m64 -unittest -main -boundscheck=on -lowmem -of="$d" "$d".d && echo -en "\n`date`: TESTING:  `ls -l "$d" | sed 's|.* \([0-9][0-9][0-9][0-9]*.*\)|\1|'`\n" && ./"$d" || echo -en '\n\n\n\n\n\n'; touch "$d"; fi; done; done

import std.stdio;

import std.math;
import std.algorithm;
import std.typecons;
import std.array;
import std.conv;


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

enum ETradeSide: uint {BUY, SELL}


/*

Notes:
	1) To represent exact values, prices and interests, we have 3 types of values:
       'exchangeValue' (uint), 'faceValue' (real), 'price' (real).
       1.1) 'price' and 'faceValue' will be the same if the security is currency based (as opposed to interest based).
            The functions 'SecurityInfo.exchangeValueToFaceValue()' and 'SecurityInfo.exchangeValueToPrice()' are able to convert
	   1.2) 'exchangeValue' represents a 'price' or 'faceValue' as an integer -- for currency based securities, this almost always
            imply multiplying by 100 in the faceValue->exchangeValue direction and deviding otherwise. Apart from the mentioned
            functions above, 'SecurityInfo.faceValueToExchangeValue()' should be used.

*/


class DExchange {

	struct SecurityInfo {
		/** prices in orders are multiplied by this amount in order to be representable by ints */
		real faceToExchangeFactor;
		// bandas, horários de negociação, lote mínimo, faceToPrice factor (ex: mini-indice bovespa tem price = 20%*face), etc.

		/** routine to convert from the 'faceValue' (real) to the 'exchangeValue' (uint) -- the value best manipulated by the exchange */
		uint faceValueToExchangeValue(real faceValue) {
			return (faceValue * faceToExchangeFactor).to!uint;
		}

		/** routine to convert from the 'exchangeValue' (uint) to the 'faceValue' (real) -- the value the user expects to see */
		real exchangeValueToFaceValue(uint exchangeValue) {
			return exchangeValue.to!real / faceToExchangeFactor;
		}
	}

	static SecurityInfo info = SecurityInfo(100.0.to!real);		// c++ requires "long double" and prices must be set as long double literals -- 37.05l

	// used when placing orders
	string party;

	// callbacks
	alias TOnExecutedOrderCallback  = void delegate (uint tradeEventId, uint orderId, ref Trade trade, bool isBuying);
	alias TOnTradeCallback          = void delegate (uint tradeEventId, ref Trade trade, bool isAttackingBids);
	alias TOnBookCallback           = void delegate (immutable PriceBookEntry[]* bidsPriceBook, immutable PriceBookEntry[]* asksPriceBook);
	alias TOnAddedOrderCallback     = void delegate (uint orderId, ETradeSide side, real limitFaceValue, uint quantity);
	alias TOnCancelledOrderCallback = TOnAddedOrderCallback;
	TOnExecutedOrderCallback           onExecutedOrderCallback;
	static TOnTradeCallback[]          onTradeCallbacks;
	// used to control whether to propagate 'onTrade' events to 'this' instance -- 'trade' will not be informed to a party whose
	// order participated on that trade -- for it already got the 'onExecution' event notification.
	TOnTradeCallback                   thisOnTradeCallback;
	static TOnBookCallback[]           onBookCallbacks;
	static TOnAddedOrderCallback[]     onAddedOrderCallbacks;
	static TOnCancelledOrderCallback[] onCancelledOrderCallbacks;
	// dummy callbacks (to be used a required callback is not passed)
	void dummyOnExecutedOrderCallback(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {}


	struct Order {
		uint       orderId;
		ETradeSide side;
		uint       exchangeValue;
		uint       quantity;
	}

	// tracked orders -- all active orders, indexeable by 'internalOrderId' (currently we use 'partyOrderId', trusting it will be unique)
	struct OrderInfo {
		string                   party;
		TOnExecutedOrderCallback onExecutionCallback;
		// necessário apenas para correlacionar trades e executions, de modo a não emitir eventos de trade para quem recebeu evento de executed order.
		// TODO: pensar melhor em como fazer isso.
		TOnTradeCallback         onTradeCallback;
	}
	static OrderInfo[uint] trackedOrders;	// := [ orderId: OrderInfo, ... ] 'OrderInfo' não poderia ser unificado com 'Order'?


	struct PriceLevel {
		Order[] orders;
		uint totalQuantity = 0;

		/** returns the sum of all 'quantity'ies in 'orders' */
/*		uint totalQuantity() {
			uint quantityAccumulator = 0;
			foreach (order; orders) {
				quantityAccumulator += order.quantity;
			}
			return quantityAccumulator;
		}
*/
		/** 'onNewOrder' event */
		void enqueueOrder(ref Order order) {
			orders ~= order;
			totalQuantity += order.quantity;
			// dispatch to everyone, even to the order creator
			foreach(onAddedOrderCallback; onAddedOrderCallbacks) {
				onAddedOrderCallback(order.orderId, order.side, info.exchangeValueToFaceValue(order.exchangeValue), order.quantity);
			}
		}

		/** 'onCancelledOrder' event for an 'orderId' */
		bool cancelOrderFromId(uint orderId) {
			for (uint i=0; i<orders.length; i++) {
				if (orders[i].orderId == orderId) {
					// dispatch to everyone, even to the order canceller
					foreach(onCancelledOrderCallback; onCancelledOrderCallbacks) {
						onCancelledOrderCallback(orders[i].orderId, orders[i].side, info.exchangeValueToFaceValue(orders[i].exchangeValue), orders[i].quantity);
					}
					totalQuantity -= orders[i].quantity;
					trackedOrders.remove(orders[i].orderId);
					orders = orders.remove(i);
					return true;
				}
			}
			return false;
		}

		/** 'onCancelledOrder' event for an orders[] 'index' */
		bool cancelOrderFromIndex(uint index) {
			// dispatch to everyone, even to the order canceller
			foreach(onCancelledOrderCallback; onCancelledOrderCallbacks) {
				onCancelledOrderCallback(orders[index].orderId, orders[index].side, info.exchangeValueToFaceValue(orders[index].exchangeValue), orders[index].quantity);
			}
			totalQuantity -= orders[index].quantity;
			trackedOrders.remove(orders[index].orderId);
			orders = orders.remove(index);
			return true;
		}

		/** 'onCancelledOrder' event for all of 'orders[]' */
		void cancelAllOrders() {
			foreach(ref order; orders) {
				// dispatch to everyone, even to the order canceller
				foreach(onCancelledOrderCallback; onCancelledOrderCallbacks) {
					onCancelledOrderCallback(order.orderId, order.side, info.exchangeValueToFaceValue(order.exchangeValue), order.quantity);
				}
				trackedOrders.remove(order.orderId);
			}
			orders = orders.remove(tuple(0, orders.length));
			totalQuantity = 0;
		}
	}

	static PriceLevel[uint] bids;
	static PriceLevel[uint] asks;


	static void resetBooks() {
		bids.clear();
		asks.clear();
		trackedOrders.clear();
	}

	this(string                    party,
		 TOnExecutedOrderCallback  onExecutedOrderCallback,
		 TOnTradeCallback          onTradeCallback,
		 TOnBookCallback           onBookCallback,
		 TOnAddedOrderCallback     onAddedOrderCallback,
		 TOnCancelledOrderCallback onCancelledOrderCallback) {

		this.party                   = party;
		this.onExecutedOrderCallback = onExecutedOrderCallback;
		this.thisOnTradeCallback     = onTradeCallback;

		// add to the static list
		if (onTradeCallback != null) {
			onTradeCallbacks ~= onTradeCallback;
		}
		if (onBookCallback != null) {
			onBookCallbacks ~= onBookCallback;
		}
		if (onAddedOrderCallback != null) {
			onAddedOrderCallbacks ~= onAddedOrderCallback;
		}
		if (onCancelledOrderCallback != null) {
			onCancelledOrderCallbacks ~= onCancelledOrderCallback;
		}
	}

	this(string                   party,
		 TOnExecutedOrderCallback onExecutedOrderCallback,
		 TOnTradeCallback         onTradeCallback) {
		this(party, onExecutedOrderCallback, onTradeCallback, null, null, null);
	}

	this(string party) {
		this(party, &dummyOnExecutedOrderCallback, null, null, null, null);
	}

	/** Dispatch 'onTrade' and 'onExecutedOrder' events.
	  * Performs like B3 (to check): parties involved on the trade will not receive the 'onTrade' event
	  * for they already received the 'onExecutedOrder' event for that trade. */
	void dispatchExecutionEvents(uint aggressedOrderId, uint aggressorOrderId, uint quantity, uint exchangeValue, ETradeSide aggressorSide) {
		static ulong time = 1000000000;
		static uint tradeEventId = 0;
		// get the info to build the 'Trade' object
		OrderInfo* aggressedOrderInfo = aggressedOrderId in trackedOrders;
		OrderInfo* aggressorOrderInfo = aggressorOrderId in trackedOrders;
		Trade trade = Trade(time++, quantity, info.exchangeValueToFaceValue(exchangeValue),
							aggressorSide == ETradeSide.BUY ? (*aggressorOrderInfo).party : (*aggressedOrderInfo).party,
							aggressorSide == ETradeSide.BUY ? (*aggressedOrderInfo).party : (*aggressorOrderInfo).party,
							"", aggressorOrderId, aggressedOrderId);
		// order execution callbacks
		(*aggressedOrderInfo).onExecutionCallback(tradeEventId, aggressedOrderId, trade, aggressorSide == ETradeSide.SELL);
		(*aggressorOrderInfo).onExecutionCallback(tradeEventId, aggressorOrderId, trade, aggressorSide == ETradeSide.BUY);
		// trade callbacks -- not for parties whose orders were just executed
		foreach(onTradeCallback; onTradeCallbacks) {
//			writeln("party=",party,"; onTradeCallback=",onTradeCallback,"; aggressorCallback=",(*aggressorOrderInfo).onExecutionCallback,"; aggressedCallback=",(*aggressedOrderInfo).onExecutionCallback);
			if ((*aggressedOrderInfo).onTradeCallback != onTradeCallback &&
				(*aggressorOrderInfo).onTradeCallback != onTradeCallback) {
				onTradeCallback(tradeEventId, trade, aggressorSide == ETradeSide.SELL);
			}
		}
		tradeEventId++;
	}

	/** builds the price level bids and asks books and dispatch them to the registered 'onBook' callbacks */
	void dispatchBookEvents() {
		static PriceBookEntry[] bidsPriceBook;
		static PriceBookEntry[] asksPriceBook;
		bool built = false;		// only build the book if there is someone to listen to it
		foreach (onBookCallback; onBookCallbacks) {
			if (!built) {
				buildPriceBookEntries(&bidsPriceBook, &asksPriceBook);
				built = true;
			}
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
	uint execute(PriceLevel* priceLevel, uint quantity, uint aggressorOrderId, uint exchangeValue, ETradeSide aggressorSide) {
		Order[]* orders = &((*priceLevel).orders);
		MatchAnalysis analysis = matchAnalysis(orders, quantity);
		// portion to fully execute
		for (uint i=0; i<analysis.fullyExecutableUntilIndex; i++) {
			//writeln("--> fully executing order #", (*orders)[i].orderId, " in response to agression #", aggressorOrderId);
			dispatchExecutionEvents((*orders)[i].orderId, aggressorOrderId, (*orders)[i].quantity, exchangeValue, aggressorSide);
			// remove the order from the 'onExecution' event notifications control list
			trackedOrders.remove((*orders)[i].orderId);
		}
		// remove all fully executed orders from the price point's order queue
		if (analysis.fullyExecutableUntilIndex > 0) {
			(*priceLevel).totalQuantity -= analysis.fullyExecutableQuantity;
			*orders = (*orders).remove(tuple(0, analysis.fullyExecutableUntilIndex));
		}
		// portion to partially execute
		if (analysis.partiallyExecutableQuantity > 0) {
			(*priceLevel).totalQuantity -= analysis.partiallyExecutableQuantity;
			(*orders)[0].quantity -= analysis.partiallyExecutableQuantity;
			//writeln("--> partially executing order #", (*orders)[0].orderId, " in response to agression #", aggressorOrderId);
			dispatchExecutionEvents((*orders)[0].orderId, aggressorOrderId, analysis.partiallyExecutableQuantity, exchangeValue, aggressorSide);
		}
		return analysis.fullyExecutableQuantity + analysis.partiallyExecutableQuantity;
	}

	bool addOrder(string oppositeBookSortExpr, ETradeSide side)
	             (PriceLevel[uint]* book, PriceLevel[uint]* oppositeBook, uint orderId, uint limitExchangeValue, uint quantity) {
		// prepare for the 'onExecuted' notifications
		trackedOrders[orderId] = OrderInfo(party, onExecutedOrderCallback, thisOnTradeCallback);
		// attempt to match this order against existing orders on the opposite book
		uint executedQuantity = 0;
		foreach(exchangeValueIndex; (*oppositeBook).keys.sort!(oppositeBookSortExpr)) {
			if (side == ETradeSide.BUY && exchangeValueIndex > limitExchangeValue) {
				break;
			} else if (side == ETradeSide.SELL && exchangeValueIndex < limitExchangeValue) {
				break;
			}
			PriceLevel* oppositePriceLevel = exchangeValueIndex in *oppositeBook;
			executedQuantity += execute(oppositePriceLevel, quantity-executedQuantity, orderId, exchangeValueIndex, side);
			if (executedQuantity >= quantity) {
				break;
			}
		}
		// enqueue the order if there is still any non executed quantity
		uint remainingQuantity = quantity-executedQuantity;
		if (remainingQuantity > 0) {
			// get & set the price level to which the order shall be added
			PriceLevel* priceLevel = limitExchangeValue in *book;
			if (priceLevel is null) {
				PriceLevel newPriceLevel = PriceLevel();
				(*book)[limitExchangeValue] = newPriceLevel;
				priceLevel = limitExchangeValue in *book;
			}
			// enqueue the remaining quantity
			Order order = Order(orderId, side, limitExchangeValue, remainingQuantity);
			(*priceLevel).enqueueOrder(order);
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

	bool addBuyOrder(uint orderId, real limitFaceValue, uint quantity) {
		return addOrder!("a < b", ETradeSide.BUY)(&bids, &asks, orderId, info.faceValueToExchangeValue(limitFaceValue), quantity);
	}

	bool addSellOrder(uint orderId, real limitFaceValue, uint quantity) {
		return addOrder!("a > b", ETradeSide.SELL)(&asks, &bids, orderId, info.faceValueToExchangeValue(limitFaceValue), quantity);
	}
	
	bool addOrder(ETradeSide side, uint orderId, real limitFaceValue, uint quantity) {
		final switch (side) {
		case ETradeSide.BUY:
			return addBuyOrder(orderId, limitFaceValue, quantity);
		case ETradeSide.SELL:
			return addSellOrder(orderId, limitFaceValue, quantity);
		}
	}

	struct PriceBookEntry {
		real price;
		uint quantity;
	}

	static void buildPriceBookEntries(PriceBookEntry[]* bidsPriceLevels, PriceBookEntry[]* asksPriceLevels) {
		(*bidsPriceLevels).length = 0;
		foreach(exchangeValueIndex; bids.keys.sort!("a > b")) {
			uint totalQuantity = bids[exchangeValueIndex].totalQuantity;
			if (totalQuantity > 0) {
				PriceBookEntry entry = PriceBookEntry(info.exchangeValueToFaceValue(exchangeValueIndex), totalQuantity);
				(*bidsPriceLevels) ~= entry;
			}
		}
		(*asksPriceLevels).length = 0;
		foreach(exchangeValueIndex; asks.keys.sort!("a < b")) {
			uint totalQuantity = asks[exchangeValueIndex].totalQuantity;
			if (totalQuantity > 0) {
				PriceBookEntry entry = PriceBookEntry(info.exchangeValueToFaceValue(exchangeValueIndex), totalQuantity);
				(*asksPriceLevels) ~= entry;
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
	DExchange amelia = new DExchange("Amelia", &onExecutedOrderAmelia, &onTradeAmelia, &onBookAmelia, null, null);

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


// testing infrastructure conditional compilation code
//////////////////////////////////////////////////////

version(unittest) {

	import std.random;
	import std.datetime;
	import std.format;


	SysTime testStartTime;
	SysTime subTestStartTime;
	uint testCount = 0;
	uint subTestsCount;
	uint orderId = 1;


	struct TestResults {
		real total;
		uint numberOfTransactions;

		bool opEquals(ref const TestResults other)
		{
			return other.numberOfTransactions == numberOfTransactions &&
				   abs(other.total-total) < 1e-6;
		}
	}

	// three ways of calculating the same results
	TestResults         onTradeResults;
	TestResults[string] onExecutionResults;		// := [ party: results, ... ]
	TestResults         expectedResults;
	// order tracking
	TestResults[string] onAdditionResults;		// := [ party~"_BUY": buyOrdersResults,          party~"_SELL": sellOrdersResults, ... ]
	TestResults[string] onCancellationResults;	// := [ party~"_BUY": cancelledBuyOrdersResults, party~"_SELL": cancelledSellOrdersResults, ... ]

	/** used to test a funcionality, mapped to a product owner requisite */
	void startTest(string requisiteName) {
		writeln(++testCount, ") ",requisiteName,":");
		stdout.flush();
		subTestsCount = 0;
		testStartTime = Clock.currTime();
	}

	/** used to test an indirect functionality/requisite -- usually a low level unfolding of a requisite defined
	    by the product owner or a developer/implementation defined behaviour (ultra low level requisite) */
	void startSubTest(string subtest) {
		write("\t",testCount,".",++subTestsCount,") ",subtest,"...");
		stdout.flush();
		subTestStartTime = Clock.currTime();
		DExchange.resetBooks();
		onExecutionResults.clear();
		onAdditionResults.clear();
		onCancellationResults.clear();
		onTradeResults  = TestResults(0, 0);
		expectedResults = TestResults(0, 0);
	}

	void finishSubTest(bool succeeded = true) {
		if (succeeded) {
			Duration elapsedTime = Clock.currTime() - subTestStartTime;
			writefln(" OK (%,dµs)", elapsedTime.total!"usecs");
		} else {
			writeln(" FAILED:");
		}
		stdout.flush();
	}

	void finishTest() {
		Duration elapsedTime = Clock.currTime() - testStartTime;
		writefln("\t--> DONE (%d sub-tests in %,dµs)", subTestsCount, elapsedTime.total!"usecs");
		stdout.flush();
	}

	void assertEquals(T)(T observed, T expected, string message) {
		if (observed != expected) {
			finishSubTest(false);
			writeln("\t\tAssertion Failed: ", message);
			writeln("\t\t\tObserved: ", observed);
			writeln("\t\t\tExpected: ", expected);
			assert(false);
		}
	}

	// callback for ignored events & statistics
	import std.functional;	// for 'toDelegate'
	uint[const(string)] onExecutedOrderCount/* = [ "John": 0u, "Mary": 0u, "Azelia": 0u ] <-- D still does not allow AA's on the static section of the object */;		// := { [party] = count, ... }
	void nullOnExecutedOrder(string party)(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {
		uint* element = party in onExecutedOrderCount;
		if (element == null) {
			onExecutedOrderCount[party] = 0u;
			element = party in onExecutedOrderCount;
		}
		(*element)++;
	}
	uint onTradeCount = 0;
	void nullOnTrade(uint tradeEventId, ref Trade trade, bool isAttackingBids) {
		onTradeCount++;
	}
	uint onBookCount = 0;
	void nullOnBook(immutable DExchange.PriceBookEntry[]* bidsPriceBook, immutable DExchange.PriceBookEntry[]* asksPriceBook) {
		onBookCount++;
	}

	/** assure there are orders on 'aggressedSide' at 'faceValue' (aka price) totalling, at least, 'quantity' (adding new orders as needed),
	while assuring there are no orders at the aggressor side at that price level (cancelling any existing ones). */
	void assureExecutability(ETradeSide aggressorSide, real faceValue, uint quantity) {
		uint exchangeValue = DExchange.info.faceValueToExchangeValue(faceValue);
		DExchange session = new DExchange("CounterParty");
		DExchange.PriceLevel* aggressedLevel;
		ETradeSide aggressedSide;
			// get the price 'level' book entry for aggressed side
		final switch (aggressorSide) {
			case ETradeSide.SELL:
				aggressedLevel = exchangeValue in DExchange.bids;
				if (!aggressedLevel) {
					DExchange.bids[exchangeValue] = DExchange.PriceLevel();
					aggressedLevel = exchangeValue in DExchange.bids;
				}
				aggressedSide = ETradeSide.BUY;
				break;
			case ETradeSide.BUY:
				aggressedLevel = exchangeValue in DExchange.asks;
				if (!aggressedLevel) {
					DExchange.asks[exchangeValue] = DExchange.PriceLevel();
					aggressedLevel = exchangeValue in DExchange.asks;
				}
				aggressedSide = ETradeSide.SELL;
				break;
		}
		// delete any existing orders (on both sides) that would prevent the creation of orders to be aggressed
		// (deletes orders at 'faceValue' on the to-be aggressed side, but leave them on the aggressor side)
		// treat the buy side
		foreach(exchangeValueIndex; DExchange.bids.keys.sort!("a > b")) {
			DExchange.PriceLevel* bidLevel = exchangeValueIndex in DExchange.bids;
			if ( (exchangeValueIndex == exchangeValue && aggressorSide == ETradeSide.SELL) || (exchangeValueIndex < exchangeValue) ) {
				break;
			}
			(*bidLevel).cancelAllOrders();
		}
		// treat the sell side
		foreach(exchangeValueIndex; DExchange.asks.keys.sort!("a < b")) {
			DExchange.PriceLevel* askLevel = exchangeValueIndex in DExchange.asks;
			if ( (exchangeValueIndex == exchangeValue && aggressorSide == ETradeSide.BUY) || (exchangeValueIndex > exchangeValue) ) {
				break;
			}
			(*askLevel).cancelAllOrders();
		}

		// assure enough counter-party orders are present on the to-be aggressed side
		uint totalQuantity = (*aggressedLevel).totalQuantity;
		if (totalQuantity < quantity) {
			uint missingQuantity = quantity - totalQuantity;
			// add the to-be aggressed order
			session.addOrder(aggressedSide, orderId++, faceValue, missingQuantity);
		}
	}

	/** Testing examples for 'assureExecutability' */
	unittest {

		startTest("Unit testing method 'assureExecutability' (which is, itself, a test method)");

		startSubTest("Assure a future BUY possibility on an empty");
		assureExecutability(ETradeSide.BUY, 10.32, 10800);
		assert(DExchange.asks[1032].totalQuantity == 10800, "to-be aggressed SELL order does not match");
		finishSubTest(true);

		startSubTest("Assure a future SELL possibility on an empty book");
		assureExecutability(ETradeSide.SELL, 10.32, 10800);
		assert(DExchange.bids[1032].totalQuantity == 10800, "to-be aggressed BUY order does not match");
		finishSubTest(true);

		startSubTest("Moving from BUY to SELL and then to BUY again, starting from an empty book");
		assureExecutability(ETradeSide.BUY, 10.32, 10800);
		assert(DExchange.asks[1032].totalQuantity == 10800, "to-be aggressed SELL order does not match");
		assureExecutability(ETradeSide.SELL, 10.32, 10800);
		assert(DExchange.asks[1032].totalQuantity == 0,     "future aggressor SELL order wasn't zeroed out");
		assert(DExchange.bids[1032].totalQuantity == 10800, "to-be aggressed BUY order does not match");
		assureExecutability(ETradeSide.BUY, 10.32, 10800);
		assert(DExchange.bids[1032].totalQuantity == 0,     "future aggressor BUY order wasn't zeroed out");
		assert(DExchange.asks[1032].totalQuantity == 10800, "to-be aggressed SELL order does not match");
		finishSubTest(true);

		finishTest();
	}

	/** Builds an innocuous book around 'faceValue' (aka price) using the following algorithm:
	  * 1) deletes all orders at 'faceValue' price level on both books;
	  * 2) add orders around 'faceValue' on both books that will not be instantly executed, leavning no price level gaps */
	void fillBook(real faceValue, uint maxBuyLevels, uint maxSellLevels, uint maxOrdersPerLevel, uint maxQuantityPerOrder) {
		uint exchangeValue = DExchange.info.faceValueToExchangeValue(faceValue);
		DExchange session = new DExchange("BookMaker");
		uint buyLevels  = min(uniform(maxBuyLevels/2, maxBuyLevels+1), exchangeValue-1);	// min exchangeValue-1 prevents the price from going below 0.01
		uint sellLevels = uniform(maxSellLevels/2, maxSellLevels+1);
		for (uint level=1; level<=max(buyLevels, sellLevels); level++) {
			uint delta      = level/* *0.01 */;
			bool shouldBuy  = level <= buyLevels;
			bool shouldSell = level <= sellLevels;
			// sell & buy loop -- orders will be added as needed to get the price level to the randomly chosen quantity
			for (uint areWeBuying = (shouldSell ? 0 : 1); areWeBuying <= (shouldBuy ? 1 : 0); areWeBuying++) {
				uint wantedQuantity   = uniform(1, (maxQuantityPerOrder+1)/100) * 100;
				DExchange.PriceLevel* priceLevel = areWeBuying ? (exchangeValue-delta) in DExchange.bids : (exchangeValue+delta) in DExchange.asks;
				uint existingQuantity = priceLevel ? (*priceLevel).totalQuantity : 0;
				if (existingQuantity < wantedQuantity) {
					uint missingQuantity = wantedQuantity - existingQuantity;
					if (areWeBuying) {
						session.addBuyOrder(orderId++, DExchange.info.exchangeValueToFaceValue(exchangeValue-delta), missingQuantity);
					} else {
						session.addSellOrder(orderId++, DExchange.info.exchangeValueToFaceValue(exchangeValue+delta), missingQuantity);
					}
				}
			}
		}
	}

	/** Testing examples for 'fillBook' */
	unittest {

		startTest("Unit testing method 'fillBook' (which is, itself, a test method)");

		void test(string testNamePrefix, real faceValue, uint minLevels, uint maxOrdersPerPriceLevel, uint maxOrderQty) {
			uint exchangeValue = DExchange.info.faceValueToExchangeValue(faceValue);
			startSubTest(testNamePrefix ~ " " ~ format!"%,3.2f"(faceValue) ~
						 " with, at least, " ~ format!"%,d"(minLevels) ~ 
						 " levels of up to " ~ format!"%,d"(maxOrdersPerPriceLevel) ~ 
						 " orders each (" ~ format!"%,d"(maxOrderQty) ~ 
						 " max qtys)");
			fillBook(faceValue, minLevels*2, minLevels*2, maxOrdersPerPriceLevel, maxOrderQty);
			// check bids
			foreach(exchangeValueIndex; DExchange.bids.keys.sort!("a > b")) {
				assert(exchangeValueIndex < exchangeValue, "no BID entry should be greater than nor equal to the given faceValue");
				assert(DExchange.bids[exchangeValueIndex].orders.length < maxOrdersPerPriceLevel, "more than the maximum number of orders were found at a BID price level");
				foreach(order; DExchange.bids[exchangeValueIndex].orders) {
					assert(order.quantity <= maxOrderQty, "an order with more than the maximum allowed quantity was found on the BIDs book");
				}
			}
			// check asks
			foreach(exchangeValueIndex; DExchange.asks.keys.sort!("a < b")) {
				assert(exchangeValueIndex > exchangeValue, "no ASK entry should be smaller than nor equal to the given faceValue");
				assert(DExchange.asks[exchangeValueIndex].orders.length < maxOrdersPerPriceLevel, "more than the maximum number of orders were found at an ASK price level");
				foreach(order; DExchange.asks[exchangeValueIndex].orders) {
					assert(order.quantity <= maxOrderQty, "an order with more than the maximum allowed quantity was found on the ASKs book");
				}
			}
			finishSubTest(true);
		}

		// test cases
		test("Building an empty, innocuous book around", 42.07, 50, 1000, 1000);
		test("Moving book to",                           42.06, 50, 1000, 1000);
		test("Moving back to",                           42.07, 50, 1000, 1000);
		DExchange.resetBooks();
		test("Building an empty book around", 0.10, 50, 100, 1000);
		test("Moving book to",                0.01, 50, 100, 1000);

		finishTest();
	}

	/** test debugging method: writes the price book to the console */
	void dumpPriceBook() {
		DExchange.PriceBookEntry[] bidsPriceBook;
		DExchange.PriceBookEntry[] asksPriceBook;
		DExchange.buildPriceBookEntries(&bidsPriceBook, &asksPriceBook);
		uint i=0;
		write("    BIDS = ");
		foreach(priceBookEntry; bidsPriceBook) {
			write("(",priceBookEntry.price,", ",priceBookEntry.quantity, "), ");
		}
		write("\n    ASKS = ");
		foreach(priceBookEntry; asksPriceBook) {
			write("(",priceBookEntry.price,", ",priceBookEntry.quantity, "), ");
		}
		writeln();
	}

}


unittest {

	startTest("Transaction tests");

	void onExecutedOrder(string party)
		                (uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {
		onExecutionResults.update(party, {
			return TestResults(trade.qty*trade.price, 1);
		}, (ref TestResults result) {
			result.total += trade.qty*trade.price;
			result.numberOfTransactions++;
			return result;
		});
	}
	void onAddedOrder(string party)
	                 (uint orderId, ETradeSide side, real limitFaceValue, uint quantity) {
		onAdditionResults.update(party~"_"~side.to!string, {
			return TestResults(limitFaceValue*quantity, 1);
		}, (ref TestResults result) {
			result.total += limitFaceValue*quantity;
			result.numberOfTransactions++;
			return result;
		});
//writeln("+++++",party,"+++++  \t detected an order was added: orderId=",orderId,"; side=",side,"; limitFaceValue=",limitFaceValue,"; quantity=",quantity);
	}
	void onCancelledOrder(string party)
		                 (uint orderId, ETradeSide side, real limitFaceValue, uint quantity) {
		onCancellationResults.update(party~"_"~side.to!string, {
			return TestResults(limitFaceValue*quantity, 1);
		}, (ref TestResults result) {
			result.total += limitFaceValue*quantity;
			result.numberOfTransactions++;
			return result;
		});
//writeln("-----",party,"-----  \t detected an order was added: orderId=",orderId,"; side=",side,"; limitFaceValue=",limitFaceValue,"; quantity=",quantity);
}
	DExchange john = new DExchange("John", &onExecutedOrder!"John", toDelegate(&nullOnTrade), toDelegate(&nullOnBook), &onAddedOrder!"John", &onCancelledOrder!"John");
	DExchange mary = new DExchange("Mary", &onExecutedOrder!"Mary", toDelegate(&nullOnTrade), toDelegate(&nullOnBook), &onAddedOrder!"Mary", &onCancelledOrder!"Mary");

	void azeliaOnTrade(uint tradeEventId, ref Trade trade, bool isAttackingBids) {
		onTradeResults.total += trade.qty*trade.price;
		onTradeResults.numberOfTransactions++;
	}
	DExchange azelia = new DExchange("Azelia", toDelegate(&nullOnExecutedOrder!"Azelia"), &azeliaOnTrade, toDelegate(&nullOnBook), &onAddedOrder!"Azelia", &onCancelledOrder!"Azelia");

	startSubTest("One order per price level, Aggressor selling");
	john.addBuyOrder(orderId++, 37.01, 100);
	john.addBuyOrder(orderId++, 37.02, 900);
	john.addBuyOrder(orderId++, 37.03, 800);
	john.addSellOrder(orderId++, 37.04, 200);
	john.addSellOrder(orderId++, 37.05, 600);
	john.addSellOrder(orderId++, 37.06, 700);
	mary.addSellOrder(orderId++, 37.02, 1000);
	expectedResults = TestResults(37.03*800+37.02*200, 2);
	assertEquals(onExecutionResults["John"], expectedResults, "Total $ in transactions, as accounted by 'onExecutedOrder[\"John\"]' events do not match.");
	assertEquals(onExecutionResults["Mary"], expectedResults, "Total $ in transactions, as accounted by 'onExecutedOrder[\"Mary\"]' events do not match.");
	assertEquals(onTradeResults,             expectedResults, "Total $ in transactions, as accounted by 'onTrade' events do not match");
	assertEquals(onAdditionResults["Azelia_BUY"],  TestResults(37.01*100+37.02*900+37.03*800, 3), "Azelia's AddedOrders callback accounted wrong BUYING results");
	assertEquals(onAdditionResults["Azelia_SELL"], TestResults(37.04*200+37.05*600+37.06*700, 3), "Azelia's AddedOrders callback accounted wrong SELLING results");
	finishSubTest(true);

	startSubTest("One order per price level, Aggressor buying");
	john.addBuyOrder(orderId++, 37.01, 100);
	john.addBuyOrder(orderId++, 37.02, 900);
	john.addBuyOrder(orderId++, 37.03, 800);
	john.addSellOrder(orderId++, 37.04, 200);
	john.addSellOrder(orderId++, 37.05, 600);
	john.addSellOrder(orderId++, 37.06, 700);
	mary.addBuyOrder(orderId++, 37.06, 1000);
	expectedResults = TestResults(37.04*200+37.05*600+37.06*200, 3);
	assertEquals(onExecutionResults["John"], expectedResults, "Total $ in transactions, as accounted by 'onExecutedOrder[\"John\"]' events do not match.");
	assertEquals(onExecutionResults["Mary"], expectedResults, "Total $ in transactions, as accounted by 'onExecutedOrder[\"Mary\"]' events do not match.");
	assertEquals(onTradeResults,             expectedResults, "Total $ in transactions, as accounted by 'onTrade' events do not match");
	assertEquals(onAdditionResults["Azelia_BUY"],  TestResults(37.01*100+37.02*900+37.03*800, 3), "Azelia's AddedOrders callback accounted wrong BUYING results");
	assertEquals(onAdditionResults["Azelia_SELL"], TestResults(37.04*200+37.05*600+37.06*700, 3), "Azelia's AddedOrders callback accounted wrong SELLING results");
	finishSubTest(true);

	startSubTest("Two orders per price level");
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
	expectedResults = TestResults(37.04*400+37.05*600, 3);
	assertEquals(onExecutionResults["John"], expectedResults, "Total $ in transactions, as accounted by 'onExecutedOrder[\"John\"]' events do not match.");
	assertEquals(onExecutionResults["Mary"], expectedResults, "Total $ in transactions, as accounted by 'onExecutedOrder[\"Mary\"]' events do not match.");
	assertEquals(onTradeResults,             expectedResults, "Total $ in transactions, as accounted by 'onTrade' events do not match");
	assertEquals(onAdditionResults["Azelia_BUY"],  TestResults(37.01*200+37.02*1800+37.03*1600, 6), "Azelia's AddedOrders callback accounted wrong BUYING results");
	assertEquals(onAdditionResults["Azelia_SELL"], TestResults(37.04*400+37.05*1200+37.06*1400, 6), "Azelia's AddedOrders callback accounted wrong SELLING results");
	finishSubTest(true);


	startSubTest("Random book, assure BUY executability at 37.06 and 37.08");
	// build a huge innocuous book, ready to execute a BUY operation at 37.06
	assureExecutability(ETradeSide.BUY, 37.06, 1800);
	fillBook(37.06, 8, 8, 15, 3700);
	// buy
	john.addBuyOrder(orderId++, 37.06, 1800);
	assertEquals(onTradeResults, TestResults(37.06*1800, 1), "Total $ in transactions, as accounted by 'onTrade' events do not match");
	// move the book, adding and deleting the minimum orders possible, to be ready to execute another BUY operation at 37.08
	onTradeResults = TestResults(0,0);
	assureExecutability(ETradeSide.BUY, 37.08, 9200);
	fillBook(37.08, 8, 8, 15, 3700);
	// buy again
	john.addBuyOrder(orderId++, 37.08, 1000);
	assertEquals(onTradeResults, TestResults(37.08*1000, onTradeResults.numberOfTransactions), "Total $ in transactions, as accounted by 'onTrade' events do not match");
	finishSubTest(true);

	startSubTest("Random book, assure SELL executability at 37.06 and 37.08");
	// fill & SELL at 37.06
	assureExecutability(ETradeSide.SELL, 37.06, 1800);
	fillBook(37.06, 8, 8, 15, 3700);
	mary.addSellOrder(orderId++, 37.06, 1800);
	assertEquals(onTradeResults, TestResults(37.06*1800, 1), "Total $ in transactions, as accounted by 'onTrade' events do not match");
	// move & SELL at 37.08
	onTradeResults = TestResults(0,0);
	assureExecutability(ETradeSide.SELL, 37.08, 9200);
	fillBook(37.08, 8, 8, 15, 3700);
	mary.addSellOrder(orderId++, 37.08, 1000);
	assertEquals(onTradeResults, TestResults(37.08*1000, onTradeResults.numberOfTransactions), "Total $ in transactions, as accounted by 'onTrade' events do not match");
	finishSubTest(true);


	void dumpAdditionsAndCancellations() {
		writef("ADDS: %d buy, %d sell; CANCELS: %d buy, %d sell",
			   onAdditionResults.require("Azelia_BUY",  TestResults(0, 0)).numberOfTransactions,
			   onAdditionResults.require("Azelia_SELL", TestResults(0, 0)).numberOfTransactions,
			   onCancellationResults.require("Azelia_BUY",  TestResults(0, 0)).numberOfTransactions,
			   onCancellationResults.require("Azelia_SELL", TestResults(0, 0)).numberOfTransactions);
	}


	startSubTest("filling & refilling book, minimizing order cancellations (please watch the outputs)");
	assureExecutability(ETradeSide.BUY, 37.06, 1800);
	write("\n\t\t ++ assure(d)Executability at 37.06: "); dumpAdditionsAndCancellations(); write(" -- "); onAdditionResults.clear(); onCancellationResults.clear();
	fillBook(37.06, 8, 8, 15, 3700);
	write("\n\t\t ++ fill(ed)Book around 37.06:       "); dumpAdditionsAndCancellations(); write(" -- "); onAdditionResults.clear(); onCancellationResults.clear();
	assureExecutability(ETradeSide.BUY, 37.07, 1800);
	write("\n\t\t >> assure(d)Executability at 37.07: "); dumpAdditionsAndCancellations(); write(" -- "); onAdditionResults.clear(); onCancellationResults.clear();
	fillBook(37.07, 8, 8, 15, 3700);
	write("\n\t\t >> fill(ed)Book to 37.07:           "); dumpAdditionsAndCancellations(); write(" -- "); onAdditionResults.clear(); onCancellationResults.clear();
	assureExecutability(ETradeSide.BUY, 37.06, 1800);
	write("\n\t\t << assure(d)Executability at 37.06: "); dumpAdditionsAndCancellations(); write(" -- "); onAdditionResults.clear(); onCancellationResults.clear();
	fillBook(37.06, 8, 8, 15, 3700);
	write("\n\t\t << fill(ed)Book back to 37.06:      "); dumpAdditionsAndCancellations(); write(" -- "); onAdditionResults.clear(); onCancellationResults.clear();
	finishSubTest(true);


	// remove unneeded callbacks to speed up the gremling tests
	DExchange.onBookCallbacks.remove(tuple(0, DExchange.onBookCallbacks.length));


	void gremling(uint startCents, uint endCents, ETradeSide side) {
		real expectedSumOfCents = ( (endCents-startCents+1) * ((endCents+startCents)/100.0) ) / 2.0;
		startSubTest("Gremling: "~side.to!string~"ing 1000 of all cents from "~format!"%,.2f"(startCents/100.0)~" to "~format!"%,.2f"(endCents/100.0)~"; then from "~format!"%,.2f"(endCents/100.0)~" to "~format!"%,.2f"(startCents/100.0));
		// back
		for (uint exchangeValue = endCents; exchangeValue >= startCents; exchangeValue--) {
			real faceValue = DExchange.info.exchangeValueToFaceValue(exchangeValue);
			assureExecutability(side, faceValue, 1800);
			fillBook(faceValue, 8, 8, 15, 3700);
			real oldOnTradeResults = onTradeResults.total;
			john.addOrder(side, orderId++, faceValue, 1000);
		}
		assertEquals(onTradeResults, TestResults(expectedSumOfCents*1000, max(endCents-startCents, onTradeResults.numberOfTransactions)), "Total $ in transactions in the BACK loop, as accounted by 'onTrade' events do not match");
		onTradeResults = TestResults(0, 0);
		// forth
		for (uint exchangeValue = startCents; exchangeValue <= endCents; exchangeValue++) {
			real faceValue = DExchange.info.exchangeValueToFaceValue(exchangeValue);
			assureExecutability(side, faceValue, 1800);
			fillBook(faceValue, 8, 8, 15, 3700);
			real oldOnTradeResults = onTradeResults.total;
			john.addOrder(side, orderId++, faceValue, 1000);
		}
		assertEquals(onTradeResults, TestResults(expectedSumOfCents*1000, max(endCents-startCents, onTradeResults.numberOfTransactions)), "Total $ in transactions in the FORTH loop, as accounted by 'onTrade' events do not match");
		write(" (");
		dumpAdditionsAndCancellations();	// NOTE about BACK and FORTH: different buy & sell orders are added depending on which of the above loops are executed first
		write(") --");
		finishSubTest(true);
	}

	uint multiplyer = 10;
	uint start = (100/multiplyer) - 1;	// from 0...
	// stress buying 
	for (uint dozens = start; dozens < (100/multiplyer); dozens++) {
		gremling(dozens*100*(multiplyer)+1, (dozens+1)*100*multiplyer, ETradeSide.BUY);
	}
	// stress selling 
	for (uint dozens = start; dozens < (100/multiplyer); dozens++) {
		gremling(dozens*100*(multiplyer)+1, (dozens+1)*100*multiplyer, ETradeSide.SELL);
	}

	finishTest();
}