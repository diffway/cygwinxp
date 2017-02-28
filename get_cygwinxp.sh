#!/bin/bash
##
# debug switch
_DEBUG=

#       Download Cygwin packages compatible with Windows XP
#         ===================================================
#
#    Created based on information from the FruitBat.org:
#               http://www.fruitbat.org/Cygwin/timemachine.html
#    Setup files will be downloaded into current directory.
#   Repo structure will be created into "./CygwinXP" directory.
#    Once downloaded use the setup to install from local repository.
#
#                                            czvtools @ 2016
#

# latest XP Compatible setup.exe version is v2.874
XP_VER=2.874
# Officical cygwin mirror
CYGWIN_TIMEMACHINE=ftp://www.fruitbat.org/pub/cygwin

# 3 at the same time.
WGET_PROCESSES=3
# set reasonable wget exec string
WGET_BIN="wget --continue --quiet"


# Download the official mirrors list and the known compatible setup file
( mkdir -p ./CygwinXP && cd ./CygwinXP && { [[ -s ./mirrors.lst ]] || ${WGET_BIN} https://cygwin.com/mirrors.lst; } )
# 32bit version
mkdir -p ./CygwinXP/cygwinxp.local/x86
(   cd ./CygwinXP/cygwinxp.local/x86;
    [[ -s setup-x86-2.874.exe ]] || ${WGET_BIN} ${CYGWIN_TIMEMACHINE}/setup/snapshots/setup-x86-2.874.exe
    && [[ -s setup.ini ]] || { ${WGET_BIN} ${CYGWIN_TIMEMACHINE}/circa/2016/08/30/104223/x86/setup.bz2 \
    && bunzip2 setup.bz2 && mv setup setup.ini; } )

# 64 bit version
mkdir -p ./CygwinXP/cygwinxp.local/x86_64
(   cd ./CygwinXP/cygwinxp.local/x86_64;
    [[ -s setup-x86_64-2.874.exe ]] || ${WGET_BIN} ${CYGWIN_TIMEMACHINE}/setup/snapshots/setup-x86_64-2.874.exe
    && [[ -s setup.ini ]] || { ${WGET_BIN} ${CYGWIN_TIMEMACHINE}/circa/64bit/2016/08/30/104235/x86_64/setup.bz2 \
    && bunzip2 setup.bz2 && mv setup setup.ini; } )

# Mirrors will be used to retrieve packages in paralel wihtout loading only a single site
typeset -A MIRRORS
typeset -i M=0
while IFS=";" read -r URL HOST
do
    MIRRORS[$M]="$URL"
    ((M++))
done < ./CygwinXP/mirrors.lst

# retrieve one package from the first random valid place (last 3 are best candidates that we don't want to stress)
get_one () {

    local REL_PATH="$1"

    # Attempt from multiple servers because most of the content doesn't change so often
    ${WGET_BIN} "${MIRRORS[$((RANDOM%M))]}$REL_PATH" \
        || ${WGET_BIN} "${MIRRORS[$((RANDOM%M))]}$REL_PATH" \
        || ${WGET_BIN} "${MIRRORS[$((RANDOM%M))]}$REL_PATH" \
        || ${WGET_BIN} "${MIRRORS[$((RANDOM%M))]}$REL_PATH" \
        || ${WGET_BIN} "${MIRRORS[$((RANDOM%M))]}$REL_PATH" \
        || ${WGET_BIN} "http://ftp.cc.uoc.gr/mirrors/cygwin/$REL_PATH" \
        || ${WGET_BIN} "http://cygwin.mirror.constant.com/$REL_PATH" \
        || ${WGET_BIN} "${CYGWIN_TIMEMACHINE}/circa/2016/08/30/104223/$REL_PATH" \
    && move_one "${REL_PATH}" || return 1
}

##
# moves package to its dir
#
function move_one () {

    local REL_PATH="$1"

    local PACKAGE_FILE="${REL_PATH##*/}"
    local PACKAGE_PATH="${REL_PATH%/*}"

    if [ -s "${PACKAGE_FILE}" ]
    then
        mkdir -vp "../${PACKAGE_PATH}" \
            && mv -v "${PACKAGE_FILE}" "../${PACKAGE_PATH}" || return 1
        return 0
    else
        return 1
    fi
}


# Replace "x86" with "x86_64" (and vice versa)
cd ./CygwinXP/cygwinxp.local/x86

[ -n "${_DEBUG}" ] && echo "# PWD: $PWD"

PACKAGES=( $(awk '/^@/{print $2}' setup.ini ) )

for ((COUNT=0;COUNT<${#PACKAGES[@]};COUNT++))
do
    # pick next package
    PACKAGE="${PACKAGES[$COUNT]}"

    while read -r REL_PATH SIZE_B SHA512
    do
        if [[ -f "../${REL_PATH}" ]]
        then
            # skip packages that are already present
            continue
        elif [[ $COUNT -lt 1 ]]
        then
             # skip a certain number of packages... should be customized
             continue
        else
            # download packages in background...
            echo "===== ${COUNT} : ${REL_PATH}"
            get_one "${REL_PATH}" >/dev/null 2>&1 &
        fi

        # not much at the same time.
        while [[ $(jobs |wc -l) -gt ${WGET_PROCESSES} ]]; do sleep 1; done

        if [ -f "../${REL_PATH}" ]
        then
            echo "===== ${COUNT}: ${REL_PATH} failed: file not found." >&2
            # now go to next download
            continue
        fi

        if [[ $(stat -c '%s' "../${REL_PATH}") -ne "${SIZE_B}" ]]
        then
            echo "===== ${COUNT}: ${REL_PATH} size mismatch." >&2
            rm -f "../$REL_PATH"
        fi

    done < <(sed --regexp-extended \
        -e '/^@[[:space:]]+'"${PACKAGE}"'$/,/^$/!d' setup.ini \
            |awk '/^install:/{print $2, $3, $4}')
done

exit 1
