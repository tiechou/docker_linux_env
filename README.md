# docker_linux_env

构建镜像：
docker build -t ubuntu:devel ./
        
启动容器：
docker run -it -p 36000:36000 --privileged=true -v /opt/projects:/home/takchi/ ubuntu:devel
        
ssh登录：
ssh -p 36000 takchi@${HOST_IP}    
