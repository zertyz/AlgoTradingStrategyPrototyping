module LocalDExchange;

import std.stdio;

import std.math;
import std.algorithm;
import std.typecons;
import std.array;
import std.conv;

import Types : ETradeSide, Trade, PriceBookEntry, securityInfos;
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
	LocalDExchangeSession[string][securityInfos.length] onExecutionSessionsByParty;			// map of sessions that want the 'OrderExecuted' event notification for their orders := {[party]=..., ...}
	LocalDExchangeSession[][securityInfos.length]       onBookSessions;						// array of sessions that want the 'BookChanged' events
	LocalDExchangeSession[][securityInfos.length]       onTradeSessions;					// array of sessions that want the 'Trade' events'
	LocalDExchangeSession[][securityInfos.length]       onAdditionAndCancellationSessions;	// array of sessions that want the order 'Addition' and 'Cancellation' events

	void resetSessions() {
		for (uint i=0; i<securityInfos.length; i++) {
			onExecutionSessionsByParty[i].clear();
			onBookSessions[i].length                    = 0;
			onTradeSessions[i].length                   = 0;
			onAdditionAndCancellationSessions[i].length = 0;
		}
	}

	/** adds the 'session' to the event dispatching containers */
	void registerSession(LocalDExchangeSession session) {
		uint securityId = session.securityId;
		uint onBookSessionsIndex                    = cast(uint)onBookSessions[securityId].countUntil(session);
		uint onTradeSessionsIndex                   = cast(uint)onTradeSessions[securityId].countUntil(session);
		uint onAdditionAndCancellationSessionsIndex = cast(uint)onAdditionAndCancellationSessions[securityId].countUntil(session);
		// set
		onExecutionSessionsByParty[securityId][session.party]   = session;
		// edit or append?
		if (onBookSessionsIndex == -1u) {
			onBookSessions[securityId] ~= session;
		} else {
			onBookSessions[securityId][onBookSessionsIndex] = session;
		}
		if (onTradeSessionsIndex == -1u) {
			onTradeSessions[securityId] ~= session;
		} else {
			onTradeSessions[securityId][onTradeSessionsIndex] = session;
		}
		if (onAdditionAndCancellationSessionsIndex == -1u) {
			onAdditionAndCancellationSessions[securityId] ~= session;
		} else {
			onAdditionAndCancellationSessions[securityId][onAdditionAndCancellationSessionsIndex] = session;
		}
	}

	/** removes 'session' from the event dispatching containers */
	void unregisterSession(LocalDExchangeSession session) {
		uint securityId = session.securityId;
		uint onBookSessionsIndex                    = cast(uint)onBookSessions[securityId].countUntil(session);
		uint onTradeSessionsIndex                   = cast(uint)onTradeSessions[securityId].countUntil(session);
		uint onAdditionAndCancellationSessionsIndex = cast(uint)onAdditionAndCancellationSessions[securityId].countUntil(session);
		// remove
		onExecutionSessionsByParty[securityId].remove(session.party);
		// really remove?
		if (onBookSessionsIndex != -1u) {
			onBookSessions[securityId] = onBookSessions[securityId].remove(onBookSessionsIndex);
		}
		if (onTradeSessionsIndex != -1u) {
			onTradeSessions[securityId] = onTradeSessions[securityId].remove(onTradeSessionsIndex);
		}
		if (onAdditionAndCancellationSessionsIndex != -1u) {
			onAdditionAndCancellationSessions[securityId] = onAdditionAndCancellationSessions[securityId].remove(onAdditionAndCancellationSessionsIndex);
		}
	}

	/** dispatch order 'Addition' events to the appropriate registered 'LocalDExchangeSession's */
	override void dispatchAdditionEvents(uint securityId, string party, uint orderId, ETradeSide side, real faceValue, uint quantity) {
		foreach(session; onAdditionAndCancellationSessions[securityId]) {
			session.onAddition(securityId, party, orderId, side, faceValue, quantity);
		}
	}

	/** dispatch order 'Cancellation' events to the appropriate registered 'LocalDExchangeSession's */
	override void dispatchCancellationEvents(uint securityId, string party, uint orderId, ETradeSide side, real faceValue, uint quantity) {
		foreach(session; onAdditionAndCancellationSessions[securityId]) {
			session.onCancellation(securityId, party, orderId, side, faceValue, quantity);
		}
	}

	/** dispatch execution events ('Trade' and 'Execution') to the appropriate registered 'LocalDExchangeSession's */
	override void dispatchExecutionEvents(uint securityId, uint aggressedOrderId, uint aggressorOrderId, AbstractDExchangeSession aggressorSession, uint quantity, uint exchangeValue, ETradeSide aggressorSide) {
		static ulong time = 1000000000;
		static uint tradeEventId = 0;
		AbstractDExchangeSession aggressedAbstractSession = trackedOrders[securityId][aggressedOrderId].session;
		LocalDExchangeSession    aggressedLocalSession    = cast(LocalDExchangeSession) aggressedAbstractSession;
		LocalDExchangeSession    aggressorLocalSession    = cast(LocalDExchangeSession) aggressorSession;
		Trade trade = Trade(time++, quantity, securityInfos[securityId].exchangeValueToFaceValue(exchangeValue),
							aggressorSide == ETradeSide.BUY ? aggressorSession.party         : aggressedAbstractSession.party,
							aggressorSide == ETradeSide.BUY ? aggressedAbstractSession.party : aggressorSession.party,
							"", aggressorOrderId, aggressedOrderId);
		// dispatch 'Execution' event (priority: aggressed, aggressor orders)
		//writeln("new TRADE: ", trade, "; aggressed: ", aggressedSession.party, "; aggressorSession: ", aggressorSession.party);
		if (aggressedLocalSession) {
			aggressedLocalSession.onExecution(securityId, tradeEventId, aggressedOrderId, trade, false);
		} else {
		}
		if (aggressorLocalSession) {
			aggressorLocalSession.onExecution(securityId, tradeEventId, aggressorOrderId, trade, true);
		}

		foreach (onTradeSession; onTradeSessions[securityId]) {
			if (onTradeSession != aggressedLocalSession && onTradeSession != aggressorLocalSession) {
				// dispatch 'Trade' event
				onTradeSession.onTrade(securityId, tradeEventId, trade, aggressorSide == ETradeSide.SELL);
			}
		}
	}

	/** dispatches the 'Book' event to all interested 'LocalDExchangeSession's */
	override void dispatchBookEvents(uint securityId) {
		static PriceBookEntry[] bidsPriceBook;
		static PriceBookEntry[] asksPriceBook;
		if (onBookSessions.length > 0) {
			buildPriceBookEntries(securityId, &bidsPriceBook, &asksPriceBook);
		}
		foreach (onBookSession; onBookSessions[securityId]) {
			onBookSession.onBook(securityId, cast(immutable)&bidsPriceBook, cast(immutable)&asksPriceBook);
		}
	}

}
