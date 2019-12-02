module LocalDExchange;

import std.stdio;

import std.math;
import std.algorithm;
import std.typecons;
import std.array;
import std.conv;

import Types : ETradeSide, Trade, PriceBookEntry;
import AbstractDExchange: AbstractDExchange;
import AbstractDExchangeSession;

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


class LocalDExchange: AbstractDExchange {

	// dispatch execution events ('Trade' and 'Execution') to the appropriate registered 'LocalDExchangeSession's
	override void dispatchExecutionEvents(uint aggressedOrderId, uint aggressorOrderId, string aggressorParty, uint quantity, uint exchangeValue, ETradeSide aggressorSide) {
		static ulong time = 1000000000;
		static uint tradeEventId = 0;
		AbstractDExchangeSession aggressedSession = trackedOrders[aggressedOrderId].session;
		AbstractDExchangeSession aggressorSession = onExecutionSessionsByParty[aggressorParty];
		Trade trade = Trade(time++, quantity, info.exchangeValueToFaceValue(exchangeValue),
							aggressorSide == ETradeSide.BUY ? aggressorSession.party : aggressedSession.party,
							aggressorSide == ETradeSide.BUY ? aggressedSession.party : aggressorSession.party,
							"", aggressorOrderId, aggressedOrderId);
		// dispatch 'Execution' event (priority: aggressed, aggressor orders)
		//writeln("new TRADE: ", trade, "; aggressed: ", aggressedSession.party, "; aggressorSession: ", aggressorSession.party);
		aggressedSession.onExecution(tradeEventId, aggressedOrderId, trade, aggressorSide == ETradeSide.SELL);
		aggressorSession.onExecution(tradeEventId, aggressorOrderId, trade, aggressorSide == ETradeSide.BUY);

		foreach (onTradeSession; onTradeSessions) {
			if (onTradeSession != aggressedSession && onTradeSession != aggressorSession) {
				// dispatch 'Trade' event
				onTradeSession.onTrade(tradeEventId, trade, aggressorSide == ETradeSide.SELL);
			}
		}
	}

	/** dispatches the 'Book' event to all interested 'LocalDExchangeSession's */
	override void dispatchBookEvents() {
		static PriceBookEntry[] bidsPriceBook;
		static PriceBookEntry[] asksPriceBook;
		if (onBookSessions.length > 0) {
			buildPriceBookEntries(&bidsPriceBook, &asksPriceBook);
		}
		foreach (onBookSession; onBookSessions) {
			onBookSession.onBook(cast(immutable)&bidsPriceBook, cast(immutable)&asksPriceBook);
		}
	}


}
