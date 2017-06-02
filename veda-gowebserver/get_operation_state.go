package main

import (
	"log"
	"strconv"

	"github.com/valyala/fasthttp"
)

func getOperationState(ctx *fasthttp.RequestCtx) {
	moduleID, _ := ctx.QueryArgs().GetUint("module_id")
	waitOpID, _ := ctx.QueryArgs().GetUint("module_id")

	mif := mifCache[moduleID]
	if mif == nil {
		moduleName := ModuleToString(Module(moduleID))
		mif = NewModuleInfoFile(moduleName, Reader)
		mifCache[moduleID] = mif
	}

	info := mif.GetInfo()
	res := int64(-1)
	if info.IsOk {
		if Module(moduleID) == fulltextIndexer || Module(moduleID) == scriptsMain {
			res = info.CommittedOpID
		} else {
			res = info.OpID
		}
	}
	log.Printf("get_operation_state(%d) info=[%v], wait_op_id=%d\n", moduleID, info, waitOpID)
	ctx.Write([]byte(strconv.FormatInt(res, 10)))
}
