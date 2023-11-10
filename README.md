# Caprover Compose Action

This Github Action allows the deployment of multiple apps directly from Github by utilizing the official Caprover CLI.
As Caprover doesn't support docker-compose stil([link](https://caprover.com/docs/docker-compose.html)), this action introduces custom logic for multiple application deployment. By the way, you have to translate the docker-compose into the format which this action can understand.

- First, in the compose context dir(configurable by `context` parameter), create one directory per one application. Directory name is used as the application name.
- In each application folder, create a `captain_definition` file. This will be used for application deployment.
- In each application folder, you can also create `json` or `yml` files to configure the application. The file format should follow Caprover configuration file for consuming Caprover API([link](https://github.com/caprover/caprover-cli/tree/master#api)). These files are applied to the application in the order of their names using `caprover api` command.
Note: If Caprover configuration file includes application name, please use `$APP` as application name because a unique application name is generated per a pull request.
For example, this is a Caprover configuration file to enable SSL.
```json
# 01_enable_ssl.json
{
  "path": "/user/apps/appDefinitions/enablebasedomainssl",
  "method": "POST",
  "data": {
    "appName": "$APP"
  }
}
```
- In each application folder, you can also create `.env` file to set environment variables for the app.
```txt
# .env
KEY1=VALUE1
KEY2=VALUE2
...
```

## Example compose context
Here is the example directory structure of a system consisting of multiple microservices.
```txt
.caprover
|_ frontend
|  |_captain_definition
|  |_01_enable_ssl.json
|  |_02_map_port.yml
|  |_...
|  |_99_output.json
|_ auth_api
|_ stock_api
|_ ...
|_ rabbitmq
|_ ...
|_ postgresql

```
Example `captain_definition` file;
```json
{
  "schemaVersion": 2,
  "imageName": "nginxdemos/hello"
}
```
Example configuration file `01_enable_ssl.json`;
```json
{
  "path": "/user/apps/appDefinitions/enablebasedomainssl",
  "method": "POST",
  "data": {
    "appName": "ci-frontend"
  }
}
```

## Action parameters
This Github Action requires the following parameters;
- server

  Captain server url. For example, https://captain.your-domain.com.
- password

  Captain password.
- context

  The path of definition and configuration files of applications. Optional. Default: `.caprover/`

Example usage;
```yaml
name: Container image

on:
  pull_request:
    branches: ["main"]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout project
        uses: actions/checkout@v3

      - name: Deploy caprover
        uses: josedev-union/caprover-compose-action@main
        with:
          server: https://captain.your-domain.com
```
