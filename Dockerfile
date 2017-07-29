FROM debian:jessie

# Needed to be able to run Valgrind on m32 binaries
RUN dpkg --add-architecture i386

RUN apt-get update && apt-get -y install ruby2.1 ruby2.1-dev rubygems build-essential wget curl strace gdb gcc-multilib jq valgrind libc6-dbg:i386

RUN gem install -n /usr/bin bundler
RUN gem install -n /usr/bin rake

VOLUME ["/app"]

WORKDIR /app

