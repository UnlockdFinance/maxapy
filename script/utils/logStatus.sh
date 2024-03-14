#!/bin/bash
source .env

# 1.- Share price
sharePrice=$(cast call $VAULT "sharePrice()(uint256)")

# 2.- [4eStrategy] estimatedTotalAssets
estimatedTotalAssets=$(cast call $YEARN_STRATEGY "estimatedTotalAssets()(uint256)")

# 2.5.- [4eStrategy] getStrategyTotalDebt
getStrategyTotalDebt=$(cast call $VAULT "getStrategyTotalDebt(address)(uint256)" $YEARN_STRATEGY)

# 3.- [Vault] totalAssets
totalAssets=$(cast call $VAULT "totalAssets()(uint256)")

# 3.5.- [Vault] totalAccountedAssets
totalAccountedAssets=$(cast call $VAULT "totalAccountedAssets()(uint256)")

# 4.- [Vault] balanceOf(user)
balanceUser=$(cast call $VAULT "balanceOf(address)(uint256)" $DEPLOYER_ADDRESS)

# 5.- [Vault] convertToAssets(#4: shares_user)
convertToAssets=$(cast call $VAULT "convertToAssets(uint256)(uint256)" $balanceUser)

# 6.- [Vault] previewRedeem(#4: shares_user)
previewRedeem=$(cast call $VAULT "previewRedeem(uint256)(uint256)" $balanceUser)

echo "[VAULT] sharePrice:" $sharePrice
echo "[YSTRAT] Total Assets: (rewards included)" $estimatedTotalAssets
echo "[YSTRAT] Principal:" $getStrategyTotalDebt
echo "[VAULT] totalAssets (rewards included):" $totalAssets
echo "[VAULT] totalAccountedAssets:" $totalAccountedAssets
echo "[VAULT] balanceOf(user) (shares):" $balanceUser
echo "[VAULT] convertToAssets:" $convertToAssets
echo "[VAULT] previewRedeem:" $previewRedeem
