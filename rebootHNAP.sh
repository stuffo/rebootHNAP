#!/bin/bash 

# reboot HNAP compatible device 
# works eg. for Dlink DIR 880L
#
# by https://github.com/stuffo/
#

IP="192.168.0.1"    # your HNAP device IP
Username="Admin"    # admin user
PIN="password"      # PIN or password for authentication

# SOAP defaults
contentType="Content-Type: text/xml; charset=utf-8"
soapHead="<?xml version=\"1.0\" encoding=\"utf-8\"?>
    <soap:Envelope xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" 
                   xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" 
                   xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\">
    <soap:Body>"
soapTail="</soap:Body></soap:Envelope>"
soapUrl="http://purenetworks.com/HNAP1/"

set -e

function getResult {
    echo -n "$2" | grep -Po "(?<=<$1>).*(?=</$1>)"
}

function hash_hmac {
	data="$1"
	key="$2"
	echo -n "$data" | openssl dgst "-md5" -hmac "$key" -binary | xxd -ps -u
}

function hnap_auth {
	local method=$1
	local timestamp=$(date +%s)
	local auth_str="$timestamp\"$soapUrl$method\""
	local auth=$(hash_hmac "$auth_str" "$privatekey")
	echo "HNAP_AUTH: $auth $timestamp"
}

function soap_body {
	local method=$1
	local data=$2
	echo "<$method xmlns=\"$soapUrl\">$data</$method>"
}

function soap_call {
	local soapAction=$1
	local data=$2
	local auth=$3
	local authHeaders

	if [ "$auth" = "y" ] ; then
		authHeaders=('-H' "$(hnap_auth $soapAction)")
		authHeaders+=('-H' "$cookie")
	fi 

	curl -s -S -f --connect-timeout 3 -s -X POST -H "$contentType" \
		-H "SOAPAction: \"$soapUrl$soapAction\"" \
        "${authHeaders[@]}" --data-binary "$soapHead$(soap_body $soapAction $data)$soapTail" \
		http://$IP/HNAP1/ 
}

function soap_get_result {
    local method=$1
    local data=$2
    local auth=$3

    ret=$(soap_call $method $data $auth)
    getResult ${method}Result "$ret"
}

login_ret=$(soap_call Login "<Action>request</Action><Username>$Username</Username><LoginPassword>password</LoginPassword><Captcha/>")
echo "Challenge Request Result: $(getResult LoginResult "$login_ret")"

challenge=$(getResult Challenge "$login_ret")
cookie="Cookie: uid="$(getResult Cookie "$login_ret")
publickey=$(getResult PublicKey "$login_ret")$PIN
privatekey=$(hash_hmac "$challenge" "$publickey")
password=$(hash_hmac "$challenge" "$privatekey")

ret=$(soap_get_result Login "<Action>login</Action><Username>$Username</Username><LoginPassword>$password</LoginPassword><Captcha/>" y)
echo "Login Result: $ret"
if [ "$ret" != "success" ] ; then
    echo "Login Failed."
    exit 1
fi

#ret=$(soap_get_result Reboot "</empty>" y)
echo "Reboot Result: $ret"
if [ "$ret" == "REBOOT" ] ; then
    echo "Reboot success"
    exit 0
fi

