#!/bin/bash
#
# Homepage: http://code.google.com/p/coderev
# License: GPLv2, see "COPYING"
#
# Generate code review page of <workspace> vs <workspace>@HEAD, by using
# `codediff.py' - a standalone diff tool
#
# $Id$

if [[ -L $0 ]]; then
    # Note readlink is not compatible
    BINDIR=$(dirname $(/bin/ls -l $0 | awk -F ' -> ' '{print $2}'))
else
    BINDIR=$(cd $(dirname $0) && pwd -P) || exit 1
fi

PROG_NAME=$(basename $0)
CODEDIFF=$BINDIR/codediff.py

function help
{
    cat << EOF

Usage:
    $PROG_NAME [-r revision] [-w width] [-o outdir] [-y] \\
               [-F comment-file | -m 'comment...'] [file...]

    $PROG_NAME [-r revision] [-w width] [-o outdir] [-y] \\
               [-F comment-file | -m 'comment...'] [-p num] < patch-file

    All options are optional.

    -r revision     - Specify a revision number, or symbol (PREV, BASE, HEAD)
                      in svn, see svn books for details.  Default revision is
                      revision of your working copy

    -w width        - Let code review pages wrap in specific column

    -o outdir       - The output dir to save code review pages

    -y              - Force overwrite if outdir alredy exists

    -F comment-file - A file to read comments from

    -m 'comment...' - To set inline comments, note '-m' precedes '-F', if
                      neither \`-F' nor \`-m' is specified, \$EDITOR (default
                      is vi) will be invoked to write comments

    file...         - File/dir list you want to diff, default is \`.'

    patch-file      - A patch file (usually generated by \`diff(1)' or \`svn
                      diff') to use to generate coderev

    -p num          - When use a patch file, this option is passed to utility
                      \`patch(1)' to strip the smallest prefix containing num
                      leading slashes from each file name found in the patch

Example 1:

    You are working on the most up-to-date revision and made some local
    modification, now you want to invite others to review, just run

        cd workspace
        $PROG_NAME -w80

    This generates coderev pages (wrap in column 80) in a temp directory.  Then
    copy the coderev dir to somewhere on a web host and send out the link for
    review.  Read coderevrc.sample for how to make this automated.

Example 2:

    You are making local modification when someone else committed some changes
    on foo.c and bar directory, you want to see what's different between your
    copy and the up-to-date revision in repository, just run

        cd workspace
        $PROG_NAME -r HEAD -o ~/public_html/coderev foo.c bar/

    This generate coderev based on diffs between HEAD revision (up-to-date
    version in repository) and locally modified revision, this will retrieve
    diffs from SVN server, output pages saved under your web home, i.e., if
    you correctly configured a web server on your work station you can visit
    http://server/~you/coderev to see the coderev.  (Replace HEAD with a
    revision number this example also works for CVS).

Example 3:

    Someone invite you to review his code change, unfortunately he sent you raw
    diff generated by \`cvs diff' named \`foo.patch', you can run

        cd workspace
        cvs up
        $PROG_NAME -m 'applying patch foo' -o ~/public_html/foo < foo.patch

    Again, you can visit http://server/~you/foo to see his change.  Note you
    may need to use option \`-p num' depends on how he generated the patch.

Example 4:

    You want to see what's different between previous revision and your
    current working copy (modified or not) for foo.c and dir bar/, just run

        cd workspace
        svn diff -r PREV foo.c bar/ | $PROG_NAME -w80 -F comments

    This read comments from file \`comments' and generate coderev in a temp
    directory.  (Replace PREV with a revision number this example also works
    for CVS).

EOF

    return 0
}

function get_list_from_patch
{
    local patch=${1?"patch file required"}
    local patch_lvl=${2?"patch level required"}

    # The trick is use regex "^([^/]+/){,n}" to match the prefixed subdirs
    #
    if [[ $(head -1 $patch) =~ ^Index:\ .+ ]]; then
        grep '^Index: ' $patch | sed 's/.* //' \
            | sed "s|^\([^/]\+/\)\{,$patch_lvl\}||"
    elif [[ $(head -1 $patch) =~ ^diff\ .+\ .+ ]]; then
        grep '^diff .+ .+' $patch | sed 's/.* //' \
            | sed "s|^\([^/]\+/\)\{,$patch_lvl\}||"
    else
        echo "Unknown patch format." >&2
        return 1
    fi

    return 0
}


####################  VCS Operations Begin #################### 

# Return string: "cvs" for CVS, "svn" for SVN, "unknown" otherwise
#
function detect_vcs
{
    local ident=""

    if [[ -f .svn/entries ]]; then
        ident="svn"
    elif [[ -f CVS/Entries ]]; then
        ident="cvs"
    else
        ident="unknown"
    fi
    echo "$ident"
}

function set_vcs_ops
{
    local ident=${1?}

    eval vcs_get_banner=${ident}_get_banner
    eval vcs_get_repository=${ident}_get_repository
    eval vcs_get_project_path=${ident}_get_project_path
    eval vcs_get_working_revision=${ident}_get_working_revision
    eval vcs_get_active_list=${ident}_get_active_list
    eval vcs_get_diff=${ident}_get_diff
    eval vcs_get_diff_opt=${ident}_get_diff_opt
}

# VCS Operations: 
#   get_banner                        - print banner, return 1 if not supported
#   get_repository                    - print repository
#   get_project_path                  - print project path without repository
#   get_working_revision pathname ... - print working revision
#   get_active_list pathname ...      - print active file list
#   get_diff [diff_opt] pathname ...  - get diffs for active files
#   get_diff_opt                      - print diff option and args

function unknown_get_banner
{
    echo "unknown"
    return 1
}

. $BINDIR/libsvn.sh || exit 1
. $BINDIR/libcvs.sh || exit 1

# Detect VCS (Version Control System) and set handler
#
set_vcs_ops $(detect_vcs)

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

while getopts "F:hm:o:p:r:w:y" op; do
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
[[ -t 0 ]] && RECV_STDIN=false || RECV_STDIN=true

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
ACTIVE_LIST="$TMPDIR/activelist"
DIFF="$TMPDIR/diffs"
BASE_SRC="$TMPDIR/$WS_NAME-base"

if $RECV_STDIN; then
    echo -e "\nReceiving diffs..."
    # TODO: consider format other than svn diff
    sed '/^Property changes on:/,/^$/d' | grep -v '^$' > $DIFF || exit 1

    # Redirect stdin, otherwise vim will complain and corrupt term after quit,
    # or codediff.py cannot get confirmation before overwrite outdir
    #
    $RECV_STDIN && exec < /dev/tty

    get_list_from_patch $DIFF $PATCH_LVL > $ACTIVE_LIST || exit 1
else
    $vcs_get_active_list $PATHNAME > $ACTIVE_LIST || exit 1
fi

[[ -s "$ACTIVE_LIST" ]] || {
    echo "No active file found."
    exit 0
}
echo -e "\nActive file list:"
sed 's/^/  * /' $ACTIVE_LIST

# Generate $BASE_SRC
#
mkdir -p $BASE_SRC || exit 1

SRC_LIST=""
for f in $(cat $ACTIVE_LIST); do
    [[ -e $f ]] && SRC_LIST+=" $f"
done

if [[ -n $SRC_LIST ]]; then
    tar -cf - $SRC_LIST | tar -C $BASE_SRC -xf - || exit 1
fi

if $RECV_STDIN; then
    PATCH_LVL=${PATCH_LVL:-0}
else
    echo -e "\nRetrieving diffs..."
    VCS_REV_OPT=""
    [[ -n $REV_ARG ]] && VCS_REV_OPT="$($vcs_get_diff_opt $REV_ARG)"
    $vcs_get_diff $VCS_REV_OPT $(cat $ACTIVE_LIST) > $DIFF || exit 1
    # PATCH_LVL default to 0
fi

# Try patch (dry-run) to detect errors and reverse patch in advance, then do
# real patch
#
PATCH_OPT="-E -t -p $PATCH_LVL -d $BASE_SRC"
PATCH_OUTPUT=$(patch $PATCH_OPT --dry-run < $DIFF 2>&1) || {
    echo "$PATCH_OUTPUT" >&2
    echo "Failed to apply patch (dry-run), aborting..." >&2
    exit 1
}

# Option "-q" of grep is not compatible
echo "$PATCH_OUTPUT" | grep 'Reversed .* detected.*Assuming -R' >/dev/null && {
    REVERSE_PATCH=true
    PATCH_OPT+=" -R"
}
patch $PATCH_OPT < $DIFF

# Form codediff options
#
CODEDIFF_OPT="-f $ACTIVE_LIST"

CODEREV=$TMPDIR/${WS_NAME}-r${WS_REV}-$(date '+%F.%H.%M.%S')
[[ -n "$OUTPUT_DIR" ]] && CODEREV=$OUTPUT_DIR
CODEDIFF_OPT+=" -o $CODEREV"

TITLE="Coderev for $(basename $(pwd)) r$WS_REV"
CODEDIFF_OPT+=" -t '$TITLE'"

if [[ -z "$COMMENTS" ]]; then
    [[ -n "$COMMENT_FILE" ]] || {
        COMMENT_FILE="$TMPDIR/comments-$$"
        COMMENT_TAG="--Enter comments above. \
This line and those below will be ignored--"
        echo -e "\n$COMMENT_TAG" >> $COMMENT_FILE
        echo -e "\n(hint: use '-F' option for comment file)" >> $COMMENT_FILE
        echo -e "\nActive file list:" >> $COMMENT_FILE
        cat $ACTIVE_LIST | sed 's/^/  /' >> $COMMENT_FILE
        echo -e "\n# vim:set ft=svn:" >> $COMMENT_FILE

        [[ -n "$EDITOR" ]] || {
            if which vim >/dev/null 2>&1; then
                EDITOR=vim
            else
                EDITOR=vi
            fi
        }
        ${EDITOR} $COMMENT_FILE
        sed -i '/^--.*--$/, $ d' $COMMENT_FILE
    }
    CODEDIFF_OPT+=" -F $COMMENT_FILE"
else
    CODEDIFF_OPT+=" -m '$COMMENTS'"
fi

[[ -n "$WRAP_NUM" ]] && CODEDIFF_OPT+=" -w $WRAP_NUM"
$OVERWRITE && CODEDIFF_OPT+=" -y"

# Generate coderev
#
echo -e "\nGenerating code review..."
if $REVERSE_PATCH ; then
    eval $CODEDIFF $CODEDIFF_OPT $BASE_SRC . || exit 1
else
    eval $CODEDIFF $CODEDIFF_OPT . $BASE_SRC || exit 1
fi
echo -e "\nCoderev pages generated in $CODEREV"

# Cleanup
#
rm -rf $ACTIVE_LIST $DIFF $BASE_SRC

# Copy to web host if output dir is generated automatically
#
if [[ -z "$OUTPUT_DIR" ]]; then
    [[ -r /etc/coderevrc ]] || [[ -r ~/.coderevrc ]] || {
        echo
        echo "[*] Hint: if you want to copy coderev pages to a remote host"
        echo "    automatically, see coderevrc.sample"
        echo
        exit 0
    }

    [[ -r /etc/coderevrc ]] && {
        . /etc/coderevrc || {
            echo "Reading /etc/coderevrc failed." >&2
            exit 1
        }
    }

    [[ -r ~/.coderevrc ]] && {
        . ~/.coderevrc || {
            echo "Reading ~/.coderevrc failed." >&2
            exit 1
        }
    }

    : ${HOST_DIR?"HOST_DIR not defined."}
    : ${WEB_URL?"WEB_URL not defined."}
    [[ -n $SSH_USER ]] || SSH_USER=$(whoami)

    LOC_PREFIX=""
    [[ -n $WEB_HOST ]] && LOC_PREFIX="${SSH_USER}@${WEB_HOST}:"

    echo -e "\nCopying to ${LOC_PREFIX}$HOST_DIR/..."
    eval scp -rpq $CODEREV ${LOC_PREFIX}$HOST_DIR/ || exit 1

    echo -e "\nCoderev link:"
    echo "$WEB_URL/$(basename $CODEREV)"
    echo
    rm -rf $TMPDIR
else
    rm -rf $TMPDIR
fi

exit 0
