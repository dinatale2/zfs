#!/bin/ksh -p
#
# CDDL HEADER START
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#
# CDDL HEADER END
#

#
# Copyright (c) 2017 by Lawrence Livermore National Security, LLC.
#

# DESCRIPTION:
#	When safeimport=off ensure that leaf vdev uberblocks are not updated.
#
# STRATEGY:
#	1. Set safeimport=off (disables mmp)
#	2. Set zfs_txg_timeout to large value
#	3. Create a zpool
#	4. Find the current "best" uberblock
#	5. Sleep for enough time for uberblocks to change
#	6. Find the current "best" uberblock
#	7. If the uberblock changed, fail
#	8. Set safeimport=on
#	9. Sleep for enough time for uberblocks to change
#	10. Find the current "best" uberblock
#	11. If uberblocks didn't change, fail
#

. $STF_SUITE/include/libtest.shlib
. $STF_SUITE/tests/functional/mmp/mmp.cfg

verify_runnable "both"

function cleanup
{
	default_cleanup_noexit
	log_must set_tunable64 zfs_txg_timeout $TXG_TIMEOUT_DEFAULT
	log_must set_tunable64 zfs_mmp_interval $MMP_INTERVAL_DEFAULT
	log_must rm -f $PREV_UBER $CURR_UBER
}

log_assert "mmp thread won't write uberblocks with safeimport=off"
log_onexit cleanup

log_must set_tunable64 zfs_mmp_interval $MMP_INTERVAL_MIN
log_must set_tunable64 zfs_txg_timeout $TXG_TIMEOUT_LONG
log_must set_spl_tunable spl_hostid $SPL_HOSTID1

default_setup_noexit $DISK
log_must zpool set safeimport=off $TESTPOOL

log_must zdb -u $TESTPOOL > $PREV_UBER
log_must sleep 5
log_must zdb -u $TESTPOOL > $CURR_UBER

if ! diff "$CURR_UBER" "$PREV_UBER"; then
	log_fail "mmp thread has updated an uberblock"
fi

log_must zpool set safeimport=on $TESTPOOL
log_must sleep 5
log_must zdb -u $TESTPOOL > $CURR_UBER

if diff "$CURR_UBER" "$PREV_UBER"; then
	log_fail "mmp failed to update uberblocks"
fi

log_pass "mmp thread won't write uberblocks with safeimport=off passed"
