# syntax=docker/dockerfile:1
#
# Test the SDK on a real, supported Ruby (3.x). The local dev box may only have an
# EOL Ruby; this image runs the guardrail (rubocop + unit + security suites) on the
# version the gem actually targets.
#
#   docker build -t api2convert-ruby .
#   docker run --rm api2convert-ruby                       # rake check on the default Ruby
#   docker build --build-arg RUBY_VERSION=3.4 -t a2c:3.4 . # pin another version
#   docker run --rm -e API2CONVERT_API_KEY=<key> api2convert-ruby bundle exec rake spec:live
#
ARG RUBY_VERSION=3.3
FROM ruby:${RUBY_VERSION}

WORKDIR /sdk

# Install gems first for layer caching. The gemspec requires lib/api2convert/version.rb
# for the version constant, so copy the metadata + that one file before the full source.
COPY Gemfile api2convert.gemspec ./
COPY lib/api2convert/version.rb lib/api2convert/version.rb
RUN bundle install

# Then the rest of the source.
COPY . .

# Default: lint + unit + independent security suite — all must pass. Live conformance
# is opt-in (needs API2CONVERT_API_KEY): `bundle exec rake spec:live`.
CMD ["bundle", "exec", "rake", "check"]
