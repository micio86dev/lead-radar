# One-shot scheduled jobs, used by the local compose scheduler and by the Railway cron services.
#
# One image, two services (see scripts/cron-entrypoint.sh):
#   CRON_MODE=prepare  hourly reply-queue preparation  → scripts/prepare-queue.sh
#   CRON_MODE=nightly  00:00 UTC opportunity import     → scripts/apify-community-sweep.py --scheduled
#
# The nightly mode is Python because the sweep reads the API, waits for terminal runs and re-ingests
# datasets; the hourly mode stays bash + curl.
FROM alpine:3.20

RUN apk add --no-cache bash curl python3

COPY scripts/cron-entrypoint.sh /usr/local/bin/cron-entrypoint.sh
COPY scripts/prepare-queue.sh /usr/local/bin/prepare-queue.sh
COPY scripts/apify-community-sweep.py /usr/local/bin/apify-community-sweep.py
RUN chmod +x /usr/local/bin/cron-entrypoint.sh \
    /usr/local/bin/prepare-queue.sh \
    /usr/local/bin/apify-community-sweep.py

# Railway cron services run the start command once per schedule and expect it to exit.
ENTRYPOINT ["/usr/local/bin/cron-entrypoint.sh"]
