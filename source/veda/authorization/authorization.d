module veda.authorization.authorization;

import std.conv, std.datetime, std.uuid, std.outbuffer, std.string, std.stdio;
import veda.common.logger, veda.core.common.define, veda.common.type;
import veda.core.common.know_predicates, veda.util.module_info;
import veda.authorization.right_set, veda.authorization.cache;

extern (C) ubyte authorize_r(immutable(char) *_uri, immutable(char) *_user_uri, ubyte _request_access, bool _is_check_for_reload);
extern (C) char *get_trace(immutable(char) * _uri, immutable(char) * _user_uri, ubyte _request_access, ubyte trace_mode, bool _is_check_for_reload);

interface Authorization
{
    ubyte authorize(string _uri, string user_uri, ubyte _request_access, bool is_check_for_reload, OutBuffer _trace_acl, OutBuffer _trace_group,
                    OutBuffer _trace_info);

    public bool open();
    public void reopen();
    public void close();
}

OutBuffer trace_acl;
OutBuffer trace_group;
OutBuffer trace_info;

const     TRACE_ACL   = 0;
const     TRACE_GROUP = 1;
const     TRACE_INFO  = 2;

char      *cstr_acl;
char      *cstr_group;
char      *cstr_info;

public class AuthorizationUseLib : Authorization
{
    Logger log;

    this(Logger _log)
    {
        log = _log;
    }

    ubyte authorize(string _uri, string user_uri, ubyte request_access, bool is_check_for_reload, OutBuffer _trace_acl, OutBuffer _trace_group,
                    OutBuffer _trace_info)
    {
        trace_acl   = _trace_acl;
        trace_group = _trace_group;
        trace_info  = _trace_info;

        if (trace_acl !is null || trace_group !is null || trace_info !is null)
        {
            if (trace_acl !is null)
            {
                cstr_acl = get_trace((_uri ~ "\0").ptr, (user_uri ~ "\0").ptr, request_access, TRACE_ACL, is_check_for_reload);
                string str = to!string(cstr_acl);
                _trace_acl.write(str);
            }

            if (trace_group !is null)
            {
                cstr_group = get_trace((_uri ~ "\0").ptr, (user_uri ~ "\0").ptr, request_access, TRACE_GROUP, is_check_for_reload);
                string str = to!string(cstr_group);
                _trace_group.write(str);
            }

            if (trace_info !is null)
            {
                cstr_info = get_trace((_uri ~ "\0").ptr, (user_uri ~ "\0").ptr, request_access, TRACE_INFO, is_check_for_reload);
                string str = to!string(cstr_info);
                _trace_info.write(str);
            }
            return 0;
        }
        else
        {
	    is_check_for_reload = false;
            return authorize_r((_uri ~ "\0").ptr, (user_uri ~ "\0").ptr, request_access, is_check_for_reload);
        }
    }

    public bool open()
    {
        return true;
    };
    public void reopen()
    {
    };
    public void close()
    {
    };
}

string access_to_short_string(const ubyte src)
{
    string res = "";

    if (src & Access.can_create)
        res ~= "C";
    if (src & Access.can_read)
        res ~= "R";
    if (src & Access.can_update)
        res ~= "U";
    if (src & Access.can_delete)
        res ~= "D";

    return res;
}

ubyte access_from_pretty_string(const string access)
{
    ubyte res;

    foreach (c_access; access)
    {
        if (c_access == 'c' || c_access == 'C')
            res = res | Access.can_create;
        if (c_access == 'r' || c_access == 'R')
            res = res | Access.can_read;
        if (c_access == 'u' || c_access == 'U')
            res = res | Access.can_update;
        if (c_access == 'd' || c_access == 'D')
            res = res | Access.can_delete;
    }
    return res;
}

string access_to_string(const ubyte src)
{
    char[] res = new char[ 4 ];

    if (src & Access.can_create)
        res[ 0 ] = 'C';
    else
        res[ 0 ] = '-';
    if (src & Access.can_read)
        res[ 1 ] = 'R';
    else
        res[ 1 ] = '-';
    if (src & Access.can_update)
        res[ 2 ] = 'U';
    else
        res[ 2 ] = '-';
    if (src & Access.can_delete)
        res[ 3 ] = 'D';
    else
        res[ 3 ] = '-';

    return cast(string)res;
}