# AlgoTradingStrategyProtyping

This project is my first try with the very fine, powerful, flexible and extremely well documented **D language** (dlang), a new acquitance that has raised to become my favorite prototyping language among all others -- Python, Javascript, Lua... you name it. C++, Java, C#, Python, Node and similar languages algo trading programmers won't have issues toying with D on this project.

This tool consists of:

  1. An algo server on which one will develop their own strategies (there are some defaut strategies useful to build the market);
  2. A real (yet simple, but very flexible) memory based Exchange -- called the `DExchange` (should it be moved to it's own project one day?);
  3. A KPI analyser (here goes the main reason for this project: the tool to measure the effectiveness of the strategy).

Once your algorithm is tuned to perfection, go on and reimplement it on your favorite platform to go for real world trades -- if you are a pro, consider the powerful and complete solution at [OgreRobot.com](https://OgreRobot.com/), responsible for this project: it is done in `C++` and, as you will learn, your `D` compiled code may be integrated into it without revealing any source code.

If you are a home trader and use MetaTrader, Zorro or a similar tool, be aware that this tool offers a more realistic environment and it is certainly worth testing it here as well as backtesting it elsewhere (if you really believe in backtests for trading).

## Clarification about Trading Strategies

Often, new developers confuse some concepts which, I believe, are very important to be distinguished from one another:

  1. Decision Strategies:
     * these are opportunistic strategies (where the intention is not to own the security) and are, most of the time, the prefered ones to be developed by robot traders & quants. These strategies should decide what to buy/sell, when to do that and at which price point. We are talking about day trading here, with custody periods counted in seconds or minutes. Some of the KPIs of interest here are: `VWAP of the buying phase` and `VWAP of the selling phase` -- a successfull algorithm will have the later greater than the former.

  2. Execution Strategies:
     * these strategies are useful to assist a human trader representing parties that have or had the intention to own the security -- they are most useful when dealing with big quantities, so... usually a financial found. The human is behind the decision and tell the algorithm what to buy, when and, some times, by up to how much -- the strategy should, then, execute the intention wasting as little money as possible (if you have a very successful strategy, some execution profit may even take place). The problem these strategies solve is related to the price & offer/demand interference that negotiating big quantities bring: the objective, however, is not "do not interfere on the market", but rather "do not let any other party realize I'm trying to buy or sell a big quantity, since they may benefit from it at my expense". This inerent drop in the VWAP of the execution is also called "execution cost" or "implementation shortfall" and the objective of an Execution Strategy, again, is to minimize it. The most important KPIs to measure the effectiveness are: `VWAP of the strategy trades` and `VWAP of the market trades (without the trades done by the strategy)`. If the former is less favorable than the later, your strategy should be improved -- by "less favorable" I mean: if you are buying, the former should not be greater than the later; if you are selling, it should not be lesser.

  3. Hybrid:
     * These are the most powerful strategies, usually resorting to some kind of AI but, most of times, having the knowledge and experience of senior human traders coded in the form of an algorithm. This is the intent of this prototyping tool: to give experienced traders a way to code their processes, test it in a real exchange with realistic parties (in opposition to backtesting, which do not offer a real exchange nor realistic parties), measure the success using the available KPIs and repeat the process as many times as you want. Later, when you go for the real thing, consider reaching us at [OgreRobot.com](https://OgreRobot.com/) for a partnership: by using `D` you will realize that your algorithm may be integrated on our platform (done in `C++`) without the need to show us your source code.

Note about **High Frequency Trading** (HFT): since we are dealing with algorithms, everything might be considered **HFT**. On the other hand, there are certain strategies that will only succeed if they are the fastest ones -- like `OportunisticMarketMaker` and the several arbitrage variations. For further clarifications, see (the blog post)[http://.].

## The Market Data

Since we use a real Exchange to prototype new strategies, a source of Market Data is needed. You have two options:
  - Real trades driven Market Data:
     * If you have a set of real market trade events, our `BookManipulators` is able to generate order events (additions, editions, cancellations) that would lead to these trades, using several different methods. Once a market trade happens, your strategy may run and generate as many other trades as feasible with the current book. Later, the next real trade will be taken into account and the book, again, appropriatedly populated. This approach is more in tune with the backtesting performed by Metatrader and Zorro and, in my opinion, is not enough to validade a real world strategy;
  - Real Market Data generated by real(ish) trading parties:
     * Now, with this method, you'll validade your algorithm in a real (maybe just realistic?) environment. It works by you editing the `config/Parties.d` module and picking up as many parties as you want, each of them having a budget, an initial security quantity (with a given initial set of KPIs), an intention (buy, sell or profit in day trade, short term or long term) and one of the strategies listed below:

Human parties (they simulate human traders placing manual orders):

  1. HumanInformedTrader
  2. HumanSpeculator
  3. HumanDayTraderSpeculator

Market manipulation strategies -- these have the intention to maintain securities at certain price boundaries, enhance their liquidity or, sometimes, by using some hidden (outlaw or not) procedures, try to mislead algorithms and/or humans:
  4. MarketMakerRobot -- usually paid to garantee a security liquidity following official rules (don't confuse it with `OpportunisticMarketMaker`, whose intention is to profit).
  5. ((the one that keeps the security at a boundary))
  6. ArbitrageRobot -- paid to guarantee related securities remain with related prices

Standard execution algo trading strategies -- here you will find, for free, only the naive implementations. If you are an algo trading company and your strategies look like these / can't perform at least like these, be worried; if you want the ones optimized for the best execution possible, visit [OgreRobot.com](https://OgreRobot.com/).

  7. NaivePOV (the professional [OgreRobot.com](https://OgreRobot.com/) ones are `AntecipativePOV`, `OptimizedForAggressionPOV` and `OgrePOV` -- the hibrid one)
  8. NaiveVWAP ([OgreRobot.com](https://OgreRobot.com/)'s version don't just use a simple average... it uses also bids/asks attacks patterns and is called `OgreVWAP`)
  9. NaiveTWAP (TWAP is always naive... don't use it professionally since you'll be giving money to others)
  11. NaiveSniper (NaiveSniper is always aggressive; `OgreSniper` is also aggressive, but is able to attack based on market patterns which yelds better executions than the naive version)
  13. NaiveIceberg (similar to NaiveSniper, but place orders to be aggressed; `OgreIceberg` is further optimized for aggressions, yelding better KPIs)
  12. NaivePegged
  13. NaiveConditional
  14. NaiveArbitrage
  15. NaiveFRAArbitrage
  16. NaiveIndexRebalancing
  17. NaiveDeltaNeutral
  18. NaiveMeanReversion
  19. NaiveSpread ()
  20. NaiveConditional (execute simple orders or algorithmic trading strategies based on triggers -- `OgreConditional` accepts also complex Lua scripts)

Opportunistic:

  20. OpportunisticMarketMaker
  21. NaiveTrendFollower

Important note: This project does not count with a `MicroMarketOrderOptimization` layer, designed to improve the execution even further by taking measures to benefit / not be prejudicted by certain order addition/deletion/edition and specific book patterns -- only [OgreRobot.com](https://OgreRobot.com/) has that. Nonetheless, this should not affect your algorithms prototyped here, since no `trading_strategy` in this project will be using any `MicroMarketOptimization`.

## The development process

One might find the following scripts useful to develop their algo trading strategies using this tool, since they benefit from one of the D compiler's most notable feature: its speed.

With these scripts, just save your code and watch, in less than 1 second, the compilation and execution happenning. Isn't this cool when prototyping?

### for DExchange development with auto build & testing, use:

```
d="DExchange"; FLAGS="-release -O -mcpu=native -m64 -inline -boundscheck=off"; _FLAGS="-boundscheck=on -check=on"; while sleep 1; do for f in *.d; do if [ "$f" -nt "$d" ]; then echo -en "`date`: COMPILING..."; dmd $FLAGS -lowmem -of="$d" AbstractDExchange.d AbstractDExchangeSession.d DExchange.d LocalDExchange.d LocalDExchangeSession.d TestUtils.d Types.d BookManipulators.d AlgoTradingStrategyPrototyping.d && echo -en "\n`date`: TESTING:  `ls -l "$d" | sed 's|.* \([0-9][0-9][0-9][0-9]*.*\)|\1|'`\n" && ./"$d" || echo -en '\n\n\n\n\n\n'; touch "$d"; rm -f "$d".obj; fi; done; done
```

### for AlgoTradingStrategyPrototyping development with auto building:

```
d="AlgoTradingStrategyPrototyping"; FLAGS="-release -O -mcpu=native -m64 -inline -boundscheck=off"; _FLAGS="-boundscheck=on -check=on"; while sleep 1; do for f in *.d; do if [ "$f" -nt "$d" ]; then echo -en "`date`: COMPILING..."; dmd $FLAGS -lowmem -of="$d" AbstractDExchange.d AbstractDExchangeSession.d DExchange.d LocalDExchange.d LocalDExchangeSession.d TestUtils.d Types.d BookManipulators.d AlgoTradingStrategyPrototyping.d && echo -en "\n`date`: TESTING:  `ls -l "$d" | sed 's|.* \([0-9][0-9][0-9][0-9]*.*\)|\1|'`\n" && ./"$d" || echo -en '\n\n\n\n\n\n'; touch "$d"; rm -f "$d".obj; fi; done; done
```
