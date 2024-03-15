#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Usage: ./removeStrategy.sh <strategy>"
	exit 1
fi

source .env

# Set allocation to 0%
update=$(./script/utils/updateStrategyData.sh $1 0)
echo "Allocation for $1 is now 0..."

# Harvest strategy
harvest=$(./script/utils/updateSharePrice.sh $1)
echo "Harvested $1..."

# Remove strategy
remove=$(cast send $VAULT --private-key $VAULT_ADMIN_PRIVATE_KEY "removeStrategy(address)()" $1)
echo "Removed strategy $1..."

echo "------------------------------------------------------"
echo "[WARNING] - Remember to DEACTIVATE strategy $1 from DB"
echo "------------------------------------------------------"

exit 0
