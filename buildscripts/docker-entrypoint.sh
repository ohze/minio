#!/bin/sh
#
# Minio Cloud Storage, (C) 2017 Minio, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# fix issue: in rancher with docker 1.11.2 (not occur on docker 1.12.1), minio1 can not ping minio2
# so this script hang on docker_wait_hosts
# fix by adding SERVICE_N_STACK env variable, ex: minio3.minio
fix_resolv() {
    if [ "$SERVICE_N_STACK" != "" ]; then
        STACK=${SERVICE_N_STACK/*./}
        sed /etc/resolv.conf \
            -e "s|^search .*|search ${STACK}.rancher.internal rancher.internal ${SERVICE_N_STACK}.rancher.internal|" \
            > /tmp/resolv.conf
        cat /tmp/resolv.conf > /etc/resolv.conf
    fi
}

# If command starts with an option, prepend minio.
if [ "${1}" != "minio" ]; then
    if [ -n "${1}" ]; then
        set -- minio "$@"
    fi
fi

# Wait for all the hosts to come online and have
# their DNS entries populated properly.
docker_wait_hosts() {
    hosts="$@"
    num_hosts=0
    # Count number of hosts in arguments.
    for host in $hosts; do
        [ $(echo "$host" | grep -E "^http") ] || continue
        num_hosts=$((num_hosts+1))
    done
    if [ $num_hosts -gt 0 ]; then
        echo -n "Waiting for all hosts to resolve..."
        while true; do
            fix_resolv
            x=0
            for host in $hosts; do
                [ $(echo "$host" | grep -E "^http") ] || continue
                # Extract the domain.
                host=$(echo $host | sed -e 's/^http[s]\?:\/\/\([^\/]\+\).*/\1/')
                echo -n .
                val=$(ping -c 1 $host 2>/dev/null)
                if [ $? != 0 ]; then
                    echo "Failed to lookup $host"
                    continue
                fi
                x=$((x+1))
            done
            # Provided hosts same as successful hosts, should break out.
            test $x -eq $num_hosts && break
            echo "Failed to resolve hosts.. retrying after 1 second."
            sleep 1
        done
        echo "All hosts are resolving proceeding to initialize Minio."
    fi
}

## Look for docker secrets in default documented location.
docker_secrets_env() {
    local MINIO_ACCESS_KEY_FILE="/run/secrets/access_key"
    local MINIO_SECRET_KEY_FILE="/run/secrets/secret_key"

    if [ -f $MINIO_ACCESS_KEY_FILE -a -f $MINIO_SECRET_KEY_FILE ]; then
        if [ -f $MINIO_ACCESS_KEY_FILE ]; then
            export MINIO_ACCESS_KEY="$(cat "$MINIO_ACCESS_KEY_FILE")"
        fi
        if [ -f $MINIO_SECRET_KEY_FILE ]; then
            export MINIO_SECRET_KEY="$(cat "$MINIO_SECRET_KEY_FILE")"
        fi
    fi
}

## Set access env from secrets if necessary.
docker_secrets_env

## Wait for all the hosts to come online.
docker_wait_hosts "$@"

exec "$@"
