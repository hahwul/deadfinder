FROM ruby:4.0.1-slim

RUN apt-get update && apt-get install -y \
    build-essential \
    libcurl4-openssl-dev \
    libxml2-dev \
    libxslt-dev \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app
COPY . .

RUN gem build deadfinder.gemspec
RUN gem install deadfinder-*.gem

CMD ["deadfinder"]
