# Build environment for the Aleph One Linux dedicated server release.
#
# Debian 11 (Bullseye) with glibc 2.31 ensures broad compatibility across
# Linux server distributions (Ubuntu 20.04+, Debian 11+, RHEL/Rocky 9+).
FROM debian:11

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      autoconf \
      automake \
      libtool \
      pkg-config \
      ca-certificates \
      file \
      libboost-filesystem-dev \
      libboost-system-dev \
      libboost-dev \
      libsdl2-dev \
      libsdl2-ttf-dev \
      libopenal-dev \
      libsndfile1-dev \
      libpng-dev \
      zlib1g-dev \
      libasio-dev \
 && rm -rf /var/lib/apt/lists/*
