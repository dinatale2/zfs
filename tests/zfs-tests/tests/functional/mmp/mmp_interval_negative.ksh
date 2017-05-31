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
#	zfs_mmp_interval should never be able to be negative
#
# STRATEGY:
#	1. Set zfs_mmp_interval to negative value, should fail 
#

. $STF_SUITE/include/libtest.shlib

verify_runnable "both"
TXG_TIMEOUT=

function cleanup
{
	set_tunable64 zfs_mmp_interval 1000
}

log_assert "zfs_mmp_interval cannot be set to a negative value"
log_onexit cleanup

if set_tunable64 zfs_mmp_interval -1; then
	log_fail "zfs_mmp_interval was set to a negative value"
fi

log_pass "zfs_mmp_interval cannot be set to a negative value passed"
