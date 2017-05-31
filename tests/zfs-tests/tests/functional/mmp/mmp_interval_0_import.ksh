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
#	2. Set hostid
#	3. Create a zpool
#	4. zpool export -F for ONLINE VDEV
#	5. Change hostid
#	6. Attempt a zpool import -f
#	7. Fail if zpool import -f took more than 2 seconds
#

. $STF_SUITE/include/libtest.shlib

verify_runnable "both"

function cleanup
{
	set_tunable64 zfs_mmp_interval 1000

	if poolexists mmptestpool; then
		log_must zpool destroy mmptestpool
	fi

	log_must rm -rf "$TEST_BASE_DIR/mmp_vdevs"
	log_must rm -f $PREV_UBER $CURR_UBER
}

log_assert "zfs_mmp_interval=0 should skip activity checks"
log_onexit cleanup

log_must mkdir "$TEST_BASE_DIR/mmp_vdevs"
log_must truncate -s 512M "$TEST_BASE_DIR/mmp_vdevs/vdev1"

if ! set_tunable64 zfs_mmp_interval 0; then
	log_fail "Failed to set zfs_mmp_interval to 0"
fi

log_note "Setting hostid"
echo 222 > /sys/module/spl/parameters/spl_hostid

log_must zpool create mmptestpool "$TEST_BASE_DIR/mmp_vdevs/vdev1"
log_must zpool export -F mmptestpool

log_note "Setting hostid"
echo 111 > /sys/module/spl/parameters/spl_hostid
SECONDS=0
log_must zpool import -f -d "$TEST_BASE_DIR/mmp_vdevs" mmptestpool
IMPORT_DURATION=$SECONDS

if [ $IMPORT_DURATION -gt 2 ]; then
	log_fail "mmp activity check occured, expected no activity check"
fi

log_pass "zfs_mmp_interval=0 should skip activity checks passed"
