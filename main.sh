#!/bin/bash

# env vars should be set by a caller (for example cron):
# mqtt_host
# email
# password
#
# Dependencies: mosquitto_sub timeout
#

cd $(dirname $(realpath $0))

function addToBasketIfLowerThen() {
	name=$1
	target=$2
	unit=$3
	pieces=$(timeout 2 mosquitto_sub -h $mqtt_host -t inventory/$name)
	pieces="$(printf "%.0f" "$pieces")"

	if [ -z $pieces ]; then
		echo "Failed to get data for $name"
		return
	fi

	if [ $pieces -lt $target ]; then
		echo "$name is low($pieces/$target), adding to the basket."
		./barbora_add_item.sh "$name" "$((target-pieces))" "$unit"
	else
		echo "$name is plenty($pieces) more then a target($target) no need to do anything."
	fi
}


# =======================
# list of items to automatically order with a minimum ammount to maintain

addToBasketIfLowerThen shitpaper    24 units #24
addToBasketIfLowerThen beer         12 units

addToBasketIfLowerThen napkins       5 packs #6
addToBasketIfLowerThen cotton-buds   5 packs #6
addToBasketIfLowerThen cotton-pads   3 packs #4

