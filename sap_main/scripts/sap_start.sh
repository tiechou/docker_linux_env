base_home=`readlink -f "$(dirname "$0")/../"`

export LD_LIBRARY_PATH=${base_home}/lib:$LD_LIBRARY_PATH
mkdir -p ${base_home}/logs
mkdir -p ${base_home}/www

${base_home}/bin/sap_server -c ${base_home}/conf/sap_server_app.cfg -k start -d -l ${base_home}/conf/sap_server_log.cfg
