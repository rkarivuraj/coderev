#!/bin/bash
#
# Homepage: http://code.google.com/p/coderev
# License: GPLv2, see "COPYING"
#
# Generate code review page of <workspace> vs <workspace>@HEAD, by using
# `codediff.py' - a standalone diff tool
#
# Usage: cd your-workspace; coderev.sh [options] [file...]
#
# $Id$

PROG_NAME=$(basename $0)
BINDIR=$(cd $(dirname $0) && pwd -L) || exit 1
CODEDIFF=$BINDIR/codediff.py

function help
{
    cat << EOF

Usage:
    $PROG_NAME [-r revsion] [-w width] [-o outdir] [-y]  \\
               [-F comment-file | -m 'comments ...'] [file...]

    \`revision' is a revision number, or symbol (PREV, BASE, HEAD) in svn,
    see svn books for details.  Default revision is revision of your working
    copy.

    \`width' is a number to make code review pages wrap in specific column.

    \`outdir' is the output dir to save code review pages, '-y' is to force
    overwrite if dest dir exists.

    \`comment-file' is a file to read comments.

    \`comments' is inline comments, note '-m' precedes '-F'.

    \`file' is file/subdir list you want to diff, default is \`.', note you
    can also rediect input to a patch file.

Example 1:
    $PROG_NAME -w80 bin lib

    Generate coderev based on diffs between your base revision and locally
    modified revision, web pages wrap in column 80.  If you are working on the
    most up-to-date version, this is suggested way (faster).  Output pages
    will be saved to a temp directory.

Example 2 (for SVN):
    $PROG_NAME -r HEAD -o ~/public_html/coderev bin lib

    Generate coderev based on diffs between HEAD revision (up-to-date version
    in repository) and locally modified revision, this will retrieve diffs
    from SVN server so it's slower, but most safely.

Example 3:
    cat hotfix.patch | $PROG_NAME -p1 -m 'applying hot fix'

    Generate coderev with the patch set \`hotfix.patch' (\`-p1' will be passed
    to \`patch' utility), use 'applying hot fix' as comments

Example 4 (for SVN):
    svn diff -r PREV foo bar/ | $PROG_NAME -w80 -F comments

    Generate coderev based on diffs between PREV revision and working files
    (modified or not), use content in file \`comments' as comments.

EOF

    return 0
}

function get_list_from_patch
{
    local patch=${1?"patch file required"}

    if [[ $(head -1 $patch) =~ ^Index:\ .+ ]]; then
        grep '^Index: ' $patch | sed 's/.* //'
    elif [[ $(head -1 $patch) =~ ^diff\ .+\ .+ ]]; then
        grep '^diff .+ .+' $patch | sed 's/.* //'
    else
        echo "Unknown patch format." >&2
        return 1
    fi

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
COMMENT_FILE=
COMMENTS=
OUTPUT_DIR=
PATCH_LVL=0
REV_ARG=
REVERSE_PATCH=false
WRAP_NUM=
OVERWRITE=false

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
        p) PATCH_LVL="$OPTARG" ;;
        r) REV_ARG="$OPTARG" ;;
        w) WRAP_NUM="$OPTARG" ;;
        y) OVERWRITE=true ;;
        ?) help; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
PATHNAME="${@:-.}"

# If terminal opened fd 0 then we aren't receiving patch from stdin
if [[ -t 0 ]]; then
    RECV_STDIN=false
else
    RECV_STDIN=true
fi

BANNER=$($vcs_get_banner) || {
    echo "Unsupported version control system ($BANNER)." >&2
    exit 1
}
echo -e "\nVersion control system \"$BANNER\" detected."

# Retrieve information
#
echo -e "\nRetrieving information..."
PROJ_PATH=$($vcs_get_project_path)
WS_NAME=$(basename $PROJ_PATH)
if [[ $PATHNAME == "-" ]]; then
    WS_REV=$($vcs_get_working_revision .)
else
    WS_REV=$($vcs_get_working_revision $PATHNAME)
fi
echo "  * Repository       : $($vcs_get_repository)"
echo "  * Project path     : $PROJ_PATH"
echo "  * Working revision : $WS_REV"

# Prepare file list and base source
#
TMPDIR=$(mktemp -d /tmp/coderev.XXXXXX) || exit 1
LIST="$TMPDIR/activelist"
DIFF="$TMPDIR/diffs"
BASE_SRC="$TMPDIR/$WS_NAME-base"

if $RECV_STDIN; then
    echo -e "\nReceiving diffs..."
    # TODO: consider format other than svn diff
    sed '/^Property changes on:/,/^$/d' | grep -v '^$' > $DIFF || exit 1
    get_list_from_patch $DIFF > $LIST || exit 1
else
    $vcs_get_active_list $PATHNAME > $LIST || exit 1
fi

[[ -s "$LIST" ]] || {
    echo "No active file found."
    exit 0
}
echo -e "\nActive file list:"
sed 's/^/  * /' $LIST

# Generate $BASE_SRC
#
mkdir -p $BASE_SRC || exit 1
tar -cf - $(cat $LIST) | tar -C $BASE_SRC -xf - || exit 1

if $RECV_STDIN; then
    PATCH_LVL=${PATCH_LVL:-0}
else
    echo -e "\nRetrieving diffs..."
    VCS_REV_OPT=""
    [[ -n $REV_ARG ]] && VCS_REV_OPT="$($vcs_get_diff_opt $REV_ARG)"
    $vcs_get_diff $VCS_REV_OPT $(cat $LIST) > $DIFF || exit 1
    PATCH_LVL=0
fi

# Try patch (dry-run) to detect errors and reverse patch in advance, then do
# real patch
#
PATCH_OPT="-E -t -p $PATCH_LVL -d $BASE_SRC"
PATCH_OUTPUT=$(patch $PATCH_OPT --dry-run < $DIFF 2>&1) || {
    echo "$PATCH_OUTPUT" >&2
    echo "Failed to apply patch!  Code base is not up-to-date?" >&2
    exit 1
}

if echo "$PATCH_OUTPUT" | grep -q 'Reversed .* detected!.*Assuming -R'; then
    REVERSE_PATCH=true
fi

patch $PATCH_OPT < $DIFF

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
        COMMENT_TAG="--Enter comments above. \
This line and those below will be ignored--"
        echo -e "\n$COMMENT_TAG" >> $COMMENT_FILE
        echo -e "\n(hint: use '-F' option for comment file)" >> $COMMENT_FILE
        echo -e "\nActive file list:" >> $COMMENT_FILE
        cat $LIST | sed 's/^/  /' >> $COMMENT_FILE
        echo -e "\n# vim:set ft=svn:" >> $COMMENT_FILE

        # Redirect stdin, otherwise vim complains & term corrupt after quit vim
        $RECV_STDIN && exec < /dev/tty
        ${EDITOR:-vi} $COMMENT_FILE
        sed -i '/^--.*--$/, $ d' $COMMENT_FILE
    }
    CODEDIFF_OPT="$CODEDIFF_OPT -F $COMMENT_FILE"
else
    CODEDIFF_OPT="$CODEDIFF_OPT -m '$COMMENTS'"
fi

[[ -n "$WRAP_NUM" ]] && CODEDIFF_OPT="-w $WRAP_NUM"
$OVERWRITE && CODEDIFF_OPT="$CODEDIFF_OPT -y"

# Generate coderev
#
echo -e "\nGenerating code review..."
if $RECV_STDIN && ! $REVERSE_PATCH ; then
    eval $CODEDIFF $CODEDIFF_OPT . $BASE_SRC || exit 1
else
    eval $CODEDIFF $CODEDIFF_OPT $BASE_SRC . || exit 1
fi
echo -e "\nCoderev pages generated at $CODEREV"

# Cleanup
#
rm -rf $LIST $DIFF $BASE_SRC

# Copy to web host if output dir is generated automatically
#
if [[ -z "$OUTPUT_DIR" ]]; then
    [[ -r ~/.coderevrc ]] || {
        echo
        echo "[*] Hint: if you want to copy coderev pages to a remote host"
        echo "    automatically, see coderevrc.sample"
        echo
        exit 0
    }

    : ${WEB_HOST?"WEB_HOST not defined."}
    : ${SSH_USER?"SSH_USER not defined."}
    : ${HOST_DIR?"HOST_DIR not defined."}
    : ${WEB_URL?"WEB_URL not defined."}

    echo -e "\nCopying to ${SSH_USER}@${WEB_HOST}:$HOST_DIR/..."
    scp -rpq $CODEREV ${SSH_USER}@${WEB_HOST}:$HOST_DIR/ || exit 1

    echo -e "\nCoderev link:"
    echo "$WEB_URL/$(basename $CODEREV)"
    echo
fi

exit 0
