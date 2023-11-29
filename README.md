# Linode Operations

# Requirements

 - A [Linode](https://www.linode.com/) account
 - A [Linode Personal Access Token](https://www.linode.com/docs/guides/getting-started-with-the-linode-api/)
 - An SSH key
	 - Public key loaded into Linode
	 - Private key stored in **keys** directory
 - Properly formatted .variables file

## .variables

The .variables file must be created in root of the script directory in the following format:

    Environment1,Username1,Key1,Token1,StackScriptID1,Domain1,DomainID1,TTL1
    Environment2,Username2,Key2,Token2,StackScriptID2,Domain2,DomainID2,TTL2

Multiple environments can be specified as demonstrated above.

## StackScript

At minimum the associated StackScript should start with the following:

    #!/bin/bash
    set -ev
    #<UDF name="hostname" label="Hostname">
    # HOSTNAME=
    # Hostname setup
    hostnamectl hostname $HOSTNAME
