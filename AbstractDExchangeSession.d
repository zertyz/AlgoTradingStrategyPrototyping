module AbstractDExchangeSession;

import Types;
import DExchange: AbstractDExchange;

/** Class representing the access permission and containing the operations clients may do on the exchange */
abstract class AbstractDExchangeSession {

	AbstractDExchange exchange;
	uint              securityId;
	string            party;

	this(AbstractDExchange exchange, uint securityId, string party) {
		this.exchange   = exchange;
		this.securityId = securityId;
		this.party      = party;
	}

	void addOrder(ETradeSide side, uint orderId, real limitFaceValue, uint quantity) {
		exchange.addOrder(securityId, side, this, orderId, limitFaceValue, quantity);
	}

}
