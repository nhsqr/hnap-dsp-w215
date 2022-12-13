#!/bin/bash
#modify next two line for your DSP-W215
IP="Enter IP address of the device here"
PIN="Enter PIN number of the device here"
#do not modify after this line if you don't know what you are doing
contentType="Content-Type: text/xml; charset=utf-8"
soapLogin="SOAPAction: \"http://purenetworks.com/HNAP1/Login\""
#Get Login data
xmlLoginData=`curl -s -X POST -H "$contentType" -H "$soapLogin" --data-binary @$(dirname $0)/data.xml http://$IP/HNAP1`

function usage {
	echo -e "\nUsage: $(basename $0) <options>"
	echo -e "\n<options> are:"
	echo -e "  --state\t   - Get state of the device"
	echo -e "  --state [on|off] - Set state of the device ON or OFF"
	echo -e "  --power\t   - Current power consumption"
	echo -e "  --temp\t   - Current temperature of the device"
	echo -e "  --total\t   - Total consumption for current month\n"
}

function hash_hmac {
	data="$1"
	key="$2"
	echo -n "$data" | openssl dgst "-md5" -hmac "$key" -binary | xxd -ps -u
}

#getValueFor Variable FromXMLresult
function getValueFor {
	echo -n "$2" | grep -Po "(?<=<$1>).*(?=</$1>)"
}

challenge=`getValueFor Challenge "$xmlLoginData"`
cookie="Cookie: uid=`getValueFor Cookie "$xmlLoginData"`"
publickey="`getValueFor PublicKey "$xmlLoginData"`$PIN"
privatekey=`hash_hmac "$challenge" "$publickey"`
password=`hash_hmac "$challenge" "$privatekey"`
timestamp=`date +%s`
auth_str="$timestamp\"http://purenetworks.com/HNAP1/Login\""
auth=`hash_hmac "$auth_str" "$privatekey"`
hnap_auth="HNAP_AUTH: $auth $timestamp"

head="<?xml version=\"1.0\" encoding=\"utf-8\"?><soap:Envelope xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\"><soap:Body>"
message="<Login xmlns=\"http://purenetworks.com/HNAP1/\"><Action>login</Action><Username>admin</Username><LoginPassword>$password</LoginPassword><Captcha/></Login>"
end="</soap:Body></soap:Envelope>"
login="$head$message$end"

#Get Login Result
xmlLogin=`curl -s -X POST -H "$contentType" -H "$soapLogin" -H "$hnap_auth" -H "$cookie" --data-binary "$login" http://$IP/HNAP1`
loginResult=`getValueFor LoginResult "$xmlLogin"`
if [ "$loginResult" != "success" ]
	then
		echo $loginResult
		exit 0
fi

function getSOAPfor {
	soapAction="SOAPAction: \"http://purenetworks.com/HNAP1/$1\""
	authStr="$timestamp\"http://purenetworks.com/HNAP1/$1\""
	auth=`hash_hmac "$authStr" "$privatekey"`
	hnap_auth="HNAP_AUTH: $auth $timestamp"
	data="$head$message$end"
	#Get result from message in xml format
	curl -s -X POST -H "$contentType" -H "$soapAction" -H "$hnap_auth" -H "$cookie" --data-binary "$data" http://$IP/HNAP1
}

function getSocketState {
	method="GetSocketSettings"
	message="<$method xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>1</ModuleID></$method>"
	xmlState=`getSOAPfor $method`
	state=`getValueFor OPStatus "$xmlState"`
	if [ "$state" = "false" ]; then
		echo "State is OFF"
	elif [ "$state" = "true" ]; then
		echo "State is ON"
	else
		echo "Error: State is UNKNOWN"
	fi
	exit 0
}

function setSocketState {
	[ $1 == "on" ] && state="true" || state="false"
	method="GetSocketSettings"
	message="<$method xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>1</ModuleID></$method>"
	xmlState=`getSOAPfor $method`
	nickname=`getValueFor NickName "$xmlState"`
	description=`getValueFor Description "$xmlState"`
	method="SetSocketSettings"
	message="<$method xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>1</ModuleID><NickName>$nickname</NickName><Description>$description</Description><OPStatus>$state</OPStatus></$method>"
	xmlResult=`getSOAPfor $method`
	echo "Set state result: `getValueFor SetSocketSettingsResult "$xmlResult"`"
}

function power {
	method="GetCurrentPowerConsumption"
	message="<$method xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>2</ModuleID></$method>"
	xmlConsumption=`getSOAPfor $method`
	power=`getValueFor CurrentConsumption "$xmlConsumption"`
	echo "Power: $power W"
}

function temperature {
	method="GetCurrentTemperature"
	message="<$method xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>3</ModuleID></$method>"
	xmlTemp=`getSOAPfor $method`
	temp=`getValueFor CurrentTemperature "$xmlTemp"`
	echo "Temperature: $temp°C"
}

function totalConsumption {
	method="GetPMWarningThreshold"
	message="<$method xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>2</ModuleID></$method>"
	xmlTotal=`getSOAPfor $method`
	totalEnergy=`getValueFor TotalConsumption "$xmlTotal"`
	echo "Total: $totalEnergy kWh"
}

case "$1" in

	"--state" )
		case "$2" in
		"" )
			getSocketState
			;;
		"on"|"off" )
			setSocketState $2
			;;
		* )
			echo "You need to provide STATE parameter \"on\" or \"off\""
			exit 0
			;;
		esac
		;;
		
	"--power" )
		power
		;;
		
	"--temp" )
		temperature
		;;
		
	"--total" )
		totalConsumption
		;;
		
	* )
		usage
		;;
		
esac
