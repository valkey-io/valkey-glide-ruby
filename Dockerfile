FROM ruby:3.3.0-slim

WORKDIR /app

# Install build tools and git for gemspec and native extensions
RUN apt-get update && apt-get install -y build-essential libffi-dev git

# Copy gem-related files and libraries
COPY Gemfile Gemfile.lock valkey.gemspec ./
COPY lib/ ./lib/

# Install bundler and all dependencies
RUN gem install bundler && bundle install

# Build and install the valkey gem itself
RUN gem build valkey.gemspec && gem install valkey-*.gem

# Copy the rest of the project (scripts, tests, README, etc.)
COPY . .

# Run sample script using Bundler
CMD ["bundle", "exec", "ruby", "test_valkey.rb"]