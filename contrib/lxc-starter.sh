#!/bin/bash

# An example of an /etc/zfsvault/post-unlock.d/ script.
# You can customize this to do anything you need after unlocking ZFS vaults.
# WARNING: This script is run as root, so be careful with what you put in it.
# All post-unlock scripts are run in alphabetical order, so you can name this file
# something like 01-lxc-starter.sh to ensure it runs before other scripts.

logger "lxc-starter.sh: Starting ZFS-dependent containers"

pct start 100
pct start 101

logger "lxc-starter.sh: Containers started"
