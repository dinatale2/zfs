/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
 * or http://www.opensolaris.org/os/licensing.
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at usr/src/OPENSOLARIS.LICENSE.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * CDDL HEADER END
 */
/*
 * Copyright (C) 2017 by Lawrence Livermore National Security, LLC.
 */

#ifndef _SYS_MMP_H
#define	_SYS_MMP_H

#include <sys/spa.h>
#include <sys/zfs_context.h>

#ifdef	__cplusplus
extern "C" {
#endif

#define MMP_SKIP_ACTIVITY_TEST 1
#define MMP_DEFAULT_INTERVAL 1000

typedef struct mmp_thread_state {
	kmutex_t	mmp_thread_lock;	/* protect thread mgmt fields */
	kcondvar_t	mmp_thread_cv;
	kthread_t	*mmp_thread;
	uint8_t		mmp_thread_exiting;
	kmutex_t	mmp_io_lock;		/* protect below */
	hrtime_t	mmp_last_write;		/* last successful MMP write */
	uint64_t	mmp_delay;		/* Recent period MMP writes */
} mmp_thread_state_t;


extern void mmp_init(struct dsl_pool *dp);
extern void mmp_fini(struct dsl_pool *dp);
extern void mmp_thread_start(struct dsl_pool *dp);
extern void mmp_thread_stop(struct dsl_pool *dp);

/* Global tuning */
extern uint zfs_mmp_interval;
extern uint zfs_mmp_fail_intervals;

#ifdef	__cplusplus
}
#endif

#endif	/* _SYS_MMP_H */
