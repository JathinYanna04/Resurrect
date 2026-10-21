# Test image: official Termux userland plus the test dependencies, so test
# runs do not download packages every time.
#   docker build -t resurrect-test tests/termux-docker
FROM termux/termux-docker:x86_64
USER system
SHELL ["/data/data/com.termux/files/usr/bin/bash", "-c"]
ENV LD_PRELOAD=/data/data/com.termux/files/usr/lib/libtermux-exec-ld-preload.so
RUN pkg update -y \
 && pkg install -y git python util-linux procps jq openssl-tool sqlite curl cronie openssh iproute2 rsync \
 && git -c advice.detachedHead=false clone -q --depth 1 --branch v1.11.1 https://github.com/bats-core/bats-core $PREFIX/tmp/bats \
 && $PREFIX/tmp/bats/install.sh $PREFIX \
 && rm -rf $PREFIX/tmp/bats $PREFIX/var/cache/apt/archives/*.deb
ENTRYPOINT []
