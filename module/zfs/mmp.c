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
 * Copyright (c) 2017 by Lawrence Livermore National Security, LLC.
 */

#include <sys/abd.h>
#include <sys/dsl_pool.h>
#include <sys/mmp.h>
#include <sys/spa.h>
#include <sys/spa_impl.h>
#include <sys/vdev.h>
#include <sys/vdev_impl.h>
#include <sys/zfs_context.h>

static void mmp_thread(dsl_pool_t *dp);

uint zfs_mmp_interval = 1000;		/* time between mmp writes in ms */
uint zfs_mmp_fail_intervals = 5;	/* safety factor for MMP writes */

void
mmp_init(dsl_pool_t *dp)
{
	mmp_thread_state_t *mmp = &dp->dp_mmp;

	bzero(mmp, sizeof (mmp_thread_state_t));
	mutex_init(&mmp->mmp_thread_lock, NULL, MUTEX_DEFAULT, NULL);
	cv_init(&mmp->mmp_thread_cv, NULL, CV_DEFAULT, NULL);
	mutex_init(&mmp->mmp_io_lock, NULL, MUTEX_DEFAULT, NULL);
}

void
mmp_fini(dsl_pool_t *dp)
{
	mmp_thread_state_t *mmp = &dp->dp_mmp;

	mutex_destroy(&mmp->mmp_thread_lock);
	cv_destroy(&mmp->mmp_thread_cv);
	mutex_destroy(&mmp->mmp_io_lock);
	bzero(mmp, sizeof (mmp_thread_state_t));
}

static void
mmp_thread_enter(mmp_thread_state_t *mmp)
{
	mutex_enter(&mmp->mmp_thread_lock);
}

void noinline
mmp_thread_exit(mmp_thread_state_t *mmp, kthread_t **mpp)
{
	ASSERT(*mpp != NULL);
	*mpp = NULL;
	cv_broadcast(&mmp->mmp_thread_cv);
	mutex_exit(&mmp->mmp_thread_lock);
	thread_exit();
}

void
mmp_thread_start(dsl_pool_t *dp)
{
	mmp_thread_state_t *mmp = &dp->dp_mmp;

	if (spa_writeable(dp->dp_spa)) {
		mutex_enter(&mmp->mmp_thread_lock);
		dprintf("mmp_thread_start pool %p\n", dp);
		mmp->mmp_last_write = gethrtime();
		mmp->mmp_thread = thread_create(NULL, 0, mmp_thread,
		    dp, 0, &p0, TS_RUN, defclsyspri);
		mutex_exit(&mmp->mmp_thread_lock);
	}
}

void noinline
mmp_thread_stop(dsl_pool_t *dp)
{
	mmp_thread_state_t *mmp;

	ASSERT(dp);
	ASSERT(dp->dp_mmp.mmp_thread);

	mmp = &dp->dp_mmp;

	dprintf("mmp_thread_stop signalling exit: pool %p\n", dp);

	mutex_enter(&mmp->mmp_thread_lock);
	mmp->mmp_thread_exiting = 1;
	cv_broadcast(&mmp->mmp_thread_cv);

	while (mmp->mmp_thread) {
		dprintf("mmp_thread_stop waiting for exit: pool %p\n", dp);
		cv_wait(&mmp->mmp_thread_cv, &mmp->mmp_thread_lock);
	}
	mutex_exit(&mmp->mmp_thread_lock);

	ASSERT(mmp->mmp_thread == NULL);
	dprintf("mmp_thread_stop completed exit: pool %p\n", dp);
	mmp->mmp_thread_exiting = 0;
}

/*
 * Randomly choose a leaf vdev, to write an MMP block to.  It must be
 * writable.  It must not have an outstanding mmp write (if so then
 * there is a problem, and a new write will also block).
 *
 * We try 10 times to pick a random leaf without an outstanding write.
 * If 90% of the leaves have pending writes, this gives us a >65%
 * chance of finding one we can write to.  There will be at least
 * (zfs_mmp_fail_intervals) tries before the inability to write an MMP
 * block causes serious problems.
 */

vdev_t *
vdev_random_leaf(spa_t *spa)
{
	vdev_t *vd, *child;
	int pending_writes = 10;

	ASSERT(spa);
	ASSERT(spa_config_held(spa, SCL_STATE, RW_READER) == SCL_STATE);

	/*
	 * Since we hold SCL_STATE, neither pool nor vdev state can
	 * change.  Therefore, if the root is not dead, there is a
	 * child that is not dead, and so on down to a leaf.
	 */

	if (vdev_is_dead(spa->spa_root_vdev))
		return (NULL);

	vd = spa->spa_root_vdev;
	while (!vd->vdev_ops->vdev_op_leaf) {
		child = vd->vdev_child[spa_get_random(vd->vdev_children)];

		if (vdev_is_dead(child))
			continue;

		if (child->vdev_ops->vdev_op_leaf &&
		    child->vdev_mmp_pending) {
			if (pending_writes-- > 0)
				continue;
			else
				return (NULL);
		}

		vd = child;
	}
	return (vd);
}

static void
mmp_write_done(zio_t *zio)
{
	vdev_t *vd = zio->io_vd;
	mmp_thread_state_t *mts = zio->io_private;

	mutex_enter(&mts->mmp_io_lock);

	vd->vdev_mmp_pending = 0;
	if (zio->io_error == 0)
	{
		mts->mmp_delay = gethrtime() - mts->mmp_last_write;
		mts->mmp_last_write = gethrtime();
	}

	mutex_exit(&mts->mmp_io_lock);
}

/*
 * Choose a random vdev, label, and MMP block, and write over it
 * with a copy of the last-synced uberblock, whose timestamp
 * has been updated to reflect that the pool is in use.  Use provided
 * char *buf and abd_t *abd to avoid repeatedly allocating them.
 */
static void
mmp_write_uberblock(dsl_pool_t *dp, abd_t *abd, char *buf, int bufsize)
{
	mmp_thread_state_t *mmp = &dp->dp_mmp;
	spa_t *spa = dp->dp_spa;
	vdev_t *vd;
	zio_t *zio;
	int l, n;
	int flags = ZIO_FLAG_CONFIG_WRITER | ZIO_FLAG_CANFAIL;

	/* Copy the latest uberblock and update the time */
	(void) memcpy(buf, &spa->spa_ubsync, sizeof (uberblock_t));
	((uberblock_t *)buf)->ub_timestamp = gethrestime_sec();
	abd_copy_from_buf(abd, buf, bufsize);

	spa_config_enter(spa, SCL_STATE, FTAG, RW_READER);
	vd = vdev_random_leaf(spa);
	if (vd) {
		n = spa_get_random(MMP_BLOCKS_PER_LABEL);
		l = spa_get_random(VDEV_LABELS);
		zio = zio_root(spa, NULL, NULL, flags);
		vd->vdev_mmp_pending = gethrtime();
		vdev_mmp_write(zio, vd, l, n, abd, mmp_write_done,
		    mmp, flags | ZIO_FLAG_DONT_PROPAGATE);
		zio_nowait(zio);
	}
	spa_config_exit(spa, SCL_STATE, FTAG);
}

static void
mmp_thread(dsl_pool_t *dp)
{
	mmp_thread_state_t *mmp = &dp->dp_mmp;
	spa_t *spa = dp->dp_spa;
	abd_t *abd;
	char *buf;
	int bufsize = (1ULL << MAX_UBERBLOCK_SHIFT);
	uint last_zfs_mmp_interval = zfs_mmp_interval;

	abd = abd_alloc(bufsize, B_TRUE);
	buf = kmem_alloc(bufsize, KM_SLEEP);
	bzero(buf, bufsize);

	mmp_thread_enter(mmp);

	mmp->mmp_last_write = gethrtime();
	dprintf("mmp_thread entered: pool %p\n", dp);

	for (;;) {
		hrtime_t start, next_time;

		if (mmp->mmp_thread_exiting)
			goto cleanup_and_exit;

		start = gethrtime();
		next_time = start + MSEC2NSEC(zfs_mmp_interval) /
		    vdev_count_leaves(dp->dp_spa);

		/*
		 * When MMP goes off => on, no writes occurred
		 * recently.  We update mmp_last_write to give
		 * us some time to try.
		 */
		if (!last_zfs_mmp_interval && zfs_mmp_interval) {
			dprintf("mmp_thread zfs_mmp_interval transtion: "
			    "pool %p last_zfs_mmp_interval %lu "
			    "zfs_mmp_interval %lu\n", dp,
			    last_zfs_mmp_interval, zfs_mmp_interval);
			mutex_enter(&mmp->mmp_io_lock);
			mmp->mmp_last_write = gethrtime();
			mutex_exit(&mmp->mmp_io_lock);
		}

		/*
		 * Check after the transition check above.
		 */
		if (zfs_mmp_interval && mmp->mmp_last_write < (start -
		    MSEC2NSEC(zfs_mmp_interval) * zfs_mmp_fail_intervals)) {
			dprintf("mmp suspending pool: pool %s zfs_mmp_interval %lu "
			    "start %llu mmp_last_write %llu interval_ns %llu "
			    "zfs_mmp_fail_intervals %lu\n", spa->spa_name,
			    zfs_mmp_interval, start, mmp->mmp_last_write, 
			    MSEC2NSEC(zfs_mmp_interval), zfs_mmp_fail_intervals);
			zio_suspend(spa, NULL);
		}

		mmp->mmp_last_write = gethrtime();
		if (zfs_mmp_interval)
			mmp_write_uberblock(dp, abd, buf, bufsize);

		if (gethrtime() >= next_time) {
			dprintf("mmp_thread skipped wait: pool %p start=%llu "
			    "next_time=%llu now=%llu\n", dp, start, next_time,
			    gethrtime());
			continue;
		}

		dprintf("mmp_thread entering wait: pool %p now=%llu "
		    "next_time=%lld\n", dp, gethrtime(), next_time);
		(void) cv_timedwait_hires(&mmp->mmp_thread_cv,
		    &mmp->mmp_thread_lock, next_time, NANOSEC,
		    CALLOUT_FLAG_ABSOLUTE);
	}

cleanup_and_exit:
	kmem_free(buf, bufsize);
	abd_free(abd);

	mmp_thread_exit(mmp, &mmp->mmp_thread);
}

#if defined(_KERNEL) && defined(HAVE_SPL)
EXPORT_SYMBOL(mmp_init);
EXPORT_SYMBOL(mmp_fini);
EXPORT_SYMBOL(mmp_thread_start);
EXPORT_SYMBOL(mmp_thread_stop);

module_param(zfs_mmp_fail_intervals, uint, 0644);
MODULE_PARM_DESC(zfs_mmp_fail_intervals, "Require MMP write in time "
"zfs_mmp_fail_intervals*zfs_mmp_interval");

module_param(zfs_mmp_interval, uint, 0644);
MODULE_PARM_DESC(zfs_mmp_interval, "Milliseconds between mmp writes to each leaf");
#endif
