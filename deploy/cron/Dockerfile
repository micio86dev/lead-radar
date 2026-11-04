# One-shot preparation job, used by the local compose scheduler and by the Railway cron service.
# The same scripts/prepare-queue.sh runs in both places: bounded batch, auto cooldown, JSON logging.
FROM alpine:3.20

RUN apk add --no-cache bash curl

COPY scripts/prepare-queue.sh /usr/local/bin/prepare-queue.sh
RUN chmod +x /usr/local/bin/prepare-queue.sh

# Railway cron services run the start command once per schedule and expect it to exit.
ENTRYPOINT ["/usr/local/bin/prepare-queue.sh"]
