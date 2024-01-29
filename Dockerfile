FROM ruby:3.3.0

RUN mkdir /app
WORKDIR /app
COPY . .

RUN gem build deadfinder.gemspec
RUN gem install deadfinder-*.gem

CMD ["deadfinder"]
