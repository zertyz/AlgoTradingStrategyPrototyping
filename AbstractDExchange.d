module AbstractDExchange;

import std.math;
import std.conv;
import std.algorithm;
import std.typecons : tuple;

import Types : ETradeSide, PriceBookEntry;
import AbstractDExchangeSession;

version (unittest) {
	import TestUtils;
}

abstract class AbstractDExchange {

	struct SecurityInfo {
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

	SecurityInfo info = SecurityInfo(100.0.to!real);		// c++ requires "long double" and prices must be set as long double literals -- 37.05l

	struct Order {
		uint       orderId;
		ETradeSide side;
		uint       exchangeValue;
		uint       quantity;
	}

	// tracked orders -- all active orders, indexeable by 'internalOrderId' (currently we use 'partyOrderId', trusting it will be unique)
	struct OrderInfo {
		string                   party;
		AbstractDExchangeSession session;
	}
	OrderInfo[uint] trackedOrders;	// := [ orderId: OrderInfo, ... ] 'OrderInfo' não poderia ser unificado com 'Order'?


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

	// books
	PriceLevel[uint] bids;
	PriceLevel[uint] asks;


	void resetBooks() {
		bids.clear();
		asks.clear();
		trackedOrders.clear();
	}


	// matching & execution
	///////////////////////

	/** informs what to do if one is to really execute a quantity -- i.e. remove a quantity from an 'Order[]' array */
	struct MatchAnalysis {
		uint fullyExecutableUntilIndex;		// Exclusive. 0 if no order may be fully executed
		uint fullyExecutableQuantity;
		uint partiallyExecutableQuantity;	// if non 0, the order at index 'fullyExecutableUntilIndex' may be subtracted by this amount (for it is bigger than that)
	}
	/** returns what to do if one is to retrieve 'quantity' from the 'orders' array */
	static MatchAnalysis matchAnalysis(Order[]* orders, uint quantity) {
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

	/** Testing examples for 'matchAnalysis' */
	unittest {

		TestUtils testUtils = new TestUtils();

		testUtils.startTest("Unit testing method 'matchAnalysis'");

		MatchAnalysis observed;
		MatchAnalysis expected;
		Order[] emptyOrderArray;
		Order[] complexOrderArray = [Order(0, ETradeSide.BUY, 0, 100),
		                             Order(0, ETradeSide.BUY, 0, 300),
		Order(0, ETradeSide.BUY, 0, 500)];

		testUtils.startSubTest("Empty price level");
		expected = MatchAnalysis(0, 0, 0);
		observed = matchAnalysis(&emptyOrderArray, 100);
		testUtils.assertEquals(observed, expected, "Empty price level test failed");
		testUtils.finishSubTest(true);

		testUtils.startSubTest("Full match fully executing the first order");
		expected = MatchAnalysis(1, 100, 0);
		observed = matchAnalysis(&complexOrderArray, 100);
		testUtils.assertEquals(observed, expected, "Match analysis do not match");
		testUtils.finishSubTest(true);

		testUtils.startSubTest("Partially match and half executing the first order");
		expected = MatchAnalysis(0, 0, 50);
		observed = matchAnalysis(&complexOrderArray, 50);
		testUtils.assertEquals(observed, expected, "Match analysis do not match");
		testUtils.finishSubTest(true);

		testUtils.startSubTest("Full match fully executing the first two orders");
		expected = MatchAnalysis(2, 400, 0);
		observed = matchAnalysis(&complexOrderArray, 400);
		testUtils.assertEquals(observed, expected, "Match analysis do not match");
		testUtils.finishSubTest(true);

		testUtils.startSubTest("Full match fully executing the first order and partially the second");
		expected = MatchAnalysis(1, 100, 150);
		observed = matchAnalysis(&complexOrderArray, 250);
		testUtils.assertEquals(observed, expected, "Match analysis do not match");
		testUtils.finishSubTest(true);

		testUtils.startSubTest("Full match fully executing all orders");
		expected = MatchAnalysis(3, 900, 0);
		observed = matchAnalysis(&complexOrderArray, 900);
		testUtils.assertEquals(observed, expected, "Match analysis do not match");
		testUtils.finishSubTest(true);

		testUtils.startSubTest("Partial match fully executing all orders");
		expected = MatchAnalysis(3, 900, 0);
		observed = matchAnalysis(&complexOrderArray, 1800);
		testUtils.assertEquals(observed, expected, "Match analysis do not match");
		testUtils.finishSubTest(true);

		testUtils.finishTest();
	}

	/** takes up to 'quantity' from 'orders', returning how much could be retrieved. Elements from 'orders' are removed if fully taken. */
	uint execute(PriceLevel* priceLevel, uint quantity, uint aggressorOrderId, string aggressorParty, uint exchangeValue, ETradeSide aggressorSide) {
		Order[]* orders = &((*priceLevel).orders);
		MatchAnalysis analysis = matchAnalysis(orders, quantity);
		// portion to fully execute
		for (uint i=0; i<analysis.fullyExecutableUntilIndex; i++) {
			//writeln("--> fully executing order #", (*orders)[i].orderId, " in response to agression #", aggressorOrderId);
			dispatchExecutionEvents((*orders)[i].orderId, aggressorOrderId, aggressorParty, (*orders)[i].quantity, exchangeValue, aggressorSide);
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
			dispatchExecutionEvents((*orders)[0].orderId, aggressorOrderId, aggressorParty, analysis.partiallyExecutableQuantity, exchangeValue, aggressorSide);
		}
		return analysis.fullyExecutableQuantity + analysis.partiallyExecutableQuantity;
	}


	// price book building
	//////////////////////

	void buildPriceBookEntries(PriceBookEntry[]* bidsPriceLevels, PriceBookEntry[]* asksPriceLevels) {
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


	// internal order manipulation
	//////////////////////////////


	/** internally enqueue the order on the appropriate 'PriceLevel', so the 'Addition' event will be dispatched and the
	    order will be available for aggression (execution) and all other operations -- updating, cancellation, ... */
	void enqueueOrder(string party, ref PriceLevel priceLevel, ref Order order) {
		priceLevel.orders ~= order;
		priceLevel.totalQuantity += order.quantity;
		dispatchAdditionEvents(party, order.orderId, order.side, info.exchangeValueToFaceValue(order.exchangeValue), order.quantity);
	}

	/** internally removes all orders from the given 'priceLevel', dispatching the 'Cancellation' events for each order & session */
	void cancelAllOrders(string party, ref PriceLevel priceLevel) {
		foreach(ref order; priceLevel.orders) {
			trackedOrders.remove(order.orderId);
			dispatchCancellationEvents(party, order.orderId, order.side, info.exchangeValueToFaceValue(order.exchangeValue), order.quantity);
		}
		priceLevel.orders = priceLevel.orders.remove(tuple(0, priceLevel.orders.length));
		priceLevel.totalQuantity = 0;
	}

	bool addOrder(string oppositeBookSortExpr, ETradeSide side)
	             (PriceLevel[uint]* book, PriceLevel[uint]* oppositeBook, string party, AbstractDExchangeSession session,
	             uint orderId, uint limitExchangeValue, uint quantity) {
			// attempt to match this order against existing orders on the opposite book
			uint executedQuantity = 0;
			foreach(exchangeValueIndex; (*oppositeBook).keys.sort!(oppositeBookSortExpr)) {
				if (side == ETradeSide.BUY && exchangeValueIndex > limitExchangeValue) {
					break;
				} else if (side == ETradeSide.SELL && exchangeValueIndex < limitExchangeValue) {
					break;
				}
				PriceLevel* oppositePriceLevel = exchangeValueIndex in *oppositeBook;
				if (oppositePriceLevel != null) {
					executedQuantity += execute(oppositePriceLevel, quantity-executedQuantity, orderId, party, exchangeValueIndex, side);
					if (executedQuantity >= quantity) {
						break;
					}
				}
			}
			// enqueue the order if there is still any non executed quantity
			uint remainingQuantity = quantity-executedQuantity;
			if (remainingQuantity > 0) {
				// get & set the price level to which the order shall be added
				PriceLevel* priceLevel = limitExchangeValue in *book;
				if (priceLevel is null) {
					PriceLevel newPriceLevel;
					(*book)[limitExchangeValue] = newPriceLevel;
					priceLevel = limitExchangeValue in *book;
				}
				// enqueue the remaining quantity
				Order order = Order(orderId, side, limitExchangeValue, remainingQuantity);
				// prepare for the 'Executed' events & enqueue the order on the book
				trackedOrders[orderId] = OrderInfo(party, session);
				enqueueOrder(party, *priceLevel, order);
				// price book events
				dispatchBookEvents();
				return true;
			} else {
				// price book events
				if (executedQuantity > 0) {
					dispatchBookEvents();
				}
				return false;
			}
		 }

	bool addBuyOrder(string party, AbstractDExchangeSession session, uint orderId, real limitFaceValue, uint quantity) {
		return addOrder!("a < b", ETradeSide.BUY)(&bids, &asks, party, session, orderId, info.faceValueToExchangeValue(limitFaceValue), quantity);
	}

	bool addSellOrder(string party, AbstractDExchangeSession session, uint orderId, real limitFaceValue, uint quantity) {
		return addOrder!("a > b", ETradeSide.SELL)(&asks, &bids, party, session, orderId, info.faceValueToExchangeValue(limitFaceValue), quantity);
	}


	// external order manipulation
	//////////////////////////////

	/** instructs the exchange that the authenticated 'party' wants to add an order with the specified parameters.
	  * Returns the 'DEOrderId' -- the internal DExchange's order id, which, from now on, should be used reference each particular order. */
	bool addOrder(ETradeSide side, string party, AbstractDExchangeSession session, uint orderId, real limitFaceValue, uint quantity) {
		final switch (side) {
			case ETradeSide.BUY:
				return addBuyOrder(party, session, orderId, limitFaceValue, quantity);
			case ETradeSide.SELL:
				return addSellOrder(party, session, orderId, limitFaceValue, quantity);
		}
	}



	// event dispatching methods
	////////////////////////////

	/** Dispatch order 'Addition' events for all session, excluding the session adding the order */
	abstract void dispatchAdditionEvents(string party, uint orderId, ETradeSide side, real faceValue, uint quantity);

	/** Dispatch order 'Cancellation' events for all session, excluding the session adding the order */
	abstract void dispatchCancellationEvents(string party, uint orderId, ETradeSide side, real faceValue, uint quantity);

	/** Dispatch 'Trade' and order 'Execution' events.
	  * priority: Execution, Trade (only called for sessions not called on 'onExecution' -- that is: only called for parties not involved on the trade) */
	abstract void dispatchExecutionEvents(uint aggressedOrderId, uint aggressorOrderId, string aggressorParty, uint quantity, uint exchangeValue, ETradeSide aggressorSide);

	/** builds the price 'bids' and 'asks' books and dispatch the 'Book' event. */
	abstract void dispatchBookEvents();

}
