FROM crystallang/crystal:1.1.1-alpine

ARG PLACE_COMMIT="DEV"
ARG PLACE_VERSION="DEV"

RUN apk add --no-cache yaml-static

WORKDIR /app

# Install shards for caching
COPY shard.yml shard.yml
COPY shard.lock shard.lock

RUN shards install --production --ignore-crystal-version

# Add src
COPY ./src /app/src

# Build application
ENV UNAME_AT_COMPILE_TIME=true
RUN PLACE_COMMIT=$PLACE_COMMIT \
    PLACE_VERSION=$PLACE_VERSION \
    crystal build --release --no-debug --error-trace /app/src/app.cr -o dispatch

# Extract dependencies
RUN ldd dispatch | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

# Build a minimal docker image
FROM scratch
WORKDIR /
ENV PATH=$PATH:/
COPY --from=0 /app/deps /
COPY --from=0 /app/dispatch /dispatch
COPY --from=0 /etc/hosts /etc/hosts

# This is required for Timezone support
COPY --from=0 /usr/share/zoneinfo/ /usr/share/zoneinfo/


# Run the app binding on port 8080
EXPOSE 8080
ENTRYPOINT ["/dispatch"]
HEALTHCHECK CMD ["/dispatch", "-c", "http://127.0.0.1:8080/api/server/healthz"]
CMD ["/dispatch", "-b", "0.0.0.0", "-p", "8080"]
