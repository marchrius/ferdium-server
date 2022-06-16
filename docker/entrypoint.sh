#!/bin/sh

if [ x"${HEROKU_ENV}" != "x" ]
then
  echo "/* HEROKU ENVIRONMENT: ${HEROKU_ENV} */"
  env > .env
  if [ x"${DATABASE_URL}" != "x" ] && [ x"${SKIP_HEROKU_DATABASE_URL}" = "x" ]
  then
    echo "Found DATABASE_URL env variable. Maybe there is an Heroku database. Updating vars. To skip this define a SKIP_HEROKU_DATABASE_URL in env"
    DB_ENVS=$(node ./parse_url.js "${DATABASE_URL}")
    if [ "$?" != "0" ]
    then
      echo "Something went wrong while updating the env file"
    else
      printf "\n$DB_ENVS\n" >> .env
      export $(grep -v '^#' .env | xargs -d '\n')
    fi
  fi
fi

cat << "EOL"
-------------------------------------------------
        _____               __
       / ___/___  _________/ (_)_  ______ ___
      / /_  / _ \/ ___/ __  / / / / / __ `__ \
     / __/ /  __/ /  / /_/ / / /_/ / / / / / /
    /_/    \___/_/   \__,_/_/\__,_/_/ /_/ /_/
       ____
      / __/ ___  ______   _____  _____
      \__ \/ _ \/ ___/ | / / _ \/ ___/
     ___/ /  __/ /   | |/ /  __/ /
    /____/\___/_/    |___/\___/_/

  Brought to you by ferdium.org (and marchrius)
EOL

if [ x"$RESET_RECIPES" != "x" ]
then
  echo "** Resetting recipes at /app/recipes"
  rm -r /app/recipes
fi

# Update recipes from official git repository
if [ ! -d "/app/recipes/.git" ] # When we mount an existing volume (ferdium-recipes-vol:/app/recipes) if this is only /app/recipes it is always true
then
  echo '**** Generating recipes for first run ****'
  if [ x"${CUSTOM_RECIPES_URL}" = "x" ]
  then
    CUSTOM_RECIPES=https://github.com/ferdium/ferdium-recipes
  fi
  git clone --branch main "${CUSTOM_RECIPES_URL}" recipes
else
  echo '**** Updating recipes ****'
  # TODO: in docker check another way to do this
  #chown -R root /app/recipes # Fixes ownership problem when doing git pull -r
  cd recipes
  git stash -u
  git pull -r
  git stash pop
  cd ..
fi

cd recipes
git config --global --add safe.directory /app/recipes
EXPECTED_PNPM_VERSION=$(node -p 'require("./package.json").engines.pnpm')
npm i -gf pnpm@$EXPECTED_PNPM_VERSION
pnpm i
pnpm package
cd ..

mkdir -p "${DATA_DIR}"

print_app_key_message() {
  printf '**** App key is %s. You can modify `%s` to update the app key ****\n' "${1}" "${2}"
}

if [ x"${HEROKU_ENV}" = "x" ]
then
  key_file="${DATA_DIR}/FERDIUM_APP_KEY.txt"

  # Create APP key if needed
  if [ -z ${APP_KEY} ] && [ ! -f ${key_file} ]
  then
    echo '**** Generating Ferdium-server app key for first run ****'
    adonis key:generate
    APP_KEY=$(grep APP_KEY .env | cut -d '=' -f2)
    echo ${APP_KEY} > ${key_file}
    print_app_key_message "${APP_KEY}" "${key_file}"
  else
    APP_KEY=$(cat ${key_file})
    print_app_key_message "${APP_KEY}" "${key_file}"
  fi

  export APP_KEY
else
  print_app_key_message "${APP_KEY}" "Config vars on Heroku"
fi

node ace migration:run --force

# TODO: why do this in docker container?
#chown -R "${PUID:-1000}":"${PGID:-1000}" "${DATA_DIR}" /app # This is the cause of the problem on line 29/32

# TODO: why do this in docker container?
#su-exec "${PUID:-1000}":"${PGID:-1000}" node server.js

node server.js
