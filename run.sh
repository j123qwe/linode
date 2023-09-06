#!/bin/bash

#Last Update: 2022-11-24

##Variables
_SCRIPTDIR=$(pwd)
_PID=$$
_PACKAGES="jq"

##Startup
mkdir -p ${_SCRIPTDIR}/tmp

##Functions
checkApps(){
for _PKG in ${_PACKAGES}; do
 dpkg -s ${_PKG} &> /dev/null
 if [ $? -eq 1 ]; then
  echo "${_PKG} is not installed. Exiting..."
  exit
 fi
done
}

checkVariables(){
if [ ! -e ${_SCRIPTDIR}/.variables ]; then
        echo "Variables file is missing. Please add create .variables file. Exiting..."
        exit
else
	source ${_SCRIPTDIR}/.variables
fi
}

checkSSH(){
if [ -e ${_KEYNAME} ]; then
        chmod 600 ${_KEYNAME} &> /dev/null
else
        echo "SSH file is missing (${_KEYNAME}). Exiting..."
        exit
fi
}

getImages(){
	curl --silent -H "Authorization: Bearer ${_TOKEN}" https://api.linode.com/v4/images | jq -r '.data[].id' | sort
}

getRegions(){
	curl --silent https://api.linode.com/v4/regions | jq -r '.data[] | .id + "," + .country' | sort
}

getTypes(){
	printf "ID,Label,vCPUs,Memory,Disk,Price\n"
	curl --silent https://api.linode.com/v4/linode/types | jq -r '.data[] | .id + "," + .label + "," + (.vcpus|tostring) + "," + (.memory|tostring) + "MB," + (.disk|tostring) + "MB,$" + (.price.hourly|tostring)'
}

listInstances(){
	printf "ID,Label,IPv4,IPv6,Status\n"
	curl --silent -H "Authorization: Bearer ${_TOKEN}" https://api.linode.com/v4/linode/instances | jq -r '.data[] | (.id|tostring) + "," + .label + "," + .ipv4[0] + "," + .ipv6 + "," + .status'
}

viewInstance(){
	listInstances
	read -r -p "Instance ID: " _ID
	curl --silent -H "Authorization: Bearer ${_TOKEN}" https://api.linode.com/v4/linode/instances/${_ID} | jq 
}

terminateInstance(){
	if [ ! -z ${1} ]; then
		_ID=${1}
        _INSTANCE=$(curl --silent -H "Authorization: Bearer ${_TOKEN}" https://api.linode.com/v4/linode/instances/${_ID} | jq -r '.label + "," + .ipv4[0]')
        _LABELX=$(echo ${_INSTANCE} | cut -d, -f1)
        _IP=$(echo ${_INSTANCE} | cut -d, -f2)
        deleteDNS
        curl --silent -H "Authorization: Bearer ${_TOKEN}" -X DELETE https://api.linode.com/v4/linode/instances/${_ID} > /dev/null
        printf "Instance ${_ID} deleted.\n"
	else
		listInstances
		read -r -p "Which image label? " _LABEL
        for _INSTANCE in $(listInstances | grep ${_LABEL}); do
            _ID=$(echo ${_INSTANCE} | cut -d, -f1)
            _LABELX=$(echo ${_INSTANCE} | cut -d, -f2)
            _IP=$(echo ${_INSTANCE} | cut -d, -f3)
			deleteDNS
            curl --silent -H "Authorization: Bearer ${_TOKEN}" -X DELETE https://api.linode.com/v4/linode/instances/${_ID} > /dev/null
            printf "Instance ${_LABELX} deleted.\n"
        done
	fi
}

checkDNS(){
	if [ -z ${_DOMAIN} ]; then
		echo "Domain is missing in .variables file. DNS records will not be updates."
		_UPDATE_DNS=0
	elif [ -z ${_DOMAINID} ]; then
        	echo "Domain ID is missing in .variables file. DNS records will not be updates."
        	_UPDATE_DNS=0
	else
		_UPDATE_DNS=1
	fi
}

createDNS(){
	curl --silent -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${_TOKEN}" \
    -X POST -d '{
      "type": "A",
      "name": "'${_LABELX}'",
      "target": "'${_IP}'",
      "ttl_sec": 300
    }' \
    https://api.linode.com/v4/domains/${_DOMAINID}/records > /dev/null
	printf "DNS record ${_LABELX}.${_DOMAIN} created\n"
}

createInstance(){
	_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo) #Generate random password
	printf "Regions: \n"
	getRegions
	read -r -p "Which region? " _REGION
	printf "\nTypes: \n"
	getTypes
	read -r -p "Which type? " _TYPE
	printf "\nImages: \n"
	getImages
	read -r -p "Which image? " _IMAGE
	read -r -p "Instance Name? " _LABEL
	read -r -p "How many instances? " _REPLICAS
	if [ ! -z ${_DOMAIN} ] && [ ! -z ${_DOMAINID} ]; then
		while true; do
			read -p "Do you wish to create DNS records? " yn
			case $yn in
				[Yy]* ) checkDNS; break;;
				[Nn]* ) _UPDATE_DNS=0; break;;
				* ) echo "Please answer yes or no.";;
			esac
		done
	else
		_UPDATE_DNS=0
	fi
	_REPLICA=0
	printf "\nThe root password is: ${_PASSWORD}\n"
	until [ ${_REPLICA} -eq ${_REPLICAS} ]; do
		_REPLICA=$(expr ${_REPLICA} + 1)
		_LABELX=$(echo "${_LABEL}-${_REPLICA}")
		curl --silent -H "Content-Type: application/json" \
			-H "Authorization: Bearer ${_TOKEN}" \
			-X POST -d '{
			"image": "'${_IMAGE}'",
			"root_pass": "'${_PASSWORD}'",
			"authorized_users": [
				"'${_USERNAME}'"
				],
			"booted": true,
			"label": "'${_LABELX}'",
			"type": "'${_TYPE}'",
			"region": "'${_REGION}'",
			"stackscript_id": '${_STACKSCRIPTID}',
			"stackscript_data": {
		        "hostname": "'${_LABELX}'"
			}
			}' \
			https://api.linode.com/v4/linode/instances | jq > ${_SCRIPTDIR}/tmp/instance.json
			_IP=$(cat ${_SCRIPTDIR}/tmp/instance.json | jq -r '.ipv4[0]')
			printf "Linode ${_LABELX} created\n"

			# DNS Records
			if [ ${_UPDATE_DNS} -eq 1 ]; then
				createDNS
			fi

			# Connect to Instance
			if [ ${_REPLICAS} -eq 1 ]; then
				while true; do
					read -p "Do you wish to connect to this instance? " yn
					case $yn in
						[Yy]* ) connectInstance 2> /dev/null; break;; #Connect and redirect stderr to /dev/null
						[Nn]* ) break;;
						* ) echo "Please answer yes or no.";;
					esac
				done
			fi
	done
	if [ ${_REPLICAS} -gt 1 ]; then
		sleep 1
		printf "\n"
		listInstances
	fi
}

createInstanceBulk(){
        _PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo) #Generate random password
        _REGION=$1
        _TYPE=$2
        _IMAGE=$3
        _LABEL=$4
        _REPLICAS=$5
        _UPDATE_DNS=0
        _REPLICA=0
        printf "\nThe root password is: ${_PASSWORD}\n"
        until [ ${_REPLICA} -eq ${_REPLICAS} ]; do
                _REPLICA=$(expr ${_REPLICA} + 1)
                _LABELX=$(echo "${_LABEL}-${_REPLICA}")
                curl --silent -H "Content-Type: application/json" \
                        -H "Authorization: Bearer ${_TOKEN}" \
                        -X POST -d '{
                        "image": "'${_IMAGE}'",
                        "root_pass": "'${_PASSWORD}'",
                        "authorized_users": [
                                "'${_USERNAME}'"
                                ],
                        "booted": true,
                        "label": "'${_LABELX}'",
                        "type": "'${_TYPE}'",
                        "region": "'${_REGION}'",
                        "stackscript_id": '${_STACKSCRIPTID}',
                        "stackscript_data": {
                        "hostname": "'${_LABELX}'"
                        }
                        }' \
                        https://api.linode.com/v4/linode/instances | jq > ${_SCRIPTDIR}/tmp/instance.json
                        _IP=$(cat ${_SCRIPTDIR}/tmp/instance.json | jq -r '.ipv4[0]')
                        printf "Linode ${_LABELX} created\n"
                        createDNS
        done
        if [ ${_REPLICAS} -gt 1 ]; then
                sleep 1
                printf "\n"
                listInstances
        fi
}

connectInstance(){
printf "\nConnecting to instance using the following command:\n\tssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${_KEYNAME} root@${_IP}\n"
printf "Note: This could take 60 seconds or more.\n"
until ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i ${_KEYNAME} root@${_IP}; do
        echo "Please wait..."
        sleep 1
done
}

connectInstanceManual(){
	listInstances
	read -r -p "Instance ID: " _ID
	_IP=$(curl --silent -H "Authorization: Bearer ${_TOKEN}" https://api.linode.com/v4/linode/instances/${_ID} | jq -r .ipv4[0])
	connectInstance 2> /dev/null
}

deleteDNS(){
	dig ${_LABELX}.${_DOMAIN} | grep "ANSWER: 1"> /dev/null
	if [ $? -eq 0 ]; then
		_DNSID=$(curl --silent -H "Authorization: Bearer ${_TOKEN}"  https://api.linode.com/v4/domains/${_DOMAINID}/records | jq ' .data[] | select(.name == "'${_LABELX}'") | .id')
		curl --silent -H "Authorization: Bearer ${_TOKEN}" -X DELETE https://api.linode.com/v4/domains/${_DOMAINID}/records/${_DNSID} > /dev/null
		printf "DNS record ${_LABELX}.${_DOMAIN} deleted.\n"
	fi
}

terminateAllInstances(){
	for _INSTANCE in $(curl --silent -H "Authorization: Bearer ${_TOKEN}" https://api.linode.com/v4/linode/instances | jq -r '.data[] | (.id|tostring) + "," + .label + "," + .ipv4[0]'); do
		_ID=$(echo ${_INSTANCE} | cut -d, -f1)
		_LABELX=$(echo ${_INSTANCE} | cut -d, -f2)
		_IP=$(echo ${_INSTANCE} | cut -d, -f3)
		terminateInstance ${_ID}
	done
}

stopInstance(){
	listInstances
	read -r -p "Which image label? " _LABEL
	for _INSTANCE in $(listInstances | grep ${_LABEL}); do
		_ID=$(echo ${_INSTANCE} | cut -d, -f1)
		_LABELX=$(echo ${_INSTANCE} | cut -d, -f2)
		curl --silent -H "Authorization: Bearer ${_TOKEN}" -X POST https://api.linode.com/v4/linode/instances/${_ID}/shutdown > /dev/null
		printf "Instance ${_LABELX} shut down.\n"
	done
}

startInstance(){
	listInstances
	read -r -p "Which image label? " _LABEL
	for _INSTANCE in $(listInstances | grep ${_LABEL}); do
		_ID=$(echo ${_INSTANCE} | cut -d, -f1)
		_LABELX=$(echo ${_INSTANCE} | cut -d, -f2)
		curl --silent -H "Authorization: Bearer ${_TOKEN}" -X POST https://api.linode.com/v4/linode/instances/${_ID}/boot > /dev/null
		printf "Instance ${_LABELX} booted.\n"
	done
}


##Execute
checkApps
checkVariables
checkSSH

if [ ! -z $1 ]; then
	if [[ $1 == "help" ]]; then
		echo "Usage:   ./run.sh REGION TYPE IMAGE LABEL REPLICAS"
		echo "Example: ./run.sh us-ord g6-standard-1 linode/ubuntu22.04 lab 10 "
		exit
	fi
	createInstanceBulk $1 $2 $3 $4 $5
	exit
fi

stty erase '^H' #Set backspace/erase charater

printf "Please select Linode operation:\n"
_OPTIONS=("Create Instance" "Terminate Instance(s)" "List Instances" "View Instance" "Connect to Instance" "Start Instance(s)" "Stop Instance(s)" "Terminate All Instances")
select _OPT in "${_OPTIONS[@]}"
do
        case ${_OPT} in
            "Create Instance")
				createInstance
                ;;
            "Terminate Instance(s)")
				terminateInstance
                ;;
            "List Instances")
				listInstances
                ;;
			"View Instance")
				viewInstance
                ;;
			"Connect to Instance")
				connectInstanceManual
                ;;
			"Start Instance(s)")
				startInstance
                ;;
			"Stop Instance(s)")
				stopInstance
                ;;
			"Terminate All Instances")
				terminateAllInstances
                ;;
            *) echo invalid option;;
        esac
    done
