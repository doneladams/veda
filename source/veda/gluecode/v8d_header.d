/**
 * обвязка к v8d
 */
module veda.gluecode.v8d_header;

import std.stdio, std.conv, std.file, std.path, std.uuid, std.algorithm, std.array, std.json;
import veda.common.type, veda.onto.individual, veda.onto.resource, veda.onto.lang, veda.onto.onto, veda.gluecode.script;
import veda.core.common.context, veda.core.common.define, veda.core.util.utils, veda.util.queue, veda.core.common.transaction;
import veda.util.container;

// ////// Logger ///////////////////////////////////////////
import veda.common.logger;
Logger log;

// //////////////////////////  call D from C //////////////////////////////////////////

string[ string ] g_ht;
Context g_context;

string  g_vm_id;

_Buff   g_super_classes;
_Buff   g_parent_script_id;
_Buff   g_parent_document_id;
_Buff   g_prev_state;
_Buff   g_execute_script;
_Buff   g_document;
_Buff   g_uri;
_Buff   g_user;
_Buff   g_ticket;
string  g_event_id;

_Buff   tmp_individual;
_Buff   tmp;

//_Buff      g_script_result;
//_Buff      g_script_out;

ResultCode g_last_result;
Cache!(string, string) g_cache_of_indv;

private string empty_uid;

bool is_filter_pass(ScriptInfo *script, string individual_id, string[] indv_types, Onto onto)
{
    bool is_pass = false;

    if (script.prevent_by_type.length != 0)
    {
        foreach (indv_type; indv_types)
        {
            if ((indv_type in script.prevent_by_type) !is null)
                return false;

            if (onto.isSubClasses(cast(string)indv_type, script.prevent_by_type.keys) == true)
                return false;
        }
    }

    if (script.trigger_by_uid.length == 0 && script.trigger_by_type.length == 0)
        return true;

    if (script.trigger_by_uid.length > 0 && (individual_id in script.trigger_by_uid) !is null)
        is_pass = true;

    if (!is_pass && script.trigger_by_type.length > 0)
    {
        foreach (indv_type; indv_types)
        {
            if ((indv_type in script.trigger_by_type) !is null)
            {
                is_pass = true;
                break;
            }

            if (onto.isSubClasses(cast(string)indv_type, script.trigger_by_type.keys) == true)
            {
                is_pass = true;
                break;
            }
        }
    }

    return is_pass;
}

void set_g_prev_state(string prev_state)
{
    if (prev_state !is null)
    {
        g_prev_state.data   = cast(char *)prev_state;
        g_prev_state.length = cast(int)prev_state.length;
    }
    else
    {
        g_prev_state.data   = cast(char *)empty_uid;
        g_prev_state.length = cast(int)empty_uid.length;
    }
}

void set_g_super_classes(string[] indv_types, Onto onto)
{
    Names super_classes;

    foreach (indv_type; indv_types)
    {
        if (super_classes == Names.init)
        {
            super_classes = onto.get_super_classes(indv_type);
        }
        else
        {
            Names i_super_classes = onto.get_super_classes(indv_type);
            foreach (i_super_class; i_super_classes.keys)
            {
                if (super_classes.get(i_super_class, false) == false)
                {
                    super_classes[ i_super_class ] = true;
                }
            }
        }
    }
    string superclasses_str = text(super_classes.keys);
    g_super_classes.data   = cast(char *)superclasses_str;
    g_super_classes.length = cast(int)superclasses_str.length;
}

private void fill_TransactionItem(TransactionItem *ti, INDV_OP _cmd, string _binobj, string _ticket_id, string _event_id)
{
    ti.cmd        = _cmd;
    ti.new_binobj = _binobj;
    ti.ticket_id  = _ticket_id;
    ti.event_id   = _event_id;
    Ticket *ticket = g_context.get_storage().get_ticket(ti.ticket_id, false);
    ti.user_uri = ticket.user_uri;

    if (ti.cmd == INDV_OP.REMOVE)
    {
        ti.new_indv.uri = _binobj;
        ti.rc           = ResultCode.OK;
    }
    else
    {
        int code = ti.new_indv.deserialize(ti.new_binobj);
        if (code < 0)
        {
            ti.rc = ResultCode.Unprocessable_Entity;
            log.trace("ERR! v8d:transaction:deserialize cmd:[%s] ticket:[%s] event:[%s] binobj[%s]", text(_cmd), _ticket_id, _event_id, _binobj);
            return;
        }
        else
            ti.rc = ResultCode.OK;

        ti.new_indv.setStatus(ti.rc);
        ti.uri = ti.new_indv.uri;

        if (ti.rc == ResultCode.OK && (ti.cmd == INDV_OP.ADD_IN || ti.cmd == INDV_OP.SET_IN || ti.cmd == INDV_OP.REMOVE_FROM))
        {
            // log.trace("fill_TransactionItem(%s) [%s]", text (_cmd), ti.new_indv);
            Individual      prev_indv;

            TransactionItem *ti1 = tnx.get(ti.new_indv.uri);
            if (ti1 !is null && ti1.new_binobj.length > 0)
            {
                prev_indv = ti1.new_indv;
            }
            else
            {
                prev_indv = g_context.get_individual(ticket, ti.new_indv.uri, OptAuthorize.NO);
            }

            if (prev_indv.getStatus() == ResultCode.Connect_Error || prev_indv.getStatus() == ResultCode.Too_Many_Requests)
                ti.rc = prev_indv.getStatus();

            if (prev_indv.getStatus() == ResultCode.OK)
                ti.new_indv = *indv_apply_cmd(ti.cmd, &prev_indv, &ti.new_indv);
            else
                log.trace("ERR! v8d:transaction: %s to individual[%s], but prev_individual read fail=%s", ti.cmd, ti.new_indv.uri,
                          prev_indv.getStatus());

            ti.cmd = INDV_OP.PUT;
        }
    }
    return;
}


Transaction tnx;

extern (C++)
{
struct _Buff
{
    char *data;
    int  length;
    int  allocated_size;
}
}

string script_id;

extern (C++) void log_trace(const char *str, int str_length)
{
    string sstr = cast(string)str[ 0..str_length ];

    log.trace("[%s] %s", script_id, sstr);
}

//////////////////

extern (C++)_Buff * get_from_ght(const char *name, int name_length)
{
    string pn  = cast(string)name[ 0..name_length ];
    string res = g_ht.get(pn, null);

    if (res !is null)
    {
        tmp.data   = cast(char *)res;
        tmp.length = cast(int)res.length;
    }
    else
    {
        tmp.data   = cast(char *)empty_uid;
        tmp.length = cast(int)empty_uid.length;
    }

    return &tmp;
}

extern (C++) void put_to_ght(const char *name, int name_length, const char *value, int value_length)
{
    string pn = cast(string)name[ 0..name_length ].dup;
    string vn = cast(string)value[ 0..value_length ].dup;

    g_ht[ pn ] = vn;
}

///////////////////
Consumer[ string ] id2consumer;

extern (C++)_Buff * new_uris_consumer()
{
    uint  id    = -1;
    Queue queue = new Queue(uris_db_path, "uris-db", Mode.R, log);

    tmp.data   = cast(char *)empty_uid;
    tmp.length = cast(int)empty_uid.length;

    if (queue.open())
    {
        UUID     new_id      = randomUUID();
        string   consumer_id = "consumer-uris-" ~ new_id.toString();

        Consumer cs = new Consumer(queue, tmp_path, consumer_id, Mode.RW, log);

        if (cs.open())
        {
            id2consumer[ consumer_id ] = cs;
            tmp.data                   = cast(char *)consumer_id;
            tmp.length                 = cast(int)consumer_id.length;
        }
    }

    return &tmp;
}

extern (C++)_Buff * uris_pop(const char *_consumer_id, int _consumer_id_length)
{
    string   consumer_id = cast(string)_consumer_id[ 0.._consumer_id_length ].dup;
    Consumer cs          = id2consumer.get(consumer_id, null);

    if (cs !is null)
    {
        string data = cs.pop();
        tmp.data   = cast(char *)data;
        tmp.length = cast(int)data.length;
    }
    else
    {
        tmp.data   = cast(char *)empty_uid;
        tmp.length = cast(int)empty_uid.length;
    }
    return &tmp;
}

extern (C++) bool uris_commit_and_next(const char *_consumer_id, int _consumer_id_length, bool is_sync_data)
{
    string   consumer_id = cast(string)_consumer_id[ 0.._consumer_id_length ].dup;
    Consumer cs          = id2consumer.get(consumer_id, null);

    if (cs !is null)
        return cs.commit_and_next(is_sync_data);

    return false;
}
//////////////////////

//чтение неправильное после операции add set
extern (C++) ResultCode put_individual(const char *_ticket, int _ticket_length, const char *_binobj, int _binobj_length)
{
    // writeln("@V8:put_individual");
    TransactionItem ti;

    fill_TransactionItem(&ti, INDV_OP.PUT, cast(string)_binobj[ 0.._binobj_length ].dup, cast(string)_ticket[ 0.._ticket_length ].dup,
                         g_event_id);

    if (ti.rc == ResultCode.OK)
        tnx.add(ti);

    return ti.rc;
}

extern (C++) ResultCode add_to_individual(const char *_ticket, int _ticket_length, const char *_binobj, int _binobj_length)
{
    TransactionItem ti;

    fill_TransactionItem(&ti, INDV_OP.ADD_IN, cast(string)_binobj[ 0.._binobj_length ].dup, cast(string)_ticket[ 0.._ticket_length ].dup,
                         g_event_id);

    if (ti.rc == ResultCode.OK)
        tnx.add(ti);

    return ti.rc;
}

extern (C++) ResultCode set_in_individual(const char *_ticket, int _ticket_length, const char *_binobj, int _binobj_length)
{
    TransactionItem ti;

    fill_TransactionItem(&ti, INDV_OP.SET_IN, cast(string)_binobj[ 0.._binobj_length ].dup, cast(string)_ticket[ 0.._ticket_length ].dup,
                         g_event_id);

    if (ti.rc == ResultCode.OK)
        tnx.add(ti);

    return ti.rc;
}

extern (C++) ResultCode remove_from_individual(const char *_ticket, int _ticket_length, const char *_binobj, int _binobj_length)
{
    TransactionItem ti;

    fill_TransactionItem(&ti, INDV_OP.REMOVE_FROM, cast(string)_binobj[ 0.._binobj_length ].dup, cast(string)_ticket[ 0.._ticket_length ].dup,
                         g_event_id);

    if (ti.rc == ResultCode.OK)
        tnx.add(ti);

    return ti.rc;
}

extern (C++) ResultCode remove_individual(const char *_ticket, int _ticket_length, const char *_uri, int _uri_length)
{
    TransactionItem ti;

    fill_TransactionItem(&ti, INDV_OP.REMOVE, cast(string)_uri[ 0.._uri_length ].dup, cast(string)_ticket[ 0.._ticket_length ].dup,
                         g_event_id);

    if (ti.rc == ResultCode.OK)
        tnx.add(ti);

    return ti.rc;
}

////

extern (C++)_Buff * get_env_str_var(const char *_var_name, int _var_name_length)
{
    //writeln("@V8: get_env_str_var");
    try
    {
        string var_name = cast(string)_var_name[ 0.._var_name_length ];

        if (var_name == "$parent_script_id")
        {
            return &g_parent_script_id;
        }
        else if (var_name == "$parent_document_id")
        {
            return &g_parent_document_id;
        }
        else if (var_name == "$user")
        {
            return &g_user;
        }
        else if (var_name == "$uri")
        {
            return &g_uri;
        }
        else if (var_name == "$ticket")
        {
            //log.trace("$ticket=%s %s", g_ticket, g_ticket.data[ 0..g_ticket.length ]);
            return &g_ticket;
        }
        else if (var_name == "$super_classes")
        {
            return &g_super_classes;
        }

        return null;
    }
    finally
    {
        //writeln ("@p:v8d end read_individual");
    }
}

extern (C++)_Buff * query(const char *_ticket, int _ticket_length, const char *_query, int _query_length,
                          const char *_sort, int _sort_length, const char *_databases, int _databases_length, int top, int limit)
{
    string res;
    string query;
    string sort;
    string databases;

    //if (g_vm_id != "V8.LowPriority")
    //{
    //    log.trace("ERR! [query] function is available only in the [low priority] jsvm (use v-s:runAt \"V8.LowPriority\")");
    //    return null;
    //}

    try
    {
        string ticket_id = cast(string)_ticket[ 0.._ticket_length ];
        query = cast(string)_query[ 0.._query_length ];

        if (_sort !is null && _sort_length > 1)
            sort = cast(string)_sort[ 0.._sort_length ];

        if (_databases !is null && _databases_length > 1)
            databases = cast(string)_databases[ 0.._databases_length ];

        Ticket *ticket = g_context.get_storage().get_ticket(ticket_id, false);

        if (ticket is null)
        {
            log.trace("ERR! [query] ticket not found, id=%s", ticket_id);
            return null;
        }

        SearchResult sr = g_context.get_individuals_ids_via_query(ticket.user_uri, query, sort, databases, 0, top, limit, null, OptAuthorize.NO, false);

        JSONValue    jres;
        jres[ "result" ]         = sr.result;
        jres[ "count" ]          = sr.count;
        jres[ "estimated" ]      = sr.estimated;
        jres[ "processed" ]      = sr.processed;
        jres[ "cursor" ]         = sr.cursor;
        jres[ "total_time" ]     = sr.total_time;
        jres[ "query_time" ]     = sr.query_time;
        jres[ "authorize_time" ] = sr.authorize_time;
        jres[ "result_code" ]    = sr.result_code;

        res = jres.toString();

        tmp_individual.data   = cast(char *)res;
        tmp_individual.length = cast(int)res.length;
        return &tmp_individual;
    }
    finally
    {
//        log.trace ("@p:v8d end query[%s][%s][%s], res=[%s]", query, sort, databases, res);
    }
}

extern (C++)_Buff * read_individual(const char *_ticket, int _ticket_length, const char *_uri, int _uri_length)
{
    try
    {
        string uri = cast(string)_uri[ 0.._uri_length ];

        //writeln("@p:v8d read_individual, uri=[", uri, "],  ticket=[", _ticket[ 0.._ticket_length ], "]");

        if (uri == "undefined")
        {
            return null;
        }
        else if (uri == "$document")
        {
            return &g_document;
        }
        else if (uri == "$prev_state")
        {
            if (g_prev_state.length > 0)
                return &g_prev_state;
            else
                return null;
        }
        else if (uri == "$execute_script")
        {
            if (g_execute_script.length > 0)
                return &g_execute_script;
            else
                return null;
        }
        else
        {
            TransactionItem *ti = tnx.get(uri);
            if (ti !is null && ti.new_binobj.length > 0)
            {
                tmp_individual.data   = cast(char *)ti.new_binobj;
                tmp_individual.length = cast(int)ti.new_binobj.length;
                return &tmp_individual;
            }

            string ticket = cast(string)_ticket[ 0.._ticket_length ];

            if (g_context !is null)
            {
                string icb;

                if (g_cache_of_indv !is null)
                {
                    icb = g_cache_of_indv.get(uri);

//                    if (icb !is null)
//                        writefln("@v8 success get from cache, uri=%s", uri);
                }

                if (icb is null)
                    icb = g_context.get_storage().get_binobj_from_individual_storage(uri);

                if (icb !is null)
                {
                    tmp_individual.data   = cast(char *)icb;
                    tmp_individual.length = cast(int)icb.length;
                    return &tmp_individual;
                }
                else
                {
                    tmp_individual.data   = cast(char *)"";
                    tmp_individual.length = cast(int)0;
                    return null;
                }
            }
            return null;
        }
    }
    finally
    {
        //writeln ("@p:v8d end read_individual");
    }
}


void dump(char *data, int count)
{
    string res;

    for (int i = 0; i < count; i++)
        res ~= "[" ~ text(cast(uint)data[ i ]) ~ "]";

    writeln("@d dump binobj=", res);
}

// //////////////////////////  call C from D //////////////////////////////////////////

extern (C++)
{
interface WrappedContext
{
}

interface WrappedScript
{
}

void InitializeICU();
void ShutdownPlatform();
void Dispose();
WrappedContext new_WrappedContext();
WrappedScript new_WrappedScript(WrappedContext _context, char *src);
void run_WrappedScript(WrappedContext _context, WrappedScript ws, _Buff *_res = null, _Buff *_out = null);
}

//alias new_WrappedContext new_ScriptVM;
//alias WrappedContext     ScriptVM;
//alias WrappedScript      Script;
//alias run_WrappedScript  run;
//alias new_WrappedScript  compile;

class JsVM : ScriptVM
{
    WrappedContext js_vm;

    this()
    {
        js_vm = new_WrappedContext();
    }

    Script compile(string code)
    {
        Js res = new Js();

        res.vm     = this;
        res.script = new_WrappedScript(js_vm, cast(char *)(code ~ "\0"));
        return res;
    }
}

class Js : Script
{
    WrappedScript script;
    JsVM          vm;

    void run()
    {
        run_WrappedScript(vm.js_vm, script);
    }
}

string   g_str_script_result;
string   g_str_script_out;
ScriptVM script_vm;


ScriptVM get_ScriptVM(Context ctx)
{
    version (libV8)
    {
        if (script_vm is null)
        {
            try
            {
                script_vm = new JsVM();
                g_context = ctx;
                log       = ctx.get_logger();

                reload_ext_scripts(ctx);
            }
            catch (Exception ex)
            {
                writeln("EX!get_ScriptVM ", ex.msg);
            }
        }
    }

    return script_vm;
}

private void reload_ext_scripts(Context ctx)
{
    Script[] scripts;
    string[] script_file_name;
    writeln("-");

    string sticket = ctx.sys_ticket().id;
    g_ticket.data   = cast(char *)sticket;
    g_ticket.length = cast(int)sticket.length;

    foreach (path; [ "./public/js/common/", "./public/js/server/" ])
    {

        DirEntry[] oFiles = [];

        auto seq = path ~ ".seq";

        if (seq.exists) {
            auto seqFile = File(seq);
            auto fileNames = seqFile.byLine();
            foreach (fileName; fileNames) {
              fileName = path ~ fileName;
              if (fileName.exists) {
                DirEntry fileEntry = DirEntry(cast(string)fileName);
                oFiles ~= fileEntry;
              }
            }
        } else {
          oFiles = dirEntries(path, SpanMode.depth).array;
        }

        foreach (o; oFiles)
        {
            if (extension(o.name) == ".js")
            {
                log.trace("load script:%s", o);
                auto str_js        = cast(ubyte[]) read(o.name);
                auto str_js_script = script_vm.compile(cast(string)str_js);
                if (str_js_script !is null)
                {
                    scripts ~= str_js_script;
                    script_file_name ~= o.name;
                }
            }
        }
    }

    foreach (idx, script; scripts)
    {
        log.tracec("init script=%s", script_file_name[ idx ]);
        script.run();
    }
}

unittest
{
    import veda.core.impl.thread_context;
    import std.datetime;
    import veda.onto.lang;
    import veda.util.tests_tools;

    Logger   log = new Logger("test", "log", "V8");

    Context  ctx = new PThreadContext("", "test", log, "");

    ScriptVM script_vm;
    script_vm = get_ScriptVM(ctx);

    assert(script_vm !is null);

    Individual new_indv_A = generate_new_test_individual();

    string     binobj = new_indv_A.serialize();

    g_document.data   = cast(char *)binobj;
    g_document.length = cast(int)binobj.length;

    string sticket = "fake_ticket";
    g_ticket.data   = cast(char *)sticket;
    g_ticket.length = cast(int)sticket.length;

    ScriptInfo script = ScriptInfo.init;

    string     str_script =
        "try { var ticket = get_env_str_var ('$ticket');"
        ~ "var document = get_individual (ticket, '$document');"
        ~ "if (document) {"
        ~ "script();"
        ~ "};"
        ~ "function script() { print (toJson (document)); put_individual (ticket, document, 'test_ev'); }} catch (e) { log_trace (e); }"
    ;
    script.str_script = str_script;

    script.compiled_script = script_vm.compile(script.str_script);

    assert(script.compiled_script !is null);

    TransactionItem *ti = transaction_buff.get(new_indv_A.uri, null);
    assert(ti is null);

    script.compiled_script.run();

    TransactionItem *ti1 = transaction_buff.get(new_indv_A.uri, null);
    assert(ti1 !is null);

    Individual indv_B;
    indv_B.deserialize(ti1.binobj);

    bool compare_res = new_indv_A.compare(indv_B);
    if (compare_res == false)
        writefln("new_indv_A [%s] != indv_B [%s]", new_indv_A, indv_B);

    assert(compare_res);

    writeln("unittest [V8: store subject from script] Ok");
}
