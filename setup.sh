#!/bin/bash
BASE_DIR=$(dirname ${0})
SCRIPT=$(basename ${0})
WEBOGRAM_VERSION="latest"
WEBOGRAM_DIR="/opt"
WEBOGRAM_USER="webogram"
WEBOGRAM_HOMEDIR="${WEBOGRAM_DIR}/${WEBOGRAM_USER}"
WEBOGRAM_BINDIR="${WEBOGRAM_HOMEDIR}/bin"
WEBOGRAM_GITDIR="${WEBOGRAM_HOMEDIR}/git"
WEBOGRAM_LOGDIR="/var/log/${WEBOGRAM_USER}"
WEBOGRAM_PID="/var/run/${WEBOGRAM_USER}.pid"
WEBOGRAM_INITSCRIPT="/etc/init.d/webogram"
WEBOGRAM_REPO="https://github.com/zhukov/webogram.git"
SYSTEM_SERVICE="FALSE"
FORCE="FALSE"
INSTALL_NODE_VM="FALSE"

# Prints help
# Syntax: print_help
print_help() {
  echo ""
  echo "Script to install webogram (optionally as a system service)"
  echo ""
  echo "Syntax: "
  echo ""
  echo "${SCRIPT} [-s] [-v <VERSION>] [-p <PATH>] [-f]"
  echo ""
  echo "Where: "
  echo "  -s               If present, install webogram as a system service"
  echo "  -v <VERSION>     A webogram version (in fact a git ref)"
  echo "                   Default: last webogram stable version"
  echo "  -p <PATH>        Path where the webogram home directory will live"
  echo "                   Default: /opt"
  echo "  -f               If present, forces an installation, even if another"
  echo "                   webogram is installed with other parameters."
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
# * Prints "TRUE" and returns 0 if the user exists
# * Prints "FALSE" and returns 1 if the user does not exist
user_exists() {
  local USER_EXISTS="FALSE"
  getent passwd ${1} >/dev/null 2>&1 && USER_EXISTS="TRUE"
  if [ "${USER_EXISTS}" == "TRUE" ]; then
    echo "TRUE"
    return 0
  else
    echo "FALSE"
    return 1
  fi
}

# Parse options
while getopts ":sv:p:fh" opts; do
  case "${opts}" in
    s) SYSTEM_SERVICE="TRUE" ;;
    p) WEBOGRAM_VERSION=${OPTARG} ;;
    p) WEBOGRAM_PATH=${OPTARG} 
       WEBOGRAM_HOMEDIR="${WEBOGRAM}/${WEBOGRAM_USER}" ;;
    f) FORCE="TRUE" ;;
    h) print_help
       exit 1 ;;
    *) print_invalid_syntax ${SCRIPT}
       exit 2 ;;
  esac
done
shift $((OPTIND-1))

# Check if we're running as root
if [ ${UID} -ne 0 ]; then
  echo "This script needs to run as root! Exiting."
  exit 3
fi

# Check if there's a webogram system service script
if [ -f ${WEBOGRAM_INITSCRIPT} ]; then
  # If there is, check if the installation directory is the same we have now
  INITSCRIPT_HOMEDIR=$(grep 'WEBOGRAM_HOMEDIR=' ${WEBOGRAM_INITSCRIPT} | cut -d'=' -f2 | tr -d '"')
  if [ "${INITSCRIPT_HOMEDIR}" != "${WEBOGRAM_HOMEDIR}" ]; then
    # If it's not and FORCE is not enabled, quit
    if [ "${FORCE}" == "FALSE" ]; then
      echo "Another webogram seems to be installed at ${INITSCRIPT_HOMEDIR}. Exiting."
      exit 4
    fi
  fi
fi

# Check for WEBOGRAM_DIR
if [ ! -d ${WEBOGRAM_DIR} ]; then
  echo "${WEBOGRAM_DIR} does not exist. Exiting"
  exit 5
fi

# Check if needed software is installed
if [ "$(which git)" == "" ]; then
  echo "Can't find git. Exiting..."
  exit 6
elif [ "$(which npm)" == "" ]; then
  echo "Can't find npm. Exiting..."
  exit 7
fi

# Check if webogram user exists. If not, create it
if [ "$(user_exists ${WEBOGRAM_USER})" == "FALSE" ]; then
  echo "Creating user ${WEBOGRAM_USER} with home ${WEBOGRAM_HOMEDIR}"
  mkdir ${WEBOGRAM_HOMEDIR}
  useradd -r -U -d ${WEBOGRAM_HOMEDIR} ${WEBOGRAM_USER}
  if [ $? -ne 0 ]; then
    echo "Could not create user ${WEBOGRAM_USER}. Exiting."
    exit 8
  fi
  chown ${WEBOGRAM_USER}. ${WEBOGRAM_HOMEDIR}
else
  echo "User ${WEBOGRAM_USER} already exists... Skipping creation."
fi

# Check if logdir exists. If not, create it.
if [ ! -d ${WEBOGRAM_LOGDIR} ]; then
  echo "Creating logdir ${WEBOGRAM_LOGDIR}"
  mkdir ${WEBOGRAM_LOGDIR}
  chown ${WEBOGRAM_USER}. ${WEBOGRAM_LOGDIR}
else
  echo "Logdir ${WEBOGRAM_LOGDIR} already exists. Skipping creation, but checking permissions..."
  chown ${WEBOGRAM_USER}. ${WEBOGRAM_LOGDIR}
fi

# Install system service if appropriate
if [ ${SYSTEM_SERVICE} == "TRUE" ]; then
  echo "Installing service at ${WEBOGRAM_INITSCRIPT}..."
  cp ${BASE_DIR}/files/init.d/webogram ${WEBOGRAM_INITSCRIPT}
  sed -i -e "s|WEBOGRAM_HOMEDIR=.*|WEBOGRAM_HOMEDIR=${WEBOGRAM_HOMEDIR}|" ${WEBOGRAM_INITSCRIPT}
fi

# Install binaries
echo "Installing binaries to ${WEBOGRAM_BINDIR}..."
if [ ! -d ${WEBOGRAM_BINDIR} ]; then
  mkdir ${WEBOGRAM_BINDIR}
fi
cp ${BASE_DIR}/files/bin/webogram ${WEBOGRAM_BINDIR}
chown -R ${WEBOGRAM_USER}. ${WEBOGRAM_BINDIR}

# Adjust git repository
cd ${WEBOGRAM_HOME_DIR}
if [ ! -d ${WEBOGRAM_GITDIR} ]; then 
  echo "Cloning webogram git repository..."
  su -c "cd ${WEBOGRAM_HOMEDIR} && git clone ${WEBOGRAM_REPO} ${WEBOGRAM_GITDIR}" -l ${WEBOGRAM_USER}
else
  echo "Pulling data from webogram git repository..."
  su -c "cd ${WEBOGRAM_GITDIR} && git pull" -l ${WEBOGRAM_USER}
fi
WEBOGRAM_LATESTSTABLEVER=$(su -c "cd ${WEBOGRAM_GITDIR} && git tag|grep 'v'|sort -r|head -n1" -l ${WEBOGRAM_USER})
if [ "${WEBOGRAM_VERSION}" != "latest" ]; then
  echo "Checking out ${WEBOGRAM_VERSION}..."
  su -c "cd ${WEBOGRAM_GITDIR} && git checkout ${WEBOGRAM_VERSION}"
  if [ $? -ne 0 ]; then
    echo "Ref ${WEBOGRAM_VERSION} does not exist. Defaulting to ${WEBOGRAM_LATESTSTABLEVER}"
    su -c "cd ${WEBOGRAM_GITDIR} && git checkout ${WEBOGRAM_LATESTSTABLEVER}"
  fi
else
  echo "Checking out ${WEBOGRAM_LATESTSTABLEVER}..."
  su -c "cd ${WEBOGRAM_GITDIR} && git checkout ${WEBOGRAM_LATESTSTABLEVER}" -l ${WEBOGRAM_USER}
fi

# Check permissions for npm folder
echo "Checking permissions for npm folder..."
if [ -d ${WEBOGRAM_HOMEDIR}/.npm ]; then
  sudo chown -R ${WEBOGRAM_USER}. ${WEBOGRAM_HOMEDIR}/.npm
fi

# Install node dependencies
echo "Installing gulp..."
su -c "cd ${WEBOGRAM_GITDIR} && NODE_PATH=${WEBOGRAM_HOMEDIR}/.npm npm -g update gulp" -l ${WEBOGRAM_USER}
if [ $? -ne 0 ]; then
  echo "Errors installing gulp! Check log!"
  exit 9
fi

# Install node dependencies
echo "Installing node dependencies..."
su -c "cd ${WEBOGRAM_GITDIR} && NODE_PATH=${WEBOGRAM_HOMEDIR}/.npm npm update" -l ${WEBOGRAM_USER}
if [ $? -ne 0 ]; then
  echo "Errors installing node dependencies! Check log!"
  exit 10
fi

echo "Installation/update complete."
echo "No need to restart the application or the service (if enabled) as gulp will take care of everything"
exit 0
