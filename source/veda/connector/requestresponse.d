module veda.connector.requestresponse;

private
{
    import veda.core.common.context;
}

class RequestResponse
{
    ResultCode   common_rc;
    ResultCode[] op_rc;
    string[]     msgpacks;
}