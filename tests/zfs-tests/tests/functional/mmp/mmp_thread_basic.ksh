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
#	zpool import should not succeed when attempting to import
#	a pool that appears to be in the ONLINE state.
#
# STRATEGY:
#	1. Set zfs_mmp_interval to 0 (disables mmp)
#	2. Set zfs_txg_timeout to large value
#	3. Create a zpool
#	4. Force a sync on the zpool
#	5. Store the current "best" uberblock
#	6. Repeatedly check that the "best" uberblock
#	   for 10 seconds
#	7. If the uberblock never changed, fail
#

. $STF_SUITE/include/libtest.shlib

verify_runnable "both"
TXG_TIMEOUT=

function cleanup
{
	if poolexists mmptestpool; then
		log_must zpool destroy mmptestpool
	fi

	log_must rm -rf "$TEST_BASE_DIR/mmp_vdevs"
	log_must rm -f $PREV_UBER $CURR_UBER
}

log_assert "mmp thread writes uberblocks (MMP)"
log_onexit cleanup

log_must mkdir "$TEST_BASE_DIR/mmp_vdevs"
log_must truncate -s 512M "$TEST_BASE_DIR/mmp_vdevs/vdev1"

log_must zpool create mmptestpool "$TEST_BASE_DIR/mmp_vdevs/vdev1"
sync_pool mmptestpool

PREV_UBER="$TEST_BASE_DIR/mmp-uber-prev.txt"
CURR_UBER="$TEST_BASE_DIR/mmp-uber-curr.txt"

zdb -u mmptestpool > $PREV_UBER

SECONDS=0
UBER_CHANGED=0
while (( SECONDS < 10 )); do
	zdb -u mmptestpool > $CURR_UBER
	if diff "$CURR_UBER" "$PREV_UBER"; then
		UBER_CHANGED=1
		break
	fi

	cp -f $PREV_UBER $CURR_UBER
done

if [ "$UBER_CHANGED" -eq 0 ]; then
	log_fail "mmp failed to update uberblocks"
fi

log_pass "mmp thread writes uberblocks (MMP) passed"
