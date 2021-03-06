/**
   авторизация
 */

module veda.mstorage.acl_manager;

import core.thread, std.stdio, std.conv, std.concurrency, std.file, std.datetime, std.array, std.outbuffer, std.string;
import veda.util.properd;
import veda.common.type, veda.onto.individual, veda.onto.resource, veda.core.common.context, veda.core.common.define;
import veda.core.common.log_msg, veda.storage.common, veda.core.common.type, veda.core.util.utils, veda.common.logger, veda.util.module_info,
       veda.core.impl.thread_context;
import veda.storage.common, veda.authorization.right_set;
import veda.storage.lmdb.lmdb_driver;
import veda.storage.tarantool.tarantool_driver;

// ////////////// ACLManager
protected byte err;
protected long count;
// ////// Logger ///////////////////////////////////////////
Logger         _log;
Logger log()
{
    if (_log is null)
        _log = new Logger("veda-core-mstorage", "log", "ACL-MANAGER");
    return _log;
}
// ////// ////// ///////////////////////////////////////////
enum CMD : byte
{
    /// Сохранить
    PUT       = 1,

    /// Коммит
    COMMIT    = 16,

    /// Включить/выключить отладочные сообщения
    SET_TRACE = 33,

    /// Пустая комманда
    NOP       = 64,

    EXIT      = 49
}

public ResultCode flush(bool is_wait)
{
    ResultCode rc;
    Tid        tid = getTid(P_MODULE.acl_preparer);

    if (tid != Tid.init)
    {
        if (is_wait == false)
        {
            send(tid, CMD_COMMIT);
        }
        else
        {
            send(tid, CMD_COMMIT, thisTid);
            receive((bool isReady) {});
        }
        rc = ResultCode.Ok;
    }
    return rc;
}


void acl_manager(string thread_name)
{
    core.thread.Thread.getThis().name = thread_name;

    KeyValueDB                   storage;

    string[ string ] properties;
    properties = readProperties("./veda.properties");

    string authorization_db_type = properties.as!(string)("authorization_db_type");

    storage = new LmdbDriver(acl_indexes_db_path, DBMode.RW, "acl_manager", log);


    long l_op_id;
    long committed_op_id;

    // SEND ready
    receive((Tid tid_response_reciever)
            {
                send(tid_response_reciever, true);
            });

    ModuleInfoFile module_info = new ModuleInfoFile(thread_name, _log, OPEN_MODE.WRITER);
    if (!module_info.is_ready)
    {
        log.trace("thread [%s] terminated", process_name);
        return;
    }

    bool is_exit = false;

    while (is_exit == false)
    {
        try
        {
            receive(
                    (byte cmd)
                    {
                        if (cmd == CMD_COMMIT)
                        {
                            if (committed_op_id != l_op_id)
                            {
                                storage.flush(1);
                                //log.trace("acl commit op_id=%d", l_op_id);
                                committed_op_id = l_op_id;
                                module_info.put_info(l_op_id, committed_op_id);
                            }
                        }
                    },
                    (byte cmd, string prev_state, string new_state, long op_id)
                    {
                        if (cmd == CMD_PUT)
                        {
                            count++;

                            if (count % 1000 == 0)
                                log.trace("INFO! count prepare: %d", count);

                            try
                            {
                                Individual new_ind;
                                if (new_ind.deserialize(new_state) < 0)
                                {
                                    log.trace("ERR! ACL: invalid individual: [%s] op_id=%d", new_state, op_id);
                                    return;
                                }

                                Individual prev_ind;
                                if (prev_state !is null && prev_ind.deserialize(prev_state) < 0)
                                {
                                    log.trace("ERR! ACL: invalid individual: [%s] op_id=%d", prev_state, op_id);
                                    return;
                                }

                                Resources rdfType = new_ind.getResources("rdf:type");

                                if (rdfType.anyExists("v-s:PermissionStatement") == true)
                                {
                                    prepare_permission_statement(prev_ind, new_ind, op_id, storage);
                                }
                                else if (rdfType.anyExists("v-s:Membership") == true)
                                {
                                    prepare_membership(prev_ind, new_ind, op_id, storage);
                                }
                                else if (rdfType.anyExists("v-s:PermissionFilter") == true)
                                {
                                    prepare_permission_filter(prev_ind, new_ind, op_id, storage);
                                }
                            }
                            finally
                            {
                                l_op_id = op_id;

                                module_info.put_info(l_op_id, committed_op_id);
                            }
                        }
                    },
                    (byte cmd, Tid tid_response_reciever)
                    {
                        if (cmd == CMD_EXIT)
                        {
                            is_exit = true;
                            writefln("[%s] recieve signal EXIT", "acl_manager");
                            send(tid_response_reciever, true);
                        }
                        else
                            send(tid_response_reciever, false);
                    },
                    (byte cmd, int arg, bool arg2)
                    {
                        if (cmd == CMD_SET_TRACE)
                            set_trace(arg, arg2);
                    },
                    (OwnerTerminated ot)
                    {
                        //log.trace("%s::acl_manager::OWNER TERMINATED", thread_name);
                        return;
                    },
                    (Variant v) { writeln(thread_name, "::acl_manager::Received some other type: [", v, "]"); });
        }
        catch (Throwable ex)
        {
            log.trace("acl manager# ERR! MSG:[%s] [%s]", ex.msg, ex.info);
        }
    }

    module_info.close();
}

void prepare_right_set(ref Individual prev_ind, ref Individual new_ind, string p_resource, string p_in_set, string prefix, ubyte default_access,
                       long op_id,
                       KeyValueDB storage)
{
    bool     is_deleted = new_ind.isExists("v-s:deleted", true);

    ubyte    access;
    Resource canCreate = new_ind.getFirstResource("v-s:canCreate");

    if (canCreate !is Resource.init)
    {
        if (canCreate == true)
            access = access | Access.can_create;
        else
            access = access | Access.cant_create;
    }

    Resource canRead = new_ind.getFirstResource("v-s:canRead");
    if (canRead !is Resource.init)
    {
        if (canRead == true)
            access = access | Access.can_read;
        else
            access = access | Access.cant_read;
    }

    Resource canUpdate = new_ind.getFirstResource("v-s:canUpdate");
    if (canUpdate !is Resource.init)
    {
        if (canUpdate == true)
            access = access | Access.can_update;
        else
            access = access | Access.cant_update;
    }

    Resource canDelete = new_ind.getFirstResource("v-s:canDelete");
    if (canDelete !is Resource.init)
    {
        if (canDelete == true)
            access = access | Access.can_delete;
        else
            access = access | Access.cant_delete;
    }

    if (access == 0)
        access = default_access;

    Resource  useFilter = new_ind.getFirstResource("v-s:useFilter");

    Resources resource = new_ind.getResources(p_resource);
    Resources in_set   = new_ind.getResources(p_in_set);

    Resources prev_resource = prev_ind.getResources(p_resource);
    Resources prev_in_set   = prev_ind.getResources(p_in_set);

    Resources removed_resource = get_disappeared(prev_resource, resource);
    Resources removed_in_set   = get_disappeared(prev_in_set, in_set);

    bool      ignoreExclusive = new_ind.getFirstBoolean("v-s:ignoreExclusive");
    bool      isExclusive = new_ind.getFirstBoolean("v-s:isExclusive");
    char      marker      = 0;

    if (isExclusive == true)
        marker = M_IS_EXCLUSIVE;
    else if (ignoreExclusive == true)
        marker = M_IGNORE_EXCLUSIVE;

    update_right_set(resource, in_set, marker, is_deleted, useFilter, prefix, access, op_id, storage);

    if (removed_resource.length > 0)
    {
        log.trace("- removed_resource=%s", removed_resource);
        update_right_set(removed_resource, in_set, marker, true, useFilter, prefix, access, op_id, storage);
    }

    if (removed_in_set.length > 0)
    {
        log.trace("- removed_in_set=%s", removed_in_set);
        update_right_set(resource, removed_in_set, marker, true, useFilter, prefix, access, op_id, storage);
    }
}

private void update_right_set(ref Resources resources, ref Resources in_set, char marker, bool is_deleted, ref Resource useFilter, string prefix, ubyte access,
                              long op_id,
                              KeyValueDB storage)
{
    // для каждого из ресурсов выполним операцию добавления/удаления
    foreach (rs; resources)
    {
        string key;

        if (useFilter !is Resource.init)
            key = prefix ~ useFilter.uri ~ rs.uri;
        else
            key = prefix ~ rs.uri;

        RightSet new_right_set = new RightSet(log);

        string   prev_data_str = storage.get_binobj(key);
        if (prev_data_str !is null)
        {
            //log.trace("prev_data_str %s[%s]", rs.uri, prev_data_str);
            rights_from_string(prev_data_str, new_right_set);
        }

        foreach (mb; in_set)
        {
            Right *rr = new_right_set.data.get(mb.uri, null);

            if (rr !is null)
            {
                rr.is_deleted                = is_deleted;
                rr.access                    = rr.access | access;
                rr.marker                    = marker;
                new_right_set.data[ mb.uri ] = rr;
                log.trace(" UPDATE [%s]", mb.uri);
            }
            else
            {
                Right *nrr = new Right(mb.uri, access, marker, is_deleted);
                new_right_set.data[ mb.uri ] = nrr;
                log.trace(" NEW [%s]", mb.uri);
            }
        }

        string new_record = rights_as_string(new_right_set);

        if (new_record.length == 0)
            new_record = "X";

        ResultCode res = storage.store(key, new_record, op_id);

        log.trace("[acl index] (%s) update right set: %s, K:[%s] V:[%s]", text(res), rs.uri, key, new_record);
    }
}

void prepare_membership(ref Individual prev_ind, ref Individual new_ind, long op_id, KeyValueDB storage)
{
    if (trace_msg[ 114 ] == 1)
        log.trace("store Membership: [%s] op_id=%d", new_ind.uri, op_id);

    prepare_right_set(prev_ind, new_ind, "v-s:resource", "v-s:memberOf", membership_prefix,
                      Access.can_create | Access.can_read | Access.can_update | Access.can_delete, op_id, storage);
}

void prepare_permission_filter(ref Individual prev_ind, ref Individual new_ind, long op_id, KeyValueDB storage)
{
    if (trace_msg[ 114 ] == 1)
        log.trace("store PermissionFilter: [%s] op_id=%d", new_ind, op_id);

    prepare_right_set(prev_ind, new_ind, "v-s:permissionObject", "v-s:resource", filter_prefix, 0, op_id, storage);
}

void prepare_permission_statement(ref Individual prev_ind, ref Individual new_ind, long op_id, KeyValueDB storage)
{
    if (trace_msg[ 114 ] == 1)
        log.trace("store PermissionStatement: [%s] op_id=%d", new_ind, op_id);

    prepare_right_set(prev_ind, new_ind, "v-s:permissionObject", "v-s:permissionSubject", permission_prefix, 0, op_id, storage);
}

