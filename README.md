# AlgoTradingStrategyProtyping

This project is my first try with the very fine, powerful, flexible and extremely well documented **D language** (dlang), a new acquitance that has raised to become my favorite prototyping language among all others -- Python, Javascript, Lua... you name it. C++, Java, C#, Python, Node and similar languages algo trading programmers won't have issues toying with **D** on this project.

This tool consists of:

  1. An **algorithmic trading server** on which one will develop their own strategies (there are some defaut strategies useful to build the market);
  2. A real (yet simple, but very flexible) memory based **Exchange** -- called the **DExchange** (should it be moved to it's own project one day?);
  3. Some **KPI analysers** (here goes the main reason for this project: the tool to measure the effectiveness of the strategies and to compare different implementations & paradigmns).

Once your algorithm is tuned to perfection, go on and reimplement it on your favorite platform to go for real world trades -- if you are a pro, consider the powerful and complete solution at [OgreRobot.com](https://OgreRobot.com/), responsible for this project: it is done in **C++** and, as you will learn, your **D** compiled code may be integrated into it without revealing any source code.

If you are a home trader and use MetaTrader, Zorro or a similar tool, be aware that this tool offers a more realistic environment and it is certainly worth testing it here as well as backtesting it elsewhere (if you really believe in backtests for trading).

## Clarification about Trading Strategies

Often, new algo trading developers confuse some concepts which, I believe, are very important to be distinguished from one another:

  1. Decision Strategies:
     * these are opportunistic strategies (where the intention is not to own the security) and are, most of the time, the prefered ones to be developed by robot traders & quants. These strategies should decide **what** to buy/sell, **when** to do that and at **which price** point and should consider a limit of all **open positions** at a given time. We are talking about day trading here, with custody periods counted in seconds or minutes. Some of the KPIs of interest here are: `VWAP of the buying phase` and `VWAP of the selling phase` -- a successfull algorithm will have the later greater than the former.

  2. Execution Strategies:
     * these strategies are useful to assist a human trader representing parties that have or had the intention to own the security -- they are most useful when dealing with big quantities, so... usually a financial fund. The **human** is behind the decision and tell the algorithm **how many** of **what** to buy/sell, **when** and, some times, by **up to how much** -- the strategy should, then, execute the intention **wasting as little money as possible** (if you have a very successful strategy, some execution profit may even take place). The problem these strategies solve is related to the price & offer/demand interference that negotiating big quantities bring: the objective, however, is not "do not interfere on the market", but rather "do not let any other party realize I'm trying to buy or sell a big quantity, since they may benefit from it at my expense". This inerent drop in the VWAP of the execution is also called "execution cost" or "implementation shortfall" and the objective of an Execution Strategy, again, is to minimize it. The most important KPIs to measure the effectiveness are: `VWAP of the strategy trades` and `VWAP of the market trades (without the trades done by the strategy)`. If the former is less favorable than the later, your strategy should be improved -- by "less favorable" I mean: if you are buying, the former should not be greater than the later; if you are selling, it should not be lesser.

  3. Hybrid:
     * These are the most powerful strategies, usually resorting to some kind of AI but, most of times, having the **knowledge and experience of senior human traders coded in the form of an algorithm**. This is the intent of this prototyping tool: to give experienced traders a way to code their processes, test it in a real exchange with realistic parties (in opposition to backtesting, which do not offer a real exchange nor realistic parties), measure the success using the available KPIs and repeat the process as many times as they want. Later, when they (or you) go for the real thing, consider reaching us at [OgreRobot.com](https://OgreRobot.com/) for a partnership: by using **D** you will realize that your algorithm may be integrated on our platform (done in **C++**) without the need to show us your source code.

Note about **High Frequency Trading** (HFT): since we are dealing with algorithms, everything might be considered **HFT**. On the other hand, there are certain decision strategies that will only succeed if they are the fastest ones to react to market events -- like `OpportunisticMarketMaker` and the several opportunistic arbitrage variations. For further clarifications, see (the blog post)[http://.].

## The Market Data

Since we use a real Exchange to prototype new strategies, a source of Market Data is needed. You have two options:
  - Real Trades driving simulated Market Data:
     * If you have a set of real market trade events, the `BookManipulators` are able to simulate all the parties by generating order events (additions, editions, cancellations) that will lead to these trades, using several different methods (regarding the probrabilities of each aggression side and unexecutable order placement intensity). Once a market trade (or a book event) happens, your strategy may react and generate as many other orders or trades as feasible, all inserted on or matched against the current book. Later, the next real trade will be taken into account and the book, again, appropriatedly populated. This approach is more in tune with the backtesting performed by Metatrader and Zorro and, in my opinion, is not enough to validade a real world strategy, although they are easy to implement, fast to run and, with some tweaks, mey offer a reasonably rich set of scenarios for validation;
  - Real Market Data generated by real(ish) trading parties:
     * Now, with this method, you will validade your algorithm in a real (maybe just realistic?) environment. It works by you editing the `config/Parties.d` module and setting your simulation to have as many parties as you want, each of them having a budget, an initial security quantity (with a given initial set of KPIs), an intention function (buy, sell or profit in day trade, short term or long term) and one of the strategies listed below:

**Human parties** (they simulate human traders placing manual orders). They may place orders every 1 or so minutes and the `MarketStatistics` module is useful to tune `config/Parties.d` to achieve the desired human participation. The already implemented ones are:

  1. HumanInformedTrader -- their decision to trade is based on factors totally unknown to parties just watching the Exchange events, meaning they are using other information to decide -- random, in our case, or following an intention function;
  2. HumanTrader -- their decision is related to the security performance, with some delay (the `SecurityStatistics` module is responsible for tracking the information). Some parameters may be used to make it behave like a financial fund trader or a home day trader speculator: `infoDelaySeconds`, `averageCustodySeconds`, `longTermDesire`, `shortTermDesire`, ...;

**Continuous & autonomous market manipulation strategies** -- these have the intention to maintain securities at certain price boundaries, enhance their liquidity or, sometimes, by using some hidden (outlaw or not) procedures, try to mislead algorithms and/or humans:

  3. MarketMakerRobot -- these parties are usually paid to garantee a security liquidity following official rules (don't confuse it with `OpportunisticMarketMaker`, whose intention is just to profit and are, likely, not official).
  4. ((the one that keeps the security at a boundary))
  5. ArbitrageRobot -- paid to guarantee related securities respect related prices based on given symbolic algebraic expressions;
  6. PeggingRobot -- the same, but with dynamic models for currencies & options.
  

**Sporadic execution algo trading strategies** -- here you will find, for free, only the naive implementations of these trading tools. If you are an algo trading company and your strategies look like these / can't perform at least like these, be worried; if you want the ones optimized for the best execution possible, visit [OgreRobot.com](https://OgreRobot.com/).

  8. NaivePOV (the professional [OgreRobot.com](https://OgreRobot.com/) ones are `AntecipativePOV`, `OptimizedForAggressionPOV` and `OgrePOV` -- the hibrid one)
  9. NaiveVWAP ([OgreRobot.com](https://OgreRobot.com/)'s version don't just use a simple average... it uses also bids/asks attacks patterns and is called `OgreVWAP`)
  10. NaiveTWAP (TWAP is always naive... don't use it professionally since you'll be giving money to others)
  11. NaiveSniper (NaiveSniper is always aggressive; `OgreSniper` aggressive as well, but is able to attack based on market patterns which yelds better executions than the naive version)
  12. NaiveIceberg (similar to NaiveSniper, but place orders to be aggressed; `OgreIceberg` is further optimized for aggressions, yelding better KPIs)
  13. NaiveTrendFollower (orders, aggressive or not, are placed when the side of interest is under aggression, cancelled otherwise)
  14. NaiveDeltaNeutral
  15. NaiveMeanReversion
  16. NaiveArbitrage
  17. NaiveSpread ()
  18. NaiveConditional (execute simple orders or algorithmic trading strategies based on triggers -- `OgreConditional` accepts also complex Lua scripts)
  19. NaiveFRAArbitrage
  20. NaiveCashAndCarry

**Continuous & autonomous opportunistic strategies**:

  21. OpportunisticMarketMakerRobot
  22. OpportunisticTrendFollowerRobot
  23. IndexRebalancingRobot
  24. FRARobot
  25. CashAndCarryRobot
  
Important note: This project does not count on a `MicroMarketOrderOptimization` layer, designed to improve the execution even further by taking measures to benefit / not be prejudicted by certain order addition/deletion/edition and specific book patterns -- only [OgreRobot.com](https://OgreRobot.com/) has that. Nonetheless, this should not affect your algorithms prototyped here, since no `trading_strategy` in this project will be using any `MicroMarketOptimization`.

## The Infrastructure available to strategies

As you may have noticed from the above, simple execution strategies behave more like extended orders. When you look at:

  * **Sniper**,
  * **Iceberg**,
  * **TrendFollowing**,
  * and **MeanReversion**

you realize they are just a way to execute a very specific intention of buying or selling and, thus, we may view them as **ExtenderOrder**s, in opposition to **LimitOrder**s, with their bookability and executability parameters (**IOC**, **AOC**) and with their duration parameters (**GTC**), etc. Extended orders will also receive parameters to control their "bookability", execution, and duration:
  * visibleQuantity, 

Strategy logic classes may assign to receive the following standard events:
  1. Order Events:
     * Order Acception / Rejection
     * Order Execution and Cancelation Reports
  2. Market Data, for any security:
     * Trading Status*
     * Trades
     * Book, by prices
     * Book, by orders
     * Booked Order Events (addition, cancelation)

  \* **Trading Status** is marked with * to exemplify that the information is both available as an event and as a queriable Indicator. **Indicators** are continuously running, receiving events and contabilizing them for efficient queries. They are:

  1. **MarketDataIndicators** -- the indicators here are continuously running and contabilizing standard Market Data events for all securities:
     1. **TradingStatusIndicator** -- keeps track of the trading status (onAuction, Suspended, Trading, ...) for every security. Some queries:
        * getLastAuctionsPeriods(n)
        * getAverageAuctionDuration(nDays|nAuctions)
     2. **TradesIndicator** -- Keeps track of every trade of every security. Some available operations:
        * getVWAP(averagePeriod, slot)
        * getNumberOfTrades | getTradesLog (start, end periods)
        * getLastTradesLog(time | number of trades)
        * ... get bid/ask attacks, etc.
     3. **OrdersIndicator** -- Keeps track of every order (booked or immediately executed) for every security:
        * getCancellationRatio(period | number of orders)
        * getAggressiveOverBookedRatio(period)
        * ... IOCOverGTC, etc...
  2. **LocalExecutionStrategiesKPIs** -- 
  3. **LocalRobotsKPIs** -- 

  1. MarketDataIndicators
  2. LocalExecutionStrategiesKPIs
  3. LocalRobotsKPIs

## The development process

One might find the following scripts useful to develop their algo trading strategies using this tool, since they benefit from one of the D compiler's most notable feature: its speed.

With these scripts, just save your code and watch, in less than 1 second, the compilation and execution happenning. Isn't this cool when prototyping?

### for DExchange development with auto build & testing, use:

```
d="DExchange"; FLAGS="-release -O -mcpu=native -m64 -inline -boundscheck=off"; _FLAGS="-boundscheck=on -check=on"; while sleep 1; do for f in *.d; do if [ "$f" -nt "$d" ]; then echo -en "`date`: COMPILING..."; dmd $FLAGS -lowmem -unittest -main -of="$d" AbstractDExchange.d AbstractDExchangeSession.d DExchange.d LocalDExchange.d LocalDExchangeSession.d TestUtils.d Types.d BookManipulators.d && echo -en "\n`date`: TESTING:  `ls -l "$d" | sed 's|.* \([0-9][0-9][0-9][0-9]*.*\)|\1|'`\n" && ./"$d" || echo -en '\n\n\n\n\n\n'; touch "$d"; rm -f "$d".obj; fi; done; done
```

### for AlgoTradingStrategyPrototyping development with auto building:

```
d="AlgoTradingStrategyPrototyping"; FLAGS="-release -O -mcpu=native -m64 -inline -boundscheck=off"; _FLAGS="-boundscheck=on -check=on"; while sleep 1; do for f in *.d; do if [ "$f" -nt "$d" ]; then echo -en "`date`: COMPILING..."; dmd $FLAGS -lowmem -of="$d" AbstractDExchange.d AbstractDExchangeSession.d DExchange.d LocalDExchange.d LocalDExchangeSession.d TestUtils.d Types.d BookManipulators.d AlgoTradingStrategyPrototyping.d && echo -en "\n`date`: TESTING:  `ls -l "$d" | sed 's|.* \([0-9][0-9][0-9][0-9]*.*\)|\1|'`\n" && ./"$d" || echo -en '\n\n\n\n\n\n'; touch "$d"; rm -f "$d".obj; fi; done; done
```
