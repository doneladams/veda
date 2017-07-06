module requestresponse;

import type;

class RequestResponse
{
    ResultCode   common_rc;
    ResultCode[] op_rc;
    string[]     msgpacks;
    ubyte[]      rights;
}