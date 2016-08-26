FROM debian:jessie
RUN apt-get update
RUN apt-get -y install ruby2.1 ruby2.1-dev rubygems build-essential wget curl strace gdb gcc-multilib jq

RUN gem install -n /usr/bin bundler
RUN gem install -n /usr/bin rake

VOLUME ["/app"]

WORKDIR /app

