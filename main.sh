#!/bin/bash

# env vars should be set by a caller (for example cron):
# mqtt_host
# email
# password
#
# Dependencies: mosquitto_sub timeout jq
#

cd $(dirname $(realpath $0))

function addToBasketIfLowerThen() {
	name=$1
	limit=$2
	pieces=$(timeout 2 mosquitto_sub -h $mqtt_host -t scale/$name-scale/data -C 1 | jq '.pieces')

	if [ -z $pieces ]; then
		echo "Failed to get data for $name"
		return
	fi

	if [ $pieces -lt $limit ]; then
		echo "$name is low($pieces), adding to the basket."
		./barbora_add_item.sh "$name"
	else
		echo "$name is plenty($pieces) more then a limit($limit) no need to do anything."
	fi
}

# =======================
# list of items to automatically order with a minimum ammount to maintain

addToBasketIfLowerThen shitpaper 15
addToBasketIfLowerThen beer 12


