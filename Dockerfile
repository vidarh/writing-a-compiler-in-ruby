FROM debian:jessie
RUN apt-get update
RUN apt-get -y install ruby ruby-dev build-essential wget curl strace gdb gcc-multilib

# For Nokogiri:
#RUN apt-get install -y libopenssl-ruby libxslt-dev libxml2-dev

# For jq
RUN apt-get install -y jq

RUN gem install -n /usr/bin bundler
RUN gem install -n /usr/bin rake

VOLUME ["/app"]

WORKDIR /app

