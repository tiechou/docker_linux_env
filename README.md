# docker_linux_env

构建镜像：
docker build -t tiechou/linux_env docker_linux_env
        
启动容器：

docker run -it --rm=true --memory=4g --publish=9981:9981 --volume=${HOME}:/home/admin --workdir=/home/admin/code tiechou/linux_env /bin/bash

docker exec -it --privileged=true $(docker ps | grep -v CONTAINER | awk '{ print $1}') /bin/bash
