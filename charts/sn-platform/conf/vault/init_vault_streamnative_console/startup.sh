#!/usr/bin/env sh
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

export VAULT_APPROLE_SUPER_NAME=apachepulsar
export VAULT_SUPER_USER_NAME=admin
# generate console password
if [ "$addInstance" = false ];then
    export VAULT_SUPER_USER_PASSWORD=$(cat /dev/urandom | base64 | tr -dc '0-9a-zA-Z' | head -c12)
fi
#export VAULT_ADDR="http://127.0.0.1:8200"

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo $BASEDIR
TMP_DIR="/tmp"
addInstance=$1
organization=$2
instance=$3
echo $addInstance, $organization, $instance

if [ "$addInstance" = true ];then
    export VAULT_ADDR=$4
fi

vault login $ROOT_TOKEN
vault auth enable userpass
vault auth enable approle
userMountAccessor=$(vault auth list | grep auth_userpass | awk '{print $3}')
echo $userMountAccessor
serviceAccountMountAccessor=$(vault auth list | grep auth_approle | awk '{print $3}')
echo $serviceAccountMountAccessor
sed "s#MOUNT_ACCESSOR#$userMountAccessor#g" $BASEDIR/user-template.json > $TMP_DIR/user-template.json
sed "s#MOUNT_ACCESSOR#$userMountAccessor#g" $BASEDIR/user.hcl > $TMP_DIR/user.hcl
sed "s#MOUNT_ACCESSOR#$userMountAccessor#g" $BASEDIR/super-user.hcl > $TMP_DIR/super-user.hcl
sed "s#MOUNT_ACCESSOR#$userMountAccessor#g" $BASEDIR/super-user-template.json > $TMP_DIR/super-user-template.json
sed "s#MOUNT_ACCESSOR#$serviceAccountMountAccessor#g" $BASEDIR/service-account-template.json > $TMP_DIR/service-account-template.json
sed "s#MOUNT_ACCESSOR#$serviceAccountMountAccessor#g" $BASEDIR/service-account.hcl > $TMP_DIR/service-account.hcl
sed "s#MOUNT_ACCESSOR#$serviceAccountMountAccessor#g" $BASEDIR/super-service-account.hcl > $TMP_DIR/super-service-account.hcl
sed "s#MOUNT_ACCESSOR#$serviceAccountMountAccessor#g" $BASEDIR/super-service-account-template.json > $TMP_DIR/super-service-account-template.json


if [ -n "$organization" ] && [ -n "$instance" ];then
    sed "s#MOUNT_ACCESSOR#$serviceAccountMountAccessor#g" $BASEDIR/organization-instance-service-account-template.json > $TMP_DIR/organization-instance-service-account-template.json
    sed "s#ORGANZATION#$organization#g" $BASEDIR/organization-instance-service-account-template.json > $TMP_DIR/organization-instance-service-account-template.json
    sed "s#INSTANCE#$instance#g" $BASEDIR/organization-instance-service-account-template.json > $TMP_DIR/organization-instance-service-account-template.json
    sed "s#ORGANZATION#$organization#g" $BASEDIR/organization-instance-service-account-template.json > $TMP_DIR/organization-instance-service-account-template.json
    sed "s#MOUNT_ACCESSOR#$serviceAccountMountAccessor#g" $BASEDIR/organization-instance-super-service-account-template.json > $TMP_DIR/organization-instance-super-service-account-template.json
    sed "s#INSTANCE#$instance#g" $BASEDIR/organization-instance-super-service-account-template.json > $TMP_DIR/organization-instance-super-service-account-template.json
fi

superApproleName=$VAULT_APPROLE_SUPER_NAME
superUser=$VAULT_SUPER_USER_NAME
superPassword=$VAULT_SUPER_USER_PASSWORD
if [ "$addInstance" = false ];then
    vault policy write service-account $TMP_DIR/service-account.hcl
    vault write identity/entity name="service-account" policies="service-account"
    canonicalId=$(vault read identity/entity/name/service-account | grep -v _id | grep id | awk '{print $2}')
    vault write identity/entity-alias name="service-account"  mount_accessor=$serviceAccountMountAccessor canonical_id=$canonicalId metadata=name='service-account'
    vault write identity/oidc/key/service-account name=service-account rotation_period=24h verification_ttl=24h
    vault write identity/oidc/role/service-account key=service-account ttl=12h template=@$TMP_DIR/service-account-template.json
    serviceAccountClientId=$(vault read identity/oidc/role/service-account | grep client_id |  awk '{print $2}')
    vault write identity/oidc/key/service-account name=service-account rotation_period=24h verification_ttl=24h allowed_client_ids=$serviceAccountClientId

    vault policy write super-service-account $TMP_DIR/super-service-account.hcl
    vault write identity/entity name="super-service-account" policies="super-service-account"
    canonicalId=$(vault read identity/entity/name/super-service-account | grep -v _id | grep id | awk '{print $2}')
    vault write identity/entity-alias name="super-service-account"  mount_accessor=$serviceAccountMountAccessor canonical_id=$canonicalId metadata=name='super-service-account'
    vault write identity/oidc/key/super-service-account name=super-service-account rotation_period=24h verification_ttl=24h
    vault write identity/oidc/role/super-service-account key=super-service-account ttl=12h template=@$TMP_DIR/super-service-account-template.json
    superServiceAccountClientId=$(vault read identity/oidc/role/super-service-account | grep client_id |  awk '{print $2}')
    vault write identity/oidc/key/super-service-account name=super-service-account rotation_period=24h verification_ttl=24h allowed_client_ids=$superServiceAccountClientId

    vault write auth/approle/role/$superApproleName policies=super-service-account

    # set a short ttl for approle to avoid vault oom caused by frequent lease generation
    vault auth tune -default-lease-ttl=5m approle/

    vault policy write super-user $TMP_DIR/super-user.hcl
    vault write auth/userpass/users/$superUser password="$superPassword" policies="super-user"
    vault write identity/entity name="super-user" policies="super-user"
    vault write identity/oidc/key/super-user name=super-user rotation_period=24h verification_ttl=24h
    vault write identity/oidc/role/super-user key=super-user ttl=12h template=@$TMP_DIR/super-user-template.json
    superUserClientId=$(vault read identity/oidc/role/super-user | grep client_id |  awk '{print $2}')
    vault write identity/oidc/key/super-user name=super-user rotation_period=24h verification_ttl=24h allowed_client_ids=$superUserClientId

    vault policy write user $TMP_DIR/user.hcl
    vault write identity/entity name="user" policies="user"
    vault write identity/oidc/key/user name=user rotation_period=24h verification_ttl=24h
    vault write identity/oidc/role/user key=user ttl=12h template=@$TMP_DIR/user-template.json
    userClientId=$(vault read identity/oidc/role/user | grep client_id |  awk '{print $2}')
    vault write identity/oidc/key/user name=user rotation_period=24h verification_ttl=24h allowed_client_ids=$userClientId
fi

serviceAccountClientId=$(vault read identity/oidc/role/service-account | grep client_id |  awk '{print $2}')
superServiceAccountClientId=$(vault read identity/oidc/role/super-service-account | grep client_id |  awk '{print $2}')

if [ -n "$organization" ] && [ -n "$instance" ];then
    vault write identity/entity name="service-account-$organization-$instance" policies="service-account"
    canonicalId=$(vault read identity/entity/name/service-account-$organization-$instance | grep -v _id | grep id | awk '{print $2}')
    vault write identity/entity-alias name="service-account-$organization-$instance"  mount_accessor=$serviceAccountMountAccessor canonical_id=$canonicalId metadata=name="service-account-$organization-$instance"
    vault write identity/oidc/key/service-account-$organization-$instance name=service-account-$organization-$instance rotation_period=24h verification_ttl=24h
    vault write identity/oidc/role/service-account-$organization-$instance key=service-account-$organization-$instance ttl=12h template=@$TMP_DIR/organization-instance-service-account-template.json
    orgInstanceServiceAccountClientId=$(vault read identity/oidc/role/service-account-$organization-$instance | grep client_id |  awk '{print $2}')
    vault write identity/oidc/key/service-account-$organization-$instance name=service-account-$organization-$instance rotation_period=24h verification_ttl=24h allowed_client_ids=$orgInstanceServiceAccountClientId


    vault write identity/entity name="super-service-account-$organization-$instance" policies="super-service-account"
    canonicalId=$(vault read identity/entity/name/super-service-account-$organization-$instance | grep -v _id | grep id | awk '{print $2}')
    vault write identity/entity-alias name="super-service-account-$orgaization-$instance"  mount_accessor=$serviceAccountMountAccessor canonical_id=$canonicalId metadata=name="super-service-account-$organization-$instance"
    vault write identity/oidc/key/super-service-account-$organization-$instance name=super-service-account-$organization-$instance rotation_period=24h verification_ttl=24h
    vault write identity/oidc/role/super-service-account-$organization-$instance key=super-service-account-$organization-$instance ttl=12h template=@$TMP_DIR/organization-instance-super-service-account-template.json
    orgInstanceSuperServiceAccountClientId=$(vault read identity/oidc/role/super-service-account-$organization-$instance | grep client_id |  awk '{print $2}')
    vault write identity/oidc/key/super-service-account-$organization-$instance name=super-service-account-$organization-$instance rotation_period=24h verification_ttl=24h allowed_client_ids=$orgInstanceSuperServiceAccountClientId
fi

userClientId=$(vault read identity/oidc/role/user | grep client_id |  awk '{print $2}')
superUserClientId=$(vault read identity/oidc/role/super-user | grep client_id |  awk '{print $2}')
loginInfo=$(vault login -method=userpass username=$superUser password=$superPassword)
superToken=$(echo "$loginInfo" | grep  -v '_' | grep 'token  ' | awk '{print $2}')
export VAULT_SUPER_USER_TOKEN=$superToken
export VAULT_USERPASS_MOUNT_ACCESSOR=$userMountAccessor
export VAULT_APPROLE_MOUNT_ACCESSOR=$serviceAccountMountAccessor
export VAULT_APPROLE_ROLE_ID=$(vault read auth/approle/role/$superApproleName/role-id | grep role_id | awk '{print $2}')
export VAULT_APPROLE_SECRET_ID=$(vault write -f auth/approle/role/$superApproleName/secret-id | grep -v secret_id_ | grep secret_id | awk '{print $2}')
approleLoginInfo=$(vault write auth/approle/login role_id=$VAULT_APPROLE_ROLE_ID secret_id=$VAULT_APPROLE_SECRET_ID)
export VAULT_APPROLE_SUPER_TOKEN=$(echo "$approleLoginInfo" | grep 'token ' | awk '{print $2}')


echo "RESULT is as below: "
echo "VAULT_USERPASS_MOUNT_ACCESSOR: "$VAULT_USERPASS_MOUNT_ACCESSOR
echo "VAULT_SUPER_USER_NAME: "$VAULT_SUPER_USER_NAME
echo "VAULT_SUPER_USER_PASSWORD: "$VAULT_SUPER_USER_PASSWORD
echo "VAULT_SUPER_USER_TOKEN: "$VAULT_SUPER_USER_TOKEN
echo "VAULT_APPROLE_MOUNT_ACCESSOR: "$VAULT_APPROLE_MOUNT_ACCESSOR
echo "VAULT_APPROLE_ROLE_ID: "$VAULT_APPROLE_ROLE_ID
echo "VAULT_APPROLE_SECRET_ID: "$VAULT_APPROLE_SECRET_ID
echo "VAULT_APPROLE_SUPER_NAME: "$VAULT_APPROLE_SUPER_NAME
echo "VAULT_APPROLE_SUPER_TOKEN: "$VAULT_APPROLE_SUPER_TOKEN
echo "oidc info ====="
echo "VAULT_HOST="$VAULT_ADDR >> /tmp/pm_env
echo "VAULT_USERPASS_MOUNT_ACCESSOR="$VAULT_USERPASS_MOUNT_ACCESSOR >> /tmp/pm_env
echo "VAULT_SUPER_USER_NAME="$VAULT_SUPER_USER_NAME >> /tmp/pm_env
echo "VAULT_SUPER_USER_PASSWORD="$VAULT_SUPER_USER_PASSWORD >> /tmp/pm_env
echo "VAULT_SUPER_USER_TOKEN="$VAULT_SUPER_USER_TOKEN >> /tmp/pm_env
echo "VAULT_APPROLE_MOUNT_ACCESSOR="$VAULT_APPROLE_MOUNT_ACCESSOR >> /tmp/pm_env
echo "VAULT_APPROLE_ROLE_ID="$VAULT_APPROLE_ROLE_ID >> /tmp/pm_env
echo "VAULT_APPROLE_SECRET_ID="$VAULT_APPROLE_SECRET_ID >> /tmp/pm_env
echo "VAULT_APPROLE_SUPER_NAME="$VAULT_APPROLE_SUPER_NAME >> /tmp/pm_env
echo "VAULT_APPROLE_SUPER_TOKEN="$VAULT_SUPER_USER_TOKEN >> /tmp/pm_env

#echo "brokerClientAuthenticationParameters={\"role\":\"super-service-account\",\"roleId\":\""$VAULT_APPROLE_ROLE_ID"\",\"secretId\":\""$VAULT_APPROLE_SECRET_ID"\",\"vaultHost\": \""$VAULT_ADDR"\"}"\" >> /tmp/pm_env

# for busybox base64 image, we need to remove \n in the result
export VAULT_PULSAR_TOKEN=$(echo "$VAULT_APPROLE_ROLE_ID:$VAULT_APPROLE_SECRET_ID"|base64|tr -d \\n)
echo "brokerClientAuthenticationParameters=$VAULT_PULSAR_TOKEN" >> /tmp/pm_env



if [ -n "$organization" ] && [ -n "$instance" ];then
    echo "oidc client ids: serviceAccount,superServiceAccount,orgInstanceServiceAccount,orgInstanceSuperServiceAccount,user,superUser "
    echo $serviceAccountClientId,$superServiceAccountClientId,$orgInstanceServiceAccountClientId,$orgInstanceSuperServiceAccountClientId,$userClientId,$superUserClientId
else
    echo "oidc client ids: serviceAccount,superServiceAccount,user,superUser "
    echo $serviceAccountClientId,$superServiceAccountClientId,$userClientId,$superUserClientId
fi


if [ -n "$organization" ] && [ -n "$instance" ];then
    echo "PULSAR_PREFIX_OIDCTokenAudienceID="$serviceAccountClientId,$superServiceAccountClientId,$userClientId,$superUserClientId,$orgInstanceServiceAccountClientId,$orgInstanceSuperServiceAccountClientId >> /tmp/pm_env
else
    echo "PULSAR_PREFIX_OIDCTokenAudienceID="$serviceAccountClientId,$superServiceAccountClientId,$userClientId,$superUserClientId >> /tmp/pm_env
fi
cat /tmp/pm_env
echo "create secret for above secrets!"

kubectl delete secret $VAULT_SECRET_KEY_NAME -n $NAMESPACE
kubectl create secret generic $VAULT_SECRET_KEY_NAME --from-env-file=/tmp/pm_env -n $NAMESPACE

echo "create secret for console password! -> $CONSOLE_SECRET_KEY_NAME"
kubectl delete secret $CONSOLE_SECRET_KEY_NAME -n $NAMESPACE
kubectl create secret generic $CONSOLE_SECRET_KEY_NAME -n $NAMESPACE --from-literal=password=$VAULT_SUPER_USER_PASSWORD

echo "create secret for toolset token -> $TOOLSET_TOKEN_SECRET_NAME"
kubectl delete secret $TOOLSET_TOKEN_SECRET_NAME -n $NAMESPACE
kubectl create secret generic $TOOLSET_TOKEN_SECRET_NAME -n $NAMESPACE --from-literal=TOKEN=$VAULT_PULSAR_TOKEN

echo "" > /tmp/pm_env