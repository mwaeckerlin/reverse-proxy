#!/bin/sh
/usr/sbin/crond -b -L /proc/1/fd/1 -l ${CRON_DEBUG:-0} -M /bin/logger
