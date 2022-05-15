#!/bin/bash

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
if [ -e ${_SCRIPTDIR}/keys/${_KEYNAME} ]; then
        chmod 600 ${_SCRIPTDIR}/keys/${_KEYNAME} &> /dev/null
else
        echo "SSH file is missing (${_SCRIPTDIR}/keys/${_KEYNAME}). Exiting..."
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
	printf "ID,Label,IPv4,IPv6\n"
	curl --silent -H "Authorization: Bearer ${_TOKEN}" https://api.linode.com/v4/linode/instances | jq -r '.data[] | (.id|tostring) + "," + .label + "," + .ipv4[0] + "," + .ipv6'
}

viewInstance(){
	listInstances
	read -r -p "Instance ID: " _ID
	curl --silent -H "Authorization: Bearer ${_TOKEN}" https://api.linode.com/v4/linode/instances/${_ID} | jq 
}

deleteInstance(){
	if [ -z ${1} ]; then
		listInstances
		read -r -p "Instance ID: " _ID
	else
		_ID=${1}
	fi
	curl --silent -H "Authorization: Bearer ${_TOKEN}" -X DELETE https://api.linode.com/v4/linode/instances/${_ID} > /dev/null
	printf "Instance ${_ID} deleted.\n"
}

createInstance(){
	_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
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
	_REPLICA=0
	printf "\nThe root password is: ${_PASSWORD}\n"
	until [ ${_REPLICA} -eq ${_REPLICAS} ]; do
		_REPLICA=$(expr ${_REPLICA} + 1)
		_LABELX=$(echo "${_LABEL}_${_REPLICA}")
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

			# Connect to Instance
			if [ ${_REPLICAS} -eq 1 ]; then
				while true; do
					read -p "Do you wish to connect to this instance? " yn
					case $yn in
						[Yy]* ) connectInstance 2> /dev/null; break;; #Connect and redirect stderr to /dev/null
						[Nn]* ) exit;;
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

connectInstance(){
printf "\nConnecting to instance using the following command:\n\tssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${_SCRIPTDIR}/keys/${_KEYNAME} root@${_IP}\n"
printf "Note: This could take 60 seconds or more.\n"
until ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i ${_SCRIPTDIR}/keys/${_KEYNAME} root@${_IP}; do
        echo "Please wait..."
        sleep 1
done
printf "Exiting...\n"
exit
}

connectInstanceManual(){
	listInstances
	read -r -p "Instance ID: " _ID
	_IP=$(curl --silent -H "Authorization: Bearer ${_TOKEN}" https://api.linode.com/v4/linode/instances/${_ID} | jq -r .ipv4[0])
	until ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i ${_SCRIPTDIR}/keys/${_KEYNAME} root@${_IP}; do
        echo "Please wait..."
        sleep 1
	done
}

terminateAllInstances(){
	for _ID in $(curl --silent -H "Authorization: Bearer ${_TOKEN}" https://api.linode.com/v4/linode/instances | jq -r '.data[] | .id'); do
		deleteInstance ${_ID}
	done
}

##Execute

checkApps
checkVariables
checkSSH

printf "Please select Linode operation:\n"
_OPTIONS=("Create Instance" "Delete Instance" "List Instances" "View Instance" "Connect to Instance" "Terminate All Instances")
select _OPT in "${_OPTIONS[@]}"
do
        case ${_OPT} in
            "Create Instance")
				createInstance
                ;;
            "Delete Instance")
				deleteInstance
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
			"Terminate All Instances")
				terminateAllInstances
                ;;
            *) echo invalid option;;
        esac
    done