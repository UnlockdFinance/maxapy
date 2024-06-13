# MaxAPY · [![License](https://img.shields.io/badge/license-GPL-blue.svg)](LICENSE) [![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.19-orange)](https://docs.soliditylang.org/en/latest/)

MaxAPY is a yield farming **gas-optimized** and **capital-efficient** vault implemented in Solidity, designed to **optimize yield** through various strategies, and earn interest in ERC20 tokens. It relies on the safety of the battle-tested [Yearn's yVault](https://github.com/yearn/yearn-vaults/blob/efb47d8a84fcb13ceebd3ceb11b126b323bcc05d/contracts/Vault.vy) and the innovation of MaxAPY.

## Contracts

```ml
├── src
│   ├── helpers
│   │   └── VaultTypes.sol
│   ├── interfaces
│   │   ├── IBalancer.sol
│   │   ├── ICellar.sol
│   │   ├── IConvexBooster.sol
│   │   ├── IConvexdETHFrxETHStrategy.sol
│   │   ├── IConvexRewards.sol
│   │   ├── ICurve.sol
│   │   ├── IMaxApyRouter.sol
│   │   ├── IMaxApyVault.sol
│   │   ├── ISommelierStrategy.sol
│   │   ├── IStakingRewardsMulti.sol
│   │   ├── IStrategy.sol
│   │   ├── IUniswap.sol
│   │   ├── IWETH.sol
│   │   ├── IWrappedTokenGateway.sol
│   │   ├── IWrappedToken.sol
│   │   ├── IYearnStrategy.sol
│   │   ├── IYVault.sol
│   │   └── IYVaultV3.sol
│   ├── lib
│   │   ├── ERC20.sol
│   │   ├── Initializable.sol
│   │   ├── OracleLibrary.sol
│   │   └── ReentrancyGuard.sol
│   ├── MaxApyRouter.sol
│   ├── MaxApyVault.sol
│   └── strategies
│       ├── base
│       │   ├── BaseConvexStrategy.sol
│       │   ├── BaseSommelierStrategy.sol
│       │   ├── BaseStrategy.sol
│       │   ├── BaseYearnV2Strategy.sol
│       │   └── BaseYearnV3Strategy.sol
│       ├── mainnet
│       │   ├── DAI
│       │   │   └── yearn
│       │   │       ├── YearnAjnaDAIStakingStrategy.sol
│       │   │       └── YearnDAIStrategy.sol
│       │   ├── USDC
│       │   │   ├── convex
│       │   │   │   └── ConvexCrvUSDWethCollateral.sol
│       │   │   ├── sommelier
│       │   │   │   └── SommelierTurboGHOStrategy.sol
│       │   │   └── yearn
│       │   │       ├── YearnLUSDStrategy.sol
│       │   │       └── YearnUSDCStrategy.sol
│       │   ├── USDT
│       │   │   └── yearn
│       │   │       └── YearnUSDTStrategy.sol
│       │   └── WETH
│       │       ├── convex
│       │       │   └── ConvexdETHFrxETHStrategy.sol
│       │       ├── sommelier
│       │       │   ├── SommelierMorphoEthMaximizerStrategy.sol
│       │       │   ├── SommelierStEthDepositTurboStEthStrategy.sol
│       │       │   ├── SommelierTurboDivEthStrategy.sol
│       │       │   ├── SommelierTurboEEthV2Strategy.sol
│       │       │   ├── SommelierTurboEthXStrategy.sol
│       │       │   ├── SommelierTurboEzEthStrategy.sol
│       │       │   ├── SommelierTurboRsEthStrategy.sol
│       │       │   ├── SommelierTurboStEthStrategy.sol
│       │       │   └── SommelierTurboSwEthStrategy.sol
│       │       └── yearn
│       │           ├── YearnAjnaWETHStakingStrategy.sol
│       │           ├── YearnCompoundV3WETHLenderStrategy.sol
│       │           ├── YearnV3WETH2Strategy.sol
│       │           ├── YearnV3WETHStrategy.sol
│       │           └── YearnWETHStrategy.sol
│       └── polygon
│           ├── DAI
│           │   └── yearn
│           │       ├── YearnDAILenderStrategy.sol
│           │       └── YearnDAIStrategy.sol
│           ├── USDCe
│           │   └── yearn
│           │       ├── YearnAjnaUSDCStrategy.sol
│           │       ├── YearnCompoundUSDCeLenderStrategy.sol
│           │       ├── YearnMaticUSDCStakingStrategy.sol
│           │       ├── YearnUSDCeLenderStrategy.sol
│           │       └── YearnUSDCeStrategy.sol
│           └── USDT
│               └── yearn
│                   └── YearnUSDTStrategy.sol

```

## Install

```bash
git clone https://github.com/UnlockdFinance/maxapy-v2.git
```

## Compile

```
forge build
```

## Test

```
forge test
```
