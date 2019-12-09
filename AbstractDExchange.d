module AbstractDExchange;

import std.stdio;
import std.math;
import std.conv;
import std.algorithm;
import std.array;
import std.typecons : tuple;

import Types : ETradeSide, PriceBookEntry, Order, PriceLevel, securityInfos;
import AbstractDExchangeSession;

version (unittest) {
	import TestUtils;
}

abstract class AbstractDExchange {

	// tracked orders -- all active orders, indexeable by 'internalOrderId' (currently we use 'partyOrderId', trusting it will be unique)
	struct OrderInfo {
		string                   party;
		AbstractDExchangeSession session;
	}
	OrderInfo[uint][securityInfos.length] trackedOrders;	// := { [securityId] = { [orderId] = OrderInfo, ... }, ... } não poderiamos unificar 'OrderInfo' com 'Order'?

	// books
	PriceLevel[uint][securityInfos.length] bids;	// := { [securityId] = { [price1] = PriceLevel, ... }, ... };
	PriceLevel[uint][securityInfos.length] asks;	// idem


	void resetBooks() {
		for (uint i=0; i<securityInfos.length; i++) {
			bids[i].clear();
			asks[i].clear();
			trackedOrders[i].clear();
		}
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
	uint execute(uint securityId, PriceLevel* priceLevel, uint quantity, uint aggressorOrderId, AbstractDExchangeSession aggressorSession, uint exchangeValue, ETradeSide aggressorSide) {
		Order[]* orders = &((*priceLevel).orders);
		MatchAnalysis analysis = matchAnalysis(orders, quantity);
		// portion to fully execute
		for (uint i=0; i<analysis.fullyExecutableUntilIndex; i++) {
			//writeln("--> fully executing order #", (*orders)[i].orderId, " in response to agression #", aggressorOrderId);
			dispatchExecutionEvents(securityId, (*orders)[i].orderId, aggressorOrderId, aggressorSession, (*orders)[i].quantity, exchangeValue, aggressorSide);
			// remove the order from the 'onExecution' event notifications control list
			trackedOrders[securityId].remove((*orders)[i].orderId);
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
			dispatchExecutionEvents(securityId, (*orders)[0].orderId, aggressorOrderId, aggressorSession, analysis.partiallyExecutableQuantity, exchangeValue, aggressorSide);
		}
		return analysis.fullyExecutableQuantity + analysis.partiallyExecutableQuantity;
	}


	// price book building
	//////////////////////

	/** generate the structures to be passed by the callbacks wishing to receive the 'Book' changed event */
	void buildPriceBookEntries(uint securityId, PriceBookEntry[]* bidsPriceLevels, PriceBookEntry[]* asksPriceLevels) {
		(*bidsPriceLevels).length = 0;
		foreach(keyVal; bids[securityId].byKeyValue.array.sort!"a.key > b.key") {
			uint exchangeValueIndex = keyVal.key;
			PriceLevel bidLevel = keyVal.value;
			uint totalQuantity = bidLevel.totalQuantity;
			if (totalQuantity > 0) {
				PriceBookEntry entry = PriceBookEntry(securityInfos[securityId].exchangeValueToFaceValue(exchangeValueIndex), totalQuantity);
				(*bidsPriceLevels) ~= entry;
			}
		}
		(*asksPriceLevels).length = 0;
		foreach(keyVal; asks[securityId].byKeyValue.array.sort!"a.key < b.key") {
			uint exchangeValueIndex = keyVal.key;
			PriceLevel askLevel = keyVal.value;
			uint totalQuantity = askLevel.totalQuantity;
			if (totalQuantity > 0) {
				PriceBookEntry entry = PriceBookEntry(securityInfos[securityId].exchangeValueToFaceValue(exchangeValueIndex), totalQuantity);
				(*asksPriceLevels) ~= entry;
			}
		}
	}


	// internal order manipulation
	//////////////////////////////


	/** internally enqueue the order on the appropriate 'PriceLevel', so the 'Addition' event will be dispatched and the
	    order will be available for aggression (execution) and all other operations -- updating, cancellation, ... */
	void enqueueOrder(uint securityId, string party, ref PriceLevel priceLevel, ref Order order) {
		priceLevel.orders ~= order;
		priceLevel.totalQuantity += order.quantity;
		dispatchAdditionEvents(securityId, party, order.orderId, order.side, securityInfos[securityId].exchangeValueToFaceValue(order.exchangeValue), order.quantity);
	}

	/** internally removes all orders from the given 'priceLevel', dispatching the 'Cancellation' events for each order & session */
	void cancelAllOrders(uint securityId, string party, ref PriceLevel priceLevel) {
		foreach(ref order; priceLevel.orders) {
			trackedOrders[securityId].remove(order.orderId);
			dispatchCancellationEvents(securityId, party, order.orderId, order.side, securityInfos[securityId].exchangeValueToFaceValue(order.exchangeValue), order.quantity);
		}
		priceLevel.orders = priceLevel.orders.remove(tuple(0, priceLevel.orders.length));
		priceLevel.totalQuantity = 0;
	}

	bool addOrder(string oppositeBookSortExpr, ETradeSide side)
	             (uint securityId, PriceLevel[uint]* book, PriceLevel[uint]* oppositeBook, AbstractDExchangeSession session,
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
				if (oppositePriceLevel != null && (*oppositePriceLevel).totalQuantity > 0) {
					executedQuantity += execute(securityId, oppositePriceLevel, quantity-executedQuantity, orderId, session, exchangeValueIndex, side);
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
				trackedOrders[securityId][orderId] = OrderInfo(session.party, session);
				enqueueOrder(securityId, session.party, *priceLevel, order);
				// price book events
				dispatchBookEvents(securityId);
				return true;
			} else {
				// price book events
				if (executedQuantity > 0) {
					dispatchBookEvents(securityId);
				}
				return false;
			}
		 }

	bool addBuyOrder(uint securityId, AbstractDExchangeSession session, uint orderId, real limitFaceValue, uint quantity) {
		return addOrder!("a < b", ETradeSide.BUY)(securityId, &bids[securityId], &asks[securityId], session, orderId, securityInfos[securityId].faceValueToExchangeValue(limitFaceValue), quantity);
	}

	bool addSellOrder(uint securityId, AbstractDExchangeSession session, uint orderId, real limitFaceValue, uint quantity) {
		return addOrder!("a > b", ETradeSide.SELL)(securityId, &asks[securityId], &bids[securityId], session, orderId, securityInfos[securityId].faceValueToExchangeValue(limitFaceValue), quantity);
	}


	// external order manipulation
	//////////////////////////////

	/** instructs the exchange that the authenticated 'party' wants to add an order with the specified parameters.
	  * Returns the 'DEOrderId' -- the internal DExchange's order id, which, from now on, should be used reference each particular order. */
	bool addOrder(uint securityId, ETradeSide side, AbstractDExchangeSession session, uint orderId, real limitFaceValue, uint quantity) {
		final switch (side) {
			case ETradeSide.BUY:
				return addBuyOrder(securityId, session, orderId, limitFaceValue, quantity);
			case ETradeSide.SELL:
				return addSellOrder(securityId, session, orderId, limitFaceValue, quantity);
		}
	}



	// event dispatching methods
	////////////////////////////

	/** Dispatch order 'Addition' events for all session, excluding the session adding the order */
	abstract void dispatchAdditionEvents(uint securityId, string party, uint orderId, ETradeSide side, real faceValue, uint quantity);

	/** Dispatch order 'Cancellation' events for all session, excluding the session adding the order */
	abstract void dispatchCancellationEvents(uint securityId, string party, uint orderId, ETradeSide side, real faceValue, uint quantity);

	/** Dispatch 'Trade' and order 'Execution' events.
	  * priority: Execution, Trade (only called for sessions not called on 'onExecution' -- that is: only called for parties not involved on the trade) */
	abstract void dispatchExecutionEvents(uint securityId, uint aggressedOrderId, uint aggressorOrderId, AbstractDExchangeSession aggressorSession, uint quantity, uint exchangeValue, ETradeSide aggressorSide);

	/** builds the price 'bids' and 'asks' books and dispatch the 'Book' event. */
	abstract void dispatchBookEvents(uint securityId);

}
