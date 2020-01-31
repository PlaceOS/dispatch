FROM crystallang/crystal:latest
ADD . /src
WORKDIR /src

# Build App
RUN shards build --error-trace --production

# Run the app binding on port 8080
EXPOSE 8080
ENTRYPOINT ["/src/bin/app"]
CMD ["/src/bin/app", "-b", "0.0.0.0", "-p", "8080"]
