#define _GLIBCXX_USE_CXX11_ABI    0

#include "v8.h"
#include <assert.h>
#include <iostream>
#include <string>
#include <string.h>
#include <math.h>
#include <string>
#include <sstream>
#include <limits>
#include <iomanip>
#include <cstdlib>
#include <cassert>
#include <cstddef>
#include <stdlib.h>
#include "msgpack8individual.h"

using namespace std;
using namespace v8;

#define MAX_BUF_SIZE    1024*1024
//char sr_buff[MAX_BUF_SIZE];
char* sr_buff = NULL;

//////////////////////////////////////////////////////////////////

namespace
{
void FatalErrorCallback_r(const char *location, const char *message)
{
    std::cout << "Fatal error in V8: " << location << " " << message;
}
}

static std::string to_string(double d)
{
    std::ostringstream oss;
    oss.precision(std::numeric_limits<double>::digits10);
    oss << std::fixed << d;
    std::string str = oss.str();

    // Remove padding
    // This must be done in two steps because of numbers like 700.00
    std::size_t pos1 = str.find_last_not_of("0");
    if(pos1 != std::string::npos)
        str.erase(pos1+1);

    std::size_t pos2 = str.find_last_not_of(".");
    if(pos2 != std::string::npos)
        str.erase(pos2+1);

    return str;
}

/// Stringify V8 value to JSON
/// return empty string for empty value
std::string json_str(v8::Isolate* isolate, v8::Handle<v8::Value> value)
{
    if (value.IsEmpty())
    {
        return std::string();
    }
 
    v8::HandleScope scope(isolate);
 
    v8::Local<v8::Object> json = isolate->GetCurrentContext()->
        Global()->Get(v8::String::NewFromUtf8(isolate, "JSON"))->ToObject();
    v8::Local<v8::Function> stringify = json->Get(v8::String::NewFromUtf8(isolate, "stringify")).As<v8::Function>();
 
    v8::Local<v8::Value> result = stringify->Call(json, 1, &value);
    v8::String::Utf8Value const str(result);
 
    return std::string(*str, str.length());
 }

string nullz = "00000000000000000000000000000000";

Handle<Value> msgpack2jsobject(Isolate *isolate, string in_str)
{
    Handle<Object>                           js_map = Object::New(isolate);
    Handle<Value>                            f_data = String::NewFromUtf8(isolate, "data");
    Handle<Value>                            f_lang = String::NewFromUtf8(isolate, "lang");
    Handle<Value>                            f_type = String::NewFromUtf8(isolate, "type");

    msgpack::unpacker unpk;
    unpk.reserve_buffer(in_str.length());
    memcpy(unpk.buffer(), in_str.c_str(), in_str.length());
    unpk.buffer_consumed(in_str.length());
    msgpack::object_handle result;
    unpk.next(result);
    msgpack::object glob_obj(result.get()); 
    msgpack::object_array obj_arr = glob_obj.via.array;

    if (obj_arr.size != 2) {
        cerr << "@ERR! OBJ ARR SIZE IS NOT 2" << endl;
        return js_map;
    }
    
    msgpack::object *obj_uri = obj_arr.ptr;
    msgpack::object *obj_map = obj_arr.ptr + 1;
    
    // individual->uri = string(obj_uri->via.str.ptr, obj_uri->via.str.size);
    // cerr << "@ URI" << string(obj_uri->via.str.ptr, obj_uri->via.str.size).c_str() << endl;
    js_map->Set(String::NewFromUtf8(isolate, "@"), String::NewFromUtf8(isolate, 
        string(obj_uri->via.str.ptr, obj_uri->via.str.size).c_str()));
    
    // std::cerr << glob_obj << endl;
    // std::cerr << "URI " << uri << endl;

    msgpack::object_map map = obj_map->via.map;
    // std::cerr << "MAP_SIZE " << map.size << endl;
    
    for (int i = 0; i < map.size; i++) {
        // std::cerr << "\tKEY "  << *obj << endl;
        // std::cerr << "\tKEY: " << pair->key << " VALUE: " << pair->val << endl;
        msgpack::object_kv pair = map.ptr[i];
        msgpack::object key = pair.key;
        msgpack::object_array res_objs = pair.val.via.array;
        if (key.type != msgpack::type::STR) 
        {
            // std::cerr << "@ERR! PREDICATE IS NOT STRING!" << endl;
            return js_map;
        }

        std::string predicate_str(key.via.str.ptr, key.via.str.size);
        Handle<Value> predicate = String::NewFromUtf8(isolate, 
            std::string(key.via.str.ptr, key.via.str.size).c_str());
        v8::Handle<v8::Array> resources = v8::Array::New(isolate, 1);
        

        // std::cerr << "SIZE " << res_objs.size << endl;
        for (int j = 0; j < res_objs.size; j++)
        {
            msgpack::object value = res_objs.ptr[j];
            Handle<Object> resource = Object::New(isolate);
            
            switch (value.type) 
            {
                case msgpack::type::ARRAY:
                {
                // std::cerr << "is array" << endl;
                    // std::cerr << "\t\t\tTRY ARR SIZE ";
                    msgpack::object_array res_arr = value.via.array;
                    // std::cerr << "ARR SIZE " << res_arr.size << endl; 
                    if (res_arr.size == 2)
                    {
                        long type = res_arr.ptr[0].via.u64;

                        if (type == _Datetime)
                        {
                            if (res_arr.ptr[1].type == msgpack::type::POSITIVE_INTEGER) {
                                resource->Set(f_data, v8::Date::New(isolate, (int64_t)res_arr.ptr[1].via.u64 * 1000));
                                // cerr << "\t@UNPACK  POSITIVE" << predicate_str << " " << (int64_t)res_arr.ptr[1].via.u64 << endl;
                            } else {
                                resource->Set(f_data, v8::Date::New(isolate, res_arr.ptr[1].via.i64 * 1000));
                                // cerr << "\t@UNPACK NEGATIVE " << predicate_str << " " <<  res_arr.ptr[1].via.i64 << endl;
                            }

                            resource->Set(f_type, Integer::New(isolate, _Datetime));
                        }
                        else if (type == _String)
                        {
                            /*Resource    rr;

                            // std::cerr << "string" << endl;
                            rr.type = _String;
                            
                            if (res_arr.ptr[1].type == msgpack::type::STR)
                                rr.str_data = string(res_arr.ptr[1].via.str.ptr, 
                                    res_arr.ptr[1].via.str.size);
                            else if (res_arr.ptr[1].type == msgpack::type::NIL)
                                rr.str_data = "";
                            else 
                            {
                                std::cerr << "@ERR! NOT A STRING IN RESOURCE ARRAY 2" << endl;
                                return -1;
                            }

                            rr.lang = LANG_NONE;
                            resources.push_back(rr);*/

                            if (res_arr.ptr[1].type == msgpack::type::STR)
                                resource->Set(f_data, String::NewFromUtf8(isolate, 
                                    string(res_arr.ptr[1].via.str.ptr, res_arr.ptr[1].via.str.size).c_str()));
                            else if (res_arr.ptr[1].type == msgpack::type::NIL)
                                resource->Set(f_data, String::NewFromUtf8(isolate, 
                                    string("").c_str()));

                            resource->Set(f_lang, Integer::New(isolate, LANG_NONE));
                            resource->Set(f_type, Integer::New(isolate, _String));
                        }
                        else
                        {
                            std::cerr << "@1" << endl;
                            return js_map;
                        }
                    }
                    else if (res_arr.size == 3)
                    {
                        long type = res_arr.ptr[0].via.u64;
                        // std::cerr << "TYPE " << type << endl;
                        if (type == _Decimal)
                        {
                            long decimal_mantissa_data, decimal_exponent_data;
                            // std::cerr << "is decimal" << endl << "\t\t\t\tTRY MANTISSA";
                            if (res_arr.ptr[1].type == msgpack::type::POSITIVE_INTEGER)
                                decimal_mantissa_data = res_arr.ptr[1].via.u64;
                            else
                                decimal_mantissa_data = res_arr.ptr[1].via.i64;
                            // std::cerr << mantissa << endl << "\t\t\t\tTRY EXP";
                            if (res_arr.ptr[2].type == msgpack::type::POSITIVE_INTEGER)
                                decimal_exponent_data = res_arr.ptr[2].via.u64;
                            else
                                decimal_exponent_data = res_arr.ptr[2].via.i64;

                            
                            // std::cerr << exponent << endl;

                          /*  Resource rr;
                            rr.type                  = _Decimal;
                            rr.decimal_mantissa_data = mantissa;
                            rr.decimal_exponent_data = exponent;
                            resources.push_back(rr);*/

                            string str_res;
                            string sign = "";
                            string str_mantissa;

                            if (decimal_mantissa_data < 0)
                            {
                                sign         = "-";
                                str_mantissa = to_string(-decimal_mantissa_data);
                            }
                            else
                                str_mantissa = to_string(decimal_mantissa_data);

                            long lh = decimal_exponent_data * -1;

                            lh = str_mantissa.length() - lh;
                            string slh;

                            if (lh >= 0)
                            {
                                if (lh <= str_mantissa.length())
                                    slh = str_mantissa.substr(0, lh);
                            }
                            else
                                slh = "";

                            string slr;

                            if (lh >= 0)
                            {
                                slr = str_mantissa.substr(lh, str_mantissa.length());
                            }
                            else
                            {
                                slr = nullz.substr(0, (-lh)) + str_mantissa;
                            }

                            string ss = sign + slh + "." + slr;

                            resource->Set(f_data, String::NewFromUtf8(isolate, ss.c_str()));
                            resource->Set(f_type, Integer::New(isolate, _Decimal));
                        }
                        else if (type == _String)
                        {
                           /* Resource    rr;
                            
                            rr.type = _String;
                            if (res_arr.ptr[1].type == msgpack::type::STR)
                                rr.str_data = string(res_arr.ptr[1].via.str.ptr, 
                                    res_arr.ptr[1].via.str.size);
                            else if (res_arr.ptr[1].type == msgpack::type::NIL)
                                rr.str_data = "";
                            else 
                            {
                                std::cerr << "@ERR! NOT A STRING IN RESOURCE ARRAY 2" << endl;
                                return -1;
                            }
                
                            long lang = res_arr.ptr[2].via.u64;
                            rr.lang     = lang;
                            resources.push_back(rr);*/

                            if (res_arr.ptr[1].type == msgpack::type::STR)
                                resource->Set(f_data, String::NewFromUtf8(isolate, 
                                    string(res_arr.ptr[1].via.str.ptr, res_arr.ptr[1].via.str.size).c_str()));
                            else if (res_arr.ptr[1].type == msgpack::type::NIL)
                                resource->Set(f_data, String::NewFromUtf8(isolate, 
                                    string("").c_str()));

                            resource->Set(f_lang, Integer::New(isolate, res_arr.ptr[2].via.u64));
                            resource->Set(f_type, Integer::New(isolate, _String));
                        }
                        else
                        {
                            std::cerr << "@2" << endl;
                            return js_map;
                        }
                    }
                    else
                    {
                        std::cerr << "@3" << endl;
                        return js_map;
                    }
                    break;
                }

                case msgpack::type::STR:
                {
                    /*Resource    rr;
                    rr.type = _Uri;
                    rr.str_data = string(string(value.via.str.ptr, value.via.str.size));
                    resources.push_back(rr);*/
                    resource->Set(f_data, String::NewFromUtf8(isolate, 
                        string(value.via.str.ptr, value.via.str.size).c_str()));
                    resource->Set(f_type, Integer::New(isolate, _Uri));
                    break;
                }

                case msgpack::type::POSITIVE_INTEGER:
                {
                    /*Resource rr;
                    rr.type      = _Integer;
                    rr.long_data = value.via.u64;
                    resources.push_back(rr);*/
                    resource->Set(f_data, v8::Integer::New(isolate, value.via.u64));
                    resource->Set(f_type, Integer::New(isolate, _Integer));
                    break;
                }

                case msgpack::type::NEGATIVE_INTEGER:
                {
                    /*Resource rr;
                    rr.type      = _Integer;
                    rr.long_data = value.via.i64;
                    resources.push_back(rr);*/
                    resource->Set(f_data, v8::Integer::New(isolate, value.via.i64));
                    resource->Set(f_type, Integer::New(isolate, _Integer));
                    break;
                }       

                case msgpack::type::BOOLEAN:
                {
                   /* Resource rr;
                    rr.type      = _Boolean;
                    rr.bool_data = value.via.boolean;
                    resources.push_back(rr);*/
                    resource->Set(f_data, v8::Boolean::New(isolate, value.via.boolean));
                    resource->Set(f_type, Integer::New(isolate, _Boolean));
                    break;
                } 

                default:
                {
                    std::cerr << "@ERR! UNSUPPORTED RESOURCE TYPE " << value.type << endl;
                    return js_map;  
                }  
            }
            
            resources->Set(j, resource);
        }

        // std::cerr << "RES SIZE " << resources.size() << endl;
        js_map->Set(predicate, resources);      
    }

    // std::cerr << individual << endl;
    // std::cerr << "END" << endl;
    //for (int i  = 0; i < individual->resources["rdfs:label"].size(); i++)
    //    if (individual->resources["rdfs:label"][i].str_data.find("Пупкин Вася") != string::npos) {
    //        std::cerr << "INDIVIDUAL BEGIN" << endl;
    //        individual->print_to_stderr();
    //        std::cerr << "INDIVIDUAL END" << endl;
    //        break;
    //    }
    return js_map;
}

Handle<Value>
individual2jsobject(Individual *individual, Isolate *isolate)
{
//    std::cout << "@#1" << std::endl;
    Handle<Object>                           js_map = Object::New(isolate);

    Handle<Value>                            f_data = String::NewFromUtf8(isolate, "data");
    Handle<Value>                            f_lang = String::NewFromUtf8(isolate, "lang");
    Handle<Value>                            f_type = String::NewFromUtf8(isolate, "type");

    map<string, vector<Resource> >::iterator p;

    for (p = individual->resources.begin(); p != individual->resources.end(); ++p)
    {
        std::string           key_str = p->first;
        Handle<Value>         key     = String::NewFromUtf8(isolate, key_str.c_str());

        v8::Handle<v8::Array> arr_1 = v8::Array::New(isolate, 1);

        for (int i = 0; i < p->second.size(); i++)
        {
            Handle<Object> in_obj = Object::New(isolate);

            Resource       value = p->second[ i ];
            if (value.type == _String)
            {
                if (value.lang == LANG_RU)
                    in_obj->Set(f_lang, Integer::New(isolate, 1));
                else if (value.lang == LANG_EN)
                    in_obj->Set(f_lang, Integer::New(isolate, 2));

                in_obj->Set(f_data, String::NewFromUtf8(isolate, value.str_data.c_str()));
            }
            else if (value.type == _Decimal)
            {
                //std::cout << "@c individual2jsobject #Q value.decimal_mantissa_data=" << value.decimal_mantissa_data << ", value.decimal_exponent_data=" << value.decimal_exponent_data << std::endl;

                string str_res;
                string sign = "";
                string str_mantissa;

                if (value.decimal_mantissa_data < 0)
                {
                    sign         = "-";
                    str_mantissa = to_string(-value.decimal_mantissa_data);
                }
                else
                    str_mantissa = to_string(value.decimal_mantissa_data);

                long lh = value.decimal_exponent_data * -1;

                lh = str_mantissa.length() - lh;
                string slh;

                if (lh >= 0)
                {
                    if (lh <= str_mantissa.length())
                        slh = str_mantissa.substr(0, lh);
                }
                else
                    slh = "";

                string slr;

                if (lh >= 0)
                {
                    slr = str_mantissa.substr(lh, str_mantissa.length());
                }
                else
                {
                    slr = nullz.substr(0, (-lh)) + str_mantissa;
                }

                string ss = sign + slh + "." + slr;

                in_obj->Set(f_data, String::NewFromUtf8(isolate, ss.c_str()));

                //std::cout << "@c individual2jsobject #Q ss=" << ss << std::endl;
            }
            else if (value.type == _Integer)
            {
                in_obj->Set(f_data, v8::Integer::New(isolate, value.long_data));
            }
            else if (value.type == _Datetime)
            {
                in_obj->Set(f_data, v8::Date::New(isolate, value.long_data * 1000));
            }
            else if (value.type == _Boolean)
            {
                in_obj->Set(f_data, v8::Boolean::New(isolate, value.bool_data));
            }
            else if (value.type == _Uri)
            {
                in_obj->Set(f_data, String::NewFromUtf8(isolate, value.str_data.c_str()));
            }

            in_obj->Set(f_type, Integer::New(isolate, value.type));

            arr_1->Set(i, in_obj);
        }

        Handle<Value> js_key = String::NewFromUtf8(isolate, key_str.c_str());
        js_map->Set(js_key, arr_1);
    }

    js_map->Set(String::NewFromUtf8(isolate, "@"), String::NewFromUtf8(isolate, individual->uri.c_str()));

    return js_map;
}

void double_to_mantissa_exponent(double inp, int64_t *mantissa, int64_t *exponent)
{
    double a     = trunc(inp);
    int    power = 0;

    while (inp - trunc(inp) != 0.0)
    {
        inp *= 10.0;
        power--;
    }

    *mantissa = (int64_t)inp;
    *exponent = power;

    //std::cout << "@c double_to_mantissa_exponent inp=" << inp << ", mantissa=" << *mantissa << ", exponent=" << *exponent << std::endl;
}

bool
jsobject_log(Local<Value> value)
{
    cerr << "!!START LOGGING!!" << endl;
    cerr << "@IS OBJECT " << value->IsObject() << endl;
    Local<Object>         obj = Local<Object>::Cast(value);

    v8::Handle<v8::Array> individual_keys = obj->GetPropertyNames();

    bool                  is_individual_value = false;
    bool                  is_lang_set         = false;

    uint32_t              length = individual_keys->Length();
    for (uint32_t i = 0; i < length; i++)
    {
        v8::Local<v8::Value> js_key        = individual_keys->Get(i);
        std::string          resource_name = std::string(*v8::String::Utf8Value(js_key));
        cerr << "@RESOURCE KEY " << resource_name << endl;

        Local<Value> js_value = obj->Get(js_key);

        if (resource_name == "@")
        {
            std::string uri = std::string(*v8::String::Utf8Value(js_value));
            cerr << "\t@URI DATA " << uri << endl;
            continue;
        }

        cerr << "\t@IS ARRAY " << js_value->IsArray() << endl;
        Local<v8::Array> resources_arr    = Local<v8::Array>::Cast(js_value);
        uint32_t         resources_length = resources_arr->Length();
        cerr << "\t@LENGTH " << resources_length << endl;
        for (uint32_t j = 0; j < resources_length; j++)
        {
            js_value = resources_arr->Get(j);


            if (js_value->IsObject())
            {
                Local<Object>         resource_obj = Local<Object>::Cast(js_value);

                v8::Handle<v8::Array> resource_keys   = resource_obj->GetPropertyNames();
                uint32_t              resource_length = individual_keys->Length();
                // jsobject2individual(js_value, indv, resource, predicate);
                for (uint32_t k = 0; k < resource_length; k++)
                {
                    Local<Value> v_data;
                    Local<Value> v_lang;
                    Local<Value> v_type;
                    js_key = resource_keys->Get(k);
                    std::string  element_name = std::string(*v8::String::Utf8Value(js_key));

                    if (element_name == "data")
                    {
                        cerr << "\t\t\t@ELEMENT KEY " << element_name << endl;
                        // это поле для модели индивида в js
                        v_data = resource_obj->Get(js_key);
                        if (v_data->IsString())
                        {
                            std::string str_data = std::string(*v8::String::Utf8Value(v_data));
                            cerr << "\t\t\t\t@STR DATA " << str_data << endl;
                        }
                        else if (v_data->IsDate()){
                            cerr << "\t\t\t\t@DATE DATA " << v_data->ToInteger()->Value() / 1000 << endl;
                        }
                    }
                    else if (element_name == "type")
                    {
                        cerr << "\t\t\t@ELEMENT KEY " << element_name << endl;
                        // это поле для модели индивида в js
                        v_type = resource_obj->Get(js_key);
                        cerr << "\t\t\t\t@TYPE " << v_type->ToInteger()->Value() << endl;
                    }
                    else if (element_name == "lang")
                    {
                        cerr << "\t\t\t@ELEMENT KEY " << element_name << endl;
                        // это поле для модели индивида в js
                        v_lang = resource_obj->Get(js_key);
                        cerr << "\t\t\t\t@TYPE " << v_lang->ToInteger()->Value() << endl;
                    }
		        }
            }
        }
    }

    cerr << "!!END LOGGING!!" << endl;
    return true;
}

void prepare_js_object(Local<Object> resource_obj, Handle<Value>         f_data, Handle<Value>         f_type,
                       Handle<Value>         f_lang,
                       msgpack::packer<msgpack::sbuffer> &pk)
{
    v8::Handle<v8::Array> resource_keys = resource_obj->GetPropertyNames();
    Local<Value>          v_data        = resource_obj->Get(f_data);
    Local<Value>          v_type        = resource_obj->Get(f_type);

    int                   type = v_type->ToInteger()->Value();
    //cerr << "\t\t@TYPE " << type << endl;
    if (type == _Uri)
    {
        string str_data = std::string(*v8::String::Utf8Value(v_data));
        pk.pack(str_data);
        //cerr << "\t\t\t@STR DATA " << str_data << endl;
    }
    else if (type == _Boolean)
    {
        bool bool_data = v_data->ToBoolean()->Value();
        pk.pack(bool_data);
        //cerr << "\t\t\t@BOOL DATA " << bool_data << endl;
    }
    else if (type == _Datetime)
    {
        int64_t long_data = v_data->ToInteger()->Value() / 1000;
        // cerr << "\t\t@PACK " << long_data << endl;
        pk.pack_array(2);
        pk.pack((int64_t)_Datetime);
        pk.pack(long_data);
        //cerr << "\t\t\t@DATETIME DATA " << long_data << endl;
    }
    else if (type == _Integer)
    {
        int64_t long_data = v_data->ToInteger()->Value();
        pk.pack(long_data);
        //cerr << "\t\t\t@LONG DATA " << long_data << endl;
    }
    else if (type == _Decimal)
    {
        int64_t decimal_mantissa_data, decimal_exponent_data;
        if (v_data->IsString())
        {
            v8::String::Utf8Value s1_1(v_data);
            std::string           num = std::string(*s1_1);
            //std::cerr << "@jsobject2individual value=" << num << std::endl;

            int pos = num.find('.');
            if (pos < 0)
                pos = num.find(',');

            //std::cerr << "@pos=" << pos << std::endl;

            if (pos > 0)
            {
                string ll = num.substr(0, pos);
                string rr = num.substr(pos + 1, num.length());

                size_t sfp = rr.length();

                decimal_mantissa_data = atol((ll + rr).c_str());
                decimal_exponent_data = -sfp;
            }
            else
            {
                decimal_mantissa_data = atol(num.c_str());
                decimal_exponent_data = 0;
            }
        }
        else
        {
            double dd = v_data->ToNumber()->Value();
            double_to_mantissa_exponent(dd, &decimal_mantissa_data, &decimal_exponent_data);
        }

        pk.pack_array(3);
        pk.pack((int64_t)_Decimal);
        pk.pack(decimal_mantissa_data);
        pk.pack(decimal_exponent_data);
        //cerr << "\t\t\t@DECIMAL DATA " << "MANT=" << decimal_mantissa_data << " EXP=" << decimal_exponent_data << endl;
    }
    else if (type == _String)
    {
        Local<Value> v_lang   = resource_obj->Get(f_lang);
        int          lang     = v_lang->ToInteger()->Value();
        string       str_data = std::string(*v8::String::Utf8Value(v_data));
        if (lang != LANG_NONE) {
            pk.pack_array(3);
            pk.pack((uint)_String);
            pk.pack(str_data);
            pk.pack(lang);
        } else {
            pk.pack_array(2);
            pk.pack((uint)_String);
            pk.pack(str_data);
        }
        //cerr << "@STR DATA " << str_data << "LANG: " << lang << endl;
    }
}


uint32_t
jsobject2msgpack(Local<Value> value, Isolate *isolate, char *in_buff)
{
    //cerr <<"!!START LOGGING!!" << endl;

    //jsobject_log(value);

    //cerr << "@IS OBJECT " << value->IsObject() << endl;
    Local<Object>         obj = Local<Object>::Cast(value);

    v8::Handle<v8::Array> individual_keys = obj->GetPropertyNames();
    Handle<Value> f_data = String::NewFromUtf8(isolate, "data");
    Handle<Value> f_type = String::NewFromUtf8(isolate, "type");
    Handle<Value> f_lang = String::NewFromUtf8(isolate, "lang");
    Handle<Value> f_uri = String::NewFromUtf8(isolate, "@");

    uint32_t length = individual_keys->Length();

    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);
    std::string indiv_uri = std::string(*v8::String::Utf8Value(obj->Get(f_uri)));
    pk.pack_array(2);
    pk.pack(indiv_uri);
    // cerr << "@URI PACK " << indiv_uri << endl;
    pk.pack_map(length - 1);
    
    for (uint32_t i = 0; i < length; i++)
    {
        v8::Local<v8::Value> js_key  = individual_keys->Get(i);
        std::string resource_name = std::string(*v8::String::Utf8Value(js_key));
        // cerr << "@RESOURCE KEY " << resource_name << endl;
        Local<Value> js_value = obj->Get(js_key);
        if (resource_name == "@")
        {
            // write_string(resource_name, ou);
            // std::string uri = std::string(*v8::String::Utf8Value(js_value));
            // write_string(uri, ou);
            //cerr << "\t@URI DATA " << uri << endl;
            continue;
        }

        // cerr << "\tPREDICATE " << resource_name << endl;
        pk.pack(resource_name);
        if (!js_value->IsArray())
        {
            if (js_value->IsObject())
            {
//              {}
                pk.pack_array(1);
                Local<Object> resource_obj = Local<Object>::Cast(js_value);
                prepare_js_object(resource_obj, f_data, f_type, f_lang, pk);
            }
            else
            {
                pk.pack_array(0);
            }
            continue;
        }


        //cerr << "\t@IS ARRAY " << js_value->IsArray() << endl;
        Local<v8::Array> resources_arr    = Local<v8::Array>::Cast(js_value);
        uint32_t         resources_length = resources_arr->Length();
        //cerr << "\t@LENGTH " << resources_length << endl;
        pk.pack_array(resources_length);

        for (uint32_t j = 0; j < resources_length; j++)
        {
            js_value = resources_arr->Get(j);

            if (js_value->IsArray())
            {
                //cerr << "[ [ {} ] ]" << endl;
//             [ [ {} ] ]

                Local<v8::Array> resources_in_arr    = Local<v8::Array>::Cast(js_value);
                uint32_t         resources_in_length = resources_in_arr->Length();

                if (resources_in_length == 1)
                {
                    js_value = resources_in_arr->Get(0);

                    Local<Object> resource_obj = Local<Object>::Cast(js_value);
                    prepare_js_object(resource_obj, f_data, f_type, f_lang, pk);
                }
                else
                {
                    //cerr << "[ [ {} ], [ {} ] ]" << endl;
//                  [ [ {} ], [ {} ] ]
                    cerr << "ERR! INVALID JS INDIVIDUAL FORMAT " << endl;
		    // jsobject_log(value);
                }
            }
            else
            {
                if (js_value->IsObject())
                {
//             [ {} ]
                    //cerr << "[ {} ]" << endl;
                    Local<Object> resource_obj = Local<Object>::Cast(js_value);
                    prepare_js_object(resource_obj, f_data, f_type, f_lang, pk);
                }
                else
                {
                    cerr << "ERR! INVALID JS INDIVIDUAL FORMAT, NULL VALUE, "  << endl;
		    // jsobject_log(value);

                    pk.pack_array(0);
                }
            }
        }
    }

    memcpy(in_buff, buffer.data(), buffer.size());
    //cerr << "!!END LOGGING!!" << endl;
    return buffer.size();
}


bool
jsobject2individual(Local<Value> value, Individual *indv, Resource *resource, string predicate)
{
    //std::cout << "@json->binobj #0 predicate=" << predicate << std::endl;

    if (value->IsArray())
    {
        //std::cout << "@json->binobj # is array" << std::endl;
        Local<v8::Array> js_arr = Local<v8::Array>::Cast(value);

        if (js_arr->Length() == 1)
        {
            Local<Value> js_value = js_arr->Get(0);
            jsobject2individual(js_value, indv, resource, predicate);
            return true;
        }

        for (uint32_t idx = 0; idx < js_arr->Length(); idx++)
        {
            Local<Value> js_value = js_arr->Get(idx);
            jsobject2individual(js_value, indv, resource, predicate);
        }
        return true;
    }
    else if (value->IsString())
    {
        if (resource == NULL)
            return false;

        //std::cout << "@json->binobj #is sring" << std::endl;
        v8::String::Utf8Value s1(value);
        std::string           vv = std::string(*s1);

        resource->type     = _String;
        resource->str_data = vv;

        return true;
    }
    else if (value->IsBoolean())
    {
        if (resource == NULL)
            return false;

        //std::cout << "@json->binobj #is boolean" << std::endl;

        resource->type      = _Boolean;
        resource->bool_data = value->ToBoolean()->Value();

        return true;
    }
    else if (value->IsDate())
    {
        if (resource == NULL)
            return false;

//        std::cout << "@json->binobj #10" << std::endl;
        resource->type      = _Datetime;
        resource->long_data = value->ToInteger()->Value();

        return true;
    }
    else if (value->IsInt32() || value->IsUint32())
    {
        if (resource == NULL)
            return false;

//        std::cout << "@json->binobj #10" << std::endl;
        resource->type      = _Integer;
        resource->long_data = value->ToInteger()->Value();

        return true;
    }
    else if (value->IsNumber())
    {
        if (resource == NULL)
            return false;

        //std::cout << "@json->cbor #is sring" << std::endl;

        double dd = value->ToNumber()->Value();

        resource->type = _Decimal;
        double_to_mantissa_exponent(dd, &resource->decimal_mantissa_data, &resource->decimal_exponent_data);

        return true;
    }
    else if (value->IsObject())
    {
        //std::cout << "@json->binobj #is object" << std::endl;
        Local<Object>         obj = Local<Object>::Cast(value);

        v8::Handle<v8::Array> propertyNames = obj->GetPropertyNames();

        bool                  is_individual_value = false;
        Local<Value>          v_data;
        Local<Value>          v_lang;
        Local<Value>          v_type;
        bool                  is_lang_set = false;

        uint32_t              length = propertyNames->Length();
        for (uint32_t i = 0; i < length; i++)
        {
            v8::Local<v8::Value>  js_key = propertyNames->Get(i);

            v8::String::Utf8Value s1(js_key);
            std::string           name = std::string(*s1);

            //std::cout << "$#1 name=" << name << std::endl;

            if (name == "data")
            {
                // это поле для модели индивида в js
                v_data              = obj->Get(js_key);
                is_individual_value = true;
            }
            else if (name == "type")
            {
                // это поле для модели индивида в js
                v_type              = obj->Get(js_key);
                is_individual_value = true;
            }
            else if (name == "lang")
            {
                // это поле для модели индивида в js
                v_lang              = obj->Get(js_key);
                is_lang_set         = true;
                is_individual_value = true;
            }
            else if (name == "@")
            {
                //Resource              rc;
                Local<Value>          js_value = obj->Get(js_key);

                v8::String::Utf8Value s2(js_value);
                std::string           vv = std::string(*s2);

                indv->uri = vv;
            }
            else
            {
                Local<Value> js_value = obj->Get(js_key);
                bool         res      = jsobject2individual(js_value, indv, resource, name);
                if (res == false)
                {
                    Resource              rc;
                    rc.lang = LANG_EN;
                    v8::String::Utf8Value s1_1(js_value);
                    std::string           std_s1_1 = std::string(*s1_1);
                    vector<Resource>      values   = indv->resources[ name ];
                    rc.type     = _String;
                    rc.str_data = std_s1_1;
                    values.push_back(rc);

                    indv->resources[ name ] = values;
                }
            }
        }

        if (is_individual_value == true)
        {
            //std::cout << "@json->binobj #4" << std::endl;
            int type = v_type->ToInt32()->Value();

            //Resource rc;

            if (type == _Boolean)
            {
                bool             boolValue = v_data->ToBoolean()->Value();
                vector<Resource> values    = indv->resources[ predicate ];
                Resource         rc;
                rc.type      = type;
                rc.bool_data = boolValue;
                values.push_back(rc);
                indv->resources[ predicate ] = values;
                return true;
            }
            else if (type == _Decimal)
            {
               vector<Resource> values = indv->resources[ predicate ];
                Resource         rc;
                rc.type = type;

                if (v_data->IsString())
                {
                    v8::String::Utf8Value s1_1(v_data);
                    std::string           std_s1_1 = std::string(*s1_1);
                    rc.str_data = std_s1_1;
                }
                else
                {
                    double dd = v_data->ToNumber()->Value();
                    double_to_mantissa_exponent(dd, &rc.decimal_mantissa_data, &rc.decimal_exponent_data);
                }

                values.push_back(rc);
                indv->resources[ predicate ] = values;
                return true;
            }
            else if (type == _Datetime)
            {
                int64_t          value  = (int64_t)(v_data->ToInteger()->Value() / 1000);
                vector<Resource> values = indv->resources[ predicate ];
                Resource         rc;
                rc.type      = type;
                rc.long_data = value;
                values.push_back(rc);
                indv->resources[ predicate ] = values;
                return true;
            }
            else if (type == _Integer)
            {
                int              intValue = v_data->ToInteger()->Value();
                vector<Resource> values   = indv->resources[ predicate ];
                Resource         rc;
                rc.type      = type;
                rc.long_data = intValue;
                values.push_back(rc);
                indv->resources[ predicate ] = values;
                return true;
            }
            else if (type == _Uri || type == _String)
            {
                Resource rc;

                if (type == _String && is_lang_set == true)
                {
                    int lang = v_lang->ToInt32()->Value();

                    if (lang == 1)
                        rc.lang = LANG_RU;
                    else if (lang == 2)
                        rc.lang = LANG_EN;
                }

                v8::String::Utf8Value s1_1(v_data);
                std::string           std_s1_1 = std::string(*s1_1);

                //std::cout << "@json->binobj #4.1" << std_s1_1 << std::endl;

                vector<Resource> values = indv->resources[ predicate ];

                rc.type     = type;
                rc.str_data = std_s1_1;
                values.push_back(rc);

                indv->resources[ predicate ] = values;

                return true;
            }
        }
    }

    //std::cout << "@json->binobj #12" << std::endl;
    return true;
}

///////pacahon IO section //////////////////////////////////////////////////////////////////////////////////////////////////

struct _Buff
{
    char *data;
    int  length;
    int  allocated_size;
};

_Buff* get_from_ght(const char *name, int name_length);
void put_to_ght(const char *name, int name_length, const char *value, int value_length);
_Buff* uris_pop(const char *consumer_id, int consumer_id_length);
_Buff* new_uris_consumer();
bool uris_commit_and_next(const char *_consumer_id, int _consumer_id_length, bool is_sync_data);

_Buff *
get_env_str_var(const char *_var_name, int _var_name_length);

_Buff *
query(const char *_ticket, int _ticket_length, const char *_query, int _query_length,
      const char *_sort, int _sort_length, const char *_databases, int _databases_length, int top, int limit);

_Buff *
read_individual(const char *_ticket, int _ticket_length, const char *_uri, int _uri_length);
int
put_individual(const char *_ticket, int _ticket_length, const char *_binobj, int _binobj_length, const char *_event_id,
               int _event_id_length);
int
remove_individual(const char *_ticket, int _ticket_length, const char *_uri, int _uri_length, const char *_event_id,
                  int _event_id_length);
int
add_to_individual(const char *_ticket, int _ticket_length, const char *_binobj, int _binobj_length, const char *_event_id,
                  int _event_id_length);
int
set_in_individual(const char *_ticket, int _ticket_length, const char *_binobj, int _binobj_length, const char *_event_id,
                  int _event_id_length);
int
remove_from_individual(const char *_ticket, int _ticket_length, const char *_binobj, int _binobj_length,
                       const char *_event_id, int _event_id_length);

void log_trace(const char *_str, int _str_length);

//char *get_resource (int individual_idx, const char* _uri, int _uri_length, int* count_resources, int resource_idx);

///////////////////////////////////////////////////////////////////////////////////////////////////////////

class WrappedContext
{
public:
    WrappedContext ();
    ~WrappedContext ();

    Persistent<Context> context_;
    Isolate             *isolate_;
    Isolate *
    GetIsolate()
    {
        return isolate_;
    }
};

class WrappedScript
{
public:

    WrappedScript ()
    {
    }
    ~WrappedScript ();

    Persistent<Script> script_;
};

// Extracts a C string from a V8 Utf8Value.
const char *
ToCString(const v8::String::Utf8Value& value)
{
    return *value ? *value : "<string conversion failed>";
}
///////////////////////////////////////////////////////////////////////////////////////////////////////////

void
GetEnvStrVariable(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 1)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "Bad parameters"));
        return;
    }

    v8::String::Utf8Value str(args[ 0 ]);
    const char            *var_name = ToCString(str);
    _Buff                 *res      = get_env_str_var(var_name, str.length());

    if (res != NULL)
    {
        std::string data(res->data, res->length);

        //std::cout << "@c:get #3 " << std::endl;
//        std::cout << "@c:get #3 [" << vv << "]" << std::endl;
        Handle<Value> oo = String::NewFromUtf8(isolate, data.c_str());
        args.GetReturnValue().Set(oo);
    }
}

std::string prepare_str_list_element(std::string data, std::string::size_type b_p, std::string::size_type e_p)
{
    while (data.at(b_p) == ' ')
        b_p++;

    while (data.at(b_p) == '"')
        b_p++;

    while (data.at(e_p - 1) == ' ')
        e_p--;

    while (data.at(e_p - 1) == '"')
        e_p--;

    std::string substring(data.substr(b_p, e_p - b_p));

    //std::cout << "@c:query, ss= " << substring << std::endl;

    return substring;
}

void
Query(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    Isolate *isolate = args.GetIsolate();

    if (args.Length() < 2)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "Bad parameters"));
        return;
    }

    v8::String::Utf8Value _ticket(args[ 0 ]);
    const char            *cticket = ToCString(_ticket);

    v8::String::Utf8Value _query(args[ 1 ]);
    if (_query.length() == 0)
        return;

    const char *cquery = ToCString(_query);

    const char *csort      = NULL;
    const char *cdatabases = NULL;

    int        sort_len      = 0;
    int        databases_len = 0;

    if (args.Length() > 2)
    {
        v8::String::Utf8Value _sort(args[ 2 ]);
        if (_sort.length() > 1)
        {
            csort    = ToCString(_sort);
            sort_len = _sort.length();
        }

        if (args.Length() > 3)
        {
            v8::String::Utf8Value _databases(args[ 3 ]);
            if (_databases.length() > 1)
            {
                cdatabases    = ToCString(_databases);
                databases_len = _databases.length();
            }
        }
    }

    int                   top   = 100000;
    int                   limit = 100000;

    _Buff                 *res  = query(cticket, _ticket.length(), cquery, _query.length(), csort, sort_len, cdatabases, databases_len, top, limit);
    v8::Handle<v8::Array> arr_1 = v8::Array::New(isolate, 0);

    if (res != NULL)
    {
        std::string data(res->data, res->length);

        if (data.length() > 5)
        {
            std::string::size_type prev_pos = 1, pos = 1;
            std::string            el;

            int                    i = 0;
            while ((pos = data.find(',', pos)) != std::string::npos)
            {
                el = prepare_str_list_element(data, prev_pos, pos);
                if (el.length() > 2)
                {
                    arr_1->Set(i, String::NewFromUtf8(isolate, el.c_str()));
                    i++;
                }
                prev_pos = ++pos;
            }
            el = prepare_str_list_element(data, prev_pos, data.length() - 1);

            if (el.length() > 2)
            {
                arr_1->Set(i, String::NewFromUtf8(isolate, el.c_str()));
            }
        }
    }
    args.GetReturnValue().Set(arr_1);
}

////////////////

void
NewUrisConsumer(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    Isolate *isolate = args.GetIsolate();
 
     if (args.Length() != 0)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "Bad parameters"));
        return;
    }

    _Buff *res = new_uris_consumer ();
    if (res != NULL)
    {
        std::string data(res->data, res->length);
		Handle<Value> oo = String::NewFromUtf8(isolate, data.c_str());
		args.GetReturnValue().Set(oo);
    }
}

void
UrisPop(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 1)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "uris_pop: bad parameters"));
        return;
    }

	v8::String::Utf8Value _id(args[ 0 ]);    
    const char* cid = ToCString(_id);

    _Buff *res = uris_pop (cid, _id.length());

    if (res != NULL)
    {
        std::string data(res->data, res->length);

		Handle<Value> oo = String::NewFromUtf8(isolate, data.c_str());

		args.GetReturnValue().Set(oo);
    }
}

void
UrisCommitAndNext(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 2)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "commit_and_next: bad parameters"));
        return;
    }

	v8::String::Utf8Value _id(args[ 0 ]);    
    const char* cid = ToCString(_id);
    
    bool is_sync_data = args[1]->BooleanValue();

    bool res = uris_commit_and_next (cid, _id.length(), is_sync_data);

	args.GetReturnValue().Set(res);
}

/////////////////////
void GetFromGHT(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 1)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "Bad parameters"));
        return;
    }
    
	v8::String::Utf8Value _name(args[ 0 ]);    
    const char* cname = ToCString(_name);
    	
    _Buff *res = get_from_ght (cname, _name.length());
    if (res != NULL)
    {
        std::string data(res->data, res->length);
		Handle<Value> oo = String::NewFromUtf8(isolate, data.c_str());
		args.GetReturnValue().Set(oo);
    }
}

void PutToGHT(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 2)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "Bad parameters"));
        return;
    }

	v8::String::Utf8Value _name(args[ 0 ]);
    const char* cname = ToCString(_name);

	v8::String::Utf8Value _value(args[ 1 ]);
    const char* cvalue = ToCString(_value);

	put_to_ght(cname, _name.length(), cvalue, _value.length());
}

////////////////////

void
GetIndividual(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 2)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "Bad parameters"));
        return;
    }

    v8::String::Utf8Value str(args[ 0 ]);
    const char            *ticket = ToCString(str);

    v8::String::Utf8Value str1(args[ 1 ]);

    if (str1.length() == 0)
        return;

    const char *cstr = ToCString(str1);

    _Buff      *doc_as_binobj = read_individual(ticket, str.length(), cstr, str1.length());

    if (doc_as_binobj != NULL)
    {
        std::string data(doc_as_binobj->data, doc_as_binobj->length);

        // Individual  individual;
        // msgpack2individual(&individual, data);
        // msgpack2jsobject(isolate, data);

		//std::cout << "@c #get_individual uri=" << cstr << std::endl;

        // Handle<Value> oo = individual2jsobject(&individual, isolate);
        Handle<Value> oo = msgpack2jsobject(isolate, data);
        cerr << "GET!!" << endl;
        jsobject_log(oo);
        cerr << "END GET!!" << endl;

		//std::cout << "@c #get_individual #E" << std::endl;
        args.GetReturnValue().Set(oo);
    }
}

void
RemoveIndividual(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    int     res      = 500;
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 3)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "RemoveIndividual::Bad count parameters"));

        return;
    }

    v8::String::Utf8Value str(args[ 0 ]);
    const char            *ticket = ToCString(str);

    v8::String::Utf8Value str1(args[ 1 ]);

    if (str1.length() == 0)
        return;

    const char            *cstr = ToCString(str1);

    v8::String::Utf8Value str_event_id(args[ 2 ]);
    const char            *event_id = ToCString(str_event_id);

    res = remove_individual(ticket, str.length(), cstr, str1.length(), event_id, str_event_id.length());

    args.GetReturnValue().Set(res);
}

void
PutIndividual(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    int     res      = 500;
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 3)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "PutIndividual::Bad count parameters"));

        return;
    }

    if (args[ 1 ]->IsObject())
    {
		//string jsnstr = json_str(isolate, args[ 1 ]);
		//std::cout << "@c #put_individual json=" << jsnstr << std::endl;
        /*Individual individual;
        jsobject2individual(args[ 1 ], &individual, NULL, "");*/

        v8::String::Utf8Value str_ticket(args[ 0 ]);
        const char            *ticket = ToCString(str_ticket);

        v8::String::Utf8Value str_event_id(args[ 2 ]);
        const char            *event_id = ToCString(str_event_id);

		if (sr_buff == NULL)
			sr_buff = new char[1024*1024];

        // int len = individual2msgpack(&individual, sr_buff);
        cerr << "PUT!!" << endl;
        jsobject_log(args[1]);
        cerr << "END PUT !!" << endl;

        int len = jsobject2msgpack(args[1], isolate, sr_buff);                    
        res = put_individual(ticket, str_ticket.length(), sr_buff, len, event_id, str_event_id.length());
    }

    args.GetReturnValue().Set(res);
}

void
AddToIndividual(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    int     res      = 500;
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 3)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "PutIndividual::Bad count parameters"));

        return;
    }

    if (args[ 1 ]->IsObject())
    {
        /*Individual individual;
        jsobject2individual(args[ 1 ], &individual, NULL, "");*/

        v8::String::Utf8Value str_ticket(args[ 0 ]);
        const char            *ticket = ToCString(str_ticket);

        v8::String::Utf8Value str_event_id(args[ 2 ]);
        const char            *event_id = ToCString(str_event_id);

		if (sr_buff == NULL)
			sr_buff = new char[1024*1024];

        // int len = individual2msgpack(&individual, sr_buff);
      
        int len = jsobject2msgpack(args[1], isolate, sr_buff);                   
        res = put_individual(ticket, str_ticket.length(), sr_buff, len, event_id, str_event_id.length());
    }

    args.GetReturnValue().Set(res);
}

void
SetInIndividual(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    int     res      = 500;
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 3)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "PutIndividual::Bad count parameters"));

        return;
    }

    if (args[ 1 ]->IsObject())
    {
        /*Individual individual;
        jsobject2individual(args[ 1 ], &individual, NULL, "");*/

        v8::String::Utf8Value str_ticket(args[ 0 ]);
        const char            *ticket = ToCString(str_ticket);

        v8::String::Utf8Value str_event_id(args[ 2 ]);
        const char            *event_id = ToCString(str_event_id);

		if (sr_buff == NULL)
			sr_buff = new char[1024*1024];

        // int len = individual2msgpack(&individual, sr_buff);
      
        int len = jsobject2msgpack(args[1], isolate, sr_buff);                   
        res = put_individual(ticket, str_ticket.length(), sr_buff, len, event_id, str_event_id.length());
    }

    args.GetReturnValue().Set(res);
}

void
RemoveFromIndividual(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    int     res      = 500;
    Isolate *isolate = args.GetIsolate();

    if (args.Length() != 3)
    {
        isolate->ThrowException(v8::String::NewFromUtf8(isolate, "PutIndividual::Bad count parameters"));

        return;
    }

    if (args[ 1 ]->IsObject())
    {
        /*Individual individual;
        jsobject2individual(args[ 1 ], &individual, NULL, "");*/

        v8::String::Utf8Value str_ticket(args[ 0 ]);
        const char            *ticket = ToCString(str_ticket);

        v8::String::Utf8Value str_event_id(args[ 2 ]);
        const char            *event_id = ToCString(str_event_id);

		if (sr_buff == NULL)
			sr_buff = new char[1024*1024];

        // int len = individual2msgpack(&individual, sr_buff);
      
        int len = jsobject2msgpack(args[1], isolate, sr_buff);                    
        res = put_individual(ticket, str_ticket.length(), sr_buff, len, event_id, str_event_id.length());
    }

    args.GetReturnValue().Set(res);
}

// The callback that is invoked by v8 whenever the JavaScript 'print'
// function is called.  Prints its arguments on stdout separated by
// spaces and ending with a newline.
void
Print(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    bool            first = true;
    v8::HandleScope handle_scope(args.GetIsolate());

    if (args.Length() == 0)
        return;

    v8::String::Utf8Value str(args[ 0 ]);
    const char            *cstr = ToCString(str);
    std::string           sstr(cstr, str.length());

    if (args.Length() > 1)
    {
        for (int i = 1; i < args.Length(); i++)
        {
            sstr = sstr + " ";

            v8::String::Utf8Value str_i(args[ i ]);
            const char            *cstr_i = ToCString(str_i);
            std::string           sstr_i(cstr_i, str_i.length());
            sstr = sstr + sstr_i;
        }
    }

    log_trace(sstr.c_str(), sstr.length());
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////

WrappedContext::WrappedContext ()
{
    isolate_ = v8::Isolate::New();

    v8::Locker         locker(isolate_);
    v8::Isolate::Scope isolateScope(isolate_);
    HandleScope        handle_scope(isolate_);

    // Create a template for the global object.
    v8::Handle<v8::ObjectTemplate> global = v8::ObjectTemplate::New(isolate_);
    // Bind the global 'print' function to the C++ Print callback.
    global->Set(v8::String::NewFromUtf8(isolate_, "print"), v8::FunctionTemplate::New(isolate_, Print));
    global->Set(v8::String::NewFromUtf8(isolate_, "log_trace"), v8::FunctionTemplate::New(isolate_, Print));

    global->Set(v8::String::NewFromUtf8(isolate_, "get_env_str_var"),
                v8::FunctionTemplate::New(isolate_, GetEnvStrVariable));

    global->Set(v8::String::NewFromUtf8(isolate_, "query"),
                v8::FunctionTemplate::New(isolate_, Query));
    global->Set(v8::String::NewFromUtf8(isolate_, "get_individual"),
                v8::FunctionTemplate::New(isolate_, GetIndividual));
    global->Set(v8::String::NewFromUtf8(isolate_, "remove_individual"),
                v8::FunctionTemplate::New(isolate_, RemoveIndividual));
    global->Set(v8::String::NewFromUtf8(isolate_, "put_individual"),
                v8::FunctionTemplate::New(isolate_, PutIndividual));
    global->Set(v8::String::NewFromUtf8(isolate_, "add_to_individual"),
                v8::FunctionTemplate::New(isolate_, AddToIndividual));
    global->Set(v8::String::NewFromUtf8(isolate_, "set_in_individual"),
                v8::FunctionTemplate::New(isolate_, SetInIndividual));
    global->Set(v8::String::NewFromUtf8(isolate_, "remove_from_individual"),
                v8::FunctionTemplate::New(isolate_, RemoveFromIndividual));
    global->Set(v8::String::NewFromUtf8(isolate_, "uris_pop"),
                v8::FunctionTemplate::New(isolate_, UrisPop));
    global->Set(v8::String::NewFromUtf8(isolate_, "new_uris_consumer"),
                v8::FunctionTemplate::New(isolate_, NewUrisConsumer));
    global->Set(v8::String::NewFromUtf8(isolate_, "put_to_ght"),
                v8::FunctionTemplate::New(isolate_, PutToGHT));
    global->Set(v8::String::NewFromUtf8(isolate_, "get_from_ght"),
                v8::FunctionTemplate::New(isolate_, GetFromGHT));
    global->Set(v8::String::NewFromUtf8(isolate_, "uris_commit_and_next"),
                v8::FunctionTemplate::New(isolate_, UrisCommitAndNext));

    v8::Handle<v8::Context> context = v8::Context::New(isolate_, NULL, global);
    context_.Reset(isolate_, context);
}

WrappedContext::~WrappedContext ()
{
//  context_.Dispose();
}

WrappedScript::~WrappedScript ()
{
//  script_.Dispose();
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

WrappedContext *
new_WrappedContext()
{
    WrappedContext *t = new WrappedContext();

    return t;
}

WrappedScript *
new_WrappedScript(WrappedContext *_context, char *src)
{
    Isolate                *isolate = _context->isolate_;
    v8::Locker             locker(isolate);
    v8::Isolate::Scope     isolateScope(isolate);
    HandleScope            scope(isolate);

    v8::Local<v8::Context> context = v8::Local<v8::Context>::New(isolate, _context->context_);
    Context::Scope         context_scope(context);

    Handle<String>         source = v8::String::NewFromUtf8(isolate, src);

    Handle<Script>         sc = Script::Compile(source);

    WrappedScript          *v8ws = new WrappedScript();
    v8ws->script_.Reset(isolate, sc);

    return v8ws;
}

void
run_WrappedScript(WrappedContext *_context, WrappedScript *ws, _Buff *_res, _Buff *_out)
{
    Isolate                *isolate = _context->isolate_;

    v8::Locker             locker(isolate);
    v8::Isolate::Scope     isolateScope(isolate);

    HandleScope            scope(isolate);

    v8::Local<v8::Context> context = v8::Local<v8::Context>::New(isolate, _context->context_);
    Context::Scope         context_scope(context);

    v8::Local<v8::Script>  script = v8::Local<v8::Script>::New(isolate, ws->script_);

    v8::V8::SetFatalErrorHandler(FatalErrorCallback_r);
    Handle<Value> result = script->Run();

    if (_res != NULL)
    {
        String::Utf8Value utf8(result);

        int               c_length;

        if (utf8.length() >= _res->allocated_size)
            c_length = _res->allocated_size;
        else
            c_length = utf8.length();

        memcpy(_res->data, *utf8, c_length);
        _res->length = c_length;
    }

//    printf("Script result: %s\n", *utf8);

//  bool finished = false;
//  for (int i = 0; i < 200 && !finished; i++)
//  {
//finished =
    isolate->IdleNotification(1000);
//  }
}

void
InitializeICU()
{
    v8::V8::InitializeICU(NULL);
}

void
ShutdownPlatform()
{
    v8::V8::ShutdownPlatform();
}

void
Dispose()
{
    v8::V8::Dispose();
}
