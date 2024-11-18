#!/bin/bash

# this script adds one cheapest available item from specified template to the cart (barbora.lt)
# templates are configured in barbora.lt manually
#
# Dependencies: curl jq
#
# usage example to add one item
# email=my@e.mail password=myPassword ./barbora_add_item.sh myTemplateName
#
# usage example to add 4 items
# email=my@e.mail password=myPassword ./barbora_add_item.sh myTemplateName 4
#

: "${email:=my@e.mail}"
: "${password:=myPassword}"
template_name="${1:-myTemplate}"
quantity="${2:-1}"
unit="${3:-packs}"

# ====================================

debug=false
cookies_file=cookie


trap "exit 1" TERM
export TOP_PID=$$
function die() {
	echo "${FUNCNAME[1]} ERROR: $1" >&2
	kill -s TERM $TOP_PID
	exit 1
}
function log() {
	if $debug ; then
		echo ">> ${FUNCNAME[1]} $1" >&2
	fi
}



function login() {
	log "($1, ****)"
	local email="$1"
	local password="$2"
	# prepare region cookie
	echo "barbora.lt	FALSE	/	FALSE	0	region	barbora.lt" > $cookies_file

	# get the seesion cookie
	curl -sSL -X GET \
		--cookie "$cookies_file" \
		--cookie-jar "$cookies_file" \
		"https://barbora.lt" \
		>/dev/null

	# login
	curl -sSL -X POST \
		--cookie "$cookies_file" \
		--cookie-jar "$cookies_file" \
		-H "Content-Type: application/json" \
		-d "{'rememberMe':true,'email':'$email','password':'$password'}" \
		"https://apikey:SecretKey@barbora.lt/api/eshop/v1/userAuth/login" \
		>/dev/null

	if fgrep -q '.BRBAUTH' $cookies_file; then
		return 0
	else
		die "LOGIN FAILED"
	fi
}

function getTemplateIdByName() {
	log "($1)"
	local template_name=$1
	local template_id=$(curl -sSL -X GET \
		--cookie "$cookies_file" \
		--cookie-jar "$cookies_file" \
		"https://apikey:SecretKey@barbora.lt/api/eshop/v1/user/GetSavedBaskets?limit=50&offset=0" \
		| jq --raw-output '.SavedBaskets[] | select(.Name == "'$template_name'") | .Id' )


	if [ -z $template_id ]; then
		die "Cant find template $template_name"
	fi
	log "got id '$template_id' for template '$template_name'"
	echo $template_id
}

function getTemplateItemsByName() {
	log "($1)"
	local template_name="$1"

	local template_id="$(getTemplateIdByName "$template_name")"

	# returns only active itmes sorted by unit price, lowest first.
	local items="$(curl -sSL -X GET \
		--cookie "$cookies_file" \
		--cookie-jar "$cookies_file" \
		"https://apikey:SecretKey@barbora.lt/api/eshop/v1/cart/getsinglebasket?basketId=$template_id" \
		| jq --raw-output '[.slices[].products[] | {id, status, comparative_unit_price, price}] | sort_by(.comparative_unit_price)[] | .id' \
		)"
	log "got $(echo "$items" | wc -l) items"
	echo "$items"
}

function getActiveTemplateItemsByName() {
	log "($1)"
	local template_name="$1"

	local template_id="$(getTemplateIdByName "$template_name")"

	# returns only active itmes sorted by unit price, lowest first.
	local items="$(curl -sSL -X GET \
		--cookie "$cookies_file" \
		--cookie-jar "$cookies_file" \
		"https://apikey:SecretKey@barbora.lt/api/eshop/v1/cart/getsinglebasket?basketId=$template_id" \
		| jq --raw-output '[.slices[].products[] | select(.status == "active") | {id, status, comparative_unit_price, price}] | sort_by(.comparative_unit_price)[] | .id' \
		)"
	log "got $(echo "$items" | wc -l) active items with cheapest id $(echo "$items" | head -n1)"
	echo "$items"
}

function getItemPackSize() {
	log "($1 $2)"
	local item_id=$1
	local template_name="$2"

	local template_id="$(getTemplateIdByName "$template_name")"

	local pack_size="$(curl -sSL -X GET \
		--cookie "$cookies_file" \
		--cookie-jar "$cookies_file" \
		"https://apikey:SecretKey@barbora.lt/api/eshop/v1/cart/getsinglebasket?basketId=$template_id" \
		| jq --raw-output '[.slices[].products[] | select(.id == "'$item_id'") | {id, status, comparative_unit_price, price}] | sort_by(.comparative_unit_price)[] | (.price/.comparative_unit_price)+0.5|floor' \
		)"
	log "got pack size: $pack_size"
	echo "$pack_size"

}

function getCartJson() {
	log
	curl -sSL -X GET \
		--cookie "$cookies_file" \
		--cookie-jar "$cookies_file" \
		"https://apikey:SecretKey@barbora.lt/api/eshop/v1/cart"
}

function isItemInCart() {
	log "($1)"
	local item_id=$1

	local items="$(getCartJson | jq --raw-output '.cart.slices[].products[].id' )"

	echo "$items" | grep -q "^$item_id$" && echo true || echo false
}

function addItemToCart() {
	log "($1, $2)"
	local item_id=$1
	local quantity=${2:-1}
	local resp="$(curl -sSL -X POST \
		--cookie "$cookies_file" \
		--cookie-jar "$cookies_file" \
		-d "product_id=$item_id" \
		-d "quantity=$quantity" \
		-d "unit=0" \
		-d "web_url=https://barbora.lt" \
		"https://apikey:SecretKey@barbora.lt/api/eshop/v1/cart/item?returnCartInfo=false" \
		)"

	if [ "$(echo "$resp" | jq '.success')" = "true" ]; then
		return "$quantity"
	else
		log "ERROR: failed to add item"
		log "Response from server: $resp"
		return 0
	fi
}

function deleteItemFromCart() {
	log "($1)"
	local item_id=$1
	local resp="$(curl -sSL -X DELETE \
		--cookie "$cookies_file" \
		--cookie-jar "$cookies_file" \
		"https://apikey:SecretKey@barbora.lt/api/eshop/v1/cart/item?returnCartInfo=false&id=$item_id" \
		)"

	if [ $(echo "$resp" | jq '.success') != "true" ]; then
		log "ERROR: failed to delete item"
		log "Response from server: $resp"
	fi

}


# =================================


login "$email" "$password"

item=$(getActiveTemplateItemsByName "$template_name" | head -n1)
items=$(getTemplateItemsByName "$template_name")


if [ $(isItemInCart "$item") == "true" ] ; then
	deleteItemFromCart "$item"
else
	for i in $items ; do
		deleteItemFromCart "$i"
	done
fi

if [ "$unit" == "units" ] ; then
	pack_size="$(getItemPackSize $item $template_name)"
else
	pack_size=1
fi

if [ "$quantity" -lt "$pack_size" ] ; then
	echo "Nothing to do, pack($pack_size) too big for requested quantity($quantity)"
else
	addItemToCart "$(echo "$item")" "$((quantity/pack_size))"
	echo "Added $? packs of $template_name"
fi

