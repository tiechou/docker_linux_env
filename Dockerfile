# This dockerfile uses the ubuntu iamge
# Author: tiechou

FROM ubuntu:14.04
 
MAINTAINER tiechou "answer.wlf@foxmail.com"  

RUN apt-get update                  \
    && apt-get -y install gcc       \
    && apt-get -y install g++       \
    && apt-get -y install scons     \
    && apt-get -y install automake  \
    && apt-get -y install autoconf  \
    && apt-get -y install libtool   \
    && apt-get -y install cmake

RUN apt-get -y install vim          \
    && apt-get -y install git       \
    && apt-get -y install ctags     \
    && apt-get -y install tree      \
    && apt-get -y install wget      \
    && apt-get -y install curl      \
    && apt-get -y install ssh       \
    && apt-get -y install sysstat
