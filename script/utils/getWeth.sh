#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Usage: ./getWeth <wei_amount>"
	exit 1;
fi

source .env
cast send $WETH --private-key $DEPLOYER_PRIVATE_KEY "deposit()" --value $1
echo "Wrapped $1 WETH for $DEPLOYER_ADDRESS"
exit 0
