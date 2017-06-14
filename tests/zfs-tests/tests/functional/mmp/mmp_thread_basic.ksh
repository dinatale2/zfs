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
#
# STRATEGY:
#	1. Set zfs_mmp_interval to 0 (disables mmp)
#	2. Set zfs_txg_timeout to large value
#	3. Create a zpool
#	4. Force a sync on the zpool
#	5. Find the current "best" uberblock
#	6. Sleep for enough time for a potential uberblock update
#	7. Find the current "best" uberblock
#	8. If the uberblock never changed, fail
#

. $STF_SUITE/include/libtest.shlib

verify_runnable "both"

PREV_UBER="$TEST_BASE_DIR/mmp-uber-prev.txt"
CURR_UBER="$TEST_BASE_DIR/mmp-uber-curr.txt"
DISK=${DISKS%% *}

function cleanup
{
	set_tunable64 zfs_txg_timeout 5
	default_cleanup
	log_must rm -f $PREV_UBER $CURR_UBER
}

log_assert "mmp thread writes uberblocks (MMP)"
log_onexit cleanup

if ! set_tunable64 zfs_txg_timeout 1000; then
	log_fail "Failed to set zfs_txg_timeout to 1000"
fi

default_setup_noexit $DISK
sync_pool $TESTPOOL

log_must zdb -u $TESTPOOL > $PREV_UBER
log_must sleep 5
log_must zdb -u $TESTPOOL > $CURR_UBER
if diff "$CURR_UBER" "$PREV_UBER"; then
	log_fail "mmp failed to update uberblocks"
fi

log_pass "mmp thread writes uberblocks (MMP) passed"
