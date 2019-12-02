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
	}

	void addOrder(ETradeSide side, uint orderId, real limitFaceValue, uint quantity) {
		exchange.addOrder(side, party, this, orderId, limitFaceValue, quantity);
	}

}
