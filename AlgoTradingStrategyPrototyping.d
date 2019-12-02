module StrategyPrototypes;

/*

	BookUpdate
	ExecutionStatus
	SymbolInfo (trading status, bands, volume, last price)
	Timers


	Ordem garantida de eventos:

	1) Execution Status
	2) Symbol Info
	3) Book Update
	4) Execution Status
	5) Timers

	<-- Algumas infos já são sabidas. Deveriam elas vir no construtor? Exec Status, Symb Info... ?
	--> Não, pra simplificar as estratégias... porém essas funcs podem ser chamadas imediatamente após a instanciação

*/

import std.stdio;

import std.algorithm;
import std.math;
import std.array;
import std.conv;
import std.string;
import std.random;
import std.typecons;

static import DExchange;

// trades & strategy raw data, defining the functions:
//	string getRecordedTradesRawData(string symbol);
//	string getStrategyDealsRawData(string symbol, string strategy);
import data;

/** Convert a TAB separated string of trades data into a structured array of 'Trades' */
template TradesFromRawData(string tradesRawData) {
	// if called to assign to an 'static immutable' array, will run at compile-time
	DExchange.Trade[] get() {
		import std.csv;
		import std.algorithm.searching;
		import std.typecons;
//		static import std.regex;

		Trade[] trades = () {
//			auto timeWithMilliSRegex = std.regex.ctRegex!(r"^([0-9][0-9]):([0-9][0-9]):([0-9][0-9])\.([0-9]+)");	// for strings like "10:26:47.445"
			Trade[] trades = new Trade[tradesRawData.count('\n')];
			uint i=0;
			foreach (ref record; tradesRawData.csvReader!(
					Tuple!(string, string, string, string, string, string))
					 (["time", "qty", "price", "buyer", "seller", "cond"], '\t')) {
//				auto match = std.regex.matchAll(record[0], timeWithMilliSRegex);
/*				trades[i].timeMilliS = match.front[4].to!long +				// ms
				                       (1000*match.front[3].to!long) +		// sec
				                       (1000*60*match.front[2].to!long) +	// min
				                       (1000*60*60*match.front[1].to!long);	// hour*/
				trades[i].timeMilliS = record[0][9..11].to!ulong +				// ms
				                       (1000*record[0][6..7].to!ulong) +		// sec
				                       (1000*60*record[0][3..4].to!ulong) +		// min
				                       (1000*60*60*record[0][0..1].to!ulong);	// hour
				trades[i].qty        = record[1].replace(".", "").to!uint;
				trades[i].price      = record[2].replace(',', '.').to!double;
				trades[i].buyer      = record[3];
				trades[i].seller     = record[4];
				trades[i].cond       = record[5];
				i++;
			}
			return trades;
		} ();
		return trades;
	}
}

/** Convert a TAB separated string of strategy deals into a structured array of 'Trades' */
template StrategyDealsFromRawData(string strategyDealsRawData) {
	// if called to assign to an 'static immutable' array, will run at compile-time
	Trade[] get() {
		import std.csv;
		import std.algorithm.searching;
		import std.typecons;
//		static import std.regex;

		// build the 'strategyDeals' array
		Trade[] strategyDeals = () {
			Trade[] strategyDeals = new Trade[strategyDealsRawData.count('\n')];
//			auto HourAndMinuteRegex = std.regex.ctRegex!(r"^[^ ]* ([0-9][0-9]):([0-9][0-9])");	// for strings like "11/6/2019 10:20"
			uint i=0;
			foreach (ref record; strategyDealsRawData.csvReader!(
					Tuple!(string, string, string, string, string, string, string, string, string, string, string))
					(["Broker", "Account", "User", "Strategy", "Symbol", "Price", "Qty", "Side", "Memo", "Id", "Date"], '\t')) {
//				auto match = std.regex.matchAll(record[10], HourAndMinuteRegex);
				// time from strategy deals have only hour and minute -- while on the general trades for the symbol we may get also the seconds and milli seconds
/*				strategyDeals[i].timeMilliS = (1000*60*match.front[2].to!long) +	// min
				                              (1000*60*60*match.front[1].to!long);	// hour*/
				strategyDeals[i].timeMilliS = (1000*60*record[10][10..11].to!ulong) +	// min
				                              (1000*60*60*record[10][13..14].to!ulong);	// hour
				strategyDeals[i].qty        = record[6].replace(".", "").to!uint;
				strategyDeals[i].price      = record[5].replace(',', '.').to!double;
				strategyDeals[i].cond       = "";
				if (record[7] == "Sell") {
					strategyDeals[i].seller = record[0];
					strategyDeals[i].buyer  = "";
				} else {
					strategyDeals[i].seller = "";
					strategyDeals[i].buyer  = record[0];
				}
				i++;
			}

			return strategyDeals;
		} ();
		return strategyDeals;
	}
}

/**  */
uint getTotalTradedQuantity(immutable DExchange.Trade[] trades) {
	uint totalQuantity = 0;
	each!(t => totalQuantity += t.qty)(trades);
	return totalQuantity;
}

double getAveragePrice(immutable DExchange.Trade[] trades) {
	double priceAndQuantityProductSum    = 0;
	uint   quantitySum                   = 0;
	each!( (DExchange.Trade t) {
		priceAndQuantityProductSum+=t.price*t.qty;
		quantitySum+=t.qty;
	}) (trades);
	return priceAndQuantityProductSum / quantitySum;
}

/** given the deals due to the strategy, 'strategyDeals', attempt to find them in the 'trades'
  * array -- returning the indexes (from the 'trades' array) which
  * corresponds to the given 'trades'. */
uint[] getStrategyDealsIndexesInTrades(immutable DExchange.Trade[] trades, immutable DExchange.Trade[] strategyDeals) {

	// attempt to find the best candidates in 'trades' matching the elements from 'strategyDeals'
	// (using, in priority order: one of seller or buyer, qty, price and time)
	DExchange.Trade[] unmatchedTrades = trades.dup;
	uint[] matchedIndexes = new uint[strategyDeals.length];

	bool matchFunc(ref immutable DExchange.Trade deal, ref DExchange.Trade trade, uint dealIndex, uint tradeIndex) {
		if (trade.qty == deal.qty && trade.price == deal.price &&
			deal.timeEqualsMinutePrecision(trade.timeMilliS) &&
			( (deal.seller != "" && trade.seller == deal.seller) ||
			  (deal.buyer  != "" && trade.buyer  == deal.buyer) ) ) {
				//writeln("deal #", dealIndex, ", strategy #", tradeIndex," (", deal, ") matched with trade (", trade, ")");
				matchedIndexes[dealIndex] = tradeIndex;
				trade.qty = 0;	// do not use this trade again to match any other deal
				return true;
		} else {
			return false;
		}
	}

	foreach (i, ref deal; strategyDeals) {
		bool matched = false;
		// back and forth looping througn trades in an attempt to scatter the distribution of the matched records
		if (i % 2) {
			foreach_reverse (j, ref trade; unmatchedTrades) {
				if (matchFunc(deal, trade, to!uint(i), to!uint(j))) {
					matched = true;
					break;
				}
			}
		}

		if (!matched) {
			foreach (j, ref trade; unmatchedTrades) {
				if (matchFunc(deal, trade, to!uint(i), to!uint(j))) {
					matched = true;
					break;
				}
			}
		}

		if (!matched) {
			//writeln("Deal #",i," not matched: ", deal);
			matchedIndexes[i] = -1;
		}
	}

	// less permissive match for any unmatched deals
	foreach(i, index; matchedIndexes) {
		bool matched = false;
		if (index == -1) {
			//write("Retrying to match deal #",i,": ");
			foreach (j, ref trade; unmatchedTrades) {
				if (trade.qty == strategyDeals[i].qty && trade.price == strategyDeals[i].price &&
					trade.timeEqualsMinutePrecision(strategyDeals[i].timeMilliS) ) {
					matchedIndexes[i] = to!uint(j);
					trade.qty = 0;	// do not use this trade again to match any other deal
					matched = true;
					break;
				}
			}
			if (!matched) {
				//writeln("NOT MATCHED...");
			} else {
				//writeln("solved!");
			}
		}
	}

	// even less permissive match for any still unmatched deals
	foreach(i, index; matchedIndexes) {
		bool matched = false;
		if (index == -1) {
			//write("Still retrying to match deal #",i,": ");
			foreach (j, ref trade; unmatchedTrades) {
				if (trade.qty == strategyDeals[i].qty && trade.price == strategyDeals[i].price) {
					matchedIndexes[i] = to!uint(j);
					trade.qty = 0;	// do not use this trade again to match any other deal
					matched = true;
					break;
				}
			}
			if (!matched) {
				//writeln("GIVING UP. REALLY NOT MATCHED...");
				assert(false, "not way to match it");
			} else {
				//writeln("solved!");
			}
		}
	}

	matchedIndexes.sort();
	return matchedIndexes;
}

/** returns a new array based on 'trades', but without the elements whose indexes are presented on 'matchedIndexes',
    which should be sorted. */
DExchange.Trade[] filterOutStrategyDealsFromTrades(immutable DExchange.Trade[] trades, uint[] matchedIndexes) {
	DExchange.Trade[] filteredTrades = new DExchange.Trade[trades.length-matchedIndexes.length];
	uint filteredTrades_i = 0;
	uint matchedIndexes_i = 0;
	foreach (tradesIndex, ref trade; trades) {
		if (matchedIndexes_i < matchedIndexes.length && tradesIndex == matchedIndexes[matchedIndexes_i]) {
			// filter
			matchedIndexes_i++;
			// order checking
			if (matchedIndexes_i < matchedIndexes.length-1) {
				assert(matchedIndexes[matchedIndexes_i] < matchedIndexes[matchedIndexes_i+1], "to-filter array must be sorted");
			}
		} else {
			// do not filter
			filteredTrades[filteredTrades_i++] = trade;
		}
	}

	// sanity checking
	assert(matchedIndexes_i == matchedIndexes.length, "How come not all to-filter array members were filtered?");
	assert(filteredTrades_i == filteredTrades.length, "How come the filtered array don't have the expected number of elements?");

	return filteredTrades;
}

/** Builds randoms "bids" and "asks" books around the given Trades */
void buildBookArroundTrades(DExchange.Trade[] trades, uint maxDepth) {

}


template ForData(string symbol, string strategy) {
	void analyze() {
		/*static immutable */Trade[] trades         = TradesFromRawData!(getRecordedTradesRawData(symbol)).get();
		double  tradesAvgPrice = getAveragePrice(cast(immutable)trades);
		uint    tradesQty      = getTotalTradedQuantity(cast(immutable)trades);
		
		/*static immutable */Trade[] strategyDeals         = StrategyDealsFromRawData!(getStrategyDealsRawData(symbol, strategy)).get();
		double  strategyDealsAvgPrice = getAveragePrice(cast(immutable)strategyDeals);
		uint    strategyDealsQty      = getTotalTradedQuantity(cast(immutable)strategyDeals);

		uint[]  strategyTradesIndexes  = getStrategyDealsIndexesInTrades(cast(immutable)trades, cast(immutable)strategyDeals);
		Trade[] filteredTrades         = filterOutStrategyDealsFromTrades(cast(immutable)trades, strategyTradesIndexes);
		double  filteredTradesAvgPrice = getAveragePrice(cast(immutable)filteredTrades);
		uint    filteredTradesQty      = getTotalTradedQuantity(cast(immutable)filteredTrades);

		enum ESideName {BUY, SELL}
		ESideName side    = strategyDeals[0].buyer != "" ? ESideName.BUY : ESideName.SELL;
		double sideFactor = side == ESideName.BUY ? 1.0 : -1.0;
		string sideName   = side == ESideName.BUY ? "COMPRANDO" : "VENDENDO";
		string clientName = strategyDeals[0].buyer != "" ? strategyDeals[0].buyer : strategyDeals[0].seller;

		// contabiliza ataques ao book dos bids e asks
		template AttacksAccountantStrategy(string symbol, string strategy) {
			auto onBook           = (uint bookEventId, ref BuyOrder[] bids, ref SellOrder[] asks) {};
			auto onExecutedOrder  = (uint tradeEventId, uint orderId, ref Trade trade, bool isAttackingBids) {};
			auto onCancelledOrder = (uint orderId) {};
			auto onTrade          = (uint tradeEventId, ref Trade trade, bool isAttackingBids) {
				if (isAttackingBids) {
					bidAttacks++;
				} else {
					askAttacks++;
				}
			};
			uint bidAttacks = 0;
			uint askAttacks = 0;
			void delegate (uint orderId,  ref BuyOrder  order) placeBuyOrderDelegate;
			void delegate (uint orderId,  ref SellOrder order) placeSellOrderDelegate;
			void simulate(Trade[] trades) {
				Exchange atacksAccountantExchange = Exchange(onBook,
															 onExecutedOrder,
															 onCancelledOrder,
															 onTrade);
				placeBuyOrderDelegate  = &atacksAccountantExchange.placeBuyOrder;
				placeSellOrderDelegate = &atacksAccountantExchange.placeSellOrder;
				atacksAccountantExchange.simulateBookEventsBasedOnTrades(trades);
			}
		}
		AttacksAccountantStrategy!(symbol, strategy).simulate(filteredTrades);

		// formatting
		string[string] f;
		f["tradesAvgPrice"]         = format("%8,3.4f", tradesAvgPrice);
		f["strategyDealsAvgPrice"]  = format("%8,3.4f", strategyDealsAvgPrice);
		f["filteredTradesAvgPrice"] = format("%8,3.4f", filteredTradesAvgPrice);
		f["tradesQty"]         = format("%9,d", tradesQty);
		f["strategyDealsQty"]  = format("%9,d", strategyDealsQty);
		f["filteredTradesQty"] = format("%9,d", filteredTradesQty);
		f["trades.length"]         = format("%6,d", trades.length);
		f["strategyDeals.length"]  = format("%6,d", strategyDeals.length);
		f["filteredTrades.length"] = format("%6,d", filteredTrades.length);
		f["correctParticipation%"] = format("%7,3.4f", (to!double(strategyDealsQty)/to!double(tradesQty))*100.0);
		f["wrongParticipation%"]   = format("%7,3.4f", (to!double(strategyDealsQty)/to!double(filteredTradesQty))*100.0);
		f["totalGain"]   = format("%8,3.2f", (filteredTradesAvgPrice-strategyDealsAvgPrice)*strategyDealsQty*sideFactor);
		f["perUnitGain"] = format("%7,3.4f", ((filteredTradesAvgPrice-strategyDealsAvgPrice)*strategyDealsQty*sideFactor)/strategyDealsQty);
		f["bidAttacks"]  = format("%,d", AttacksAccountantStrategy!(symbol, strategy).bidAttacks);
		f["askAttacks"]  = format("%,d", AttacksAccountantStrategy!(symbol, strategy).askAttacks);

		writeln(strategy, " em ", symbol, " (", clientName, " estava ", sideName, "):");
		writeln("\tNegócios no período, incluindo trades da estratégia: \t avgPrice: ",         f["tradesAvgPrice"], "  \t  qty: ",         f["tradesQty"], "    \t @: ", f["trades.length"]);
		writeln("\t                               Trades da estratégia: \t avgPrice: ",  f["strategyDealsAvgPrice"], "  \t  qty: ",  f["strategyDealsQty"], "    \t @: ", f["strategyDeals.length"]);
		writeln("\t                           Mercado sem a estratégia: \t avgPrice: ", f["filteredTradesAvgPrice"], "  \t  qty: ", f["filteredTradesQty"], "    \t @: ", f["filteredTrades.length"]);
		writeln("\tparticipação:    ", f["correctParticipation%"], " % \t --  \t ou ", f["wrongParticipation%"]," %");
		writeln("\t       ganho: R$ ", f["totalGain"], "  \t --  \t R$ ", f["perUnitGain"]," por und");
		writeln("\tAtaques: BIDS=",f["bidAttacks"],"; ASKS=",f["askAttacks"]);
		writeln();
	}
}

void spikes() {

	bool amIInCTFE()
	{
		return __ctfe;
	}

    bool                  a = amIInCTFE(); // regular runtime initialization
    enum bool             b = amIInCTFE(); // forces compile-time evaluation with enum
    static immutable bool c = amIInCTFE(); // forces compile-time evaluation with static immutable

    writeln(a, " ", &a);   // Prints: "false <address of a>"
    //writeln(b, " ", &b); // Error: enum declarations have no address
    writeln(c, " ", &c);   // Prints: "true <address of c>"


	//static immutable uint[] arr = [3, 2, 1, 0];
	static immutable uint[] arr = () {
		uint[] arr = new uint[32];
		arr[] = 0;
		arr[8] = 1;
		string t = "12:21";
		arr[16] = (t[0 .. 1].to!uint) +		// min
		          (60*t[3 .. 4].to!uint);	// hour

		return arr;
	}();
	static foreach (i, v; arr) {
		writeln("arr[",i,"]=",v);
	}

	writeln("arr.length=", arr.length);

	import std.random;
	for (uint i=0; i<100; i++) {
		uint rnd = uniform(0, 2);
		write(rnd, ", ");
	}

}

struct BuyOrder {
	uint   qty;
	double limitPrice;
}

struct SellOrder {
	uint   qty;
	double limitPrice;
}

struct Exchange {

	// delegates
	void function (uint bookEventId,  ref BuyOrder[] bids, ref SellOrder[] asks)                     onBookDelegate;
	void function (uint tradeEventId, uint orderId, ref DExchange.Trade trade, bool isAttackingBids) onExecutedOrderDelegate;
	void function (uint orderId)                                                                     onCancelledOrderDelegate;
	void function (uint tradeEventId, ref DExchange.Trade trade, bool isAttackingBids)               onTradeDelegate;

	// books
	uint bookEventId  = 1;
	static immutable uint   priceLevels        = 5;
	static immutable double maxPriceLevelDelta = 0.01;
	static immutable double maxSpread          = 0.05;
	BuyOrder[]  bids = new BuyOrder[priceLevels];
	SellOrder[] asks = new SellOrder[priceLevels];

	// trade
	uint tradeEventId = 1;


	this(void function (uint bookEventId,  ref BuyOrder[] bids, ref SellOrder[] asks)                     onBookDelegate,
         void function (uint tradeEventId, uint orderId, ref DExchange.Trade trade, bool isAttackingBids) onExecutedOrderDelegate,
         void function (uint orderId)                                                                     onCancelledOrderDelegate,
         void function (uint tradeEventId, ref DExchange.Trade trade, bool isAttackingBids)               onTradeDelegate) {
		this.onBookDelegate           = onBookDelegate;
		this.onExecutedOrderDelegate  = onExecutedOrderDelegate;
		this.onCancelledOrderDelegate = onCancelledOrderDelegate;
		this.onTradeDelegate          = onTradeDelegate;
	}

	void removeFromBids(uint index) {
		bids.remove(index);
		bids[$-1].qty        = 0;
		bids[$-1].limitPrice = 0;
	}

	void removeFromAsks(uint index) {
		asks.remove(index);
		asks[$-1].qty        = 0;
		asks[$-1].limitPrice = 0;
	}

	/** Tries to match the order against the 'asks' book, yelding a an 'onExecutedOrder' event
	    to the caller and a 'trade' event to everyone else in case of success.
	    In case the order cannot be matched immediately, it will be added to the 'bids' book
	    and events will be issued on execution as described above. */
	void placeBuyOrder(uint orderId, ref BuyOrder order) {
		int askIndex = 0;
		uint qty = order.qty;
		while (askIndex < priceLevels) {
			auto ask = &asks[askIndex];
			if (ask.limitPrice <= order.limitPrice && qty > 0) {
				if (ask.qty >= qty) {
					// fully execute the first entry on the ask book, immediatelly
					DExchange.Trade trade = DExchange.Trade(100000+tradeEventId, qty, ask.limitPrice, "ayr", "codla", "");
					//onTradeDelegate();	// para todos os outros
					this.onExecutedOrderDelegate(tradeEventId++, orderId, trade, false);
					write("######");
					ask.qty -= qty;
					this.onBookDelegate(bookEventId++, bids, asks);
					break;
				} else if (ask.qty > 0) {
					// partially execute the first entry on the ask book, immediatelly
					DExchange.Trade trade = DExchange.Trade(100000+tradeEventId, ask.qty, ask.limitPrice, "ary", "cloda", "");
					qty -= ask.qty;
					//onTradeDelegate();	// para todos os outros
					this.onExecutedOrderDelegate(tradeEventId++, orderId, trade, false);
					removeFromAsks(askIndex);
					this.onBookDelegate(bookEventId++, bids, asks);
					continue;
				}
			}
			askIndex++;
		}
	};

	void placeSellOrder(uint orderId, ref SellOrder order) {

	};

	void simulateBookEventsBasedOnTrades(ref DExchange.Trade[] trades) {

		// zero the book
		for (uint i=0; i<priceLevels; i++) {
			bids[i].qty = 0;
			bids[i].limitPrice = 0.0;
			asks[i].qty = 0;
			asks[i].limitPrice = 0.0;
		}

		foreach (trade; trades) {

			// monta book inoquo (preenche posições vazias com valores não executáveis):
			double lastBidPrice = bids[0].limitPrice > 0 ? min(trade.price, bids[0].limitPrice) : trade.price;
			double lastAskPrice = asks[0].limitPrice > 0 ? max(trade.price, asks[0].limitPrice) : trade.price;
			while (lastAskPrice-lastBidPrice > maxSpread) {
				if (uniform(0, 2) == 1) {
					lastBidPrice += 0.01;
				} else {
					lastAskPrice -= 0.01;
				}
			}
			// garante spread mínimo de 0.01
			if (abs(lastAskPrice-lastBidPrice) < 1e-3) {
				if (uniform(0, 2) == 1) {
					lastBidPrice -= 0.01;
				} else {
					lastAskPrice += 0.01;
				}
			}
			bool didBookChange = false;
			for (uint i=0; i<priceLevels; i++) {
				if (bids[i].limitPrice == 0 || abs(lastBidPrice-bids[i].limitPrice) > maxPriceLevelDelta) {
					bids[i].qty        = (uniform(0, 21)+1)*100;
					bids[i].limitPrice = lastBidPrice;
					lastBidPrice -= 0.01;
					didBookChange = true;
				} else {
					lastBidPrice = bids[i].limitPrice - 0.01;
				}
				if (asks[i].limitPrice == 0 || abs(asks[i].limitPrice-lastAskPrice) > maxPriceLevelDelta) {
					asks[i].qty        = (uniform(0, 21)+1)*100;
					asks[i].limitPrice = lastAskPrice;
					lastAskPrice += 0.01;
					didBookChange = true;
				} else {
					lastAskPrice = asks[i].limitPrice + 0.01;
				}
			}
			if (didBookChange) {
				onBookDelegate(bookEventId++, bids, asks);
			}

			// determina ordem a ser agredida
			double targetPrice = trade.price;
			uint   targetQty   = trade.qty;
			bool   isAttackingBids = abs(targetPrice - asks[0].limitPrice) > abs(bids[0].limitPrice - targetPrice)
									 ? true : abs(targetPrice - asks[0].limitPrice) == abs(bids[0].limitPrice - targetPrice)
									   ? uniform(0, 2) == 1
										 ? true : false
									  : false;
			// cancela ordens com prioridade maior que a a ser agredida
			bool isAsksOK = false;
			bool isBidsOK = false;
			while (true) {
				// deleta ordens até que haja um spread entre bid e ask onde se possa encaixar o targetPrice,
				// tomando o cuidado para não deletar nenhuma ordem que já exista e possa ser atacada
				if (asks[0].limitPrice > 0 && (asks[0].limitPrice < targetPrice || asks[0].limitPrice == targetPrice && isAttackingBids)) {
					removeFromAsks(0);
				} else {
					isAsksOK = true;
				}
				if (bids[0].limitPrice > 0 && (bids[0].limitPrice > targetPrice || bids[0].limitPrice == targetPrice && !isAttackingBids)) {
					removeFromBids(0);
				} else {
					isBidsOK = true;
				}
				if (!isBidsOK || !isAsksOK) {
					onBookDelegate(bookEventId++, bids, asks);
				} else {
					break;
				}
			}

			// garante que a ordem a ser agredida existe
			if (isAttackingBids) {
				// garante que a ordem a ser agredida existe no topo dos BIDS
				if (bids[0].limitPrice == targetPrice) {
					// garante a quantidade
					if (bids[0].qty < targetQty) {
						bids[0].qty = targetQty;
						onBookDelegate(bookEventId++, bids, asks);
					}
				} else {
					// simulate a new BUY order -- insert at the beginning
					for (int i=priceLevels-2; i>=0; i--) {
						bids[i+1] = bids[i];
					}
					bids[0].qty        = targetQty;
					bids[0].limitPrice = targetPrice;
					onBookDelegate(bookEventId++, bids, asks);
				}
			} else {
				// garante que a ordem a ser agredida existe no topo dos ASKS
				if (asks[0].limitPrice == targetPrice) {
					// garante a quantidade
					if (asks[0].qty < targetQty) {
						asks[0].qty = targetQty;
						onBookDelegate(bookEventId++, bids, asks);
					}
				} else {
					// simulate a new SELL order -- insert at the beginning
					for (int i=priceLevels-2; i>=0; i--) {
						asks[i+1] = asks[i];
					}
					asks[0].qty        = targetQty;
					asks[0].limitPrice = targetPrice;
					onBookDelegate(bookEventId++, bids, asks);
				}
			}

			// trade
			onTradeDelegate(tradeEventId++, trade, isAttackingBids);

			// remove a ordem agredida do book (sem emitir evento de book)
			if (isAttackingBids) {
				// remove the quantity or remove the order
				if (bids[0].qty > targetQty) {
					bids[0].qty -= targetQty;
				} else {
					removeFromBids(0);
				}
			} else {
				// remove the quantity or remove the order
				if (asks[0].qty > targetQty) {
					asks[0].qty -= targetQty;
				} else {
					removeFromAsks(0);
				}
			}

		}
	}

}


int main() {

	//import core.stdc.locale;
	//setlocale(LC_ALL, "pt-BR");

	template TestStrategy(string symbol, string strategy) {

		Trade[] _trades = [
			{100000, 100, 37.12, "pappa",   "mamma", ""},
			{101000, 600, 36.12, "pappa",   "aunt",  ""},
			{102000, 700, 37.01, "little",  "pappa", ""},
			{103000, 100, 37.13, "selling", "mamma", ""},
			{104000, 200, 37.15, "A", "B", ""},
			{105000, 700, 37.13, "A", "B", ""},
			{106000, 100, 37.11, "A", "B", ""},
			{107000, 300, 37.09, "A", "B", ""},
			{108000, 400, 37.13, "A", "B", ""},
		];

		Trade[] load() {
			Trade[] trades                 = TradesFromRawData!(getRecordedTradesRawData(symbol)).get();
			Trade[] strategyDeals          = StrategyDealsFromRawData!(getStrategyDealsRawData(symbol, strategy)).get();
			uint[]  strategyTradesIndexes  = getStrategyDealsIndexesInTrades(cast(immutable)trades, cast(immutable)strategyDeals);
			Trade[] filteredTrades         = filterOutStrategyDealsFromTrades(cast(immutable)trades, strategyTradesIndexes);
			return filteredTrades;
		}

		BuyOrder[]  lastBids;
		SellOrder[] lastAsks;
		uint lastBookEventId;
		auto onBook = (uint bookEventId, ref BuyOrder[] bids, ref SellOrder[] asks) {
			lastBids = bids;
			lastAsks = asks;
			lastBookEventId = bookEventId;
			if (bids[0].qty > 0 && asks[0].qty > 0) {
				double spread = asks[0].limitPrice-bids[0].limitPrice;
				if (spread > 0.0501) {
					{///*
						write("spread = ", spread, " -- ");
						write("BIDS: [");
						foreach (bid; lastBids) {
							write("{",bid.limitPrice,", ",bid.qty,"}, ");
						}
						write("]; ASKS: [");
						foreach (ask; lastAsks) {
							write("{",ask.limitPrice,", ",ask.qty,"}, ");
						}
						writeln();//*/
					}
					BuyOrder order = BuyOrder(asks[0].qty, asks[0].limitPrice);
					placeBuyOrderDelegate(1000000+bookEventId, order);
				}
			}
//			writeln("Book change #",bookEventId,":\n\t\tbids=",bids,";\n\t\tasks=",asks);
		};

		auto onExecutedOrder  = (uint tradeEventId, uint orderId, ref Trade trade, bool isAttackingBids) {
			writeln("!!!!!!!!!Ordem executada: tradeEventId: ",tradeEventId,"; orderId: ",orderId, "; trade=",trade,"; isAttackingBids=",isAttackingBids);
		};

		auto onCancelledOrder = (uint orderId) {};

		uint bidAttacks = 0;
		uint askAttacks = 0;
		auto onTrade = (uint tradeEventId, ref Trade trade, bool isAttackingBids) {
///*
			writeln("Last BOOK change #",lastBookEventId,":");
			write("\t\tBIDS: [");
			foreach (bid; lastBids) {
			write("{",bid.limitPrice,", ",bid.qty,"}, ");
			}
			write("]\n\t\tASKS: [");
			foreach (ask; lastAsks) {
			write("{",ask.limitPrice,", ",ask.qty,"}, ");
			}
			write("]\n");
			writeln("===> Trade #",tradeEventId,": ", trade, " due to an attack on ", isAttackingBids ? "BIDS" : "ASKS", ":");
			//*/
			// statistics
			if (isAttackingBids) {
				bidAttacks++;
			} else {
				askAttacks++;
			}
		};

		void delegate (uint orderId,  ref BuyOrder  order) placeBuyOrderDelegate;
		void delegate (uint orderId,  ref SellOrder order) placeSellOrderDelegate;

		void simulate() {
			Exchange exchange = Exchange(onBook, onExecutedOrder, onCancelledOrder, onTrade);
			placeBuyOrderDelegate  = &exchange.placeBuyOrder;
			placeSellOrderDelegate = &exchange.placeSellOrder;
			//load();
			exchange.simulateBookEventsBasedOnTrades(_trades);
		}

	}
/*
	TestStrategy!("BBAS3", "POV").simulate();
	writeln("\tAtaques: BIDS=",TestStrategy!("BBAS3", "POV").bidAttacks,"; ASKS=",TestStrategy!("BBAS3", "POV").askAttacks);
//*/

/*
	// analyze POV operations
	ForData!("BBAS3", "POV").analyze();
	ForData!("PETR4", "POV").analyze();
	ForData!("GGBR4", "POV").analyze();
	ForData!("CVCB3", "POV").analyze();
//*/

//	spikes();

	DExchange.test();

	//readln();
    return 0;
}