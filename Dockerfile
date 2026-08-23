# Development image for running the gem's test suite exactly as CI does.
# RUBY_VERSION and AR_VERSION mirror the CI matrix axes, so a local run can
# reproduce any cell of it:
#   docker compose build --build-arg RUBY_VERSION=3.3
#   AR_VERSION=7.2 docker compose run --rm test
ARG RUBY_VERSION=3.4
FROM ruby:${RUBY_VERSION}-slim

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential git libpq-dev libsqlite3-dev libyaml-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /gem

# The lockfile is untracked on purpose (the CI matrix pins ActiveRecord through
# AR_VERSION), so dependencies resolve at container start, not at image build.
COPY Gemfile statecraft.gemspec ./
COPY lib/statecraft/version.rb lib/statecraft/version.rb

CMD ["bash", "-lc", "bundle install --quiet && bundle exec rspec"]
