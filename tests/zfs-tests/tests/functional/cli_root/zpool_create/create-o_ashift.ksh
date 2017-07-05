#!/bin/ksh -p
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#

#
# Copyright 2016, loli10K. All rights reserved.
# Copyright (c) 2017 Datto Inc.
#

. $STF_SUITE/include/libtest.shlib
. $STF_SUITE/tests/functional/cli_root/zpool_create/zpool_create.shlib

#
# DESCRIPTION:
#	'zpool create -o ashift=<n> ...' should work with different ashift
#	values.
#
# STRATEGY:
#	1. Create various pools with different ashift values.
#	2. Verify -o ashift=<n> works only with allowed values (9-16).
#	   Also verify that the lowest number of uberblocks in a label is 16 and
#	   smallest uberblock size is 8K even with higher ashift values.
#

verify_runnable "global"

function cleanup
{
	poolexists $TESTPOOL && destroy_pool $TESTPOOL
	log_must rm -f $disk
}

#
# Commit the specified number of TXGs to the provided pool
# We use 'zpool sync' here because we can't force it via sync(1) like on illumos
# $1 pool name
# $2 number of txg syncs
#
# 'zpool sync' results in 3 syncs, because it waits for the open txg to be
# synced.  However in a quiet pool 2 of those syncs have no dirty data nor
# config, and write no uberblock to disk.  If the number of uberblock slogs
# is not divisible by 3, then we wrap around and this does not matter.  But
# if it _is_ divisible by 3 we do not write all the slots and the test fails.
#
# The cat of $DIRTY_FILE_PATH forces an atime update, so each sync likely
# produces an uberblock write.
#
# Since we cannot guarantee every txg sync produces an uberblock, we wait for
# more syncs than were requested to provide some fudge factor.
#
#
function txg_sync
{
	typeset pool=$1
	typeset -i count=$(($2*8/6))
	typeset -i i=0;

	DIRTY_FILE_PATH=/$TESTPOOL/txg_sync_file
	log_must dd if=/dev/urandom of=$DIRTY_FILE_PATH count=1
	log_must eval "while true; do cat $DIRTY_FILE_PATH > /dev/null 2>&1; done &"
	WATCHPID=$!

	typeset -i start_txg=$(zdb -u $pool | awk '/txg = / {print $NF}')
	typeset -i new_txg=$start_txg
	typeset -i cycles=0
	while [ $((new_txg-start_txg)) -lt $count ] && [ $cycles -lt $count ]
	do
		log_must zpool sync $pool
		new_txg=$(zdb -u $pool | awk '/txg = / {print $NF}')
		((cycles=cycles+1))
	done

	if [ -n "$WATCHPID" ]; then
		if ps -p $WATCHPID > /dev/null; then
			log_must kill -s 9 $WATCHPID
			wait $WATCHPID
		fi
	fi
}

#
# Verify device $1 labels contains $2 valid uberblocks in every label
# $1 device
# $2 uberblocks count
#
function verify_device_uberblocks
{
	typeset device=$1
	typeset expected=$2

	typeset ubcount=$(zdb -qul $device | egrep '^(\s+)?Uberblock' | wc -l)
	typeset invalid=$(zdb -qul $device | egrep '^(\s+)?Uberblock' |
	    egrep 'invalid$' | wc -l)
	typeset labels_identical=$(zdb -qul $device | egrep 'labels = 0 1 2 3' |
	    wc -l)

	log_note "expected $expected ubcount $ubcount invalid $invalid " \
	    " labels_identical $labels_identical"
	if [[ $expected -ne $ubcount ]]; then
		return 1
	fi

	return 0
}

log_assert "zpool create -o ashift=<n>' works with different ashift values"
log_onexit cleanup

disk=$TEST_BASE_DIR/$FILEDISK0
log_must mkfile $SIZE $disk

typeset ashifts=("9" "10" "11" "12" "13" "14" "15" "16")
# since Illumos 4958 the largest uberblock is 8K so we have at least of 16/label
# MMP occupies one uberblock slot
typeset ubcount=("127" "127" "63" "31" "15" "15" "15" "15")
typeset -i i=0;
while [ $i -lt "${#ashifts[@]}" ]
do
	typeset ashift=${ashifts[$i]}
	log_must zpool create -o ashift=$ashift $TESTPOOL $disk
	typeset pprop=$(get_pool_prop ashift $TESTPOOL)
	verify_ashift $disk $ashift
	if [[ $? -ne 0 || "$pprop" != "$ashift" ]]
	then
		log_fail "Pool was created without setting ashift value to "\
		    "$ashift (current = $pprop)"
	fi
	# force 128 txg sync to fill the uberblock ring.
	txg_sync $TESTPOOL 128
	verify_device_uberblocks $disk ${ubcount[$i]}
	if [[ $? -ne 0 ]]
	then
		log_fail "Pool was created with unexpected number of uberblocks"
	fi
	# clean things for the next run
	log_must zpool destroy $TESTPOOL
	log_must zpool labelclear $disk
	log_must eval "verify_device_uberblocks $disk 0"
	((i = i + 1))
done

typeset badvals=("off" "on" "1" "8" "17" "1b" "ff" "-")
for badval in ${badvals[@]}
do
	log_mustnot zpool create -o ashift="$badval" $TESTPOOL $disk
done

log_pass "zpool create -o ashift=<n>' works with different ashift values"
