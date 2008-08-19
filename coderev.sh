#!/bin/bash
#
# Homepage: http://code.google.com/p/coderev
# License: GPLv2, see "COPYING"
#
# Generate code review page of <workspace> vs <workspace>@HEAD, by using
# `codediff.py' - a standalone diff tool
#
# Usage: coderev.sh [subdir ...]
#
# $Id$

PROG_NAME=$(basename $0)

function help
{
    cat << EOF

Usage:
    $PROG_NAME [-r revsion] [subdir ...]

    \`revision' is a revision number, or symbol (PREV, BASE, HEAD), see svn
    books for details.  Default revision is revision of your working copy
    (aka. BASE)

    Default \`subdir' is working dir.

Example 1:
    $PROG_NAME bin lib

    Generate coderev based on your working copy.  If you are working on the
    most up-to-date version, this is suggested way (faster).

Example 2:
    $PROG_NAME -r HEAD bin lib

    Generate coderev based on HEAD revision (up-to-date version in repository),
    this will retrive diffs from SVN server so it's slower, but most safely.

EOF

    return 0
}

while getopts "r:h" op; do
    case $op in
        r) REV="$OPTARG" ;;
        h) help; exit 0 ;;
        ?) help; exit 1 ;;
    esac
done

shift $((OPTIND - 1))
SUBDIRS="$@"

[[ -n "$REV" ]] && SVN_OPT="-r $REV"

# Get codediff path
#
BINDIR=$(cd $(dirname $0) && pwd -L) || exit 1
CODEDIFF=$BINDIR/codediff.py

# Retrive SVN information
#
echo "Retriving SVN information ..."
URL=$(svn info | grep '^URL:' | awk '{print $2}') || exit 1
WS_NAME=$(basename "$URL")
WS_REV=$(svn info | grep 'Revision:' | awk '{print $2}') || exit 1
BASE_REV=$(svn info $SVN_OPT | grep 'Revision:' | awk '{print $2}') || exit 1
echo "URL     : $URL"
echo "WS_REV  : $WS_REV"
echo "BASE_REV: $BASE_REV"


# Prepare file list and base source
#
LIST=$(mktemp /tmp/list.XXXXXX) || exit 1
DIFF=$(mktemp /tmp/diff.XXXXXX) || exit 1
BASE_SRC="/tmp/${WS_NAME}@${BASE_REV}"

for file in $(svn st $SUBDIRS | grep '^[A-Z]' | awk '{print $2}'); do
    [[ -d $file ]] && continue
    echo $file >> $LIST || exit 1
done

echo "Active file list:"
echo "============================"
cat $LIST
echo "============================"

# Generate $base_src
#
mkdir -p $BASE_SRC || exit 1
tar -cf - $(cat $LIST) | tar -C $BASE_SRC -xf - || exit 1

echo "Retriving diffs ..."
svn diff $SVN_OPT $(cat $LIST) > $DIFF || exit 1
cat $DIFF | patch -NER -p0 -d $BASE_SRC || exit 1

# Generate coderev
#
CODEREV=/tmp/${WS_NAME}-diff-${BASE_REV}
cat $LIST | $CODEDIFF -o $CODEREV -w80 -y -f- $BASE_SRC . || exit 1

echo
echo "Coderev generated under $CODEREV"
echo

# Cleanup
#
rm -rf $LIST $DIFF $BASE_SRC


##############################################################################
#
# Customize your webdir to save coderev:
#
# 1. define WEBHOST, SSH_USER, HOST_DIR and WEBDIR
# 2. Comment out the line ":<< \__copy_to_webserver__" below
#
##############################################################################

: << __copy_to_webserver__

WEBHOST=example.org
SSH_USER=me
HOST_DIR='~/public_html/coderev'
WEBDIR="http://$WEBHOST/~$SSH_USER/coderev"

scp -r $CODEREV ${SSH_USER}@${WEBHOST}:$HOST_DIR/ || exit 1

echo
echo "Coderev link:"
echo "$WEBDIR/$(basename $CODEREV)"
echo

exit 0

__copy_to_webserver__
