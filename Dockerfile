# Pull base image  
FROM ubuntu:14.04
 
MAINTAINER TAKCHICHAN "answer.wlf@foxmail.com"  

RUN apt-get update
  
# Install curl  
RUN apt-get -y install gcc && apt-get -y install g++
RUN apt-get -y install automake && apt-get -y install autoconf && apt-get -y install libtool
RUN apt-get -y install wget && apt-get -y install curl
RUN apt-get -y install vim
RUN apt-get -y install git
RUN apt-get -y install ssh
 
RUN mkdir /var/run/sshd
 
# change sshd listen port
RUN sed -i 's/Port[ ]*22/Port 36000/' /etc/ssh/sshd_config
RUN echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
 
# add user
RUN mkdir /home/admin
RUN useradd -s /bin/bash admin
RUN echo "admin:123456" | chpasswd
 
# Container should expose ports.  
EXPOSE 36000
CMD ["/usr/sbin/sshd", "-D"]

