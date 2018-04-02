#!/bin/bash

#Set OpenStack Env
#Following OpenStack auth environment variables must be set for your environment
#export OS_PROJECT_ID=
#export OS_REGION_NAME=
#export OS_USER_DOMAIN_NAME=
#export OS_PROJECT_NAME=
#export OS_IDENTITY_API_VERSION=3
#export OS_PASSWORD=
#export OS_AUTH_URL=
#export OS_USERNAME=
#export OS_INTERFACE=


TS=`date +%Y%m%d-%H%M`


if [ -z ${ETCD_CLUSTER+x} ]; then
	echo "[ERROR] - Etcd Enpoints not defined, Exiting"
	exit 1;
fi

if [ -z ${OBJ_CONTAINER+x} ]; then
	OBJ_CONTAINER=etcd-snapshots
fi

if [ -z ${EXPIRE_TIME+x} ]; then
	EXPIRE_TIME=432000
fi

if [ -z ${CACERT+x} ]; then
	CACERT="/etc/secret-volume/etcd-client-ca.crt"
fi

if openstack container list --insecure -f value |grep $OBJ_CONTAINER; then
	echo "$OBJ_CONTAINER exists"
else
	echo "$OBJ_CONTAINER doesnt exists"
	echo "Creating $OBJ_CONTAINER"
	openstack container create $OBJ_CONTAINER --insecure
fi

if [[ "$USE_INSECURE" == "true" ]]; then
	ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints=${ETCD_CLUSTER} --insecure-skip-tls-verify=true --insecure-transport=false --write-out=table snapshot save /tmp/snapshot${TS}.db
else
	ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints=${ETCD_CLUSTER} --cacert="${CACERT}" --write-out=table snapshot save /tmp/snapshot${TS}.db
	
fi
CREATE_SEC=`date +%s`

openstack object create --name snapshot${TS}.db $OBJ_CONTAINER /tmp/snapshot${TS}.db --insecure
openstack object set --property CREATE=$CREATE_SEC $OBJ_CONTAINER snapshot${TS}.db --insecure

for i in `openstack object list --all -f value $OBJ_CONTAINER --insecure |grep -v Name`
do
	eval `openstack object show $OBJ_CONTAINER $i -f value --insecure |grep Create`
	AGE=$((`date +%s` - $Create))
	if (( $EXPIRE_TIME < $AGE )); then
		echo "Expiring $i"
		openstack object delete $OBJ_CONTAINER $i --insecure
	fi

done
