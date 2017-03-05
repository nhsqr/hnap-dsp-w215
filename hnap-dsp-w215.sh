#!/bin/bash
#modify next two line for your DSP-W215
IP="192.168.1.70"
PIN="777260"
#do not modify after this line if you don't know what you are doing

function usage {
	echo -e "\nUsage: $(basename $0) [OPTION]"
	echo -e "\nOPTION:"
	echo -e "\t--getstate\t\t- Returns the state of the device ON or OFF"
	echo -e "\t--getpower\t\t- Returns the current power consumption"
	echo -e "\t--setstate on|off\t- Turns the device ON or OFF"
}

function hash_hmac {
  data="$1"
  key="$2"
  echo -n "$data" | openssl dgst "-md5" -hmac "$key" -binary | xxd -ps -u
}

contentType="Content-Type: text/xml; charset=utf-8"
soapLogin="SOAPAction: \"http://purenetworks.com/HNAP1/Login\""

#Get Login data
ret=`curl -s -X POST -H "$contentType" -H "$soapLogin" --data-binary @data.xml http://$IP/HNAP1`

function getResult {
  opt=`echo -n "$ret" | grep -Po "(?<=<$1>).*(?=</$1>)"`
  echo -n "$opt"
}

challenge=`getResult Challenge`
cookie="Cookie: uid=`getResult Cookie`"
publickey="`getResult PublicKey`$PIN"
privatekey=`hash_hmac "$challenge" "$publickey"`
password=`hash_hmac "$challenge" "$privatekey"`
timestamp=`date +%s`
auth_str="$timestamp\"http://purenetworks.com/HNAP1/Login\""
auth=`hash_hmac "$auth_str" "$privatekey"`
hnap_auth="HNAP_AUTH: $auth $timestamp"

head="<?xml version=\"1.0\" encoding=\"utf-8\"?><soap:Envelope xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\"><soap:Body>"
end="</soap:Body></soap:Envelope>"

message="<Login xmlns=\"http://purenetworks.com/HNAP1/\"><Action>login</Action><Username>admin</Username><LoginPassword>$password</LoginPassword><Captcha/></Login>"

login="$head$message$end"

#Get Login Result
ret=`curl -s -X POST -H "$contentType" -H "$soapLogin" -H "$hnap_auth" -H "$cookie" --data-binary "$login" http://$IP/HNAP1`

#Next line is for debug purposes only
#echo -e "Login: `getResult LoginResult`" #\tAuthStr=$auth_str\tHNAP=$hnap_auth"


case "$1" in
--getstate )
	#Next 2 rows to modify query
	method="GetSocketSettings"
	message="<$method xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>1</ModuleID></$method>"

	#Do not modify after this line
	soapAction="SOAPAction: \"http://purenetworks.com/HNAP1/$method\""
	authStr="$timestamp\"http://purenetworks.com/HNAP1/$method\""
	auth=`hash_hmac "$authStr" "$privatekey"`
	hnap_auth="HNAP_AUTH: $auth $timestamp"
	data="$head$message$end"

	#Get Device state from GetSocketSettings
	ret=`curl -s -X POST -H "$contentType" -H "$soapAction" -H "$hnap_auth" -H "$cookie" --data-binary "$data" http://$IP/HNAP1`
	#echo -e "Timestamp=$timestamp\tSOAPAction=$soapAction\tAuthStr=$authStr\tAUTH=$auth\tHNAP=$hnap_auth\tRET = $ret" #This line is for debug purpose

	state=`getResult OPStatus`
	if [ "$state" = "false" ]
	then
		echo "State is OFF"
	elif [ "$state" = "true" ]
	then
		echo "State is ON"
	else
		echo "State is UNKNOWN"
	fi
	;;
--setstate )
        #Next 3 rows to modify query
	case "$2" in
	"on" )
		state="true"
		;;
	"off" )
		state="false"
		;;
	* )
		echo "You need to provide STATE parameter \"on\" or \"off\""
		exit 0
		;;
	esac
 	#Next 2 rows to modify query
	method="SetSocketSettings"
	message="<$method xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>1</ModuleID><NickName>Socket 1</NickName><Description>Socket 1</Description><OPStatus>$state</OPStatus><Controller>1</Controller></$method>"

        #Do not modify after this line
	soapAction="SOAPAction: \"http://purenetworks.com/HNAP1/$method\""
        authStr="$timestamp\"http://purenetworks.com/HNAP1/$method\""
        auth=`hash_hmac "$authStr" "$privatekey"`
        hnap_auth="HNAP_AUTH: $auth $timestamp"
        data="$head$message$end"

        #Get Device state from GetSocketSettings
        ret=`curl -s -X POST -H "$contentType" -H "$soapAction" -H "$hnap_auth" -H "$cookie" --data-binary "$data" http://$IP/HNAP1`
        #echo -e "Timestamp=$timestamp\tSOAPAction=$soapAction\tAuthStr=$authStr\tAUTH=$auth\tHNAP=$hnap_auth\tRET = $ret\tMessage=$message" #This line is for debug purpose
	/bin/bash $0 --getstate
	;;
--getpower )
        #Next 2 rows to modify query
	method="GetCurrentPowerConsumption"
        message="<$method xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>2</ModuleID></$method>"

	#Do not modify after this line
        soapAction="SOAPAction: \"http://purenetworks.com/HNAP1/$method\""
        authStr="$timestamp\"http://purenetworks.com/HNAP1/$method\""
        auth=`hash_hmac "$authStr" "$privatekey"`
        hnap_auth="HNAP_AUTH: $auth $timestamp"
        data="$head$message$end"

        #Get Device state from GetSocketSettings
        ret=`curl -s -X POST -H "$contentType" -H "$soapAction" -H "$hnap_auth" -H "$cookie" --data-binary "$data" http://$IP/HNAP1`
        #echo -e "Timestamp=$timestamp\tSOAPAction=$soapAction\tAuthStr=$authStr\tAUTH=$auth\tHNAP=$hnap_auth\tRET = $ret" #This line is for debug purpose

        power=`getResult CurrentConsumption`
        echo "Power: $power W"
	;;
* )
	usage
	;;
esac
