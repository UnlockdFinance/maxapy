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
## Run local fork 
Set the `.env` environment values and fetch them everytime you open a new terminal:
```
source .env
```
Run the local fork:
```
anvil --fork-url $RPC_MAINNET  --fork-block-number $FORK_BLOCK_NUMBER --accounts <number of test accounts to have available>
```
**Note:** It's recommended using one of the private keys provided by anvil for testing 

Run the deployment script in a new terminal:
```solidity 
forge script script/MaxApyV2.s.sol:DeploymentScript --fork-url http://localhost:8545 --etherscan-api-key $ETHERSCAN_API_KEY --broadcast -vvv
```

After that interact with the fork freely using `cast`, here some example of what you can do:
```
cast rpc anvil_impersonateAccount <address of user to impersonate>
```
For calling contract performing a transaction:
```
cast send <address of contract to interact with> \
--private-key <private key of sender> \
  <function signature as string> \
  arg1 \
  arg2 \
  ...
```
For calling contract view methods:
```
cast call <address of contract to interact with> \
  <function signature as string> \
  arg1 \
  arg2 \
  ...
```

```
cast gas-price     
```

```
cast storage <address of contract to read storage from>
```