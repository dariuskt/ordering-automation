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
		echo "${FUNCNAME[1]} $1" >&2
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
		"https://apikey:SecretKey@barbora.lt/api/eshop/v1/user/login" \
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
		| jq --raw-output '[.slices[].products[] | select(.status == "active") | {id, status, comparative_unit_price, price}] | sort_by(.comparative_unit_price)[] | .id' \
		)"
	log "got $(echo "$items" | wc -l) items with cheapest id $(echo "$items" | head -n1)"
	echo "$items"
}

function getCartJson() {
	log "($1)"
	item_id=$1
	curl -sSL -X GET \
		--cookie "$cookies_file" \
		--cookie-jar "$cookies_file" \
		"https://barbora.lt" \
		| fgrep 'window.b_cart' \
		| grep -o "{.*}"
}

function isItemInCart() {
	log "($1)"
	local item_id=$1

	local items="$(getCartJson | jq --raw-output '.slices[].products[].id' )"

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

	if [ $(echo "$resp" | jq '.success') != "true" ]; then
		log "ERROR: failed to add item"
		log "Response from server: $resp"
	fi
}

# =================================


login "$email" "$password"

item=$(getTemplateItemsByName "$template_name" | head -n1)

if [ $(isItemInCart "$item") == "true" ] ; then
	echo "Nothing to do, item already in the cart"
else
	addItemToCart "$(echo "$item")" "$quantity"
fi

