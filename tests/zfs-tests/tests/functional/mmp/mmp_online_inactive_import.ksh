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
#	Ensure that a pool can be forcefully imported from another
#	host when the pool is inactive.
#
# STRATEGY:
#	1. Set hostid to x
#	2. Create a pool
#	3. Run zpool export -F <pool>
#	4. Run zpool import -f, should succeed
#	5. Run zpool export -F <pool>
#	6. Run zpool import, should succeed
#	7. Run zpool export -F <pool>
#	8. Set hostid to y to simulate another node
#	9. Run zpool import <pool>, should fail
#	10. Run zpool import -f <pool>, should succeed
#

. $STF_SUITE/include/libtest.shlib

verify_runnable "both"

function cleanup
{
	default_cleanup
	set_spl_tunable spl_hostid 0
}

log_assert "zpool import behaves correcly with inactive ONLINE pools"
log_onexit cleanup

if ! set_spl_tunable spl_hostid 111 ; then
	log_fail "Failed to set spl_hostid to 111"
fi

default_setup $DISKS

log_must zpool export -F $TESTPOOL
log_must zpool import -f $TESTPOOL
log_must zpool export -F $TESTPOOL
log_must zpool import $TESTPOOL
log_must zpool export -F $TESTPOOL

if ! set_spl_tunable spl_hostid 222 ; then
	log_fail "Failed to set spl_hostid to 222"
fi
log_mustnot zpool import $TESTPOOL
log_must zpool import -f $TESTPOOL

log_pass "zpool import behaves correcly with inactive ONLINE pools passed"
