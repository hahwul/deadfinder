FROM ruby:3.1

RUN gem install deadfinder
CMD ["deadfinder"]