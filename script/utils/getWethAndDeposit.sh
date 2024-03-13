#!/bin/bash
if [ $# -ne 1 ]; then
    echo "Usage: ./getWETH.sh <wei_amount>"
    exit 1
fi

source .env
amount=$1

# 1.- Deposit WETH to the contract
cast send $WETH --private-key $DEPLOYER_PRIVATE_KEY "deposit()" --value $amount
echo "WETH Balance of Deployer:" $(cast call $WETH "balanceOf(address)(uint256)" $DEPLOYER_ADDRESS)

# 2.- Approve in WETH contract the maxapyvault
cast send $WETH --private-key $DEPLOYER_PRIVATE_KEY "approve(address,uint256)" $VAULT $amount

# 3.- Deposit WETH to the vault
cast send $VAULT --private-key $DEPLOYER_PRIVATE_KEY "deposit(uint256,address)" $amount $DEPLOYER_ADDRESS

# 4.- Check the balance of the vault
echo "Vault balance of deployer:" $(cast call $VAULT "balanceOf(address)(uint256)" $DEPLOYER_ADDRESS)
