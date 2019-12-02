module LocalDExchangeSession;

import Types;
import DExchange : AbstractDExchange, LocalDExchange, AbstractDExchangeSession, BookManipulators;

/**

	'DExchangeSession' is the class local programs must instantiate in order to interact with a local exchange.

*/

class LocalDExchangeSession: AbstractDExchangeSession {

	this(LocalDExchange exchange, string party) {
		super(exchange, party);
		exchange.registerSession(this);
	}

	~this() {
		(cast (LocalDExchange)exchange).unregisterSession(this);
	}

	// event handling methods
	/////////////////////////
	// these events are propagated by 'LocalDExchange'

	/** receives 'Addition' events, meaning that an order has been added to one of the books.
	    The session adding the order will not receive the event. */
	abstract void onAddition(string party, uint orderId, ETradeSide side, real limitFaceValue, uint quantity);

	/** receives 'Cancencellation' events, meaning that an order has been cancelled on one of the books.
	    If the cancellation was intentional, the session owning the order will not receive the event. */
	abstract void onCancellation(string party, uint orderId, ETradeSide side, real limitFaceValue, uint quantity);

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

}

// testing infrastructure conditional compilation code
//////////////////////////////////////////////////////

version (unittest) {

	import TestUtils;

	import std.stdio;
	import std.conv;
	import std.algorithm;
	import std.format;
	import std.typecons : tuple;
	import std.functional : toDelegate;

	class TestDExchangeSession: LocalDExchangeSession {

		this(LocalDExchange exchange, string party) {
			super(exchange, party);
		}

		TestResults onExecutionResults;
		override void onExecution(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {
			onExecutionResults.total               += trade.qty*trade.price;
			onExecutionResults.numberOfTransactions++;
		}

		TestResults onTradeResults;
		override void onTrade(uint tradeEventId, ref Trade trade, bool isAttackingBids) {
			onTradeResults.total               += trade.qty*trade.price;
			onTradeResults.numberOfTransactions++;
		}

		uint onBookCount = 0;
		override void onBook(immutable PriceBookEntry[]* bidsPriceBook, immutable PriceBookEntry[]* asksPriceBook) {
			onBookCount++;
		}

		TestResults onBuyAdditionResults;
		TestResults onSellAdditionResults;
		override void onAddition(string party, uint orderId, ETradeSide side, real limitFaceValue, uint quantity) {
			TestResults* results;
			final switch (side) {
				case ETradeSide.BUY:
					results = &onBuyAdditionResults;
					break;
				case ETradeSide.SELL:
					results = &onSellAdditionResults;
					break;
			}
			results.total += limitFaceValue*quantity;
			results.numberOfTransactions++;
		}

		TestResults onBuyCancellationResults;
		TestResults onSellCancellationResults;
		override void onCancellation(string party, uint orderId, ETradeSide side, real limitFaceValue, uint quantity) {
			TestResults* results;
			final switch (side) {
				case ETradeSide.BUY:
					results = &onBuyCancellationResults;
					break;
				case ETradeSide.SELL:
					results = &onBuyCancellationResults;
					break;
			}
			results.total += limitFaceValue*quantity;
			results.numberOfTransactions++;
		}

		void reset() {
			onBookCount               = 0;
			onTradeResults            = TestResults(0, 0);
			onExecutionResults        = TestResults(0, 0);
			onBuyAdditionResults      = TestResults(0, 0);
			onSellAdditionResults     = TestResults(0, 0);
			onBuyCancellationResults  = TestResults(0, 0);
			onSellCancellationResults = TestResults(0, 0);
		}

	}
}

unittest {

	LocalDExchange exchange = new LocalDExchange();
	uint orderId = 1;

	auto john   = new TestDExchangeSession(exchange, "John");
	auto mary   = new TestDExchangeSession(exchange, "Mary");
	auto azelia = new TestDExchangeSession(exchange, "Azelia");

	TestResults expectedResults;
	auto testUtils = new class TestUtils {
		override void startSubTest(string subtest) {
			super.startSubTest(subtest);
			exchange.resetBooks();
			expectedResults = TestResults(0, 0);
			john.reset();
			mary.reset();
			azelia.reset();
		}
	};

	BookManipulators bookManipulators = new BookManipulators(exchange);

	testUtils.startTest("'LocalDExchange.d' & 'LocalDExchangeSession.d' tests");

	testUtils.startSubTest("One order per price level, Aggressor selling");
	john.addOrder(ETradeSide.BUY, orderId++, 37.01, 100);
	john.addOrder(ETradeSide.BUY, orderId++, 37.02, 900);
	john.addOrder(ETradeSide.BUY, orderId++, 37.03, 800);
	john.addOrder(ETradeSide.SELL, orderId++, 37.04, 200);
	john.addOrder(ETradeSide.SELL, orderId++, 37.05, 600);
	john.addOrder(ETradeSide.SELL, orderId++, 37.06, 700);
	mary.addOrder(ETradeSide.SELL, orderId++, 37.02, 1000);
	expectedResults = TestResults(37.03*800+37.02*200, 2);

	testUtils.assertEquals(john.onExecutionResults, expectedResults, "Total $ in transactions, as accounted by 'john.onExecutionResults' events do not match.");
	testUtils.assertEquals(mary.onExecutionResults, expectedResults, "Total $ in transactions, as accounted by 'mary.onExecutionResults' events do not match.");
	testUtils.assertEquals(azelia.onTradeResults,   expectedResults, "Total $ in transactions, as accounted by 'onTrade' events do not match");
	testUtils.assertEquals(azelia.onBuyAdditionResults,  TestResults(37.01*100+37.02*900+37.03*800, 3), "Azelia's AddedOrders callback accounted wrong BUYING results");
	testUtils.assertEquals(azelia.onSellAdditionResults, TestResults(37.04*200+37.05*600+37.06*700, 3), "Azelia's AddedOrders callback accounted wrong SELLING results");
	testUtils.finishSubTest(true);

	testUtils.startSubTest("One order per price level, Aggressor buying");
	john.addOrder(ETradeSide.BUY, orderId++, 37.01, 100);
	john.addOrder(ETradeSide.BUY, orderId++, 37.02, 900);
	john.addOrder(ETradeSide.BUY, orderId++, 37.03, 800);
	john.addOrder(ETradeSide.SELL, orderId++, 37.04, 200);
	john.addOrder(ETradeSide.SELL, orderId++, 37.05, 600);
	john.addOrder(ETradeSide.SELL, orderId++, 37.06, 700);
	mary.addOrder(ETradeSide.BUY, orderId++, 37.06, 1000);
	expectedResults = TestResults(37.04*200+37.05*600+37.06*200, 3);
	testUtils.assertEquals(john.onExecutionResults, expectedResults, "Total $ in transactions, as accounted by 'john.onExecutionResults' events do not match.");
	testUtils.assertEquals(mary.onExecutionResults, expectedResults, "Total $ in transactions, as accounted by 'mary.onExecutionResults' events do not match.");
	testUtils.assertEquals(azelia.onTradeResults,   expectedResults, "Total $ in transactions, as accounted by 'onTrade' events do not match");
	testUtils.assertEquals(azelia.onBuyAdditionResults,  TestResults(37.01*100+37.02*900+37.03*800, 3), "Azelia's AddedOrders callback accounted wrong BUYING results");
	testUtils.assertEquals(azelia.onSellAdditionResults, TestResults(37.04*200+37.05*600+37.06*700, 3), "Azelia's AddedOrders callback accounted wrong SELLING results");
	testUtils.finishSubTest(true);

	testUtils.startSubTest("Two orders per price level");
	mary.addOrder(ETradeSide.BUY, orderId++, 37.01, 100);
	mary.addOrder(ETradeSide.BUY, orderId++, 37.02, 900);
	mary.addOrder(ETradeSide.BUY, orderId++, 37.03, 800);
	mary.addOrder(ETradeSide.SELL, orderId++, 37.04, 200);
	mary.addOrder(ETradeSide.SELL, orderId++, 37.05, 600);
	mary.addOrder(ETradeSide.SELL, orderId++, 37.06, 700);
	mary.addOrder(ETradeSide.BUY, orderId++, 37.01, 100);
	mary.addOrder(ETradeSide.BUY, orderId++, 37.02, 900);
	mary.addOrder(ETradeSide.BUY, orderId++, 37.03, 800);
	mary.addOrder(ETradeSide.SELL, orderId++, 37.04, 200);
	mary.addOrder(ETradeSide.SELL, orderId++, 37.05, 600);
	mary.addOrder(ETradeSide.SELL, orderId++, 37.06, 700);
	john.addOrder(ETradeSide.BUY, orderId++, 37.06, 1000);
	expectedResults = TestResults(37.04*400+37.05*600, 3);
	testUtils.assertEquals(john.onExecutionResults, expectedResults, "Total $ in transactions, as accounted by 'john.onExecutionResults' events do not match.");
	testUtils.assertEquals(mary.onExecutionResults, expectedResults, "Total $ in transactions, as accounted by 'mary.onExecutionResults' events do not match.");
	testUtils.assertEquals(azelia.onTradeResults,   expectedResults, "Total $ in transactions, as accounted by 'onTrade' events do not match");
	testUtils.assertEquals(azelia.onBuyAdditionResults,  TestResults(37.01*200+37.02*1800+37.03*1600, 6), "Azelia's AddedOrders callback accounted wrong BUYING results");
	testUtils.assertEquals(azelia.onSellAdditionResults, TestResults(37.04*400+37.05*1200+37.06*1400, 6), "Azelia's AddedOrders callback accounted wrong SELLING results");
	testUtils.finishSubTest(true);


	testUtils.startSubTest("Random book, assure BUY executability at 37.06 and 37.08");
	// build a huge innocuous book, ready to execute a BUY operation at 37.06
	bookManipulators.assureExecutability(ETradeSide.BUY, 37.06, 1800);
	bookManipulators.fillBook(37.06, 8, 8, 15, 3700);
	// buy
	john.addOrder(ETradeSide.BUY, orderId++, 37.06, 1800);
	testUtils.assertEquals(azelia.onTradeResults, TestResults(37.06*1800, 1), "Total $ in transactions, as accounted by 'onTrade' events do not match");
	// move the book, adding and deleting the minimum orders possible, to be ready to execute another BUY operation at 37.08
	azelia.reset();
	bookManipulators.assureExecutability(ETradeSide.BUY, 37.08, 9200);
	bookManipulators.fillBook(37.08, 8, 8, 15, 3700);
	// buy again
	john.addOrder(ETradeSide.BUY, orderId++, 37.08, 1000);
	testUtils.assertEquals(azelia.onTradeResults, TestResults(37.08*1000, -1), "Total $ in transactions, as accounted by 'onTrade' events do not match");
	testUtils.finishSubTest(true);

	testUtils.startSubTest("Random book, assure SELL executability at 37.06 and 37.08");
	// fill & SELL at 37.06
	bookManipulators.assureExecutability(ETradeSide.SELL, 37.06, 1800);
	bookManipulators.fillBook(37.06, 8, 8, 15, 3700);
	mary.addOrder(ETradeSide.SELL, orderId++, 37.06, 1800);
	testUtils.assertEquals(azelia.onTradeResults, TestResults(37.06*1800, 1), "Total $ in transactions, as accounted by 'onTrade' events do not match");
	// move & SELL at 37.08
	azelia.reset();
	bookManipulators.assureExecutability(ETradeSide.SELL, 37.08, 9200);
	bookManipulators.fillBook(37.08, 8, 8, 15, 3700);
	mary.addOrder(ETradeSide.SELL, orderId++, 37.08, 1000);
	testUtils.assertEquals(azelia.onTradeResults, TestResults(37.08*1000, -1), "Total $ in transactions, as accounted by 'onTrade' events do not match");
	testUtils.finishSubTest(true);


	void dumpAdditionsAndCancellations() {
		writef("ADDS: %d buy, %d sell; CANCELS: %d buy, %d sell",
			   azelia.onBuyAdditionResults.numberOfTransactions,
			   azelia.onSellAdditionResults.numberOfTransactions,
			   azelia.onBuyCancellationResults.numberOfTransactions,
			   azelia.onSellCancellationResults.numberOfTransactions);
	}


	testUtils.startSubTest("filling & refilling book, minimizing order cancellations (please watch the outputs)");
	bookManipulators.assureExecutability(ETradeSide.BUY, 37.06, 1800);
	write("\n\t\t ++ assure(d)Executability at 37.06: "); dumpAdditionsAndCancellations(); write(" -- "); azelia.reset();
	bookManipulators.fillBook(37.06, 8, 8, 15, 3700);
	write("\n\t\t ++ fill(ed)Book around 37.06:       "); dumpAdditionsAndCancellations(); write(" -- "); azelia.reset();
	bookManipulators.assureExecutability(ETradeSide.BUY, 37.07, 1800);
	write("\n\t\t >> assure(d)Executability at 37.07: "); dumpAdditionsAndCancellations(); write(" -- "); azelia.reset();
	bookManipulators.fillBook(37.07, 8, 8, 15, 3700);
	write("\n\t\t >> fill(ed)Book to 37.07:           "); dumpAdditionsAndCancellations(); write(" -- "); azelia.reset();
	bookManipulators.assureExecutability(ETradeSide.BUY, 37.06, 1800);
	write("\n\t\t << assure(d)Executability at 37.06: "); dumpAdditionsAndCancellations(); write(" -- "); azelia.reset();
	bookManipulators.fillBook(37.06, 8, 8, 15, 3700);
	write("\n\t\t << fill(ed)Book back to 37.06:      "); dumpAdditionsAndCancellations(); write(" -- "); azelia.reset();
	testUtils.finishSubTest(true);


	// remove unneeded callbacks to speed up the gremling tests
	//DExchange.onBookCallbacks.remove(tuple(0, DExchange.onBookCallbacks.length));


	void gremling(uint startCents, uint endCents, ETradeSide side) {
		real expectedSumOfCents = ( (endCents-startCents+1) * ((endCents+startCents)/100.0) ) / 2.0;
		testUtils.startSubTest("Gremling: "~side.to!string~"ing 1000 of all cents from "~format!"%,.2f"(startCents/100.0)~" to "~format!"%,.2f"(endCents/100.0)~"; then from "~format!"%,.2f"(endCents/100.0)~" to "~format!"%,.2f"(startCents/100.0));
		// back
		for (uint exchangeValue = endCents; exchangeValue >= startCents; exchangeValue--) {
			real faceValue = exchange.info.exchangeValueToFaceValue(exchangeValue);
			bookManipulators.assureExecutability(side, faceValue, 1800);
			bookManipulators.fillBook(faceValue, 8, 8, 15, 3700);
			real oldOnTradeResults = azelia.onTradeResults.total;
			john.addOrder(side, orderId++, faceValue, 1000);
		}
		testUtils.assertEquals(azelia.onTradeResults, TestResults(expectedSumOfCents*1000, max(endCents-startCents, azelia.onTradeResults.numberOfTransactions)), "Total $ in transactions in the BACK loop, as accounted by 'onTrade' events do not match");
		azelia.reset();
		// forth
		for (uint exchangeValue = startCents; exchangeValue <= endCents; exchangeValue++) {
			real faceValue = exchange.info.exchangeValueToFaceValue(exchangeValue);
			bookManipulators.assureExecutability(side, faceValue, 1800);
			bookManipulators.fillBook(faceValue, 8, 8, 15, 3700);
			real oldOnTradeResults = azelia.onTradeResults.total;
			john.addOrder(side, orderId++, faceValue, 1000);
		}
		testUtils.assertEquals(azelia.onTradeResults, TestResults(expectedSumOfCents*1000, max(endCents-startCents, azelia.onTradeResults.numberOfTransactions)), "Total $ in transactions in the FORTH loop, as accounted by 'onTrade' events do not match");
		write(" (");
		dumpAdditionsAndCancellations();	// NOTE about BACK and FORTH: different buy & sell orders are added depending on which of the above loops are executed first
		write(") --");
		testUtils.finishSubTest(true);
	}

	uint multiplier = 10;
	uint start = (100/multiplier) - 1;	// from 0...
	// stress buying 
	for (uint dozens = start; dozens < (100/multiplier); dozens++) {
		gremling(dozens*100*(multiplier)+1, (dozens+1)*100*multiplier, ETradeSide.BUY);
	}
	// stress selling 
	for (uint dozens = start; dozens < (100/multiplier); dozens++) {
		gremling(dozens*100*(multiplier)+1, (dozens+1)*100*multiplier, ETradeSide.SELL);
	}

	testUtils.finishTest();
}
