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
#	Verify import behavior for exported pool (no activity check)
#
# STRATEGY:
#	1. Create a zpool
#	2. Verify safeimport=off and hostids match (no activity check)
#	3. Verify safeimport=off and hostids differ (no activity check)
#	4. Verify safeimport=on and hostids match (no activity check)
#	5. Verify safeimport=on and hostids differ (no activity check)
#


. $STF_SUITE/include/libtest.shlib
. $STF_SUITE/tests/functional/mmp/mmp.cfg
. $STF_SUITE/tests/functional/mmp/mmp.kshlib

verify_runnable "both"

function cleanup
{
	default_cleanup_noexit
	log_must set_spl_tunable spl_hostid $SPL_HOSTID_DEFAULT
}

log_assert "safeimport=on|off activity checks exported pool"
log_onexit cleanup

# 1. Create a zpool
log_must set_spl_tunable spl_hostid $SPL_HOSTID1
default_setup_noexit $DISK

# 2. Verify safeimport=off and hostids match (no activity check)
log_must zpool set safeimport=off $TESTPOOL

for opt in "" "-f"; do
	log_must zpool export $TESTPOOL
	log_must import_no_activity_check $opt $TESTPOOL
done

# 3. Verify safeimport=off and hostids differ (no activity check)
for opt in "" "-f"; do
	log_must mmp_pool_set_hostid $TESTPOOL $SPL_HOSTID1
	log_must zpool export $TESTPOOL
	log_must set_spl_tunable spl_hostid $SPL_HOSTID2
	log_must import_no_activity_check $opt $TESTPOOL
done

# 4. Verify safeimport=on and hostids match (no activity check)
log_must zpool set safeimport=on $TESTPOOL
log_must mmp_pool_set_hostid $TESTPOOL $SPL_HOSTID1

for opt in "" "-f"; do
	log_must zpool export $TESTPOOL
	log_must import_no_activity_check $opt $TESTPOOL
done

# 5. Verify safeimport=on and hostids differ (no activity check)
for opt in "" "-f"; do
	log_must mmp_pool_set_hostid $TESTPOOL $SPL_HOSTID1
	log_must zpool export $TESTPOOL
	log_must set_spl_tunable spl_hostid $SPL_HOSTID2
	log_must import_no_activity_check $opt $TESTPOOL
done

log_pass "safeimport=on|off exported pool activity checks passed"
