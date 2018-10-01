module veda.util.queue;

import std.conv, std.stdio, std.file, std.array, std.digest.crc, std.format;
import veda.common.type, veda.core.common.define, veda.util.tools;
import veda.common.logger;

enum QMessageType
{
    STRING = 'S',
    OBJECT = 'O'
}

enum Mode
{
    R       = 0,
    RW      = 1,
    DEFAULT = 2
}

struct Header
{
    ulong        start_pos;
    ulong        msg_length;
    uint         count_pushed;
    ubyte[ 4 ] crc;
    QMessageType type;

//

    void to_buff(ubyte[] buff)
    {
        int pos = 0;

        ulong_to_buff(buff, pos, start_pos);
        pos += ulong.sizeof;
        ulong_to_buff(buff, pos, msg_length);
        pos += ulong.sizeof;
        uint_to_buff(buff, pos, count_pushed);
        pos            += uint.sizeof;
        buff[ pos ]     = type;
        pos            += QMessageType.sizeof;
        buff[ pos + 0 ] = 0;
        buff[ pos + 1 ] = 0;
        buff[ pos + 2 ] = 0;
        buff[ pos + 3 ] = 0;

        //writeln ("write header:", this);
    }

    void from_buff(ubyte[] buff)
    {
        int pos = 0;

        start_pos    = ulong_from_buff(buff, pos);
        pos         += ulong.sizeof;
        msg_length   = ulong_from_buff(buff, pos);
        pos         += ulong.sizeof;
        count_pushed = uint_from_buff(buff, pos);
        pos         += uint.sizeof;
        type         = cast(QMessageType)buff[ pos ];
        pos         += QMessageType.sizeof;

        crc[ 0 ] = buff[ pos + 0 ];
        crc[ 1 ] = buff[ pos + 1 ];
        crc[ 2 ] = buff[ pos + 2 ];
        crc[ 3 ] = buff[ pos + 3 ];

        //writeln ("read header:", this);
    }

    void toString(scope void delegate(const(char)[]) sink) const
    {
        sink("header:");
        sink("  start_pos=" ~ text(start_pos));
        sink(", count_pushed=" ~ text(count_pushed));
        sink(", msg_length=" ~ text(msg_length));
        sink(", crc=" ~ text(crc[ 0 ]) ~ ", " ~  text(crc[ 1 ]) ~ ", " ~ text(crc[ 2 ]) ~ ", " ~ text(crc[ 3 ]));
    }

    int length()
    {
        return ulong.sizeof + ulong.sizeof + uint.sizeof + QMessageType.sizeof + crc.length;
    }
}


class Consumer
{
    ubyte[] buff;
    ubyte[] header_buff;
    ubyte[ 1 ] buff1;
    ubyte[ 4 ] buff4;
    ubyte[ 8 ] buff8;
    ubyte[ 4 ] crc;

    Logger  log;
    bool    isReady;
    Queue   queue;
    string  name;
    string  path;
    ulong   first_element;
    uint    count_popped;
    ubyte[] last_read_msg;
    Mode    mode;
    int     chunk;

    File    *ff_info_pop_w = null;
    File    *ff_info_pop_r = null;

    string  file_name_info_pop;

    // tmp
    Header header;
    CRC32  hash;

    this(Queue _queue, string _path, string _name, Mode _mode, Logger _log)
    {
        queue = _queue;
        path  = _path;
        name  = _name;
        mode  = _mode;

        log         = _log;
        buff        = new ubyte[ 4096 * 100 ];
        header_buff = new ubyte[ header.length() ];
    }

    public bool open(bool open_only_if_exists = false, Mode _mode = Mode.DEFAULT)
    {
        if (_mode != Mode.DEFAULT)
            mode = _mode;

        if (!queue.isReady)
        {
            isReady = false;
            return false;
        }

        file_name_info_pop = path ~ "/" ~ queue.name ~ "_info_pop_" ~ name;

        if (open_only_if_exists && !exists(file_name_info_pop))
        {
            return false;
        }

        if (mode == Mode.RW)
        {
            if (exists(file_name_info_pop) == false)
                ff_info_pop_w = new File(file_name_info_pop, "w");
            else
                ff_info_pop_w = new File(file_name_info_pop, "r+");
        }

        ff_info_pop_r = new File(file_name_info_pop, "r");

        isReady = get_info();

        return isReady;
    }

    public void close()
    {
        if (ff_info_pop_w !is null)
        {
            ff_info_pop_w.flush();
            ff_info_pop_w.close();
        }

        if (ff_info_pop_r !is null)
            ff_info_pop_r.close();
    }

    public void reopen()
    {
        close();
        open();
    }


    public void remove()
    {
        close();
        std.file.remove(file_name_info_pop);
    }

    private bool put_info(bool is_sync_data)
    {
        if (!queue.isReady || !isReady || mode == Mode.R)
            return false;

        try
        {
            ff_info_pop_w.seek(0);
            ff_info_pop_w.writefln("%s;%d;%s;%d;%d", queue.name, queue.chunk, name, first_element, count_popped);

            if (is_sync_data)
                ff_info_pop_w.flush();
        }
        catch (Throwable tr)
        {
            log.trace("consumer:put_info [%s;%d;%s;%d;%d] %s", queue.name, queue.chunk, name, first_element, count_popped, tr.msg);
            return false;
        }
        return true;
    }

    public bool get_info()
    {
        if (!queue.isReady)
            return false;

        if (ff_info_pop_r is null)
            return false;

        ff_info_pop_r.seek(0);
//        writeln("@2 ff_info_push_r.size=", ff_info_push_r.size);

        string str = ff_info_pop_r.readln();
        //writeln("@3 str=[", str, "]");
        if (str !is null)
        {
            string[] ch = str[ 0..$ - 1 ].split(';');
            //writeln("@ queue.get_info ch=", ch);
            if (ch.length != 5)
            {
                isReady = false;
                return false;
            }

            string _name = ch[ 0 ];
            if (_name != queue.name)
            {
                log.trace("consumer:get_info:queue name from info [%s] != consumer.queue.name[%s]", _name, queue.name);
                isReady = false;
                return false;
            }

            int _chunk = to!int (ch[ 1 ]);
            if (_chunk != queue.chunk)
            {
                log.trace("consumer:get_info:queue chunk from info [%d] != consumer.queue.chunk[%d]", _chunk, queue.chunk);
                isReady = false;
                return false;
            }
            chunk = _chunk;

            _name = ch[ 2 ];
            if (_name != name)
            {
                log.trace("consumer:get_info:consumer name from info[%s] != consumer.name[%s]", _name, name);
                isReady = false;
                return false;
            }

            first_element = to!ulong (ch[ 3 ]);
            count_popped  = to!uint (ch[ 4 ]);
        }

        //log.trace("get_info:%s", text(this));

        return true;
    }

    public string pop()
    {
        if (!queue.isReady || !isReady || mode == Mode.R)
            return null;

        queue.get_info(chunk);

        if (count_popped >= queue.count_pushed)
            return null;

        File *ff_queue_r = queue.get_chunk_file(chunk);

        ff_queue_r.seek(first_element);

        ff_queue_r.rawRead(header_buff);
        header.from_buff(header_buff);

        if (header.start_pos != first_element)
        {
            log.trace("pop:invalid msg: header.start_pos[%d] != first_element[%d] : %s", header.start_pos, first_element, text(header));
            return null;
        }

        if (header.msg_length >= buff.length)
        {
            log.trace("pop:inc buff size %d -> %d", buff.length, header.msg_length);
            buff = new ubyte[ header.msg_length + 1 ];
        }

        if (header.msg_length < buff.length)
        {
            last_read_msg = ff_queue_r.rawRead(buff[ 0..header.msg_length ]).dup;
            if (last_read_msg.length < header.msg_length)
            {
                log.trace("pop:invalid msg: msg.length < header.msg_length : %s", text(header));
                return null;
            }
        }
        else
        {
            log.trace("pop:invalid msg: header.msg_length[%d] < buff.length[%d] : %s", header.msg_length, buff.length, text(header));
            return null;
        }

        return cast(string)last_read_msg;
    }

    public void sync()
    {
        ff_info_pop_w.flush();
    }

    public bool commit_and_next(bool is_sync_data)
    {
        if (!queue.isReady || !isReady || mode == Mode.R)
        {
            log.trace("ERR! queue:commit_and_next:!queue.isReady || !isReady");
            return false;
        }

        queue.get_info(chunk);

        if (count_popped >= queue.count_pushed)
        {
            log.trace("ERR! queue[%s][%s]:commit_and_next:count_popped(%d) >= queue.count_pushed(%d)", queue.name, name, count_popped,
                      queue.count_pushed);
            return false;
        }

        header_buff[ header_buff.length - 4 ] = 0;
        header_buff[ header_buff.length - 3 ] = 0;
        header_buff[ header_buff.length - 2 ] = 0;
        header_buff[ header_buff.length - 1 ] = 0;

        hash.start();
        hash.put(header_buff);
        hash.put(last_read_msg);
        crc = hash.finish();

        if (header.crc[ 0 ] != crc[ 0 ] || header.crc[ 1 ] != crc[ 1 ] || header.crc[ 2 ] != crc[ 2 ] || header.crc[ 3 ] != crc[ 3 ])
        {
            log.trace("ERR! queue[%s][%s]:commit_and_next:invalid last_read_msg[%s]: fail crc[%s] : %s", queue.name, name, last_read_msg, text(
                                                                                                                                               crc),
                      text(header));
            log.trace(text(last_read_msg.length));
            log.trace(cast(string)last_read_msg);
            return false;
        }

        count_popped++;
        first_element += header.length + header.msg_length;

        return put_info(is_sync_data);
    }

    void toString(scope void delegate(const(char)[]) sink) const
    {
        sink("consumer:" ~ name);
        sink(", queue:" ~ queue.name);
        sink(", first_element=" ~ text(first_element));
        sink(", count_popped=" ~ text(count_popped));
    }
}

class Queue
{
    bool            isReady;

    private ubyte[] buff;
    private ubyte[] header_buff;
    private ubyte[ 1 ] buff1;
    private ubyte[ 4 ] buff4;
    private ubyte[ 8 ] buff8;
    private ubyte[ 4 ] crc;

    private Logger log;
    private string name;
    private string path;
    int            chunk;
    private ulong  right_edge;
    uint           count_pushed;
    private Mode   mode;

    // Write (current chunk)
    private File *ff_info_push_w = null;
    private File *ff_queue_w     = null;

    // Read (request chunk)
    private File   *ff_queue_chunk_r     = null;
    private File   *ff_info_push_chunk_r = null;

    private string file_name_current_chunk;
    private string file_name_info_push;
    private string file_name_queue;
    private string file_name_lock;

    // tmp
    private Header header;
    private CRC32  hash;

    this(string _path, string _name, Mode _mode, Logger _log)
    {
        log         = _log;
        mode        = _mode;
        path        = _path;
        name        = _name;
        isReady     = false;
        buff        = new ubyte[ 4096 * 100 ];
        header_buff = new ubyte[ header.length() ];

        set_filenames();
    }

    void set_filenames()
    {
        file_name_current_chunk = path ~ "/" ~ name ~ "_current_chunk";
        file_name_queue         = path ~ "/" ~ name ~ "_queue_" ~ text(chunk);
        file_name_info_push     = path ~ "/" ~ name ~ "_info_push_" ~ text(chunk);
        file_name_lock          = path ~ "/" ~ name ~ "_queue.lock";
    }

    ~this()
    {
        close();
    }

    void toString(scope void delegate(const(char)[]) sink) const
    {
        sink("queue:" ~ name);
//      sink (", first_element=" ~ text(first_element));
        sink(", right_edge=" ~ text(right_edge));
        sink(", count_pushed=" ~ text(count_pushed));
//      sink (", count_popped=" ~ text(count_popped));
    }

    public static bool is_lock(string _queue_name)
    {
        return(exists(queue_db_path ~ "/" ~ _queue_name ~ "_queue.lock"));
    }

    public void remove()
    {
        close();
        std.file.remove(file_name_info_push);
        std.file.remove(file_name_queue);
    }

    public bool open(Mode _mode = Mode.DEFAULT)
    {
        try
        {
            if (isReady == false)
            {
                if (_mode != Mode.DEFAULT)
                    mode = _mode;

                //writeln("open ", text (mode));

                if (mode == Mode.RW)
                {
                    if (exists(file_name_lock))
                    {
                        log.trace("Queue [%s] already open, or not deleted lock file", name);
                        return false;
                    }

                    try
                    {
                        string s_chunk = readText(file_name_current_chunk);
                        chunk = to!int (s_chunk);
                        log.trace("queue %s, current chunk=%d", name, chunk);
                    }
                    catch (Throwable tr)
                    {
                        std.file.write(file_name_current_chunk, text(chunk));
                    }

                    std.file.write(file_name_lock, text(chunk));

                    if (exists(file_name_info_push) == false)
                        ff_info_push_w = new File(file_name_info_push, "w");
                    else
                        ff_info_push_w = new File(file_name_info_push, "r+");

                    if (exists(file_name_queue) == false)
                        ff_queue_w = new File(file_name_queue, "wb");
                    else
                        ff_queue_w = new File(file_name_queue, "ab+");

                    get_info(chunk, false);
                }

                if (mode == Mode.RW && ff_info_push_w !is null && ff_queue_w !is null || mode == Mode.R)
                {
                    isReady = true;
                    //put_info();
                }
            }
        }
        catch (Throwable ex)
        {
            log.trace("ERR! queue, not open: ex: %s", ex.msg);
        }
        return isReady;
    }

    File *get_chunk_file(int chunk)
    {
        if (ff_queue_chunk_r is null)
        {
            file_name_queue  = path ~ "/" ~ name ~ "_queue_" ~ text(chunk);
            ff_queue_chunk_r = new File(file_name_queue, "r");
        }

        return ff_queue_chunk_r;
    }

    private void remove_lock()
    {
        if (mode == Mode.R)
            return;

        try
        {
            std.file.remove(file_name_lock);
            log.trace("queue:remove lock file %s", file_name_lock);
        }
        catch (Throwable tr)
        {
            log.trace("queue:fail remove %s", tr.msg);
        }
    }

    public void close()
    {
        if (isReady == true)
        {
            //writeln("queue_close:", file_name_queue);

            if (ff_info_push_chunk_r !is null)
            {
                ff_info_push_chunk_r.close();
                ff_info_push_chunk_r = null;
            }

            if (ff_queue_chunk_r !is null)
            {
                ff_queue_chunk_r.close();
                ff_queue_chunk_r = null;
            }

            if (mode == Mode.RW)
            {
                flush();
                ff_info_push_w.close();
                ff_queue_w.close();
                remove_lock();
            }
            isReady = false;
        }
    }

    private void put_info(bool is_check_ready = true)
    {
        if ((is_check_ready && !isReady) || mode == Mode.R)
            return;

        ff_info_push_w.seek(0);

        auto writer = appender!string();
        formattedWrite(writer, "%s;%d;%d;%d;", name, chunk, right_edge, count_pushed);

        hash.start();
        hash.put(cast(ubyte[])writer.data);
        string hash_hex = crcHexString(hash.finish());

        ff_info_push_w.write(writer.data);
        ff_info_push_w.writeln(hash_hex);
    }

    public bool get_info(int r_chunk, bool is_check_ready = true)
    {
        if (is_check_ready && !isReady)
            return false;

        if (ff_info_push_chunk_r is null)
        {
            ff_info_push_chunk_r = new File(path ~ "/" ~ name ~ "_info_push_" ~ text(r_chunk), "r");
        }

        ff_info_push_chunk_r.seek(0);
//        writeln("@2 ff_info_push_r.size=", ff_info_push_r.size);

        string str = ff_info_push_chunk_r.readln();
        //writeln("@3 str=[", str, "]");
        if (str !is null)
        {
            string[] ch = str[ 0..$ - 1 ].split(';');
            //writeln("@ queue.get_info ch=", ch);
            if (ch.length != 5)
            {
                isReady = false;
                return false;
            }

            name = ch[ 0 ];

            if (ch[ 0 ] != name)
            {
                isReady = false;
                return false;
            }
            name         = ch[ 0 ];
            chunk        = to!int (ch[ 1 ]);
            right_edge   = to!ulong (ch[ 2 ]);
            count_pushed = to!uint (ch[ 3 ]);
            string hash_hex = ch[ 4 ];
        }

        //writeln(this);

        return true;
    }

    private void flush()
    {
        if (mode == Mode.R)
            return;

        if (ff_queue_w !is null)
            ff_queue_w.flush();

        if (ff_info_push_w !is null)
            ff_info_push_w.flush();
    }

    private void put_msg(string msg, QMessageType type = QMessageType.STRING)
    {
        if (mode == Mode.R)
            return;

        ubyte[] _buff2 = cast(ubyte[])msg;

        header.start_pos    = right_edge;
        header.msg_length   = _buff2.length;
        header.count_pushed = count_pushed;
        header.type         = type;

        header.to_buff(header_buff);

        hash.start();
        hash.put(header_buff);
        hash.put(_buff2);
        crc = hash.finish();

        header_buff[ header_buff.length - 4 ] = crc[ 0 ];
        header_buff[ header_buff.length - 3 ] = crc[ 1 ];
        header_buff[ header_buff.length - 2 ] = crc[ 2 ];
        header_buff[ header_buff.length - 1 ] = crc[ 3 ];

        ff_queue_w.rawWrite(header_buff);
        ff_queue_w.rawWrite(_buff2);

        right_edge += header_buff.length + _buff2.length;
    }

///////////////////////////////////////////////////////////////////////////

    public void push(string msg, bool is_flush = true, QMessageType type = QMessageType.STRING)
    {
        if (!isReady || mode == Mode.R)
        {
            log.trace("ERR! queue, no push into [%s], ready=%s, mode=%s", name, text(isReady), text(mode));
            return;
        }

        count_pushed++;
        put_msg(msg, type);
        put_info();

        if (is_flush)
            flush();
    }
}

unittest
{
    import std.datetime, std.uuid;
    import veda.util.tests_tools;
    import veda.onto.individual, veda.onto.resource;

    Logger log = new Logger("test", "log", "QUEUE");

    Queue  queue = new Queue("queue1" ~ randomUUID().toString(), Mode.RW, log);
    queue.open(Mode.RW);
    assert(queue.isReady);

    Consumer cs = new Consumer(queue, "consumer1", log);
    cs.open();

    assert(cs.isReady);

    Individual new_indv_A1 = generate_new_test_individual();
    string     binobj      = new_indv_A1.serialize();
    queue.push(binobj);

    Individual new_indv_A = generate_new_test_individual();
    binobj = new_indv_A.serialize();

    queue.push(binobj);
    queue.push(binobj);
    queue.push(binobj);

    string val = cs.pop();
    val = cs.pop();
    val = cs.pop();

    Individual indv_B;
    indv_B.deserialize(val);

    bool compare_res = new_indv_A.compare(indv_B);
    if (compare_res == false)
        writefln("new_indv_A [%s] != indv_B [%s]", new_indv_A, indv_B);

    assert(compare_res);

    val = cs.pop();

    Individual indv_B1;
    indv_B1.deserialize(val);

    compare_res = new_indv_A1.compare(indv_B1);
    if (compare_res == false)
        writefln("new_indv_A1 [%s] != indv_B [%s]", new_indv_A1, indv_B1);

    assert(compare_res);

    //queue.close();
    //cs.close();

    queue.remove();
    cs.remove();

    writeln("unittest [Queue] Ok");
}
