#!/bin/bash
BASE_DIR=$(readlink -f $(dirname ${0}))
SCRIPT=$(basename ${0})
WEBOGRAM_VERSION="latest"
WEBOGRAM_PID="/var/run/${WEBOGRAM_USER}.pid"
WEBOGRAM_INITSCRIPT="/etc/init.d/webogram"
WEBOGRAM_REPO="https://github.com/zhukov/webogram.git"
GITLOGFILE="${BASE_DIR}/log/git-$(date +%Y%m%d-%H%M%S).log"
NPMLOGFILE="${BASE_DIR}/log/npm-$(date +%Y%m%d-%H%M%S).log"

redbold=$'\033[1;31m'
greenbold=$'\033[1;32m'
yellowbold=$'\033[1;33m'
cyanbold=$'\033[1;36m'
resetcolor=$'\033[0m' # No Color

print_error() {
  echo -e "[${redbold}ERR ${resetcolor}] ${1}"
}

print_info() {
  echo -e "[${cyanbold}INFO${resetcolor}] ${1}"
}

print_warning() {
  echo -e "[${yellowbold}WARN${resetcolor}] ${1}"
}

print_ok() {
  echo -e "[${greenbold} OK ${resetcolor}] ${1}"
}

# Prints help
# Syntax: print_help
print_help() {
  echo ""
  echo "Script to install webogram (optionally as a system service)"
  echo ""
  echo "Syntax: "
  echo ""
  echo "${SCRIPT} [-c] [-s] [-p <PATH>] [-v <VERSION> ] [-f]"
  echo ""
  echo "Where: "
  echo "  -c               If present, webogram does not need superuser access"
  echo "                   It will be installed with the current user"
  echo ""
  echo "  -s               If present, install webogram as a system service"
  echo "                   Not availabie if -c is present"
  echo ""
  echo "  -p <PATH>        Path where the webogram home directory will live"
  echo "                   Default: \$HOME when -c is present or /opt"
  echo "                   when is not"
  echo ""
  echo "  -v <VERSION>     A webogram version (in fact a git ref, so use a tag"
  echo "                   to select a version, or master for last commit"
  echo "                   Default: last webogram stable version"
  echo ""
  echo "  -f               If present, forces an installation, even if another"
  echo "                   webogram is installed as with other parameters"
  echo "                   (this option is only relevant if -s is present)"
  echo "                   NOT RECOMMENDED!"
  echo ""

}

# Prints an error showing that an invalid syntax was used
# Syntax: print_invalid_syntax
print_invalid_syntax() {
  echo "Incorrect syntax. Use -h for help."
}

# Checks if a user exists.
# Syntax: user_exists <username>
#
# * Prints true and returns 0 if the user exists
# * Prints nothing and returns 1 if the user does not exist
user_exists() {
  getent passwd ${1} >/dev/null 2>&1 && local USER_EXISTS=true
  echo ${USER_EXISTS}
  if [ ${USER_EXISTS} ]; then
    return 0
  else
    return 1
  fi
}

run() {
  local SUUSER=${1}
  local COMMAND=${2}
  local LOGFILE=${3}
  if [ ${SUUSER} != "NONE" ]; then
    su -l ${SUUSER} -c "${COMMAND}" >> ${LOGFILE} 2>&1
    return $?
  else 
    ${COMMAND} >> ${LOGFILE} 2>&1
    return $?
  fi
}

# Check if we're running as root
check_root() {
  if [ ${UID} -ne 0 ]; then
    print_error "This script needs to run as root! Exiting."
    exit 1
  fi
}

# Check if there's a webogram system service script
check_system_service() {
  if [ -f ${WEBOGRAM_INITSCRIPT} ]; then
    # If there is, check if the installation directory is the same we have now
    INITSCRIPT_HOMEDIR=$(grep 'WEBOGRAM_HOMEDIR=' ${WEBOGRAM_INITSCRIPT} | cut -d'=' -f2 | tr -d '"')
    if [ "${INITSCRIPT_HOMEDIR}" != "${WEBOGRAM_HOMEDIR}" ]; then
      # If it's not and FORCE is not enabled, quit
      if ! ${FORCE} ; then
        print_error "Another webogram seems to be installed at ${INITSCRIPT_HOMEDIR}. Exiting."
        exit 1
      fi
    fi
  fi
}

# Check for WEBOGRAM_DIR
check_webogram_dir() {
  if [ ! -d ${WEBOGRAM_DIR} ]; then
    print_error "${WEBOGRAM_DIR} does not exist. Exiting"
    exit 1
  fi
}

# Check if needed software is installed
check_software() {
  if  [ "$(which git)" == "" ]; then
    print_error "Can't find git. Exiting..."
    exit 1
  elif [ "$(which npm)" == "" ]; then
    print_error "Can't find npm. Exiting..."
    exit 1
  fi
}

# Create home dir
create_home_dir() {
  if [ -d ${WEBOGRAM_HOMEDIR} ]; then
    WAS_INSTALED="true"
  else
    mkdir ${WEBOGRAM_HOMEDIR}
  fi
}

# Check if webogram user exists. If not, create it
check_create_user() {
  if [ ! $(user_exists ${WEBOGRAM_USER}) ]; then
    print_info "Creating user ${WEBOGRAM_USER} with home ${WEBOGRAM_HOMEDIR}"
    useradd -r -U -d ${WEBOGRAM_HOMEDIR} ${WEBOGRAM_USER}
    if [ $? -ne 0 ]; then
      print_error "Could not create user ${WEBOGRAM_USER}. Exiting."
      exit 1
    fi
    chown ${WEBOGRAM_USER}. ${WEBOGRAM_HOMEDIR}
  else
    WAS_INSTALLED=true
    print_info "User ${WEBOGRAM_USER} already exists... Skipping creation."
  fi
}

# Check if logdir exists. If not, create it.
check_logdir() {
  if [ ! -d ${WEBOGRAM_LOGDIR} ]; then
    print_info "Creating logdir ${WEBOGRAM_LOGDIR}"
    mkdir ${WEBOGRAM_LOGDIR}
    chown ${WEBOGRAM_USER}. ${WEBOGRAM_LOGDIR}
  else
    print_info "Logdir ${WEBOGRAM_LOGDIR} already exists. Skipping creation, but checking permissions..."
    chown ${WEBOGRAM_USER}. ${WEBOGRAM_LOGDIR}
  fi
}

# Install system service if appropriate
install_system_service() {
  print_info "Installing service at ${WEBOGRAM_INITSCRIPT}..."
  cp ${BASE_DIR}/files/init.d/webogram ${WEBOGRAM_INITSCRIPT}
  sed -i -e "s|WEBOGRAM_HOMEDIR=.*|WEBOGRAM_HOMEDIR=${WEBOGRAM_HOMEDIR}|" ${WEBOGRAM_INITSCRIPT}
}

# Install wrapper
install_wrapper() {
  print_info "Installing wrapper to ${WEBOGRAM_BINDIR}..."
  if [ ! -d ${WEBOGRAM_BINDIR} ]; then
    mkdir ${WEBOGRAM_BINDIR}
  fi
  cp ${BASE_DIR}/files/bin/webogram ${WEBOGRAM_BINDIR}
  chown -R ${WEBOGRAM_USER}. ${WEBOGRAM_BINDIR}
}

# Adjust git repository
config_gitdir() {
  if [ ! -d ${WEBOGRAM_GITDIR} ]; then 
    print_info "Cloning webogram git repository (log at ${GITLOGFILE})..."
    run ${SUUSER} "cd ${WEBOGRAM_HOMEDIR} && git clone ${WEBOGRAM_REPO} ${WEBOGRAM_GITDIR}" ${GITLOGFILE}
  else
    print_info "Pulling data from webogram git repository (log at ${GITLOGFILE})..."
    run ${SUUSER} "cd ${WEBOGRAM_GITDIR} && git checkout master" ${GITLOGFILE}
    run ${SUUSER} "cd ${WEBOGRAM_GITDIR} && git pull" ${GITLOGFILE}
  fi
  WEBOGRAM_LATESTSTABLEVER=$(cd ${WEBOGRAM_GITDIR} && git tag|grep 'v'|sort -r|head -n1)
  if [ "${WEBOGRAM_VERSION}" != "latest" ]; then
    print_info "Checking out ${WEBOGRAM_VERSION}..."
    run ${SUUSER} "cd ${WEBOGRAM_GITDIR} && git checkout ${WEBOGRAM_VERSION}" ${GITLOGFILE}
    if [ $? -ne 0 ]; then
      print_warning "Ref ${WEBOGRAM_VERSION} does not exist. Defaulting to ${WEBOGRAM_LATESTSTABLEVER}"
      run ${SUUSER} "cd ${WEBOGRAM_GITDIR} && git checkout ${WEBOGRAM_LATESTSTABLEVER}" ${GITLOGFILE}
    fi
  else
    print_info "Checking out ${WEBOGRAM_LATESTSTABLEVER}..."
    run ${SUUSER} "cd ${WEBOGRAM_GITDIR} && git checkout ${WEBOGRAM_LATESTSTABLEVER}" ${GITLOGFILE}
  fi
}

# Configure NPM folder
config_npmfolder() {
if [ -d ${WEBOGRAM_HOMEDIR}/.npm ]; then
  print_info "Checking permissions for npm folder..."
  chown -R ${WEBOGRAM_USER}. ${WEBOGRAM_HOMEDIR}/.npm
else
  print_info "Creating npm folder..." 
  run ${SUUSER} "cd ${WEBOGRAM_HOMEDIR} && mkdir .npm" /dev/null
fi
}

# Install gulp
install_gulp() {
  print_info "Installing gulp (log at ${NPMLOGFILE})..."
  run ${SUUSER} "cd ${WEBOGRAM_GITDIR} && NODE_PATH=${WEBOGRAM_HOMEDIR}/.npm npm update gulp" ${NPMLOGFILE}
  if [ $? -ne 0 ]; then
    print_error "Errors installing gulp! Check log!"
    exit 1
  fi
}

# Install node dependencies
install_node_deps() {
  print_info "Installing node dependencies (log at ${NPMLOGFILE})..."
  run ${SUUSER} "cd ${WEBOGRAM_GITDIR} && NODE_PATH=${WEBOGRAM_HOMEDIR}/.npm npm update" ${NPMLOGFILE}
  if [ $? -ne 0 ]; then
    print_error "Errors installing node dependencies! Check log!"
    exit 1
  fi
}

end() {
  if ${WAS_INSTALED} ; then
    print_ok "Update complete"
    print_info "If the application was running there is no need to restart as gulp will take care of everything"
  else
    pint_ok "Installation complete"
    if $SYSTEM_SERVICE ; then
      print_warning "System service was installed, but note that you still need to configure automatic start:"
      print_warning "- For Debian-like systems: update-rc.d webogram enable"
      print_warning "- For RHEL-like systems: chkconfig webogram on"
    fi
  fi
  exit 0
}

# Parse options
while getopts "v:p:csfh" opts; do
  case "${opts}" in
    v) WEBOGRAM_VERSION=${OPTARG} ;;
    p) WEBOGRAM_PATH=${OPTARG}
       WEBOGRAM_HOMEDIR="${WEBOGRAM_PATH}/${WEBOGRAM_USER}" ;;
    c) CURRENT_USER="true" ;;
    s) SYSTEM_SERVICE="true" ;;
    f) FORCE="true" ;;
    h) print_help
       exit 1 ;;
    *) print_invalid_syntax ${SCRIPT}
       exit 1 ;;
  esac
done
shift $((OPTIND-1))

if [ ${CURRENT_USER} ]; then
  if [ ${SYSTEM_SERVICE} ]; then
    print_invalid_syntax ${SCRIPT}
    exit 1
  else
    WEBOGRAM_USER=${USER}
    SUUSER="NONE"
    WEBOGRAM_DIR="${HOME}"
    # Install for current user
    if ! [ ${WEBOGRAM_PATH} ]; then
      WEBOGRAM_HOMEDIR="${HOME}/webogram"
    fi
    WEBOGRAM_BINDIR="${WEBOGRAM_HOMEDIR}/bin"
    WEBOGRAM_GITDIR="${WEBOGRAM_HOMEDIR}/git"
    WEBOGRAM_LOGDIR="${WEBOGRAM_HOMEDIR}/log"
    check_webogram_dir
    check_software
    create_home_dir
    check_logdir
    install_wrapper
    config_gitdir
    config_npmfolder
    install_gulp
    install_node_deps
    end
  fi
else 
  # Install creating a own user for webogram
  WEBOGRAM_USER="webogram"
  SUUSER=${WEBOGRAM_USER}
  WEBOGRAM_DIR="/opt"
  if ! [ ${WEBOGRAM_PATH} ]; then
    WEBOGRAM_HOMEDIR="${WEBOGRAM_DIR}/${WEBOGRAM_USER}"
  fi
  WEBOGRAM_BINDIR="${WEBOGRAM_HOMEDIR}/bin"
  WEBOGRAM_GITDIR="${WEBOGRAM_HOMEDIR}/git"
  WEBOGRAM_LOGDIR="/var/log/${WEBOGRAM_USER}"
  check_root
  if [ $SYSTEM_SERVICE ]; then
    check_system_service
  fi
  check_webogram_dir
  check_software
  create_home_dir
  check_create_user
  check_logdir
  if [ $SYSTEM_SERVICE ]; then
    install_system_service
  fi
  install_wrapper
  config_gitdir
  config_npmfolder
  install_gulp
  install_node_deps
  end
fi

