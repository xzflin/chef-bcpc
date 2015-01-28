#!/bin/bash

hash -r

wait_for_ssh(){
  local hostname="$1"
  local min=${2:-1} max=${3:-10}

  if [ -z "${hostname}" ] ; then return 1 ; fi
  exec 3>&2
  exec 2>/dev/null
  while true ; do
    if echo > /dev/tcp/${hostname}/22 ; then
      return 0
    fi
    sleep $(( $RANDOM % $max + $min ))
  done
  exec 2>&3
  exec 3>&-
}

bootstrap_heads(){
  time -p wait_for_ssh 10.0.100.11
  echo "Configuring temporary hosts entry for chef server"
  read -d %% ent <<EoF
# Added by ${0##*/}
10.0.100.3 bcpc-bootstrap
%%
EoF
  echo $ent
  ssh -ostricthostkeychecking=no -i "${keyfile}" -lroot 10.0.100.11 <<EoF
  if ! getent ahosts bcpc-bootstrap &> /dev/null ; then
  cat <<EoS >> /etc/hosts
$ent
EoS
  fi
  getent hosts bcpc-bootstrap
EoF
  knife bootstrap --bootstrap-no-proxy "${chef_server_host}" --bootstrap-proxy "${https_proxy}" \
    -i "${keyfile}" -x root --node-ssl-verify-mode=none \
    --bootstrap-wget-options "--no-check-certificate" \
    -r 'role[BCPC-Headnode]' -E Test-Laptop 10.0.100.11
    knife actor map
    # TODO: hardcode nodename prob bad...
    knife group add actor admins bcpc-vm1.local.lan
}

# TODO: This and above name together are confusing!
bootstrap_worker(){
  local ip="$1"
  if [ -z "${ip}" ] ; then return 1 ; fi
  time -p wait_for_ssh "${ip}"
  knife bootstrap --bootstrap-no-proxy "${chef_server_host}" --bootstrap-proxy "${https_proxy}" \
    -i "${keyfile}" -x root \
    --bootstrap-wget-options "--no-check-certificate" \
    -r 'role[BCPC-Worknode]' -E Test-Laptop "$ip"
}

if [[ -f ./proxy_setup.sh ]]; then
  . ./proxy_setup.sh
  export -n http{,s}_proxy  # do not interfere with subsequent calls to knife
fi

chef_server_host=bcpc-bootstrap
keyfile=~/.ssh/id_rsa.bcpc

bootstrap_heads
set -e
ssh -i "${keyfile}" -lroot 10.0.100.11 chef-client

echo "Waiting to bootstrap workers"
set -x
for ip in 10.0.100.{12..13} ; do eval "bootstrap_worker ${ip} &" ; done
wait
