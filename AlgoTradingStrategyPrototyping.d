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

import Types: Trade, ETradeSide, PriceBookEntry;
import DExchange: LocalDExchange, LocalDExchangeSession, BookManipulators;

// trades & strategy raw data, defining the functions:
//	string getRecordedTradesRawData(string symbol);
//	string getStrategyDealsRawData(string symbol, string strategy);
import data;

/** Convert a TAB separated string of trades data into a structured array of 'Trades' */
Trade[] getTradesFromRawData(string tradesRawData) {
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

/** Convert a TAB separated string of strategy deals into a structured array of 'Trades' */
Trade[] getStrategyDealsFromRawData(string strategyDealsRawData) {
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

/**  */
uint getTotalTradedQuantity(immutable Trade[] trades) {
	uint totalQuantity = 0;
	each!(t => totalQuantity += t.qty)(trades);
	return totalQuantity;
}

double getAveragePrice(immutable Trade[] trades) {
	double priceAndQuantityProductSum    = 0;
	uint   quantitySum                   = 0;
	each!( (Trade t) {
		priceAndQuantityProductSum+=t.price*t.qty;
		quantitySum+=t.qty;
	}) (trades);
	return priceAndQuantityProductSum / quantitySum;
}

/** given the deals due to the strategy, 'strategyDeals', attempt to find them in the 'trades'
  * array -- returning the indexes (from the 'trades' array) which
  * corresponds to the given 'trades'. */
uint[] getStrategyDealsIndexesInTrades(immutable Trade[] trades, immutable Trade[] strategyDeals) {

	// attempt to find the best candidates in 'trades' matching the elements from 'strategyDeals'
	// (using, in priority order: one of seller or buyer, qty, price and time)
	Trade[] unmatchedTrades = trades.dup;
	uint[] matchedIndexes = new uint[strategyDeals.length];

	bool matchFunc(ref immutable Trade deal, ref Trade trade, uint dealIndex, uint tradeIndex) {
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
Trade[] filterOutStrategyDealsFromTrades(immutable Trade[] trades, uint[] matchedIndexes) {
	Trade[] filteredTrades = new Trade[trades.length-matchedIndexes.length];
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
void buildBookArroundTrades(Trade[] trades, uint maxDepth) {

}


void analyzeForData(string symbol, string strategy) {
	/*static immutable */Trade[] trades         = getTradesFromRawData(getRecordedTradesRawData(symbol));
	double  tradesAvgPrice = getAveragePrice(cast(immutable)trades);
	uint    tradesQty      = getTotalTradedQuantity(cast(immutable)trades);
		
	/*static immutable */Trade[] strategyDeals         = getStrategyDealsFromRawData(getStrategyDealsRawData(symbol, strategy));
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
/*	template AttacksAccountantStrategy(string symbol, string strategy) {
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
*/
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
//	f["bidAttacks"]  = format("%,d", AttacksAccountantStrategy!(symbol, strategy).bidAttacks);
//	f["askAttacks"]  = format("%,d", AttacksAccountantStrategy!(symbol, strategy).askAttacks);

	writeln(strategy, " em ", symbol, " (", clientName, " estava ", sideName, "):");
	writeln("\tNegócios no período, incluindo trades da estratégia: \t avgPrice: ",         f["tradesAvgPrice"], "  \t  qty: ",         f["tradesQty"], "    \t @: ", f["trades.length"]);
	writeln("\t                               Trades da estratégia: \t avgPrice: ",  f["strategyDealsAvgPrice"], "  \t  qty: ",  f["strategyDealsQty"], "    \t @: ", f["strategyDeals.length"]);
	writeln("\t                           Mercado sem a estratégia: \t avgPrice: ", f["filteredTradesAvgPrice"], "  \t  qty: ", f["filteredTradesQty"], "    \t @: ", f["filteredTrades.length"]);
	writeln("\tparticipação:    ", f["correctParticipation%"], " % \t --  \t ou ", f["wrongParticipation%"]," % (sem contar os trades da estratégia)");
	writeln("\t       ganho: R$ ", f["totalGain"], "  \t --  \t R$ ", f["perUnitGain"]," por und");
//	writeln("\tAtaques: BIDS=",f["bidAttacks"],"; ASKS=",f["askAttacks"]);
	writeln();
}


int main() {

	//import core.stdc.locale;
	//setlocale(LC_ALL, "pt-BR");

	/** From a given set of trades, constructs a possible set of order additions and cancellations that would lead to those
	    trades in such a way that all exchange session events are available. The purpose of this class is to intercept these
	    events and generate the source code to test strategies in the ATG's algo node -- book and trade events are the ones used. */
	class ToAlgoNodeExchangeEventsReplayer: LocalDExchangeSession {

		string     symbol;
		ETradeSide side;

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

		Trade[] load(string symbol, string strategy) {
			Trade[] trades                 = getTradesFromRawData(getRecordedTradesRawData(symbol));
			Trade[] strategyDeals          = getStrategyDealsFromRawData(getStrategyDealsRawData(symbol, strategy));
			uint[]  strategyTradesIndexes  = getStrategyDealsIndexesInTrades(cast(immutable)trades, cast(immutable)strategyDeals);
			Trade[] filteredTrades         = filterOutStrategyDealsFromTrades(cast(immutable)trades, strategyTradesIndexes);
			return filteredTrades;
//			return _trades;
		}

		immutable uint nLevels = 1;
		real lastBidPrice = 0;
		real lastAskPrice = 0;
		uint lastBidQuantity = 0;
		uint lastAskQuantity = 0;
		uint algoNodePriceBookEvents = 0;
		/** dumps the 'bids' and 'asks' books, up to 'n' level each */
		void dumpAlgoNodePriceBook(immutable PriceBookEntry[]* bidsPriceBook, immutable PriceBookEntry[]* asksPriceBook) {
			real bidPrice    = lastBidPrice;
			real askPrice    = lastAskPrice;
			uint bidQuantity = lastBidQuantity;
			uint askQuantity = lastAskQuantity;
			uint c = 0;
			foreach(priceBookEntry; *bidsPriceBook) {
				bidPrice    = priceBookEntry.price;
				bidQuantity = priceBookEntry.quantity;
				c++;
				if (c >= nLevels) {
					break;
				}
			}
			c = 0;
			foreach(priceBookEntry; *asksPriceBook) {
				askPrice    = priceBookEntry.price;
				askQuantity = priceBookEntry.quantity;
				c++;
				if (c >= nLevels) {
					break;
				}
			}
			// comment with /* at the start of this line to activate a more realistic book, with several updates that don't change the first position
			if (bidPrice != lastBidPrice || bidQuantity != lastBidQuantity ||
				askPrice != lastAskPrice || askQuantity != lastAskQuantity) //*/
			{
				lastBidPrice    = bidPrice;
				lastBidQuantity = bidQuantity;
				lastAskPrice    = askPrice;
				lastAskQuantity = askQuantity;
				writeln("\t\tsandbox.marketData.priceBook(\"",symbol,"\", ",bidPrice,", ",askPrice,", ",bidQuantity,", ",askQuantity,");");
				algoNodePriceBookEvents++;
			}
		}

		uint dexchangeBookEvents;
		override void onBook(uint securityId, immutable PriceBookEntry[]* bidsPriceBook, immutable PriceBookEntry[]* asksPriceBook) {
			//bookManipulators.dumpPriceBook(bidsPriceBook, asksPriceBook);
			dumpAlgoNodePriceBook(bidsPriceBook, asksPriceBook);
			dexchangeBookEvents++;
		}

		Trade realTrade;			// will be set prior to execution -- the real trade used to derive this trade (we may have n trades to account for the real trade quantity)
		ETradeSide aggressorSide;	// will be set prior to placing aggressive orders
		uint tradedQuantitySoFar = 0;
		real tradedCurrencySoFar = 0;
		override void onExecution(uint securityId, uint tradeEventId, uint orderId, ref Trade trade, bool isAggressor) {
			ETradeSide aggressedSide = (aggressorSide == ETradeSide.BUY) ? ETradeSide.SELL : ETradeSide.BUY;
			//writeln("!!!!!!!!!Ordem simulada foi executada! tradeEventId: ",tradeEventId,"; orderId: ",orderId, "; trade=",trade,/*"; isAggressor=",isAggressor,*/"; aggressedSide=",aggressedSide);
			writeln("preTrade();");
			writeln("\tsandbox.marketData.sendTrade(\"",symbol,"\",",trade.price,", ",trade.qty,", false, false, \"",realTrade.buyer,"\", \"",realTrade.seller,"\");");
			tradedQuantitySoFar += trade.qty;
			tradedCurrencySoFar += trade.qty*trade.price;
			//writeln("console.log(\"tradedQuantitySoFar=",tradedQuantitySoFar,"; tradedCurrencySoFar=",tradedCurrencySoFar,"; tradesCompletionSoFar=",tradedCurrencySoFar / totalTradedCurrency,"\");");
			writeln("posTrade(\"",symbol,"\", sandbox, ",tradedQuantitySoFar,", ",tradedCurrencySoFar,", ",tradedCurrencySoFar / totalTradedCurrency,", \"",side,"\", ",lastBidPrice,", ",lastAskPrice,", ",lastBidQuantity,", ",lastAskQuantity,");");

			// statistics
			final switch (aggressorSide) {
				case ETradeSide.BUY:
					askAttacks++;
					break;
				case ETradeSide.SELL:
					bidAttacks++;
					break;
			}
		}

		override void onAddition(uint securityId, string party, uint orderId, ETradeSide side, real limitFaceValue, uint quantity) {}
		override void onCancellation(uint securityId, string party, uint orderId, ETradeSide side, real limitFaceValue, uint quantity) {}

		uint bidAttacks = 0;
		uint askAttacks = 0;
		override void onTrade(uint securityId, uint tradeEventId, ref Trade trade, bool isAttackingBids) {
			///*
			writeln("?????????Ordem não emitida por mim foi executada????????? -- trade=",trade,":");
			writeln("\t===> Trade #",tradeEventId,": ", trade, " due to an attack on ", isAttackingBids ? "BIDS" : "ASKS", ":");
			//dumpNextPriceBook = true;
			//*/
		}

		void dumpPOVTestOpeningCode(uint wantedQuantity, real targetParticipation, real minParticipation, real maxParticipation) {
			writeln(q"[tests.POV]",symbol,q"[Test = function (sandbox) {

	console.log("Starting production data replay test for POV. ]",side,q"[ING with parameters: quantity=]",wantedQuantity,q"[, participation=]",targetParticipation,q"[, minParticipation=]",minParticipation,q"[,maxParticipation=]",maxParticipation,q"[");

	resetTestMetrics();

    var strategy = new sandbox.MarketParticipationWorker();
    var request = util.getDefaultRequest(povUtil.defaultCreate);
    request.instruments[0].instrument = "]", symbol, q"[";
    request.instrumentsInfo[0].instrument = "]",symbol,q"[";

    request.extraparam[povUtil.povParams.commomParams.endHour] = "23";
    request.extraparam[povUtil.povParams.commomParams.endMinute] = "59";

    request.instruments[0].quantity = ]",wantedQuantity,q"[;
	request.instruments[0].side = "]",side,q"[";

    request.extraparam[povUtil.povParams.minParticipation] = "]",minParticipation,q"[";
    request.extraparam[povUtil.povParams.participation] = "]",targetParticipation,q"[";
    request.extraparam[povUtil.povParams.maxParticipation] = "]",maxParticipation,q"[";

    util.initStrategy(strategy, request, povUtil.validator);
    sandbox.marketData.setTradingStatus("]",symbol,q"[", povUtil.auctionStates.READY_TO_TRADE);


]");
		}

		BookManipulators bookManipulators;
		uint totalTradedQuantity = -1;
		real totalTradedCurrency = -1;
		Trade[] realTrades;
		// book generation constants
		immutable uint minLevels              = 5;
		immutable uint maxOrdersPerPriceLevel = 10;
		/** simulate orders based on trades */
		this(string symbol) {
			LocalDExchange exchange = new LocalDExchange();
			bookManipulators = new BookManipulators(exchange, 0u);
			super(exchange, 0u, "TrdSym");
			this.symbol = symbol;

		}

		ToAlgoNodeExchangeEventsReplayer generatePOVReplayCode(ETradeSide side, uint wantedQuantity, real targetParticipation, real minParticipation, real maxParticipation) {
			this.side = side;
			// load the strategy production real data
			uint firstOrderId = 100001u;
			uint orderId      = firstOrderId;
			realTrades = load(symbol, "POV");
			totalTradedQuantity = getTotalTradedQuantity(cast(immutable)realTrades);
			totalTradedCurrency = totalTradedQuantity * getAveragePrice(cast(immutable)realTrades);
			dumpPOVTestOpeningCode(wantedQuantity, targetParticipation, minParticipation, maxParticipation);
			// simulate the exchange & exchange session events
			foreach (ref realTrade; realTrades) {
				// for every real trade we want to replay:
				this.realTrade = realTrade;
				uint quantity = bookManipulators.checkExecutability(realTrade.price, &aggressorSide);	// determines the aggressor side which would require the lesser interventions on the current book
				bookManipulators.assureExecutability(aggressorSide, realTrade.price, realTrade.qty);	// guarantee we may aggress at least wanted quantity at the exact price point
				bookManipulators.fillBook(realTrade.price, minLevels*2, minLevels*2,
										  maxOrdersPerPriceLevel, realTrade.qty);						// fill the book randomly, leaving no empty price levels
				// at this point, we have a realistic book able to perform the desired trade when we add an order to the aggressor side
				addOrder(aggressorSide, orderId++, realTrade.price, realTrade.qty);						// add the order to make the desired trade
			}

			writeln(q"[
				console.log("\n\nPré-análise dos dados reais:");
				console.log(String.raw`]");analyzeForData(symbol, "POV");writeln(q"[`);
				console.log("\tDExchange Regenerated events:");
				console.log("\t\tAttacks: BIDS=]",bidAttacks,q"[, ASKS=]",askAttacks,q"[");
				//console.log("\t\tOrdens: ]",orderId-firstOrderId,q"[");	não funciona pois não levamos em conta as ordens dos BookManipulators... um refactoring na DExchange seria necessário para ela gerar um id de ordens...
				console.log("\t\tBook events: ]",dexchangeBookEvents,q"[");
				console.log("\tEstatísticas da execução da estratégia:");
				console.log("\t\tPrice Books: ]",algoNodePriceBookEvents,q"[");
				posTest(511);
					]");

			// test closing code
			writeln("\n\n\t}\n\n");

			return this;
		}
	}

	// analyze and generate the algo node replay test code for the following POV executions
	new ToAlgoNodeExchangeEventsReplayer("BBAS3").generatePOVReplayCode(ETradeSide.SELL, 25000,   0.15, 0.01, 0.47);
	new ToAlgoNodeExchangeEventsReplayer("PETR4").generatePOVReplayCode(ETradeSide.SELL, 1000000, 0.15, 0.14, 0.16);
	new ToAlgoNodeExchangeEventsReplayer("GGBR4").generatePOVReplayCode(ETradeSide.SELL, 450000,  0.15, 0.14, 0.16);
	new ToAlgoNodeExchangeEventsReplayer("CVCB3").generatePOVReplayCode(ETradeSide.SELL, 129700,  0.15, 0.14, 0.16);

    return 0;
}
