#!/bin/bash
source .env
echo "Previous SP:" $(cast call $VAULT "sharePrice()(uint256)")
cast send $YEARN_STRATEGY --private-key $KEEPER1_PRIVATE_KEY "harvest(uint256,uint256,uint256,address)" 0 0 0 $VAULT
echo "Final SP:" $(cast call $VAULT "sharePrice()(uint256)")