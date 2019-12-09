module BookManipulators;

import Types : Trade, ETradeSide, PriceLevel, PriceBookEntry, SecurityInfo, securityInfos;
import DExchange: AbstractDExchange, LocalDExchange, AbstractDExchangeSession, LocalDExchangeSession;

import std.stdio;
import std.algorithm;
import std.array;
import std.random;


version (unittest) {
	import TestUtils;

	import std.format;
}

/** Session class used internally for building the book */
class BookBuildingSession(string party): AbstractDExchangeSession {
	this(LocalDExchange exchange, uint securityId) {
		super(exchange, securityId, party);
	}

}

class BookManipulators {

	LocalDExchange exchange;
	uint           securityId;

	uint orderId = 10000000;

	// sessions for book manipulation
	BookBuildingSession!"CounterParty" counterPartySession;
	BookBuildingSession!"BookMaker"    bookMakerSession;


	this(LocalDExchange exchange, uint securityId) {
		this.exchange   = exchange;
		this.securityId = securityId;
		counterPartySession = new BookBuildingSession!"CounterParty"(exchange, securityId);
		bookMakerSession    = new BookBuildingSession!"BookMaker"(exchange, securityId);
	}

	/** Used to check how many quantities, at least, the current book might execute at the given 'faceValue'.
	  * if the return is > 0, 'aggressorSide' is modifyed to reflect the side of the order that needs
	    to be placed to actually execute. */
	uint checkExecutability(real faceValue, ETradeSide* aggressorSide) {
		uint exchangeValue = securityInfos[securityId].faceValueToExchangeValue(faceValue);
		PriceLevel* bidPriceLevel = exchangeValue in exchange.bids[securityId];
		uint totalQuantity = 0;
		if (bidPriceLevel != null) {
			totalQuantity = (*bidPriceLevel).totalQuantity;
			if (totalQuantity > 0) {
				*aggressorSide = ETradeSide.SELL;
			}
		}
		PriceLevel* askPriceLevel = exchangeValue in exchange.asks[securityId];
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
		uint exchangeValue = securityInfos[securityId].faceValueToExchangeValue(faceValue);
		PriceLevel* aggressedLevel;
		ETradeSide aggressedSide;
		// get the price 'level' book entry for aggressed side
		final switch (aggressorSide) {
			case ETradeSide.SELL:
				aggressedLevel = exchangeValue in exchange.bids[securityId];
				if (!aggressedLevel) {
					exchange.bids[securityId][exchangeValue] = PriceLevel();
					aggressedLevel = exchangeValue in exchange.bids[securityId];
				}
				aggressedSide = ETradeSide.BUY;
				break;
			case ETradeSide.BUY:
				aggressedLevel = exchangeValue in exchange.asks[securityId];
				if (!aggressedLevel) {
					exchange.asks[securityId][exchangeValue] = PriceLevel();
					aggressedLevel = exchangeValue in exchange.asks[securityId];
				}
				aggressedSide = ETradeSide.SELL;
				break;
		}
		// delete any existing orders (on both sides) that would prevent the creation of orders to be aggressed
		// (deletes orders at 'faceValue' on the to-be aggressed side, but leave them on the aggressor side)
		// treat the buy side
		foreach(exchangeValueIndex; exchange.bids[securityId].keys.sort!"a > b") {
			PriceLevel*     bidLevel = exchangeValueIndex in exchange.bids[securityId];
			if ( (exchangeValueIndex == exchangeValue && aggressorSide == ETradeSide.SELL) || (exchangeValueIndex < exchangeValue) ) {
				break;
			}
			exchange.cancelAllOrders(securityId, counterPartySession.party, *bidLevel);
		}
		// treat the sell side
		foreach(exchangeValueIndex; exchange.asks[securityId].keys.sort!"a < b") {
			PriceLevel*     askLevel = exchangeValueIndex in exchange.asks[securityId];
			if ( (exchangeValueIndex == exchangeValue && aggressorSide == ETradeSide.BUY) || (exchangeValueIndex > exchangeValue) ) {
				break;
			}
			exchange.cancelAllOrders(securityId, counterPartySession.party, *askLevel);
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
		uint exchangeValue = securityInfos[securityId].faceValueToExchangeValue(faceValue);
		uint buyLevels  = min(uniform(maxBuyLevels/2, maxBuyLevels+1), exchangeValue-1);	// min exchangeValue-1 prevents the price from going below 0.01
		uint sellLevels = uniform(maxSellLevels/2, maxSellLevels+1);
		for (uint level=1; level<=max(buyLevels, sellLevels); level++) {
			uint delta      = level/* *0.01 */;
			bool shouldBuy  = level <= buyLevels;
			bool shouldSell = level <= sellLevels;
			// sell & buy loop -- orders will be added as needed to get the price level to the randomly chosen quantity
			for (uint areWeBuying = (shouldSell ? 0 : 1); areWeBuying <= (shouldBuy ? 1 : 0); areWeBuying++) {
				uint wantedQuantity   = uniform(1, (maxQuantityPerOrder/100)+1) * 100;
				PriceLevel* priceLevel = areWeBuying ? (exchangeValue-delta) in exchange.bids[securityId] : (exchangeValue+delta) in exchange.asks[securityId];
				uint existingQuantity = priceLevel ? (*priceLevel).totalQuantity : 0;
				if (existingQuantity < wantedQuantity) {
					uint missingQuantity = wantedQuantity - existingQuantity;
					if (areWeBuying) {
						bookMakerSession.addOrder(ETradeSide.BUY, orderId++, securityInfos[securityId].exchangeValueToFaceValue(exchangeValue-delta), missingQuantity);
					} else {
						bookMakerSession.addOrder(ETradeSide.SELL, orderId++, securityInfos[securityId].exchangeValueToFaceValue(exchangeValue+delta), missingQuantity);
					}
				}
			}
		}
	}

	void dumpPriceBook(immutable PriceBookEntry[]* bidsPriceBook, immutable PriceBookEntry[]* asksPriceBook) {
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

	void dumpPriceBook() {
		PriceBookEntry[] bidsPriceBook;
		PriceBookEntry[] asksPriceBook;
		exchange.buildPriceBookEntries(securityId, &bidsPriceBook, &asksPriceBook);
		dumpPriceBook(cast(immutable)&bidsPriceBook, cast(immutable)&asksPriceBook);
	}

}


unittest {

	uint securityId                   = 0;
	TestUtils        testUtils        = new TestUtils();
	LocalDExchange   exchange         = new LocalDExchange();
	BookManipulators bookManipulators = new BookManipulators(exchange, 0u);

	// 'assureExecutability'
	////////////////////////

	writeln("## BookManipulators.d ##");
	testUtils.startTest("Unit testing method 'assureExecutability'");

	exchange.resetBooks();
	testUtils.startSubTest("Assure a future BUY possibility on an empty");
	bookManipulators.assureExecutability(ETradeSide.BUY, 10.32, 10800);
	assert(exchange.asks[securityId][1032].totalQuantity == 10800, "to-be aggressed SELL order does not match");
	testUtils.finishSubTest(true);

	exchange.resetBooks();
	testUtils.startSubTest("Assure a future SELL possibility on an empty book");
	bookManipulators.assureExecutability(ETradeSide.SELL, 10.32, 10800);
	assert(exchange.bids[securityId][1032].totalQuantity == 10800, "to-be aggressed BUY order does not match");
	testUtils.finishSubTest(true);

	exchange.resetBooks();
	testUtils.startSubTest("Moving from BUY to SELL and then to BUY again, starting from an empty book");
	bookManipulators.assureExecutability(ETradeSide.BUY, 10.32, 10800);
	assert(exchange.asks[securityId][1032].totalQuantity == 10800, "to-be aggressed SELL order does not match");
	bookManipulators.assureExecutability(ETradeSide.SELL, 10.32, 10800);
	assert(exchange.asks[securityId][1032].totalQuantity == 0,     "future aggressor SELL order wasn't zeroed out");
	assert(exchange.bids[securityId][1032].totalQuantity == 10800, "to-be aggressed BUY order does not match");
	bookManipulators.assureExecutability(ETradeSide.BUY, 10.32, 10800);
	assert(exchange.bids[securityId][1032].totalQuantity == 0,     "future aggressor BUY order wasn't zeroed out");
	assert(exchange.asks[securityId][1032].totalQuantity == 10800, "to-be aggressed SELL order does not match");
	testUtils.finishSubTest(true);

	testUtils.finishTest();


	// 'fillBook'
	/////////////

	void test(string testNamePrefix, real faceValue, uint minLevels, uint maxOrdersPerPriceLevel, uint maxOrderQty) {
		static securityId = 0;
		uint exchangeValue = securityInfos[securityId].faceValueToExchangeValue(faceValue);
//		exchange.resetBooks();
		testUtils.startSubTest(testNamePrefix ~ " " ~ format!"%,3.2f"(faceValue) ~
					           " with, at least, " ~ format!"%,d"(minLevels) ~ 
					           " levels of up to " ~ format!"%,d"(maxOrdersPerPriceLevel) ~ 
					           " orders each (" ~ format!"%,d"(maxOrderQty) ~ 
					           " max qtys)");
		ETradeSide aggressorSide;
		uint quantity = bookManipulators.checkExecutability(faceValue, &aggressorSide);
		write(" ",aggressorSide," will atack ",(aggressorSide == ETradeSide.BUY ? ETradeSide.SELL : ETradeSide.BUY),"...");
		bookManipulators.assureExecutability(aggressorSide, faceValue, maxOrderQty);

		bookManipulators.fillBook(faceValue, minLevels*2, minLevels*2, maxOrdersPerPriceLevel, maxOrderQty);
		// check bids
		foreach(exchangeValueIndex; exchange.bids[securityId].keys.sort!("a > b")) {
			if (!(exchangeValueIndex <= exchangeValue) && exchange.bids[securityId][exchangeValueIndex].totalQuantity > 0) {
				writeln("no BID entry (",exchangeValueIndex,") should be greater than the given faceValue (",exchangeValue,"). BOOK:");
				bookManipulators.dumpPriceBook();
				quantity = bookManipulators.checkExecutability(faceValue, &aggressorSide);
				writeln("checkExecutability: we may ",aggressorSide," at least ",quantity," for ",faceValue," with the current book");
				assert(false);
			}
			//assert(exchangeValueIndex < exchangeValue, "no BID entry should be greater than nor equal to the given faceValue");
			assert(exchange.bids[securityId][exchangeValueIndex].orders.length < maxOrdersPerPriceLevel, "more than the maximum number of orders were found at a BID price level");
			foreach(order; exchange.bids[securityId][exchangeValueIndex].orders) {
				assert(order.quantity <= maxOrderQty, "an order with more than the maximum allowed quantity was found on the BIDs book");
			}
		}
		// check asks
		foreach(exchangeValueIndex; exchange.asks[securityId].keys.sort!("a < b")) {
			if (!(exchangeValueIndex >= exchangeValue) && exchange.asks[securityId][exchangeValueIndex].totalQuantity > 0) {
				writeln("no ASK entry (",exchangeValueIndex,") should be smaller than the given faceValue (",exchangeValue,"). BOOK:");
				bookManipulators.dumpPriceBook();
				quantity = bookManipulators.checkExecutability(faceValue, &aggressorSide);
				writeln("checkExecutability: we may ",aggressorSide," at least ",quantity," for ",faceValue," with the current book");
				assert(false);
			}
			//assert(exchangeValueIndex > exchangeValue, "no ASK entry should be smaller than nor equal to the given faceValue");
			assert(exchange.asks[securityId][exchangeValueIndex].orders.length < maxOrdersPerPriceLevel, "more than the maximum number of orders were found at an ASK price level");
			foreach(order; exchange.asks[securityId][exchangeValueIndex].orders) {
				assert(order.quantity <= maxOrderQty, "an order with more than the maximum allowed quantity was found on the ASKs book");
			}
		}
		testUtils.finishSubTest(true);
	}

	// test cases
	testUtils.startTest("Unit testing method 'checkExecutability', 'assureExecutability' & 'fillBook'");

	exchange.resetBooks();
	test("Building an empty, innocuous book around", 42.07, 50, 1000, 1000);
	test("Moving book to",                           42.06, 50, 1000, 1000);
	test("Moving back to",                           42.07, 50, 1000, 1000);
	test("Building an empty book around", 0.10, 50, 100, 1000);
	test("Moving book to",                0.01, 50, 100, 1000);

	testUtils.finishTest();

}
