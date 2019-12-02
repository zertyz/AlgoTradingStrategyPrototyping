module AbstractDExchangeSession;

import Types;
import DExchange: AbstractDExchange;

/** Class representing the access permission and containing the operations clients may do on the exchange */
abstract class AbstractDExchangeSession {

	AbstractDExchange exchange;
	string party;

	this(AbstractDExchange exchange, string party) {
		this.exchange = exchange;
		this.party    = party;
		exchange.registerSession(this);
	}

	~this() {
		exchange.unregisterSession(this);
	}

	void addOrder(ETradeSide side, uint orderId, real limitFaceValue, uint quantity) {
		exchange.addOrder(side, party, this, orderId, limitFaceValue, quantity);
	}

	// event handling methods
	/////////////////////////
	// these events are propagated by 'LocalDExchange'

	/** receives 'Execution' events, denoting that an order you've sent has just been executed.
	    The first to be notifyed will be the aggressed order's owner session, then the aggressor's.
	    Sessions notified via 'onExecution' will not receive the corresponding 'onTrade' event. */
	abstract void onExecution(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying);

	/** receives 'Trade' events, denoting that two opposing orders matched each other and a trade has been made.
	    First the 'onExecution' events will be issued for the parties involved on the trade, then the 'Trade'
	    event will be broadcasted for all other sessions (Sessions involved on the trade will not receive this event
	    for they already received the 'Execution' event). */
	abstract void onTrade(uint tradeEventId, ref Trade trade, bool isAttackingBids);

	/** receives 'Book' events, denoting that one of the price ordered books for 'bids' and/or 'asks' have changed.
	  * Book events are expensive to generate, therefore they are generated as less frequently as possible -- one for each of these cases:
	  *   - When provoked by a match, first all n orders will be executed, generating 'Execution' and 'Trade' events, then the 'Book';
	  *   - When provoked by order(s) cancellation, first the 'Cancelled' event(s) will take -- bulks may happen when a session disconnects;
	  *   - Order additions will first propagate the 'Added' event to all sessions, then the 'Book' event;
	  *   - Order editions will first propagate the 'Edited' event to all sessions, then the 'Book' event.
	  * All existing price levels will be present on the 'bids' and 'asks' price books, regardless of their depth.
      *
	  * bidsPriceBook | asksPriceBook := { [faceValue1] = PriceBookEntry1, ... } */
	abstract void onBook(immutable PriceBookEntry[]* bidsPriceBook, immutable PriceBookEntry[]* asksPriceBook);

	/** receives 'Addition' events, meaning that an order has been added to one of the books.
	    The session adding the order will not receive the event. */
	abstract void onAddition(uint orderId, ETradeSide side, real limitFaceValue, uint quantity);

	/** receives 'Cancencellation' events, meaning that an order has been cancelled on one of the books.
	    If the cancellation was intentional, the session owning the order will not receive the event. */
	abstract void onCancellation(uint orderId, ETradeSide side, real limitFaceValue, uint quantity);

}