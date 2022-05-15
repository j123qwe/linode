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

    _USERNAME=<Linode Username>
    _KEYNAME=<SSH private key file>
    _TOKEN=<Linode Personal Access Token>
    _STACKSCRIPTID=<Linode StackScript ID>

## StackScript

At minimum the associated StackScript should start with the following:

    #!/bin/bash
    set -ev
    #<UDF name="hostname" label="Hostname">
    # HOSTNAME=
    # Hostname setup
    hostnamectl hostname $HOSTNAME
