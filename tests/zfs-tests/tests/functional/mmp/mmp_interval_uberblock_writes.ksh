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
# Copyright (c) 2017 by Lawrence Livermore National Security, LLC.
#

# DESCRIPTION:
#	Ensure that MMP updates uberblocks at the expected intervals.
#
# STRATEGY:
#	1. Set zfs_txg_timeout to large value
#	2. Create a zpool
#	3. Force a sync on the zpool
#	4. Find the current "best" uberblock
#	5. Loop for 10 seconds, increment counter for each change in UB
#	6. If number of changes seen is less than min threshold, then fail
#	7. If number of changes seen is more than max threshold, then fail
#

. $STF_SUITE/include/libtest.shlib

verify_runnable "both"

PREV_UBER="$TEST_BASE_DIR/mmp-uber-prev.txt"
CURR_UBER="$TEST_BASE_DIR/mmp-uber-curr.txt"
UBER_CHANGES=0
DISK=${DISKS%% *}

function cleanup
{
	set_tunable64 zfs_txg_timeout 5
	default_cleanup
	log_must rm -f $PREV_UBER $CURR_UBER
}

log_assert "Ensure MMP uberblocks update at the correct interval"
log_onexit cleanup

if ! set_tunable64 zfs_txg_timeout 1000; then
	log_fail "Failed to set zfs_txg_timeout"
fi

default_setup_noexit $DISK
sync_pool $TESTPOOL

log_must zdb -u $TESTPOOL > $PREV_UBER
SECONDS=0
while [[ $SECONDS -le 10 ]]; do
	log_must eval "echo $SECONDS"
	log_must zdb -u $TESTPOOL > $CURR_UBER
	if ! diff "$CURR_UBER" "$PREV_UBER"; then
		(( UBER_CHANGES = UBER_CHANGES + 1 ))
		log_must mv "$CURR_UBER" "$PREV_UBER"
	fi
done

log_note "Uberblock changed $UBER_CHANGES times"

if [[ $UBER_CHANGES -lt 8 ]]; then
	log_fail "Fewer uberblock writes occured than expected (10)"
fi

if [[ $UBER_CHANGES -gt 12 ]]; then
	log_fail "More uberblock writes occured than expected (10)"
fi

log_pass "Ensure MMP uberblocks update at the correct interval passed"
