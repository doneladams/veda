/**
 * Общие определения

   Copyright: © 2014-2016 Semantic Machines
   License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
   Authors: Valeriy Bushenev
 */
module type;

import std.math, std.stdio, std.conv, std.string;

/// Имена процессов
public enum P_MODULE : byte
{
    /// Выдача и проверка тикетов
    ticket_manager  = 0,

    /// Чтение и сохранение индивидуалов
    subject_manager = 1,

    /// Индексирование прав
    acl_preparer    = 2,

    /// Полнотекстовое индексирование
    //xapian_thread_context      = 3,

    /// Полнотекстовое индексирование
    fulltext_indexer           = 4,

    /// Сбор статистики
    statistic_data_accumulator = 5,

    /// исполнение скриптов
    scripts_main               = 6,

    /// Сохранение накопленных данных в полнотекстовом индексаторе
    commiter                   = 7,

    /// Вывод статистики
    print_statistic            = 8,

    /// Загрузка из файлов
    file_reader                = 10,

    zmq_listener               = 11,

    fanout_email               = 12,

    //// data change signal
    ltr_scripts                = 14,

    webserver                  = 15,

    n_channel                  = 16,

    ccus_channel               = 17,
    
    fanout_sql_np              = 20,
    
    fanout_sql_lp              = 21,

    nop                        = 99
}

/**
 * Коды результата выполнения
 */
public enum ResultCode
{
    /// 0
    zero                  = 0,

    /// 200
    OK                    = 200,

    /// 201
    Created               = 201,

    /// 204
    No_Content            = 204,

    /// 400
    Bad_Request           = 400,

    /// 403
    Forbidden             = 403,

    /// 404
    Not_Found             = 404,

    /// 422
    Unprocessable_Entity  = 422,

    /// 429
    Too_Many_Requests     = 429,

    /// 470
    Ticket_not_found      = 470,

    /// 471
    Ticket_expired        = 471,

    /// 472
    Not_Authorized        = 472,

    /// 473
    Authentication_Failed = 473,

    /// 474
    Not_Ready             = 474,

    /// 475
    Fail_Open_Transaction = 475,

    /// 476
    Fail_Commit           = 476,

    /// 477
    Fail_Store            = 477,

    /// 500
    Internal_Server_Error = 500,

    /// 501
    Not_Implemented       = 501,

    /// 503
    Service_Unavailable   = 503,

    Invalid_Identifier    = 904,

    /// 1021
    Disk_Full             = 1021,

    /// 1022
    Duplicate_Key         = 1022,

    /// 1118
    Size_too_large        = 1118,

    /// 4000
    Connect_Error         = 4000
}

enum OptFreeze
{
	INGORE,
	NONE 
}

enum OptAuthorize
{
	NO,
	YES
}

enum OptTrace
{
	TRACE,
	NONE
}

public struct OpResult
{
    ResultCode result;
    long       op_id;
}

/// Результат
public enum Result
{
    /// OK
    Ok,

    /// Ошибка
    Err,

    /// Ничего
    Nothing
}

/// Uri
alias string Uri;

/// Битовые поля для прав
public enum Access : ubyte
{
    /// Создание
    can_create  = 1,

    /// Чтение
    can_read    = 2,

    /// Изменеие
    can_update  = 4,

    /// Удаление
    can_delete  = 8,

    /// Запрет создания
    cant_create = 16,

    /// Запрет чтения
    cant_read   = 32,

    /// Запрет обновления
    cant_update = 64,

    /// Запрет удаления
    cant_delete = 128
}

Access[] access_list =
[
    Access.can_create, Access.can_read, Access.can_update, Access.can_delete
];

Access[] denied_list =
[
    Access.cant_create, Access.cant_read, Access.cant_update, Access.cant_delete
];

/// Перечисление - Типы данных
public enum DataType : ubyte
{
    /// URI
    Uri      = 1,

    /// Строка
    String   = 2,

    /// Целочисленное число
    Integer  = 4,

    /// Время
    Datetime = 8,

    /// Десятичное число
    Decimal  = 32,

    /// Boolean
    Boolean  = 64
}

public enum INDV_OP : byte
{
    /// Сохранить
    PUT         = 1,

    /// Сохранить
    GET         = 2,

    /// Получить тикет
    GET_TICKET = 3,

    /// Авторизовать
    AUTHORIZE = 8, 

    /// Установить в
    SET_IN      = 45,

    /// Добавить в
    ADD_IN      = 47,

    /// Убрать из
    REMOVE_FROM = 48,

    /// Убрать
    REMOVE      = 51
}

/// Команды используемые процессами
/// Сохранить
byte CMD_PUT          = 1;

/// Найти
byte CMD_FIND         = 2;

/// Получить
byte CMD_GET          = 2;

/// Проверить
byte CMD_EXAMINE      = 4;

/// Авторизовать
byte CMD_AUTHORIZE    = 8;

/// Коммит
byte CMD_COMMIT       = 16;

byte CMD_MSG          = 17;

/// Конец данных
byte CMD_END_DATA     = 32;

/// Включить/выключить отладочные сообщения
byte CMD_SET_TRACE    = 33;

/// Выгрузить
byte CMD_UNLOAD       = 34;

/// Перезагрузить
byte CMD_RELOAD       = 40;

/// Backup
byte CMD_BACKUP       = 41;

/// Остановить прием команд на изменение
byte CMD_FREEZE       = 42;

/// Возобновить прием команд на изменение
byte CMD_UNFREEZE     = 43;

/// Сохранить соответствие ключ - слот (xapian)
byte CMD_PUT_KEY2SLOT = 44;

/// Установить в
byte CMD_SET_IN       = 45;

/// Удалить
byte CMD_DELETE       = 46;

/// Добавить в
byte CMD_ADD_IN       = 47;

/// Убрать из
byte CMD_REMOVE_FROM  = 48;


byte CMD_EXIT         = 49;

/// Установить
byte CMD_SET          = 50;

/// Убрать
byte CMD_REMOVE       = 51;

byte CMD_START        = 52;

byte CMD_STOP         = 53;

byte CMD_RESUME       = 54;

byte CMD_PAUSE        = 55;

byte CMD_WAIT         = 56;

/// Пустая комманда
byte   CMD_NOP        = 64;

string nullz          = "00000000000000000000000000000000";

/// Десятичное число
struct decimal
{
    /// мантисса
    long mantissa;

    /// экспонента
    byte exponent;

    this(string m, string e)
    {
        mantissa = to!long (m);
        exponent = to!byte (e);
    }

    /// конструктор
    this(long m, byte e)
    {
        mantissa = m;
        exponent = e;
    }

    /// конструктор
    this(string num)
    {
        if (num is null)
            return;

        if (num.indexOf(',') > 0)
        {
            string[] ff = split(num, ",");
            writeln("ff=", ff);
            if (ff.length == 2)
            {
                mantissa = to!long (ff[ 0 ]);
                exponent = to!byte (ff[ 1 ]);
            }
        }
        else
        {
            string[] ff = split(num, ".");

            if (ff.length == 2)
            {
                byte sfp = cast(byte)ff[ 1 ].length;

                mantissa = to!long (ff[ 0 ] ~ff[ 1 ]);
                exponent = -sfp;
            }
            else if (ff.length == 1)
            {
                mantissa = to!long (num);
                exponent = 0;
            }
        }
    }

    /// конструктор
    this(double num)
    {
        byte sign = 1;

        if (num < 0)
        {
            num  = -num;
            sign = -1;
        }

        byte   count;
        double x = num;
        while (true)
        {
            if (x - cast(long)(x) <= 0)
                break;

            x *= 10;
            ++count;
        }
        mantissa = cast(long)(num * pow(10L, count)) * sign;
        exponent = -count;
    }

    /// вернуть double
    double toDouble()
    {
        try
        {
            return mantissa * pow(10.0, exponent);
        }
        catch (Exception ex)
        {
            writeln("EX! ", ex.msg);
            return 0;
        }
    }

    string asString()
    {
        string str_res;
        string sign = "";
        string str_mantissa;

        if (mantissa < 0)
        {
            sign         = "-";
            str_mantissa = text(-mantissa);
        }
        else
            str_mantissa = text(mantissa);

        long lh = exponent * -1;

        lh = str_mantissa.length - lh;
        string slh;

        if (lh >= 0)
        {
            if (lh <= str_mantissa.length)
                slh = str_mantissa[ 0 .. lh ];
        }
        else
            slh = "";

        string slr;

        if (lh >= 0)
        {
            slr = str_mantissa[ lh..$ ];
        }
        else
        {
            slr = nullz[ 0.. (-lh) ] ~str_mantissa;
        }

        str_res = sign ~ slh ~ "." ~ slr;
        return str_res;
    }

    ///
    double toDouble_wjp()
    {
        string str_res;
        double res;
        bool   is_complete = false;

        if (exponent < 0)
        {
            string str_mantissa = text(mantissa);
            try
            {
                long lh = exponent * -1;
                lh = str_mantissa.length - lh;

                if (lh > 0 && lh > str_mantissa.length)
                {
                    res         = toDouble();
                    is_complete = true;
                }

                string slh;

                if (is_complete == false)
                {
                    if (lh >= 0)
                    {
                        if (lh > str_mantissa.length)
                        {
                            res         = toDouble();
                            is_complete = true;
                        }
                        else
                            slh = str_mantissa[ 0 .. lh ];
                    }
                    else
                        slh = "";

                    string slr;

                    if (lh >= 0)
                    {
                        slr = str_mantissa[ lh..$ ];
                    }
                    else
                        slr = nullz[ 0.. (-lh) ] ~str_mantissa;

                    str_res = slh ~ "." ~ slr;

                    res = to!double (str_res);
                }
            }
            catch (Exception ex)
            {
                res = toDouble();
            }
        }
        else
        {
            res = toDouble();
        }
        return res;
    }
}