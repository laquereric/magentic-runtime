# magentic-runtime -- the local governed-flow runtime (Docker Desktop).
FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential libsqlite3-dev git ca-certificates && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . /app
# In the image, resolve rr-grammar from git (the ../rr-grammar path dep is local-dev only).
RUN printf 'source "https://rubygems.org"\ngemspec\ngem "rr-grammar", git: "https://github.com/laquereric/rr-grammar.git"\n' > Gemfile && \
    bundle install
EXPOSE 4700
ENV MAGENTIC_ROOT=/work
ENTRYPOINT ["bundle", "exec", "magentic"]
# Default: serve the workspace over WebDAV (no volume mount; local container == k3s pod).
CMD ["serve", "--root", "/work", "--port", "4700"]