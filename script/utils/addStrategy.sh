#!/bin/bash
if [ $# -ne 2 ]; then
	echo "Usage: ./addStrategy.sh <strategy> <new_allocation>"
	exit 1
fi

source .env

emergency=$(cast send $1 --private-key $STRATEGY_ADMIN_PRIVATE_KEY "setEmergencyExit(uint256)()" 1)
echo "Removed EmergencyExit for $1"

updateStrategyData=$(./script/utils/updateStrategyData.sh $1 $2)
echo "Setted allocation: [$2] for $1"
exit 0
