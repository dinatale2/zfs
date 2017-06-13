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
#	Under no circumstances when MMP is active, should an active pool
#	with one hostid be importable by a host with a different hostid.
#
# STRATEGY:
#	1. Run ztest in the background with one hostid.
#	2. Set hostid to simulate a second node
#	3. Repeatedly attempt a `zpool import -f` on the pool created
#	   by ztest. `zpool import -f` should never succeed.
#	4. Repeatedly attempt a `zpool import` on the pool created
#	   by ztest. `zpool import` should never succeed.
#

. $STF_SUITE/include/libtest.shlib

verify_runnable "both"
ZTESTPID=

function cleanup
{
	if [ -n "$ZTESTPID" ]; then
		if ps -p $ZTESTPID > /dev/null; then
			log_must kill -s 9 $ZTESTPID
			wait $ZTESTPID
		fi
	fi

	log_must rm -rf "$TEST_BASE_DIR/mmp_vdevs"
	set_spl_tunable spl_hostid 0
}

log_assert "zpool import fails on active pool (MMP)"
log_onexit cleanup

log_must mkdir "$TEST_BASE_DIR/mmp_vdevs"

log_note "Starting ztest in the background"
export ZFS_HOSTID=16
log_must eval "ztest -t1 -K -k0 -f $TEST_BASE_DIR/mmp_vdevs > /dev/null 2>&1 &"
ZTESTPID=$!
if ! ps -p $ZTESTPID > /dev/null; then
	log_fail "ztest failed to start"
fi

if ! set_spl_tunable spl_hostid 963 ; then
	log_fail "Failed to set spl_hostid to 963"
fi

log_must sleep 5

for i in {1..10}; do
	log_mustnot zpool import -f -d "$TEST_BASE_DIR/mmp_vdevs" ztest
done

for i in {1..10}; do
	log_mustnot zpool import -d "$TEST_BASE_DIR/mmp_vdevs" ztest
done

log_pass "zpool import fails on active pool (MMP) passed"
