#include "individual.h"

bool Resource::operator== (Resource &res) {
    if (this->type != res.type)
        return false;
    
    switch (this->type) {
        case _Uri: {
            if (this->str_data == res.str_data)
                return true;
            break;
        } 
        case  _String: {
            if (this->str_data == res.str_data && this->lang == lang)
                return true;
            break;
        }
        case _Integer: {
            if (this->long_data == res.long_data)
                return true;
            break;
        }
        case _Datetime: {
            if (this->long_data == res.long_data)
                return true;
            break;
        }
        case _Decimal: {
            if (this->decimal_mantissa_data == res.decimal_mantissa_data &&
                this->decimal_exponent_data == res.decimal_exponent_data)
                return true;
            break;
        }
        case _Boolean: {
            if (this->bool_data == res.bool_data)
                return true;
        }
        default: {
            cout << "@ERR LISTENER! UNKNOWN RESOURCE TYPE " << this->type << endl;
            return false;
        }
    }

    return false;
}