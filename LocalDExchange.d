module LocalDExchange;

import std.stdio;

import std.math;
import std.algorithm;
import std.typecons;
import std.array;
import std.conv;

import Types : ETradeSide, Trade, PriceBookEntry;
import AbstractDExchange: AbstractDExchange;
import LocalDExchangeSession: LocalDExchangeSession;
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

	// event dispatching containers (containing sessions)
	LocalDExchangeSession[string] onExecutionSessionsByParty;			// map of sessions that want the 'OrderExecuted' event notification for their orders := {[party]=..., ...}
	LocalDExchangeSession[]       onBookSessions;						// array of sessions that want the 'BookChanged' events
	LocalDExchangeSession[]       onTradeSessions;						// array of sessions that want the 'Trade' events'
	LocalDExchangeSession[]       onAdditionAndCancellationSessions;		// array of sessions that want the order 'Addition' and 'Cancellation' events

	void resetSessions() {
		onExecutionSessionsByParty.clear();
		onBookSessions.length                    = 0;
		onTradeSessions.length                   = 0;
		onAdditionAndCancellationSessions.length = 0;
	}

	/** adds the 'session' to the event dispatching containers */
	void registerSession(LocalDExchangeSession session) {
		onExecutionSessionsByParty[session.party] = session;
		uint onBookSessionsIndex                    = cast(uint)onBookSessions.countUntil(session);
		uint onTradeSessionsIndex                   = cast(uint)onTradeSessions.countUntil(session);
		uint onAdditionAndCancellationSessionsIndex = cast(uint)onAdditionAndCancellationSessions.countUntil(session);
		// edit or append?
		if (onBookSessionsIndex == -1u) {
			onBookSessions ~= session;
		} else {
			onBookSessions[onBookSessionsIndex] = session;
		}
		if (onTradeSessionsIndex == -1u) {
			onTradeSessions ~= session;
		} else {
			onTradeSessions[onTradeSessionsIndex] = session;
		}
		if (onAdditionAndCancellationSessionsIndex == -1u) {
			onAdditionAndCancellationSessions ~= session;
		} else {
			onAdditionAndCancellationSessions[onAdditionAndCancellationSessionsIndex] = session;
		}
	}

	/** removes 'session' from the event dispatching containers */
	void unregisterSession(LocalDExchangeSession session) {
		onExecutionSessionsByParty.remove(session.party);
		uint onBookSessionsIndex                    = cast(uint)onBookSessions.countUntil(session);
		uint onTradeSessionsIndex                   = cast(uint)onTradeSessions.countUntil(session);
		uint onAdditionAndCancellationSessionsIndex = cast(uint)onAdditionAndCancellationSessions.countUntil(session);
		// really remove?
		if (onBookSessionsIndex != -1u) {
			onBookSessions = onBookSessions.remove(onBookSessionsIndex);
		}
		if (onTradeSessionsIndex != -1u) {
			onTradeSessions = onTradeSessions.remove(onTradeSessionsIndex);
		}
		if (onAdditionAndCancellationSessionsIndex != -1u) {
			onAdditionAndCancellationSessions = onAdditionAndCancellationSessions.remove(onAdditionAndCancellationSessionsIndex);
		}
	}

	/** dispatch order 'Addition' events to the appropriate registered 'LocalDExchangeSession's */
	override void dispatchAdditionEvents(string party, uint orderId, ETradeSide side, real faceValue, uint quantity) {
		foreach(session; onAdditionAndCancellationSessions) {
			session.onAddition(party, orderId, side, faceValue, quantity);
		}
	}

	/** dispatch order 'Cancellation' events to the appropriate registered 'LocalDExchangeSession's */
	override void dispatchCancellationEvents(string party, uint orderId, ETradeSide side, real faceValue, uint quantity) {
		foreach(session; onAdditionAndCancellationSessions) {
			session.onCancellation(party, orderId, side, faceValue, quantity);
		}
	}

	/** dispatch execution events ('Trade' and 'Execution') to the appropriate registered 'LocalDExchangeSession's */
	override void dispatchExecutionEvents(uint aggressedOrderId, uint aggressorOrderId, string aggressorParty, uint quantity, uint exchangeValue, ETradeSide aggressorSide) {
		static ulong time = 1000000000;
		static uint tradeEventId = 0;

		AbstractDExchangeSession aggressedAbstractSession = trackedOrders[aggressedOrderId].session;
		LocalDExchangeSession    aggressedLocalSession    = cast(LocalDExchangeSession) aggressedAbstractSession;
		LocalDExchangeSession    aggressorSession         = onExecutionSessionsByParty[aggressorParty];
		Trade trade = Trade(time++, quantity, info.exchangeValueToFaceValue(exchangeValue),
							aggressorSide == ETradeSide.BUY ? aggressorParty                 : aggressedAbstractSession.party,
							aggressorSide == ETradeSide.BUY ? aggressedAbstractSession.party : aggressorParty,
							"", aggressorOrderId, aggressedOrderId);
		// dispatch 'Execution' event (priority: aggressed, aggressor orders)
		//writeln("new TRADE: ", trade, "; aggressed: ", aggressedSession.party, "; aggressorSession: ", aggressorSession.party);
		if (aggressedLocalSession) {
			aggressedLocalSession.onExecution(tradeEventId, aggressedOrderId, trade, aggressorSide == ETradeSide.SELL);
		} else {
		}
		if (aggressorSession) {
			aggressorSession.onExecution(tradeEventId, aggressorOrderId, trade, aggressorSide == ETradeSide.BUY);
		}

		foreach (onTradeSession; onTradeSessions) {
			if (onTradeSession != aggressedAbstractSession && onTradeSession != aggressorSession) {
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
