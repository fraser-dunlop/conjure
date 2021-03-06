#!/bin/bash

set -o errexit
set -o nounset

export BIN_DIR=${BIN_DIR:-${HOME}/.local/bin}

rm -rf ${BIN_DIR}/tmp-install-minion
mkdir ${BIN_DIR}/tmp-install-minion
pushd ${BIN_DIR}/tmp-install-minion

OS=$(uname)

if [ "$OS" == "Darwin" ]; then
    wget --no-check-certificate -c https://savilerow.cs.st-andrews.ac.uk/savilerow-1.7.0RC-mac.tgz
    tar zxf savilerow-1.7.0RC-mac.tgz
    mv savilerow-1.7.0RC-mac/bin/minion ${BIN_DIR}/minion
elif [ "$OS" == "Linux" ]; then
    wget --no-check-certificate -c https://savilerow.cs.st-andrews.ac.uk/savilerow-1.7.0RC-linux.tgz
    tar zxf savilerow-1.7.0RC-linux.tgz
    mv savilerow-1.7.0RC-linux/bin/minion ${BIN_DIR}/minion
else
    echo "Cannot determine your OS, uname reports: ${OS}"
    exit 1
fi

echo "minion executable is at ${BIN_DIR}/minion"
ls -l ${BIN_DIR}/minion
popd
rm -rf ${BIN_DIR}/tmp-install-minion

