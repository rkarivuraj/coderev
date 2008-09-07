#!/bin/bash
#
# Homepage: http://code.google.com/p/coderev
# License: GPLv2, see "COPYING"
#
# Generate code review page of <workspace> vs <workspace>@HEAD, by using
# `codediff.py' - a standalone diff tool
#
# Usage: cd your-workspace; coderev.sh [file|subdir ...]
#
# $Id$

PROG_NAME=$(basename $0)
BINDIR=$(cd $(dirname $0) && pwd -L) || exit 1
CODEDIFF=$BINDIR/codediff.py

function help
{
    cat << EOF

Usage:
    $PROG_NAME [-r revsion] [-w width] [-o outdir] [-y] \\
               [-F comment-file | -m 'comments'] [file|subdir ...]

    \`revision' is a revision number, or symbol (PREV, BASE, HEAD) in svn,
    see svn books for details.  Default revision is revision of your working
    copy.

    \`width' is a number to make code review pages wrap in specific column.

    \`outdir' is the output dir to save code review pages, '-y' is to force
    overwrite if dest dir exists.

    \`comment-file' is a file to read comments.

    \`comments' is inline comments, note '-m' precedes '-F'.

    Default \`subdir' is working dir.

Example 1:
    $PROG_NAME -w80 bin lib

    Generate coderev based on your working copy, web pages wrap in column 80.
    If you are working on the most up-to-date version, this is suggested way
    (faster).  Output pages will be saved to a temp directory.

Example 2 (for SVN):
    $PROG_NAME -r HEAD -o ~/public_html/coderev bin lib

    Generate coderev based on HEAD revision (up-to-date version in repository),
    this will retrieve diffs from SVN server so it's slower, but most safely.

EOF

    return 0
}

####################  VCS Operations Begin #################### 

# Return code: 0 - Unknown, 1 - SVN, 2 - CVS
#
function detect_vcs
{
    [[ -f .svn/entries ]] && return 1
    [[ -f CVS/Entries ]] && return 2
    return 0
}

function set_vcs_ops
{
    local i=${1?}
    local vcs_opt=${VCS_OPS_TABLE[i]}

    eval vcs_get_banner=\${$vcs_opt[0]}
    eval vcs_get_repository=\${$vcs_opt[1]}
    eval vcs_get_project_path=\${$vcs_opt[2]}
    eval vcs_get_working_revision=\${$vcs_opt[3]}
    eval vcs_get_active_list=\${$vcs_opt[4]}
    eval vcs_get_diff=\${$vcs_opt[5]}
    eval vcs_get_diff_opt=\${$vcs_opt[6]}
}

# VCS Operations: 
#   get_banner                        - print banner, return 1 if not supported
#   get_repository                    - print repository
#   get_project_path                  - print project path without repository
#   get_working_revision pathname ... - print working revision
#   get_active_list pathname ...      - print active file list
#   get_diff [diff_opt] pathname ...  - get diffs for active files
#   get_diff_opt                      - print diff option and args

# Unknown ops just defined here, others see libxxx.sh
#
UNKNOWN_OPS=( unknown_get_banner : : : : : : )

function unknown_get_banner
{
    echo "unknown"
    return 1
}

VCS_OPS_TABLE=( UNKNOWN_OPS  SVN_OPS  CVS_OPS )

. $BINDIR/libsvn.sh || exit 1
. $BINDIR/libcvs.sh || exit 1

# Detect VCS (Version Control System) and set handler
#
detect_vcs
set_vcs_ops $?

####################  VCS Operations End #################### 

# Main Proc
#
[[ -r ~/.coderevrc ]] && {
    . ~/.coderevrc || {
        echo "Reading ~/.coderevrc failed." >&2
        exit 1
    }
}

while getopts "F:hm:o:r:w:y" op; do
    case $op in
        F) COMMENT_FILE="$OPTARG" ;;
        h) help; exit 0 ;;
        m) COMMENTS="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        r) REV_ARG="$OPTARG" ;;
        w) WRAP_NUM="$OPTARG" ;;
        y) OVERWRITE=true ;;
        ?) help; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
PATHNAME="${@:-.}"

BANNER=$($vcs_get_banner) || {
    echo "Unsupported version control system ($BANNER)." >&2
    exit 1
}
echo "Version control system \"$BANNER\" detected."

# Retrieve information
#
echo "Retrieving information ..."
PROJ_PATH=$($vcs_get_project_path)
WS_NAME=$(basename $PROJ_PATH)
WS_REV=$($vcs_get_working_revision $PATHNAME)
echo "Repository       : $($vcs_get_repository)"
echo "Project path     : $PROJ_PATH"
echo "Working revision : $WS_REV"

# Prepare file list and base source
#
TMPDIR=$(mktemp -d /tmp/coderev.XXXXXX) || exit 1
LIST="$TMPDIR/activelist"
DIFF="$TMPDIR/diffs"
BASE_SRC="$TMPDIR/$WS_NAME-base"

$vcs_get_active_list $PATHNAME > $LIST || exit 1
echo "==========  Active file list  =========="
cat $LIST
echo "========================================"

# Generate $BASE_SRC
#
mkdir -p $BASE_SRC || exit 1
tar -cf - $(cat $LIST) | tar -C $BASE_SRC -xf - || exit 1

echo "Retrieving diffs ..."
VCS_REV_OPT=""
[[ -n $REV_ARG ]] && VCS_REV_OPT="$($vcs_get_diff_opt $REV_ARG)"
$vcs_get_diff $VCS_REV_OPT $(cat $LIST) > $DIFF || exit 1
patch -NER -p0 -d $BASE_SRC < $DIFF || {
    echo "Warning: reverse patch failed, possibly caused by keywords" \
         "subsititution." >&2
}

# Form codediff options
#
CODEDIFF_OPT="-f $LIST"

CODEREV=$TMPDIR/${WS_NAME}-r${WS_REV}-diff
[[ -n "$OUTPUT_DIR" ]] && CODEREV=$OUTPUT_DIR
CODEDIFF_OPT="$CODEDIFF_OPT -o $CODEREV"

TITLE="Coderev for $(basename $(pwd)) r$WS_REV"
CODEDIFF_OPT="$CODEDIFF_OPT -t '$TITLE'"

if [[ -z "$COMMENTS" ]]; then
    [[ -n "$COMMENT_FILE" ]] || {
        COMMENT_FILE="$TMPDIR/comments-$$"
        COMMENT_TAG="~~Enter comments above. \
This line and those below will be ignored~~"
        echo -e "\n$COMMENT_TAG" >> $COMMENT_FILE
        ${EDITOR:-vi} $COMMENT_FILE
        sed -i '/^~~.*~~$/, $ d' $COMMENT_FILE
    }
    CODEDIFF_OPT="$CODEDIFF_OPT -F $COMMENT_FILE"
else
    CODEDIFF_OPT="$CODEDIFF_OPT -m '$COMMENTS'"
fi

[[ -n "$WRAP_NUM" ]] && CODEDIFF_OPT="-w $WRAP_NUM"
[[ -n "$OVERWRITE" ]] && CODEDIFF_OPT="$CODEDIFF_OPT -y"

# Generate coderev
#
echo "Generating code review ..."
eval $CODEDIFF $CODEDIFF_OPT $BASE_SRC . || exit 1
echo -e "\nCoderev pages generated at $CODEREV"
echo

# Cleanup
#
rm -rf $LIST $DIFF $BASE_SRC

# Copy to web host if output dir is generated automatically
#
if [[ -z "$OUTPUT_DIR" ]]; then
    [[ -r ~/.coderevrc ]] || {
        echo "[*] Hint: if you want to copy coderev pages to a remote host"
        echo "    automatically, see coderevrc.sample"
        echo
        exit 0
    }

    : ${WEB_HOST?"WEB_HOST not defined."}
    : ${SSH_USER?"SSH_USER not defined."}
    : ${HOST_DIR?"HOST_DIR not defined."}
    : ${WEB_URL?"WEB_URL not defined."}

    scp -r $CODEREV ${SSH_USER}@${WEB_HOST}:$HOST_DIR/ || exit 1

    echo
    echo "Coderev link:"
    echo "$WEB_URL/$(basename $CODEREV)"
    echo
fi

exit 0
