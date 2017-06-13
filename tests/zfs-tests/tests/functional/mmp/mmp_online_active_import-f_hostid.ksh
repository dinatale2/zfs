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
#	Force importing an active pool when the hostid in the pool is
#	equivalent to the current host's hostid, even though dangerous,
#	it should succeed.
#
# STRATEGY:
#	1. Run ztest in the background with hostid x.
#	2. Set hostid to x.
#	3. A `zpool import` on the pool created by ztest should succeed.
#
# NOTES:
#	This test cases tests a situation which we do not support. Two hosts
#	with the same hostid is strictly unsupported. While it is expected
#	that a zpool import will succeed in this circumstance, a kernel panic
#	and other known issues may result. This test case may be useful in
#	the future in situations when pools can be imported in both kernel
#	and user space on the same node.
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

	if poolexists ztest; then
                log_must zpool destroy ztest
        fi

	log_must rm -rf "$TEST_BASE_DIR/mmp_vdevs"
	set_spl_tunable spl_hostid 0
}

log_assert "zpool import -f succeeds on active pool with same hostid (MMP)"
log_onexit cleanup

log_must mkdir "$TEST_BASE_DIR/mmp_vdevs"

log_note "Starting ztest in the background"
export ZFS_HOSTID=16
log_must eval "ztest -t1 -K -k0 -f $TEST_BASE_DIR/mmp_vdevs > /dev/null 2>&1 &"
ZTESTPID=$!
if ! ps -p $ZTESTPID > /dev/null; then
	log_fail "ztest failed to start"
fi

if ! set_spl_tunable spl_hostid "$ZFS_HOSTID"; then
	log_fail "Failed to set spl_hostid to $ZFS_HOSTID"
fi
log_must zpool import -f -d "$TEST_BASE_DIR/mmp_vdevs" ztest

log_pass "zpool import -f succeeds on active pool with same hostid (MMP) passed"
