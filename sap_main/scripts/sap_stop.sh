base_home=`readlink -f "$(dirname "$0")/../"`

${base_home}/bin/sap_server -c ${base_home}/conf/sap_server_app.cfg -l ${base_home}/conf/sap_server_log.cfg -k stop
rm -f ${base_home}/www/*.html
