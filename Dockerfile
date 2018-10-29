FROM ruby:alpine

WORKDIR /usr/src/app
COPY . .
RUN addgroup -S app && adduser -S -G app app
RUN mkdir -p tmp log && chown app:app tmp log

RUN apk add build-base ghostscript git

RUN bundle install
RUN apk del build-base git

EXPOSE 9292
USER app
CMD bundle exec puma config.ru
