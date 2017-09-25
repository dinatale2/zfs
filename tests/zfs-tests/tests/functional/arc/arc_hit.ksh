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
#	zfs_multihost_interval should only accept valid values.
#
# STRATEGY:
#	1. Flush the ARC
#	2. Create a file small enough to fit in the ARC
#	3. Confirm hit rate is close to 100%
#

. $STF_SUITE/include/libtest.shlib
. $STF_SUITE/tests/functional/arc/arc.cfg
. $STF_SUITE/tests/functional/arc/arc.kshlib

verify_runnable "both"

log_assert "100% hit rate for small file in arc"

mntpnt=$(get_prop mountpoint $TESTPOOL)

function cleanup
{
	log_must rm -rf "$mntpnt/testfile"
}

log_onexit cleanup

flush_arc
prev_hits=$(get_arcstat "hits")
log_must dd bs=1M count=20 < /dev/urandom > "$mntpnt/testfile"
log_must cat $mntpnt/testfile > /dev/null
new_hits=$(get_arcstat "hits")
total_hits=$((new_hits - prev_hits))

log_note "prev_hits: $prev_hits new_hits: $new_hits total: $total_hits"
log_pass "100% hit rate for small file in arc"
