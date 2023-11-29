# Linode Operations

# Requirements

 - A [Linode](https://www.linode.com/) account
 - A [Linode Personal Access Token](https://www.linode.com/docs/guides/getting-started-with-the-linode-api/)
 - An SSH key
	 - Public key loaded into Linode
	 - Private key stored in **keys** directory
 - Properly formatted .variables file

## .variables

The .variables file must be created in root of the script directory in the following format. Multiple environments can be specified.

    Environment1,Username1,Key1,Token1,StackScriptID1,Domain1,DomainID1,TTL1,DefaultRegion1,DefaultType1,DefaultImage1
    Environment2,Username2,Key2,Token2,StackScriptID2,Domain2,DomainID2,TTL2,DefaultRegion2,DefaultType2,DefaultImage2

Example:

    Personal,jdoe,aabbccddeeffgghhiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz112233445566,1234567,domain.example.local,1234567,30,us-east,g6-nanode-1,linode/ubuntu22.04

## StackScript

At minimum the associated StackScript should start with the following:

    #!/bin/bash
    set -ev
    #<UDF name="hostname" label="Hostname">
    # HOSTNAME=
    # Hostname setup
    hostnamectl hostname $HOSTNAME

## Bulk Create

Bulk Linodes can be created using the following syntax:

    ./run.sh ENVIRONMENT REGION TYPE IMAGE LABEL REPLICAS PASSWORD

Example:

    ./run.sh Personal us-west g6-standard-1 linode/ubuntu22.04 lab 2 PaSs312!

Note: The password has to meet the Linode complexity requirements. A random password will be created if omitted.