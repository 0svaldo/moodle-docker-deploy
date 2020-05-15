#!/bin/bash
set -eu
# Initial Deploy
# Ver. 0.1 - bash
#
# Two options
# 1- one instance: createMoodle.sh -e mail -l language -n "full_name" -u "url" [--internaldb] )
# 2- -f file: CSV - several instances


# Inicialización de variables
# load database variables for database creation:
# MYSQL_ROOT_PASSWORD
# MOODLE_DB_HOST
set -a
[ -f .env ] && . .env
set +a

MOODLE_ADMIN_USER="adminuser"
MOODLE_ADMIN_PASSWORD="camb1ameperoYA"
MOODLE_ADMIN_EMAIL="admin@centro.com"

MOODLE_LANG="es"
MOODLE_SITE_NAME="AEduca"
MOODLE_SITE_FULLNAME="AEduca del CPI/IES Mi Centro"
MOODLE_URL="http://localhost"
# MOODLE_DB_HOST=db
EXTERNAL_DB="true"
MOODLE_DB_NAME="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)"
MOODLE_MYSQL_USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
MOODLE_MYSQL_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)


# Additional initial configuration (plugin related)
DEFAULT_THEME="snap"
BBB_SERVER_URL="http://bbb.aragon.es/bigbluebutton/"
BBB_SECRET="thisShouldBeMySharedSecretKey"

# deberíamos generar un usuario de conexión a bbdd y un nombre en base al nombre del centro
# y una contraseña aleatoria

usage () {
    echo "###################"
    echo "## Deploy moodle ##"
    echo '# Use: createMoodle.sh [-e mail_admin] [-l es|fr|..] [-n "full_name"] -u "url" [-i] short_name'
    echo "# Options:"
    echo "#   -e -> administrator email. soportecatedu@educa.aragon.es by default"
    echo "#   -l -> default language. es by default"
    echo "#   -n -> Full Name Site. AEduca de Mi Centro by default"
    echo "#   -u -> url moodle: https://sitie.domain.com"
    echo "#   -i use internal db docker. External db by default"
    echo "#   -h this message"
    echo "###################"
}

get_parameter(){
    while getopts ":o:e:n:u:a:ih" opt; do
        case $opt in
            e)
                [[ "${OPTARG}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$ ]] || \
                { echo "Incorrect email..."; usage; exit 1;}
                MOODLE_ADMIN_EMAIL="${OPTARG}"
            ;;
            l)
                [[ "${OPTARG}" =~ ^[a-z]{2}$ ]] || \
                { echo "Incorrect language format..."; usage; exit 1;}
                MOODLE_LANG="${OPTARG}"
            ;;
            n)
                MOODLE_SITE_FULLNAME="${OPTARG}"
            ;;
            u)
                [[ "${OPTARG}" =~ ^https?://[A-Za-z0-9._]+$ ]] || \
                { echo "Incorrect url format..."; usage; exit 1;}
                MOODLE_URL="${OPTARG}"
            ;;
            i)
                EXTERNAL_DB="false"
            ;;
            h)
                usage
                exit 0
            ;;
            \?)
                echo "Invalid option: -${OPTARG}" >&2
                exit 1
            ;;
            :)
                echo "Option -${OPTARG} requiere a field" >&2
                exit 1
            ;;
        esac
    done
    
    # Mandatory options
    [ "${MOODLE_URL}" = "http://localhost" ] && { echo "You must to indicate a url to moodle"; usage; exit 1;}
    
    # Arguments
    shift "$((OPTIND-1))"
    for var in "$@"; do
        if [[ "${var:0:1}" = "-" ]]; then
            usage
            exit 0
        fi
    done
    set +u
    [ -z "${1}" ] && { echo "You must to indicate a short_name"; usage; exit 1;}
    set -u
    MOODLE_SITE_NAME="${1}"
}
check_create_dir_exist(){
    if [ -d "${1}" ]; then
        echo "Caution: Deploy Duplicate!!. Directory $1 exists"
        # Comment to continue (override docker-compose, for upgrade)
        exit 1
    else
        mkdir "${1}"
    fi
}
yq() {   docker run --rm -i -v ${PWD}:/workdir mikefarah/yq yq $@; }
create_service_db(){
    #Delete backend section
    FILEYAML="${1}"
    yq d -i "${FILEYAML}" networks.backend
    
    # Merge moodle with internal db
    [ -f "./template/service_db_internal.yml" ] && \
    yq merge -i "${FILEYAML}" "template/service_db_internal.yml"
    
}

get_parameter "$@"

VIRTUALHOST="${MOODLE_URL##*//}"
check_create_dir_exist "${VIRTUALHOST}"


[ -f "template/docker-compose.yml" ] && cp "template/docker-compose.yml" "${VIRTUALHOST}"

if [ "${EXTERNAL_DB}" = "false" ]; then
    create_service_db "${VIRTUALHOST}/docker-compose.yml"
    MOODLE_DB_HOST="db"
fi

if [ ! -f "${VIRTUALHOST}/.env" ]; then
    cat > "${VIRTUALHOST}/.env" << EOF
# for reverse nginx proxy:
VIRTUAL_HOST="$VIRTUALHOST"
SSL_EMAIL=soportecatedu@educa.aragon.es

# for database connection:
MOODLE_DB_HOST="$MOODLE_DB_HOST"
MOODLE_DB_NAME="$MOODLE_DB_NAME"
MOODLE_MYSQL_USER="$MOODLE_MYSQL_USER"
MOODLE_MYSQL_PASSWORD="$MOODLE_MYSQL_PASSWORD"
EXTERNAL_DB="$EXTERNAL_DB"

SSL_PROXY=true

MOODLE_URL="$MOODLE_URL"

# for installing moodle, user data:
MOODLE_ADMIN_USER="$MOODLE_ADMIN_USER"
MOODLE_ADMIN_PASSWORD="$MOODLE_ADMIN_PASSWORD"
MOODLE_ADMIN_EMAIL="$MOODLE_ADMIN_EMAIL"
MOODLE_LANG="$MOODLE_LANG"
MOODLE_SITE_NAME="$MOODLE_SITE_NAME"
MOODLE_SITE_FULLNAME="$MOODLE_SITE_FULLNAME"


# for moodle initial configuration (plugin related)
DEFAULT_THEME="$DEFAULT_THEME"
BBB_SERVER_URL="$BBB_SERVER_URL"
BBB_SECRET="$BBB_SECRET"
EOF
    
fi




echo "DEPLOY ${MOODLE_URL} CREATED!"

#up_services

# create database, user and grants
#mysql --user="root" --password="${MYSQL_ROOT_PASSWORD}" --host="${MOODLE_DB_HOST}" --execute="CREATE DATABASE ${MOODLE_DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER ${MOODLE_MYSQL_USER} IDENTIFIED BY '${MOODLE_MYSQL_PASSWORD}'; GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,CREATE TEMPORARY TABLES,DROP,INDEX,ALTER ON moodle.* to '${MOODLE_MYSQL_USER}'@'%'"

# TO-DO
# - Mandar un correo al MOODLE_ADMIN_EMAIL????
# - También deberíamos tener claro si hacemos importación de datos y como
