module BookManipulators;

import Types;
import DExchange: AbstractDExchange, LocalDExchange, AbstractDExchangeSession;

import std.algorithm;
import std.random;


version (unittest) {
	import TestUtils;

	import std.stdio;
	import std.format;
}

/** Session class used internally for building the book */
class BookBuildingSession(string party): AbstractDExchangeSession {

	this(AbstractDExchange exchange) {
		super(exchange, party);
	}

	// no events are needed
	override void onExecution(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {}
	override void onTrade(uint tradeEventId, ref Trade trade, bool isAttackingBids) {}
	override void onBook(immutable PriceBookEntry[]* bidsPriceBook, immutable PriceBookEntry[]* asksPriceBook) {}
	override void onAddition(uint orderId, ETradeSide side, real limitFaceValue, uint quantity) {}
	override void onCancellation(uint orderId, ETradeSide side, real limitFaceValue, uint quantity) {}

}

class BookManipulators {

	AbstractDExchange exchange;

	uint orderId = 10000000;

	// sessions for book manipulation
	BookBuildingSession!"CounterParty" counterPartySession;
	BookBuildingSession!"BookMaker"    bookMakerSession;


	this(AbstractDExchange exchange) {
		this.exchange = exchange;
		counterPartySession = new BookBuildingSession!"CounterParty"(exchange);
		bookMakerSession    = new BookBuildingSession!"BookMaker"(exchange);
	}

	/** Used to check how many quantities, at least, the current book might execute at the given 'faceValue'.
	  * if the return is > 0, 'aggressorSide' is modifyed to reflect the side of the order that needs
	    to be placed to actually execute. */
	uint checkExecutability(real faceValue, ETradeSide* aggressorSide) {
		uint exchangeValue = exchange.info.faceValueToExchangeValue(faceValue);
		AbstractDExchange.PriceLevel* bidPriceLevel = exchangeValue in exchange.bids;
		uint totalQuantity = 0;
		if (bidPriceLevel != null) {
			totalQuantity = (*bidPriceLevel).totalQuantity;
			if (totalQuantity > 0) {
				*aggressorSide = ETradeSide.SELL;
			}
		}
		AbstractDExchange.PriceLevel* askPriceLevel = exchangeValue in exchange.asks;
		if (askPriceLevel != null) {
			totalQuantity = (*askPriceLevel).totalQuantity;
			if (totalQuantity > 0) {
				*aggressorSide = ETradeSide.BUY;
			}
		}
		return totalQuantity;
	}


	/** assure there are orders on 'aggressedSide' at 'faceValue' (aka price) totalling, at least, 'quantity' (adding new orders as needed),
	* while assuring there are no orders at the aggressor side at that price level (cancelling any existing ones). */
	void assureExecutability(ETradeSide aggressorSide, real faceValue, uint quantity) {
		uint exchangeValue = exchange.info.faceValueToExchangeValue(faceValue);
		AbstractDExchange.PriceLevel* aggressedLevel;
		ETradeSide aggressedSide;
		// get the price 'level' book entry for aggressed side
		final switch (aggressorSide) {
			case ETradeSide.SELL:
				aggressedLevel = exchangeValue in exchange.bids;
				if (!aggressedLevel) {
					exchange.bids[exchangeValue] = exchange.new PriceLevel();
					aggressedLevel = exchangeValue in exchange.bids;
				}
				aggressedSide = ETradeSide.BUY;
				break;
			case ETradeSide.BUY:
				aggressedLevel = exchangeValue in exchange.asks;
				if (!aggressedLevel) {
					exchange.asks[exchangeValue] = exchange.new PriceLevel();
					aggressedLevel = exchangeValue in exchange.asks;
				}
				aggressedSide = ETradeSide.SELL;
				break;
		}
		// delete any existing orders (on both sides) that would prevent the creation of orders to be aggressed
		// (deletes orders at 'faceValue' on the to-be aggressed side, but leave them on the aggressor side)
		// treat the buy side
		foreach(exchangeValueIndex; exchange.bids.keys.sort!("a > b")) {
			AbstractDExchange.PriceLevel* bidLevel = exchangeValueIndex in exchange.bids;
			if ( (exchangeValueIndex == exchangeValue && aggressorSide == ETradeSide.SELL) || (exchangeValueIndex < exchangeValue) ) {
				break;
			}
			(*bidLevel).cancelAllOrders();
		}
		// treat the sell side
		foreach(exchangeValueIndex; exchange.asks.keys.sort!("a < b")) {
			AbstractDExchange.PriceLevel* askLevel = exchangeValueIndex in exchange.asks;
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
			counterPartySession.addOrder(aggressedSide, orderId++, faceValue, missingQuantity);
		}
	}

	/** Builds an innocuous book around 'faceValue' (aka price) using the following algorithm:
	* 1) deletes all orders at 'faceValue' price level on both books;
	* 2) add orders around 'faceValue' on both books that will not be instantly executed, leavning no price level gaps */
	void fillBook(real faceValue, uint maxBuyLevels, uint maxSellLevels, uint maxOrdersPerLevel, uint maxQuantityPerOrder) {
		uint exchangeValue = exchange.info.faceValueToExchangeValue(faceValue);
		uint buyLevels  = min(uniform(maxBuyLevels/2, maxBuyLevels+1), exchangeValue-1);	// min exchangeValue-1 prevents the price from going below 0.01
		uint sellLevels = uniform(maxSellLevels/2, maxSellLevels+1);
		for (uint level=1; level<=max(buyLevels, sellLevels); level++) {
			uint delta      = level/* *0.01 */;
			bool shouldBuy  = level <= buyLevels;
			bool shouldSell = level <= sellLevels;
			// sell & buy loop -- orders will be added as needed to get the price level to the randomly chosen quantity
			for (uint areWeBuying = (shouldSell ? 0 : 1); areWeBuying <= (shouldBuy ? 1 : 0); areWeBuying++) {
				uint wantedQuantity   = uniform(1, (maxQuantityPerOrder+1)/100) * 100;
				AbstractDExchange.PriceLevel* priceLevel = areWeBuying ? (exchangeValue-delta) in exchange.bids : (exchangeValue+delta) in exchange.asks;
				uint existingQuantity = priceLevel ? (*priceLevel).totalQuantity : 0;
				if (existingQuantity < wantedQuantity) {
					uint missingQuantity = wantedQuantity - existingQuantity;
					if (areWeBuying) {
						bookMakerSession.addOrder(ETradeSide.BUY, orderId++, exchange.info.exchangeValueToFaceValue(exchangeValue-delta), missingQuantity);
					} else {
						bookMakerSession.addOrder(ETradeSide.SELL, orderId++, exchange.info.exchangeValueToFaceValue(exchangeValue+delta), missingQuantity);
					}
				}
			}
		}
	}

	void dumpPriceBook() {
		PriceBookEntry[] bidsPriceBook;
		PriceBookEntry[] asksPriceBook;
		exchange.buildPriceBookEntries(&bidsPriceBook, &asksPriceBook);
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

	TestUtils        testUtils        = new TestUtils();
	LocalDExchange   exchange         = new LocalDExchange();
	BookManipulators bookManipulators = new BookManipulators(exchange);

	// 'assureExecutability'
	////////////////////////

	testUtils.startTest("Unit testing method 'assureExecutability'");

	testUtils.startSubTest("Assure a future BUY possibility on an empty");
	bookManipulators.assureExecutability(ETradeSide.BUY, 10.32, 10800);
	assert(exchange.asks[1032].totalQuantity == 10800, "to-be aggressed SELL order does not match");
	testUtils.finishSubTest(true);

	testUtils.startSubTest("Assure a future SELL possibility on an empty book");
	bookManipulators.assureExecutability(ETradeSide.SELL, 10.32, 10800);
	assert(exchange.bids[1032].totalQuantity == 10800, "to-be aggressed BUY order does not match");
	testUtils.finishSubTest(true);

	testUtils.startSubTest("Moving from BUY to SELL and then to BUY again, starting from an empty book");
	bookManipulators.assureExecutability(ETradeSide.BUY, 10.32, 10800);
	assert(exchange.asks[1032].totalQuantity == 10800, "to-be aggressed SELL order does not match");
	bookManipulators.assureExecutability(ETradeSide.SELL, 10.32, 10800);
	assert(exchange.asks[1032].totalQuantity == 0,     "future aggressor SELL order wasn't zeroed out");
	assert(exchange.bids[1032].totalQuantity == 10800, "to-be aggressed BUY order does not match");
	bookManipulators.assureExecutability(ETradeSide.BUY, 10.32, 10800);
	assert(exchange.bids[1032].totalQuantity == 0,     "future aggressor BUY order wasn't zeroed out");
	assert(exchange.asks[1032].totalQuantity == 10800, "to-be aggressed SELL order does not match");
	testUtils.finishSubTest(true);

	testUtils.finishTest();


	// 'fillBook'
	/////////////

	void test(string testNamePrefix, real faceValue, uint minLevels, uint maxOrdersPerPriceLevel, uint maxOrderQty) {
		uint exchangeValue = exchange.info.faceValueToExchangeValue(faceValue);
		testUtils.startSubTest(testNamePrefix ~ " " ~ format!"%,3.2f"(faceValue) ~
					           " with, at least, " ~ format!"%,d"(minLevels) ~ 
					           " levels of up to " ~ format!"%,d"(maxOrdersPerPriceLevel) ~ 
					           " orders each (" ~ format!"%,d"(maxOrderQty) ~ 
					           " max qtys)");
		bookManipulators.fillBook(faceValue, minLevels*2, minLevels*2, maxOrdersPerPriceLevel, maxOrderQty);
		// check bids
		foreach(exchangeValueIndex; exchange.bids.keys.sort!("a > b")) {
			if (!(exchangeValueIndex < exchangeValue)) {
				writeln("no BID entry should be greater than nor equal to the given faceValue. BOOK:");
				bookManipulators.dumpPriceBook();
				ETradeSide aggressorSide;
				uint qty = bookManipulators.checkExecutability(faceValue, &aggressorSide);
				writeln("checkExecutability: we may ",aggressorSide," at least ",qty," for ",faceValue," with the current book");
				//assert(false);
			}
			//assert(exchangeValueIndex < exchangeValue, "no BID entry should be greater than nor equal to the given faceValue");
			assert(exchange.bids[exchangeValueIndex].orders.length < maxOrdersPerPriceLevel, "more than the maximum number of orders were found at a BID price level");
			foreach(order; exchange.bids[exchangeValueIndex].orders) {
				assert(order.quantity <= maxOrderQty, "an order with more than the maximum allowed quantity was found on the BIDs book");
			}
		}
		// check asks
		foreach(exchangeValueIndex; exchange.asks.keys.sort!("a < b")) {
			if (!(exchangeValueIndex > exchangeValue)) {
				writeln("no ASK entry should be smaller than nor equal to the given faceValue. BOOK:");
				bookManipulators.dumpPriceBook();
				ETradeSide aggressorSide;
				uint qty = bookManipulators.checkExecutability(faceValue, &aggressorSide);
				writeln("checkExecutability: we may ",aggressorSide," at least ",qty," for ",faceValue," with the current book");
			}
			//assert(exchangeValueIndex > exchangeValue, "no ASK entry should be smaller than nor equal to the given faceValue");
			assert(exchange.asks[exchangeValueIndex].orders.length < maxOrdersPerPriceLevel, "more than the maximum number of orders were found at an ASK price level");
			foreach(order; exchange.asks[exchangeValueIndex].orders) {
				assert(order.quantity <= maxOrderQty, "an order with more than the maximum allowed quantity was found on the ASKs book");
			}
		}
		testUtils.finishSubTest(true);
	}

	// test cases
	testUtils.startTest("Unit testing method 'fillBook'");

	exchange.resetBooks();
	test("Building an empty, innocuous book around", 42.07, 50, 1000, 1000);
	test("Moving book to",                           42.06, 50, 1000, 1000);
	test("Moving back to",                           42.07, 50, 1000, 1000);
	exchange.resetBooks();
	test("Building an empty book around", 0.10, 50, 100, 1000);
	test("Moving book to",                0.01, 50, 100, 1000);

	testUtils.finishTest();

}