#!/bin/bash

if [ $# -ne 0 ]; then
	echo "Usage: ./setupProtocol"
	exit 1
fi

source .env
echo "Getting 100 WETH and depositing..."
./script/utils/getWethAndDeposit.sh 100000000000000000000  
./script/utils/harvestAll.sh
./script/utils/logStatus.sh
