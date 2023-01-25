#!/bin/bash -e

cmp() {
    if test "$1" = "$2"; then
        echo "success"
    else
        echo "failed"
        return -1
    fi
}

check() {
    echo -n "testing if $1 resolves ... "
    if ! cmp "$(LANG= wget -O/dev/null $1 2>&1 | sed -n 's/^Resolving.*127\.0\.0\.1.*/FOUND/p')" "FOUND"; then
        echo "**** Name Resolution Failed - did you configure /etc/hosts?"
        return -1
    fi
    echo -n "testing if return code of $1 is ${2:-200} ... "
    cmp "$(LANG= wget -O/dev/null $1 2>&1 | sed -n 's/^HTTP request sent.*\.\.\. \([0-9]\+\).*/\1/p')" "${2:-200}"
    if test "${2:-200}" = "200"; then
        echo -n "testing if $1 delivers html ... "
        cmp "$(wget -qO- $1 | head -1 )" "<!DOCTYPE html>"
    fi
}

check http://localhost:8080 200
check http://demo:8080 200
check http://test:8080 200
check http://doesnotrun:8080 502
check http://lokal:8080 404

echo "#### SUCCESS ####"
