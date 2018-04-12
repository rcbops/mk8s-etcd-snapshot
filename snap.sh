#!/bin/bash

#Takes snapshot of Kubernetes Etcd database and uses mk8s ETS Service to push the file to Object Storage

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

if [ -z ${ETCD_CA_CRT+x} ]; then
	CACERT="/etc/secret-volume/etcd-client-ca.crt"
fi

if [ -z ${ETCD_CLIENT_CRT+x} ]; then
	ETCD_CLIENT_CRT="/etc/secret-volume/etcd-client.crt"
fi

if [ -z ${ETCD_CLIENT_KEY+x} ]; then
	ETCD_CLIENT_KEY="/etc/secret-volume/etcd-client.key"
fi


if [[ "$USE_INSECURE" == "true" ]]; then
	ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints=${ETCD_CLUSTER} --insecure-skip-tls-verify=true --insecure-transport=false --write-out=table snapshot save /tmp/snapshot${TS}.db
	if [ $? == 1 ]; then
		echo "ERROR - Snapshot failed"
		exit 1
	fi
else
	ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints=${ETCD_CLUSTER} --cacert="${ETCD_CA_CRT}" --cert-file="${ETCD_CLIENT_CRT}" --key-file="${ETCD_CLIENT_KEY}"  --write-out=table snapshot save /tmp/snapshot${TS}.db
	if [ $? == 1 ]; then
		echo "ERROR - Snapshot failed"
		exit 1
	fi

fi
CREATE_SEC=`date +%s`

#hit the ETA for a url/token on the ETP
AUTH_URL=`curl -q http://localhost:8887/auth/v3/auth/tokens | grep -o '<a .*href=.*>' | sed -e 's/<a /\n<a /g' | sed -e 's/<a .*href=['"'"'"]//' -e 's/["'"'"'].*$//' -e '/^$/ d'`

#hit the ETP through the ETA via  Referer to get a list of endpoints
OBJ_URL=`curl -L -k -H "Referer: ${AUTH_URL}" http://localhost:8887/auth/v3/auth/tokens |jq '[.token.catalog[] |  select(.name=="swift") | .endpoints[] | select(.interface=="public") |.url]' | awk -F\" '{print $2}'`
echo $OBJ_URL

#hit the ETG to get another token
TOKEN=`curl http://169.254.169.254/openstack/latest/vendor_data2.json  |jq '.etg.token' |awk -F\" '{print $2}'`
echo "TOKEN: $TOKEN"

#Validate Object container exists and create if it doesn't
if curl -L  -k -X GET -H "X-Auth-Token:${TOKEN}" ${OBJ_URL} |grep ${OBJ_CONTAINER}; then
	echo "$OBJ_CONTAINER exists"
else
	echo "$OBJ_CONTAINER doesnt exists"
	echo "Creating $OBJ_CONTAINER"
	curl -L  -k -X PUT -H "X-Container-Meta-Book: K8S-Etcd-Snapshots" -H "X-Auth-Token:${TOKEN}" ${OBJ_URL}/${OBJ_CONTAINER}
fi

#hit the ETP endpoint to push snapshot
curl -L  -k -X PUT -H "X-Delete-After:$EXPIRE_TIME" -H "X-Auth-Token:${TOKEN}" ${OBJ_URL}/${OBJ_CONTAINER}/snapshot${TS}.db -T /tmp/snapshot${TS}.db

