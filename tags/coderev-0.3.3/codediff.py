#!/usr/bin/env python
#
# Homepage: http://code.google.com/p/coderev
# License: GPLv2, see "COPYING"
#

'''
Diff two files/directories and produce HTML pages.
Class: CodeDiffer
Method: make_diff()
Exception: CodeDifferError
Following templates could be customized after init:
    _index_template
    _style_template
    _header_info_template
    _comments_template
    _summary_info_template
    _data_rows_template
    _diff_data_row_template
    _deleted_data_row_template
    _added_data_row_template
    _footer_info_template
'''

_id_ = '$Id$'

import sys, os, stat, errno, time, re, difflib, filecmp

_global_dir_ignore_list = (
    r'^CVS$',
    r'^SCCS$',
    r'^\.svn$',
)

_global_file_ignore_list = (
    r'.*\.o$',
    r'.*\.swp$',
    r'.*\.bak$',
    r'.*\.old$',
    r'.*~$',
    r'^\.cvsignore$',
)

def get_myname():
    svn_id = _id_.split()
    if len(svn_id) > 1:
        return svn_id[1]
    else:
        return '???'

def get_myrev():
    svn_id = _id_.split()
    if len(svn_id) > 2:
        return svn_id[2]
    else:
        return '???'

def make_title(pathname, width):
    'Wrap long pathname to abbreviate name to fit the text width'
    if not pathname:
        return 'None'

    if not width or width <= 0:
        title = pathname
    elif len(pathname) > width:
        if width > 3:
            title = '...' + pathname[-(width-3):]
        else:
            title = pathname[-width:]
    else:
        title = pathname
    return title


def get_lines(file):
    '''Return content of file (a list, each is a line)'''
    fp = open(file, 'r')
    lines = fp.readlines()
    fp.close()
    return lines


def write_file(file, content):
    f = open(file, 'w')
    f.write(content)
    f.close()


def sdiff_lines(from_lines, to_lines, from_title, to_title, use_context,
                wrap_num, context_line):
    '''
    Generate side by side diff and return html, if use_context is False,
    then all context around diff will be output
    '''
    d = difflib.HtmlDiff(tabsize=8, wrapcolumn=wrap_num)
    d._styles += '''
        /* customized style */
        body { font-family:monospace; font-size: 9pt; }
        table.diff {font-family:monospace; border:medium;}'''
    html = d.make_file(from_lines, to_lines, from_title, to_title, use_context,
                       context_line)
    return html


def cdiff_lines(from_lines, to_lines, from_name, to_name,
               from_date, to_date, context_line):
    'cdiff two text, return summary info and html content'
    d = difflib.context_diff(from_lines, to_lines, from_name, to_name,
                             from_date, to_date, context_line)
    title = 'Cdiff of %s and %s' % (from_name, to_name)
    summary, html = cdiff_to_html(d, title)
    return summary, html


def udiff_lines(from_lines, to_lines, from_name, to_name,
               from_date, to_date, context_line):
    'udiff two texts and return html page'
    d = difflib.unified_diff(from_lines, to_lines, from_name, to_name,
                             from_date, to_date, context_line)
    title = 'Udiff of %s and %s' % (from_name, to_name)
    html = udiff_to_html(d, title)
    return html


def html_filter(s):
    return s.replace('&', '&amp;').replace('>', '&gt;').replace('<', '&lt;')


def convert_to_html(src):
    "Read file 'src' and convert to html"
    html = '<html><head><title>%s</title></head><body>' % src
    html += '<pre style="font-family:monospace; font-size:9pt;">'
    lines = get_lines(src)
    for s in lines:
        html += html_filter(s)
    html += '</pre></body></html>'
    return html


def is_binary_file(file):
    '''
    Determine a binary file by reading the first 1024 bytes of the file
    and counting the non-text characters, if the number is great than 8, then
    the file is considered as binary file.  This is not very reliable but is
    effective'''
    non_text = 0
    target_count = 8

    fp = open(file, 'rb')
    data = fp.read(1024)
    for c in data:
        a = ord(c)
        if a < 8 or (a > 13 and a < 32): # not printable
            non_text += 1
            if non_text >= target_count: break
    fp.close()
    return non_text >= target_count


def cdiff_to_html(cdiff, title):
    '''cdiff is context diff (a list) that generated by difflib.context_diff,
    return summary and html page'''
    summary = { 'changed': 0, 'added': 0, 'deleted': 0 }
    line_pattern = '<span class="%s">%s</span>'

    body = ''
    old_group = False
    for line in cdiff:
        n = len(line)
        line = html_filter(line)
        if n >= 4 and line[0:4] == '*** ':
            old_group = True
            body += line_pattern % ('fromtitle', line)
        elif n >= 4 and line[0:4] == '--- ':
            old_group = False
            body += line_pattern % ('totitle', line)
        elif n >= 2 and line[0:2] == '  ':
            body += line_pattern % ('same', line)
        elif n >= 2 and line[0:2] == '! ':
            body += line_pattern % ('change', line)
            if old_group:
                summary['changed'] += 1
        elif n >= 2 and line[0:2] == '- ':
            body += line_pattern % ('delete', line)
            summary['deleted'] += 1
        elif n >= 2 and line[0:2] == '+ ':
            body += line_pattern % ('insert', line)
            summary['added'] += 1
        elif n >= 15 and line[0:15] == '*' * 15:
            body += '<hr>'
        else: # shouldn't happen
            body += line

    html = '''<html><head>
        <title>%s</title>
        <style type="text/css">
            .fromtitle {color:brown; font:bold 11pt;}
            .totitle {color:green; font:bold 11pt;}
            .same {color:black; font:9pt;}
            .change {color:blue; font:9pt;}
            .delete {color:brown; font:9pt;}
            .insert {color:green; font:9pt;}
        </style>
        <body>
            <pre>%s</pre>
        </body>
        </head></html>''' % (title, body)
    return summary, html


def udiff_to_html(udiff, title):
    '''udiff is uniform diff (a list) that generated by difflib.uniform_diff,
    return html page'''

    line_pattern = '<span class="%s">%s</span>'
    body = ''
    for line in udiff:
        n = len(line)
        line = line.replace("&","&amp;").replace(">","&gt;").replace("<","&lt;")
        if n >= 4 and line[0:4] == '--- ':
            body += line_pattern % ('fromtitle', line)
        elif n >= 4 and line[0:4] == '+++ ':
            body += line_pattern % ('totitle', line)
        elif n >= 1 and line[0] == ' ':
            body += line_pattern % ('same', line)
        elif n >= 1 and line[0] == '-':
            body += line_pattern % ('old', line)
        elif n >= 1 and line[0] == '+':
            body += line_pattern % ('new', line)
        elif n >= 4 and line[0:4] == '@@ -':
            body += '<hr>'
            body += line_pattern % ('head', line)
        else: # shouldn't happen
            body += line

    html = '''<html><head>
        <title>%s</title>
        <style type="text/css">
            .fromtitle {color:brown; font:bold 11pt;}
            .totitle {color:green; font:bold 11pt;}
            .head {color:blue; font:bold 9pt;}
            .same {color:black; font:9pt;}
            .old {color:brown; font:9pt;}
            .new {color:green; font:9pt;}
        </style>
        <body>
            <pre>%s</pre>
        </body>
        </head></html>''' % (title, body)
    return html


def strip_prefix(name, p=0):
    '''strip NUM slashes, like patch(1) -pNUM
    eg1: /foo/bar/a/b/x.c
    -p0 gives orignal name (no change)
    -p1 gives foo/bar/a/b/x.c
    -p2 gives bar/a/b/x.c
    -p9 gives x.c

    eg2: foo/bar/a/b/x.c
    -p0 gives orignal name (no change)
    -p1 gives bar/a/b/x.c
    -p2 gives a/b/x.c
    -p9 gives x.c

    eg3: ./foo/bar/a/b/x.c
    -p0 gives orignal name (no change)
    -p1 gives foo/bar/a/b/x.c
    -p2 gives bar/a/b/x.c
    -p9 gives x.c
    '''
    cur = 0
    tail = len(name) - 1
    while p > 0:
        index = name.find('/', cur)
        #print 'p:', p, 'cur:', cur, 'index:', index
        if index == -1: break
        while index <= tail and name[index] == '/':
            index += 1
        cur = index
        p -= 1
    return name[cur:]


class CodeDifferError(Exception):
    pass


class CodeDiffer:

    # index page layout (templates are public):
    #
    # h1: dir1 vs dir2
    # comments:
    #   comments here
    # summary of files
    #   Changed Deleted Added
    # Filename C/D/A Summary      Diffs                  Sources
    # Pathname x/y/z         Cdiff  Udiff  Sdiff  Fdiff  Old New
    # Pathname x/y/z         Cdiff  Udiff  Sdiff  Fdiff  Old New
    # Pathname x/y/z         -      -      -      -      -   New
    # Pathname x/y/z         -      -      -      -      Old -
    # <hr>
    # footer_info
    #

    ########## templates begin ##########

    _index_template = """
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
          "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>

<head>
    <meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-1" />
    <title>
        %(title)s
    </title>
    <style type="text/css">
        %(styles)s
    </style>
</head>

<body>
    %(header_info)s
    %(comments_info)s
    %(summary_info)s
    %(data_rows)s
    <hr>
    %(footer_info)s
</body>

</html>"""

    # TODO: provide as template
    _style_template = """
    body {font-family: monospace; font-size: 9pt;}
    .comments { margin-left: 20px; font-stlye: italic; }
    #summary_table {
        text-align:left;font-family:monospace;
        border: 1px solid #ccc; border-collapse: collapse
    }
    td {padding-left:5px;padding-right:5px;}
    #summary {margin-left: 16px; border:medium;text-align:center;}
    #footer_info {color:#333; font-size:8pt;}
    .diff {background-color:#ffd;}
    .added {background-color:#afa;}
    .deleted {background-color:#faa;}
    .table_header th {
        text-align:center;
        background-color:#f0f0f0;
        border-bottom: 1px solid #aaa;
        padding: 4px 4px 4px 4px;
    }
    """

    _header_info_template = """
    <h1>%(header)s</h1>"""

    _comments_template = """
    <p><b>Comments:</b></p>
    <pre class="comments">%(comments)s</pre>"""

    _summary_info_template = """
    <p><b>Summary of file changes:</b></p>
    <table id="summary">
        <tr>
            <td class="diff">%(changed)d Changed</td>
            <td class="deleted">%(deleted)d Deleted</td>
            <td class="added">%(added)d Added</td>
        </tr>
    </table><br>"""

    _data_rows_template = """
    <table id="summary_table" cellspacing="1" border="1" nowrap="nowrap">
    <tr class="table_header">
        <th>Filename</th>
        <th><abbr title="Changed/Deleted/Added">C/D/A</abbr> Summary</th>
        <th colspan="4">Diffs</th>
        <th colspan="2">Sources</th>
    </tr>
    %(data_rows)s
    </table>"""

    _diff_data_row_template = """
    <tr class="diff">
        <td>%(pathname)s</td>
        <td><abbr title="Changed/Deleted/Added">\
                %(changed)s/%(deleted)s/%(added)s</abbr></td>
        <td><a href=%(pathname)s.cdiff.html title="context diff">Cdiff</a>\
                </td>
        <td><a href=%(pathname)s.udiff.html title="unified diff">Udiff</a>\
                </td>
        <td><a href=%(pathname)s.sdiff.html title="side-by-side context diff">\
                Sdiff</a></td>
        <td><a href=%(pathname)s.fdiff.html title="side-by-side full diff">\
                Fdiff</a></td>
        <td><a href=%(pathname)s-.html title="old file">Old</a></td>
        <td><a href=%(pathname)s.html title="new file">New</a></td>
    </tr>"""

    _deleted_data_row_template = """
    <tr class="deleted">
        <td>%(pathname)s</td>
        <td>-/-/-</td>
        <td>-</td>
        <td>-</td>
        <td>-</td>
        <td>-</td>
        <td><a href=%(pathname)s-.html title="old file">Old</a></td>
        <td>-</td>
    </tr>"""

    _added_data_row_template = """
    <tr class="added">
        <td>%(pathname)s</td>
        <td>-/-/-</td>
        <td>-</td>
        <td>-</td>
        <td>-</td>
        <td>-</td>
        <td>-</td>
        <td><a href=%(pathname)s.html title="new file">New</a></td>
    </tr>"""

    _footer_info_template = """
    <i id="footer_info">
        Generated by %(myname)s r%(revision)s at %(time)s
    </i>"""

    ########## templates end ##########


    def __init__(self, obj1, obj2, output, input_list=None, strip_level=0,
                       wrap_num=0, context_line=3, title='', comments=''):
        self.__obj1 = obj1
        self.__obj2 = obj2
        self.__output = output
        self.__input_list = input_list
        self.__strip_level = strip_level
        self.__wrap_num = wrap_num
        self.__context_line = context_line
        self.__file_list = []
        self.__title = title
        self.__comments = comments
        # TODO: provide options
        self.__dir_ignore_list = _global_dir_ignore_list
        self.__file_ignore_list = _global_file_ignore_list

    def __diff_file(self):
        '''
        Generate side by side diff in html and write to output file, if
        context_line is 0, then all context around diff will be output
        '''
        from_lines = get_lines(self.__obj1)
        to_lines = get_lines(self.__obj2)
        from_title = make_title(self.__obj1, self.__wrap_num)
        to_title = make_title(self.__obj2, self.__wrap_num)
        use_context = self.__context_line != 0
        html = sdiff_lines(from_lines, to_lines, from_title, to_title,
                           use_context, self.__wrap_num, self.__context_line)
        write_file(self.__output, html)

    def __is_igore_dir(self, dir):
        for pat in self.__dir_ignore_list:
            if re.match(pat, dir):
                return True
        return False

    def __is_igore_file(self, file):
        for pat in self.__file_ignore_list:
            if re.match(pat, file):
                return True
        return False

    def __grab_dir(self, dir):
        'Get file list of dir, and remove unwanted file from the list'
        flist = []
        while dir[-1] == '/':   # remove unwanted trailling slash
            dir = dir[:-1]
        prefix = dir + '/'      # os.path.sep
        plen = len(prefix)

        for root, dirs, files in os.walk(dir):
            for d in [k for k in dirs]:
                if self.__is_igore_dir(d):
                    dirs.remove(d)
            for f in files:
                if not self.__is_igore_file(f):
                    name = os.path.join(root, f)
                    flist.append(name[plen:])
        return flist

    def __make_file_list(self):
        'Read file list from input file or stdin or get from obj1 and obj2'
        file_list = []
        if self.__input_list:
            if self.__input_list == '-':
                file_list = sys.stdin.readlines()
            else:
                f = open(self.__input_list, 'r')
                file_list = f.readlines()
                f.close()
            for i in file_list:
                s = strip_prefix(i, self.__strip_level).rstrip()
                self.__file_list.append(s)
        else:
            a = self.__grab_dir(self.__obj1)
            b = self.__grab_dir(self.__obj2)
            c = [k for k in a]
            for i in b:
                if i not in a:
                    c.append(i)
            # c now is merged list
            self.__file_list = c

    def __diff_dir_by_list(self):
        data_rows = ''
        data_row = ''
        summary = { 'changed': 0, 'added': 0, 'deleted': 0 }
        file_summary = { 'changed': 0, 'added': 0, 'deleted': 0 }
        has_diff = False

        self.__file_list.sort()

        for f in self.__file_list:
            # set default values
            from_lines = ''
            to_lines = ''
            from_date = ''
            to_date = ''

            target = os.path.join(self.__output, f)
            obj1 = os.path.join(self.__obj1, f)
            obj2 = os.path.join(self.__obj2, f)

            # make output dir and sub dir
            try:
                os.makedirs(os.path.join(self.__output, os.path.dirname(f)))
            except OSError, e:
                if e.errno != errno.EEXIST:
                    raise CodeDifferError, 'OSError: ' + str(e)

            stat1 = None
            stat2 = None
            if os.path.exists(obj1): stat1 = os.lstat(obj1)
            if os.path.exists(obj2): stat2 = os.lstat(obj2)

            if stat1 and not stat2: # deleted
                print '  * %-40s |' % f,
                print 'File removed',
                #st_mtime = time.localtime(stat1[8])
                if not stat.S_ISREG(stat1[0]) or is_binary_file(obj1):
                    print '(skipped dir/special/binary)'
                    continue
                print
                write_file(target + '-.html', convert_to_html(obj1))
                data_row = self._deleted_data_row_template % {'pathname': f}
                summary['deleted'] += 1
                has_diff = True

            elif not stat1 and stat2: # added
                print '  * %-40s |' % f,
                print 'New file',
                if not stat.S_ISREG(stat2[0]) or is_binary_file(obj2):
                    print '(skipped special/binary)'
                    continue
                print
                write_file(target + '.html', convert_to_html(obj2))
                data_row = self._added_data_row_template % {'pathname': f}
                summary['added'] += 1
                has_diff = True

            elif stat1 and stat2: # same or diff
                # do not compare special or binary file
                if not stat.S_ISREG(stat1[0]) or is_binary_file(obj1):
                    print '  * %-40s |' % f,
                    print '(skipped, former file is special)'
                    continue
                if not stat.S_ISREG(stat2[0]) or is_binary_file(obj2):
                    print '  * %-40s |' % f,
                    print '(skipped, latter file is binary)'
                    continue
                if filecmp.cmp(obj1, obj2):
                    continue

                has_diff = True
                from_date = time.ctime(stat1[8])
                to_date = time.ctime(stat2[8])
                from_lines = get_lines(obj1)
                to_lines = get_lines(obj2)

                # Cdiff
                file_summary, html = cdiff_lines(from_lines, to_lines, obj1,
                        obj2, from_date, to_date, self.__context_line)
                write_file(target + '.cdiff.html', html)

                # Udiff
                html = udiff_lines(from_lines, to_lines, obj1, obj2, from_date,
                                   to_date, self.__context_line)
                write_file(target + '.udiff.html', html)

                # Sdiff
                html = sdiff_lines(from_lines, to_lines, obj1, obj2, True,
                                   self.__wrap_num, self.__context_line)
                write_file(target + '.sdiff.html', html)

                # Fdiff
                html = sdiff_lines(from_lines, to_lines, obj1, obj2, False,
                                   self.__wrap_num, self.__context_line)
                write_file(target + '.fdiff.html', html)

                print '  * %-40s |' % f,
                print 'Changed/Deleted/Added: %d/%d/%d' % (\
                    file_summary['changed'],
                    file_summary['deleted'],
                    file_summary['added'])

                write_file(target + '-.html', convert_to_html(obj1))
                write_file(target + '.html', convert_to_html(obj2))
                data_row = self._diff_data_row_template % dict(
                    pathname = f,
                    changed = file_summary['changed'],
                    deleted = file_summary['deleted'],
                    added = file_summary['added'],
                )
                summary['changed'] += 1
            else: # this case occured when controlled by master file list
                print '  * %-40s |' % f,
                print 'Not found'
                data_row = ''

            data_rows += data_row

        if not has_diff:
            return False

        # Generate footer info
        footer_info = self._footer_info_template % dict(
            time = time.strftime('%a %b %d %X %Z %Y', time.localtime()),
            myname = get_myname(),
            revision = get_myrev()
        )

        # now wirte index page
        if self.__title:
            title = html_filter(self.__title)
        else:
            title = '%s vs %s' % (self.__obj1, self.__obj2)
        header_info = self._header_info_template % {'header': title}

        index = open(os.path.join(self.__output, 'index.html'), 'w')
        index.write(self._index_template % dict(
            title = title,
            styles = self._style_template,
            header_info = header_info,
            comments_info = self._comments_template % \
                {'comments': html_filter(self.__comments)},
            summary_info = self._summary_info_template % summary,
            data_rows = self._data_rows_template % {'data_rows': data_rows},
            footer_info = footer_info,
        ))
        index.close()

    def __diff_dir(self):
        self.__make_file_list()
        self.__diff_dir_by_list()

    def make_diff(self):
        try:
            # Note: use stat instead lstat to permit symbolic links
            stat1 = os.stat(self.__obj1)[0]
            stat2 = os.stat(self.__obj2)[0]

            if stat.S_ISREG(stat1) and stat.S_ISREG(stat2):
                self.__diff_file()
            elif stat.S_ISDIR(stat1) and stat.S_ISDIR(stat2):
                self.__diff_dir()
            else:
                e = '%s and %s are of different type, aborted' % \
                    (self.__obj1, self.__obj2)
                raise CodeDifferError, e
        except OSError, e:
            raise CodeDifferError, 'OSError: ' + str(e)
        except IOError, e:
            raise CodeDifferError, 'IOError: ' + str(e)


#
# Test code
#
if __name__ == '__main__':
    def warn_overwrite(pathname):
        'Warnning for overwriting, return True if answered yes, False if no'
        msg = "`%s' exists, are you sure you want to overwrite it (yes/no)? "
        while True:
            sys.stderr.write(msg % pathname)
            answer = raw_input('')
            if answer == 'yes':
                return True
            elif answer == 'no':
                return False
            # else: prompt again

    import optparse

    usage = '''
    %(name)s [options] OLD NEW
    %(name)s OLD NEW [options]

    Diff two files/directories and produce HTML pages.''' % \
    {'name': os.path.basename(sys.argv[0])}

    parser = optparse.OptionParser(usage)
    parser.add_option('-c', '--context', action='store_true',
                      dest='context', default=False,
                      help='generate context diff (default is full diff),' + \
                           ' only take effect when diffing two files')
    parser.add_option('-F', '--commentfile', dest='commentfile', metavar='FILE',
                      help='specify a file to read comments')
    parser.add_option('-f', '--filelist', dest='filelist', metavar='FILE',
                      help='specify a file list to read from, filelist can ' + \
                           'be generated by find -type f, specify - to read' + \
                           ' from stdin')
    parser.add_option('-m', '--comments', dest='comments',
                      help='specify inline comments (precedes -F)')
    parser.add_option('-n', '--lines', dest='lines',
                      type='int', metavar='NUM', default=3,
                      help='specify context line count when generating ' + \
                           'context diff or unified diff, default is 3')
    parser.add_option('-o', '--outupt', dest='output',
                      help='specify output file or directory name')
    parser.add_option('-p', '--striplevel', dest='striplevel',
                      type='int', metavar='NUM',
                      help='for all pathnames in the filelist, delete NUM ' + \
                           'path name components from the beginning of each' + \
                           ' path name, it is similar to patch(1) -p')
    parser.add_option('-t', '--title', dest='title',
                      help='specify title of output index page')
    parser.add_option('-w', '--wrap', dest='wrapnum',
                      type='int', metavar='WIDTH',
                      help='specify column number where lines are broken ' + \
                      'and wrapped for sdiff, default is no line wrapping')
    parser.add_option('-y', '--yes', action='store_true',
                      dest='overwrite', default=False,
                      help='do not prompt for overwriting')
    opts, args = parser.parse_args()

    if len(args) != 2:
        sys.stderr.write("Sorry, you must specify two file/directory names\n" \
                         + "type `%s -h' for help\n" % get_myname())
        sys.exit(1)
    if not opts.output:
        sys.stderr.write("Sorry, you must specify output name (use `-o')\n")
        sys.exit(2)

    if opts.comments:
        comments = opts.comments
    elif opts.commentfile:
        try:
            comments = ''.join(get_lines(opts.commentfile))
        except IOError, e:
            sys.stderr.write(str(e) + '\n')
            sys.exit(1)
    else:
        comments = ''

    if not opts.overwrite and os.path.exists(opts.output):
        if opts.filelist == '-':
            # stdin redirected, so we cannot read answer from stdin
            print "`%s' exists, please select another output directory, " \
                  "or specify '-y' to force overwriting." % opts.output
            sys.exit(1)
        else:
            if not warn_overwrite(opts.output):
                sys.exit(1)

    try:
        differ = CodeDiffer(args[0], args[1], opts.output, opts.filelist,
                            opts.striplevel, opts.wrapnum, opts.lines,
                            opts.title, comments)
        differ.make_diff()
    except CodeDifferError, e:
        sys.stderr.write(str(e) + '\n')
        sys.exit(1)
    else:
        sys.exit(0)

# vim:set et sts=4 sw=4 tw=80:
# EOF
