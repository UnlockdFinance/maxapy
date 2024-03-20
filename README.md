# MaxAPY · [![License](https://img.shields.io/badge/license-GPL-blue.svg)](LICENSE) [![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.19-orange)](https://docs.soliditylang.org/en/latest/)

MaxAPY is a yield farming **gas-optimized** and **capital-efficient** vault implemented in Solidity, designed to **optimize yield** through various strategies, and earn interest in ERC20 tokens. It relies on the safety of the battle-tested [Yearn's yVault](https://github.com/yearn/yearn-vaults/blob/efb47d8a84fcb13ceebd3ceb11b126b323bcc05d/contracts/Vault.vy) and the innovation of MaxAPY.

## Contracts
```ml
src
├─ base
    ├─ BaseVault — "Base abstract implementation of MaxAPYVault"
├─ helpers
    ├─ VaultTypes — "Contains data structures of the vault"
├─ interfaces  — "Interfaces of all the contracts involved in the protocol"
    ├─ IConvexBooster
    ├─ IConvexRewards
    ├─ IMaxApyVaultV2
    ├─ IStrategy
    ├─ IWETH
    ├─ IWrappedToken
    ├─ IYVault
    ├─ ICellar
    ├─ IConvexdETHFrxETHStrategy
    ├─ ICurve
    ├─ ISommelierStrategy  
    ├─ IUniswap
    ├─ IWrappedTokenGateway
    ├─ IYearnStrategy
    ├─ IStakingRewardsMulti
    ├─ IYVaultV3
├─ lib
    ├─ ERC20 — "Abstract ERC20 implementation"
    ├─ Initializable — "Base contract for proxy initialization"
    ├─ ReentrancyGuard — "Efficient Solidity & assembly version of ReentrancyGuard"
├─ strategies
    ├─ base
        ├─ BaseStrategy — "Base vault strategy implementation"
    ├─ mainnet — "Mainent chain strategies" 
        ├─ DAI — "DAI strategies" 
            ├─ yearn — "Strategies interacting with Yearn Finance"
                ├─YearnAjnaDAIStakingStrategy
        ├─ USDC — "USDC strategies" 
            ├─ sommelier — "Strategies interacting with Sommelier Finance"
                ├─SommelierTurboGHOStrategy
        ├─ WETH — "Wrapped Ether strategies" 
            ├─ convex — "Strategies interacting with Convex Finance"
                ├─ConvexdETHFrxETHStrategy 
            ├─ sommelier — "Stratgies interacting with Sommelier Finance"
                ├─SommelierMorphoEthMaximizerStrategy
                ├─SommelierStEthDepositTurboStEthStrategy
                ├─SommelierTurboStEthStrategy
                ├─SommelierTurboSwEthStrategy
                ├─SommelierTurboEzEthStrategy
                ├─SommelierTurboEthXStrategy
            ├─ yearn — "Strategies interacting with Yearn Finance"
                ├─YearnWETHStrategy
                ├─YearnAjnaWETHStakingStrategy
    ├─ polygon — "Polygon chain strategies" 
        ├─ USDC — "USDC strategies" 
            ├─ yearn — "Strategies interacting with Yearn Finance"
                ├─YearnMaticUSDCStakingStrategy
├─ MaxApyVaultV2 — "Yield farming vault"
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
