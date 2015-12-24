#!/bin/bash
# This script creates a small logical volume in the given LVM volume group
# in order to detect problems with LVM or the underlying RAID 0 device
# (mdadm does not indicate problems with the array even when drives drop out).

if [[ "$1" == "" ]]; then
	echo "You must provide the path of a LVM volume group." >&2
	exit 100
fi

FAILED=0
LV_NAME=EphemeralFunctionalTest_$(date +%s)
# create a 4MB logical volume in the given volume group
LV_CREATION_OUTPUT=$(/sbin/lvcreate $1 -n $LV_NAME -L 4M 2>&1)

if echo $LV_CREATION_OUTPUT | egrep -q '(Input/output error|failed)'; then
	FAILED=1
fi

# attempt to clean up LV
/sbin/lvremove -f /dev/$1/$LV_NAME >/dev/null 2>&1

# according to kelvk, need to echo something here for Zabbix trigger expression to evaluate
echo $FAILED
exit $FAILED
