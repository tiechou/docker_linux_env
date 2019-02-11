# Pull base image  
FROM ubuntu:14.04
 
MAINTAINER tiechou "answer.wlf@foxmail.com"  

RUN apt-get update
  
RUN apt-get -y install gcc && apt-get -y install g++
RUN apt-get -y install automake && apt-get -y install autoconf && apt-get -y install libtool
RUN apt-get -y install cmake
RUN apt-get -y install vim
RUN apt-get -y install git
RUN apt-get -y install ctags
RUN apt-get -y install tree 
RUN apt-get -y install wget 
RUN apt-get -y install curl
RUN apt-get -y install ssh
