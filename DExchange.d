module DExchange;

// develop with:  d="DExchange"; FLAGS="-release -O -mcpu=native -m64 -inline"; FLAGS=""; while sleep 1; do for f in *.d; do if [ "$f" -nt "$d" ]; then echo -en "`date`: COMPILING..."; /c/D/dmd-2.089.0/windows/bin/dmd.exe $FLAGS -unittest -main -boundscheck=on -lowmem -of="$d".exe AbstractDExchange.d AbstractDExchangeSession.d DExchange.d LocalDExchange.d DExchangeSession.d TestUtils.d Types.d BookManipulators.d && echo -en "\n`date`: TESTING:  `ls -l "$d" | sed 's|.* \([0-9][0-9][0-9][0-9]*.*\)|\1|'`\n" && ./"$d" || echo -en '\n\n\n\n\n\n'; touch "$d".exe; rm -f "$d".obj; fi; done; done

public import AbstractDExchange;
public import AbstractDExchangeSession;
public import LocalDExchange;
public import LocalDExchangeSession;
public import BookManipulators;
public import Types;

// test methods
/*
void test() {

	uint orderId = 1;

	void onExecutedOrderJohn(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {
		writeln("--> JOHN: my order #",orderId,", attempting to ",isBuying?"BUY":"SELL",", was executed in ",trade.qty," units for $",trade.price," each");
	}
	void onTradeJohn(uint tradeEventId, ref Trade trade, bool isAttackingBids) {
		writeln("--> JOHN: trade #",tradeEventId,": aggressor #",trade.aggressorOrderId," ",isAttackingBids?"SOLD":"BOUGHT", " ",trade.qty," ",isAttackingBids?"to":"from"," order #", trade.aggressedOrderId, " for $",trade.price);
	}

	void onExecutedOrderMary(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {
		writeln("--> MARY: my order #",orderId,", attempting to ",isBuying?"BUY":"SELL",", was executed in ",trade.qty," units for $",trade.price," each");
	}
	void onTradeMary(uint tradeEventId, ref Trade trade, bool isAttackingBids) {
		writeln("--> MARY: trade #",tradeEventId,": aggressor #",trade.aggressorOrderId," ",isAttackingBids?"SOLD":"BOUGHT", " ",trade.qty," ",isAttackingBids?"to":"from"," order #", trade.aggressedOrderId, " for $",trade.price);
	}

	void onExecutedOrderAmelia(uint tradeEventId, uint orderId, ref Trade trade, bool isBuying) {
		writeln("--> AMELIA: my order #",orderId,", attempting to ",isBuying?"BUY":"SELL",", was executed in ",trade.qty," units for $",trade.price," each");
	}
	void onTradeAmelia(uint tradeEventId, ref Trade trade, bool isAttackingBids) {
		writeln("--> AMELIA: trade #",tradeEventId,
				": aggressor #",trade.aggressorOrderId," (",isAttackingBids?trade.seller:trade.buyer,") ",
				isAttackingBids?"SOLD":"BOUGHT", " ",trade.qty," ",
				isAttackingBids?"to":"from"," order #", trade.aggressedOrderId," (",isAttackingBids?trade.buyer:trade.seller,
				") for $",trade.price);
	}

	void onBookAmelia(immutable PriceBookEntry[]* bidsPriceBook, immutable PriceBookEntry[]* asksPriceBook) {
		uint i=0;
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

	DExchange john = new DExchange("John", &onExecutedOrderJohn, &onTradeJohn);
	DExchange mary = new DExchange("Mary", &onExecutedOrderMary, &onTradeMary);
	DExchange amelia = new DExchange("Amelia", &onExecutedOrderAmelia, &onTradeAmelia, &onBookAmelia, null, null);

	writeln();
	DExchange.resetBooks();
	john.addBuyOrder(orderId++, 37.01, 100);
	john.addBuyOrder(orderId++, 37.02, 900);
	john.addBuyOrder(orderId++, 37.03, 800);
	john.addSellOrder(orderId++, 37.04, 200);
	john.addSellOrder(orderId++, 37.05, 600);
	john.addSellOrder(orderId++, 37.06, 700);
	mary.addSellOrder(orderId++, 37.02, 1000);

	writeln();
	DExchange.resetBooks();
	john.addBuyOrder(orderId++, 37.01, 100);
	john.addBuyOrder(orderId++, 37.02, 900);
	john.addBuyOrder(orderId++, 37.03, 800);
	john.addSellOrder(orderId++, 37.04, 200);
	john.addSellOrder(orderId++, 37.05, 600);
	john.addSellOrder(orderId++, 37.06, 700);
	mary.addBuyOrder(orderId++, 37.06, 1000);

	writeln();
	DExchange.resetBooks();
	mary.addBuyOrder(orderId++, 37.01, 100);
	mary.addBuyOrder(orderId++, 37.02, 900);
	mary.addBuyOrder(orderId++, 37.03, 800);
	mary.addSellOrder(orderId++, 37.04, 200);
	mary.addSellOrder(orderId++, 37.05, 600);
	mary.addSellOrder(orderId++, 37.06, 700);
	mary.addBuyOrder(orderId++, 37.01, 100);
	mary.addBuyOrder(orderId++, 37.02, 900);
	mary.addBuyOrder(orderId++, 37.03, 800);
	mary.addSellOrder(orderId++, 37.04, 200);
	mary.addSellOrder(orderId++, 37.05, 600);
	mary.addSellOrder(orderId++, 37.06, 700);
	john.addBuyOrder(orderId++, 37.06, 1000);

}
*/

