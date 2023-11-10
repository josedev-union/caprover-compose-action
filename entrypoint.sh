#!/bin/bash -e

# TODO(joseb):
#     1. Convert to python. ref: https://github.com/ak4zh/Caprover-API
#     2. Set output, like app url etc. This will be much easier with python sdk.
#     3. App name validation


########################### Global var def
COMPOSE_CTX_PATH=${INPUT_CONTEXT:-.caprover}
APP_NAME_PREFIX=${INPUT_PREFIX:-pr}
EVENT_ID=$(echo "$GITHUB_REF" | awk -F / '{print $3}')
KEEP_APP=${INPUT_KEEP:-"true"}
## caprover cli config vars
export CAPROVER_URL=$INPUT_SERVER
export CAPROVER_PASSWORD=${INPUT_PASSWORD:-captain42}
export CAPROVER_NAME=default
## caprover api request vars
NS="x-namespace: captain"
CTYPE="Content-Type: application/json"
# getToken gets the token from Caprover API.
getToken() {
  res=$(curl -sSf "$CAPROVER_URL/api/v2/login" -X POST -d '{"password":"'$CAPROVER_PASSWORD'"}' -H "$CTYPE" -H "$NS")
  token=$(echo "$res"|awk -F'"token":"' '{print $2}'|awk -F'"' '{print $1}'|grep .)
  echo $token
}
AUTH="x-captain-auth: $(getToken)"

########################### Function def

# waitApp waits until the app is ready.
#
# Arguments:
#     $1: app name.
#
waitApp() {
  app_name=$1
  for i in $(seq 10); do
    res=$(curl -sSf "$CAPROVER_URL/api/v2/user/apps/appData/$app_name" -H "$CTYPE" -H "$NS" -H "$AUTH")
    echo $res|jq '.description' -r && echo "$res"|grep '"status":100,' >/dev/null
    is_building=$(echo $res|jq '.data.isAppBuilding')
    echo "App building: $is_building"
    if [ "$is_building" == "false" ]; then
      echo "App is ready now!"
      break
    else
      echo "Waiting until ready (try: $i)"
      sleep 10
    fi
  done
}

# setOutput does action output
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

renderConfigTemplate() {
  app_name=${1}
  tpl_path=${2}
  sed -i "s/\$APP/$app_name/g" $tpl_path
}

# setAppEnvVars converts .env file to json and sets environment variables for a Caprover app.
#
# Arguments:
#     $1: app name.
#     $2: path to the environment variables file.
#
setAppEnvVars() {
  app_name=${1}
  env_file_path=${2}

  env_data=$(echo $(
    for i in $(cat $env_file_path|awk -F"=" '{print $1}'); do
      val=$(awk -F"=" -v i="$i" '{ if ($1==i) print }' $env_file_path|sed "s/^$i=//");
      echo '{"key":"'$i'","value":"'$val'"},';
    done
  ) | sed 's/.$//')

  caprover api \
  --path "/user/apps/appDefinitions/update" \
  --method "POST" \
  --data "{\"appName\":\"${app_name}\",\"envVars\":[${env_data}]}"

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
    echo "$res";
    echo "[app:$app_alias] successfully deployed!";
  else
    set -e
    if [[ "$res" == *"not exist"* ]]; then
      echo "[app:$app_alias] create a new app as it doesn't exist!";
      createApp $app_name;
      waitApp $app_name;
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
    renderConfigTemplate $app_name $f
    caprover api -c $f
  done
  if [ -f $app_ctx_path/.env ]; then
    echo "[app:$app_alias] - seting env vars...";
    setAppEnvVars $app_name $app_ctx_path/.env
  fi
}

deleteSingleApp() {
  app_alias=${1}
  app_name=$(generateAppName ${2})
  echo "[app:$app_alias] app name: $app_name";

  # Scale down instance number to zero
  echo "[app:$app_alias] scaling down instance number to zero...";
  caprover api \
  --path "/user/apps/appDefinitions/update" \
  --method "POST" \
  --data "{\"appName\":\"${app_name}\",\"instanceCount\":0}"

  # Delete app
  echo "[app:$app_alias] deleting app...";
  caprover api \
  --path "/user/apps/appDefinitions/delete" \
  --method "POST" \
  --data "{\"appName\":\"${app_name}\"}"
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
  echo "${APP_NAME_PREFIX}-${GITHUB_REPOSITORY_ID}-${EVENT_ID}-${1}"
}

########################### Main
# 1. validate the request
preValidate

# 2. Deploy
for app in $COMPOSE_CTX_PATH/*/; do
  echo "Deploying $(basename "$app") app...";
  ensureSingleApp "${app}" "$(basename $app)"
done

# 3. Destroy
if [ "$KEEP_APP" == "false" ]; then
for app in $COMPOSE_CTX_PATH/*/; do
  echo "Removing $(basename "$app") app...";
  deleteSingleApp "${app}" "$(basename $app)"
done
