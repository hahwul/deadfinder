FROM ruby:3.2.2

RUN mkdir /app
WORKDIR /app
COPY . .

RUN gem build deadfinder.gemspec
RUN gem install deadfinder-*.gem

CMD ["deadfinder"]
