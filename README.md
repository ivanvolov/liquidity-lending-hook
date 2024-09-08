# YieldYoda

Maximizing Uniswap LP yields with Morpho lending protocols and Redstone oracles for improved capital and gas efficiency

## The problem it solves

It improves Uniswap LP performance and ehnance execution for traders.

## Challenges we ran into

It was so hard to do NoOp hooks, there are about 3 articles out there at most. Moreover, we need to do NoOp with a custom curve, even though it's similar to Uniswap, we still need to have a custom curve to get balances from Morpho. So it was like, let's create a Uniswap V3 in 2 days, but make it different;)

## Video Demo

https://www.loom.com/share/c2c9518a8a2342bd9451388857522431

## Applicable Tracks
RedStone Bounty track

## Brief description on how your project fits into RedStone: RedStone Bounty track

YieldYoda optimizes Uniswap V4 liquidity provision by leveraging Morpho lending protocols and Redstone oracles:

The idea is that we can deposit and hold all of the LP funds into lending protocols and execute withdrawals only on-demand for traders swaps. While also, we use RedStone oracles to predict upcoming trade flow based on the underlying asset price action. Based on the prediction - it withdraws optimal amount of funds from Morpho to Uniswap Hook. This way, by withdrawing funds strategically, YieldYoda reduces the number of withdrawal transactions significantly enhancing gas-efficiency.

After trades executed, any excess liquidity is quickly redeposited into Morpho to ensure maximum capital efficiency, keeping funds earning yield when not needed for trades.

## Team members & Wallets for Ticker recovery
- Ivan: 0x34595bF7Cd411608F526BAF9f7923bB1F1F63F89
- Yevhen



## Setting up

```
forge install
```

#### Testing

Test all project
```
make ta
```