#!/bin/sh
set -ex

# TODO(joseb):
#     1. Convert to python. ref: https://github.com/ak4zh/Caprover-API
#     2. Exception handling. This will be much easier with python sdk.
#     3. Set output, like app url etc. This will be much easier with python sdk.

compose_ctx_path=${INPUT_CONTEXT:-.caprover}

export CAPROVER_URL=$INPUT_SERVER
export CAPROVER_PASSWORD=${INPUT_PASSWORD:-captain42}
export CAPROVER_NAME=default
# caprover login

setOutput() {
    echo "${1}=${2}" >> "${GITHUB_OUTPUT}"
}

# createApp creates a single Caprover app.
# 
# Arguments:
#     $1: app name.
#
createApp() {
  app_name=${1}
  caprover api \
  --path "/user/apps/appDefinitions/register?detached=1" \
  --method "GET" \
  --data "{\"appName\":\"${app_name}\",\"hasPersistentData\":false}"
}

# ensureSingleApp deploy and configure a single Caprover app.
#
# Arguments:
#     $1: app context directory path.
#     $2: app name.
#
ensureSingleApp() {
  app_ctx_path=${1}
  app_name=${2}
  echo "[app:$app_name] deployment step!";
  set +e
  res=$(caprover deploy --appName $app_name -c $app_ctx_path/captain-definition)
  set -e
  if [[ $res == *"not exist"* ]]; then
    echo "[app:$app_name] create a new app!";
    createApp $app_name
    echo "[app:$app_name] deployment step!";
    caprover deploy --appName $app_name -c $app_ctx_path/captain-definition
  fi
  echo "[app:$app_name] configuration step!";
  for f in $(find $app_ctx_path/ -iregex '.*\.\(yml\|yaml\|json\)' -type f | sort); do
    echo "[app:$app_name] - processing $f config file...";
    caprover api -c $app_ctx_path/$f
  done
}

for app in $(ls $compose_ctx_path/*/); do
  echo "Deploying $(basename "$app") app...";
  ensureSingleApp $app $(basename "$app")
done
