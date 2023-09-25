#!/bin/bash

# env vars should be set by a caller (for example cron):
# mqtt_host
# email
# password
#
# Dependencies: mosquitto_sub timeout jq
#

cd $(dirname $(realpath $0))

function addToBasketIfLowerThenLegacy() {
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

function addToBasketIfLowerThen() {
	name=$1
	target=$2
	pieces=$(timeout 2 mosquitto_sub -h $mqtt_host -t inventory/$name)
	pieces="$(printf "%.0f" "$pieces")"

	if [ -z $pieces ]; then
		echo "Failed to get data for $name"
		return
	fi

	if [ $pieces -lt $target ]; then
		echo "$name is low($pieces), adding to the basket."
		./barbora_add_item.sh "$name" "$((target-pieces))"
	else
		echo "$name is plenty($pieces) more then a target($target) no need to do anything."
	fi
}


# =======================
# list of items to automatically order with a minimum ammount to maintain

addToBasketIfLowerThenLegacy shitpaper 17
addToBasketIfLowerThenLegacy beer 12

addToBasketIfLowerThen napkins 5
addToBasketIfLowerThen cotton-buds 4
addToBasketIfLowerThen cotton-pads 3

