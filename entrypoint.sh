#!/bin/bash
set -e

# TODO(joseb):
#     1. Convert to python. ref: https://github.com/ak4zh/Caprover-API
#     2. Exception handling. This will be much easier with python sdk.
#     3. Set output, like app url etc. This will be much easier with python sdk.
#     4. App name validation
#     5. Detect appName in config files and append prefix automatically
#     6. Generate prefix based on the git ref automatically if not presented.


compose_ctx_path=${INPUT_CONTEXT:-.caprover}
app_name_prefix=${INPUT_PREFIX:-pr}

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
  --method "POST" \
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
  app_alias=${2}
  app_name=$(generateAppName ${2})
  echo "[app:$app_alias] app name: $app_name";

  # Deploy app
  echo "[app:$app_alias] deployment step!";
  set +e
  res=$(caprover deploy --appName $app_name -c $app_ctx_path/captain-definition)
  if [ $? -eq 0 ]; then
    set -e
    echo "[app:$app_alias] successfully deployed! $res";
  else
    set -e
    if [[ "$res" == *"not exist"* ]]; then
      echo "[app:$app_alias] create a new app as it doesn't exist!";
      createApp $app_name;
      echo "[app:$app_alias] deployment step!";
      caprover deploy --appName $app_name -c $app_ctx_path/captain-definition;
    else
      echo "::error::[app:$app_alias]Caprover deploy failed."
      exit 1;
    fi
  fi

  # Configure app
  echo "[app:$app_alias] configuration step!";
  for f in $(find $app_ctx_path/ -type f | egrep -i 'yml|yaml|json' | sort); do
    echo "[app:$app_alias] - processing $f config file...";
    sed -i 's/\$APP/${app_name}/g' $f
    caprover api -c $f
  done
}

preValidate() {
  # Allow only pull requests
  if [ "${GITHUB_EVENT_NAME}" != "pull_request" ]
  then
    echo "This action only works in pull requests."
    exit 0
  fi
}

generateAppName() {
  echo "${app_name_prefix}-${GITHUB_REPOSITORY_ID}-${GITHUB_EVENT_NUMBER}-${1}"
}

for app in $compose_ctx_path/*/; do
  echo "Deploying $(basename "$app") app...";
  ensureSingleApp "${app}" "$(basename $app)"
done
