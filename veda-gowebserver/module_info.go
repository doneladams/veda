package main

import (
	"encoding/hex"
	"fmt"
	"hash/crc32"
	"io/ioutil"
	"log"
	"os"
	"strconv"
	"strings"
)

type MInfo struct {
	Name          string
	OpID          int64
	CommittedOpID int64
	IsOk          bool
}

type OpenMode uint8
type Module uint8

const (
	Reader       OpenMode = 1
	Writer       OpenMode = 2
	ReaderWriter OpenMode = 3
)

const (
	ticketManager            Module = 0
	subjectManager           Module = 1
	aclPreparer              Module = 2
	xapianThreadContext      Module = 3
	fulltextIndexer          Module = 4
	statisticDataAccumulator Module = 5
	scriptsMain              Module = 6
	commiter                 Module = 7
	printStatistic           Module = 8
	fileReader               Module = 10
	zmqListener              Module = 11
	fanoutEmail              Module = 12
	fanoutSQL                Module = 13
	ltrScripts               Module = 14
	webserver                Module = 15
	nChannel                 Module = 16
	ccusChannel              Module = 17
	nop                      Module = 99
)

const (
	maxModuleInfoFileSize = 1024
)

func ModuleToString(module Module) string {
	switch module {
	case ticketManager:
		return "ticket_manager"
	case subjectManager:
		return "subject_manager"
	case aclPreparer:
		return "acl_preparer"
	case xapianThreadContext:
		return "xapian_thread_context"
	case fulltextIndexer:
		return "fulltext_indexer"
	case statisticDataAccumulator:
		return "statistic_data_accumulator"
	case scriptsMain:
		return "scripts_main"
	case commiter:
		return "commiter"
	case printStatistic:
		return "print_statistic"
	case fileReader:
		return "file_reader"
	case zmqListener:
		return "zmq_listener"
	case fanoutEmail:
		return "fanout_email"
	case fanoutSQL:
		return "fanout_sql"
	case ltrScripts:
		return "ltr_scripts"
	case webserver:
		return "webserver"
	case nChannel:
		return "n_channel"
	case ccusChannel:
		return "ccus_channel"
	case nop:
		return "nop"
	}

	return fmt.Sprintf("unknown %v", module)
}

type ModuleInfoFile struct {
	fnModuleInfo  string
	ffModuleInfoW *os.File
	ffModuleInfoR *os.File
	moduleName    string
	isWriterOpen  bool
	isReaderOpen  bool
	buff          []byte
	mode          OpenMode
	isReady       bool
	crc           [4]byte
	CRC32         uint32
}

var moduleInfoPath = "./data/module-info"

func NewModuleInfoFile(moduleName string, mode OpenMode) *ModuleInfoFile {
	mif := new(ModuleInfoFile)
	mif.moduleName = moduleName
	mif.fnModuleInfo = moduleInfoPath + "/" + moduleName + "_info"
	mif.mode = mode
	if mode == Writer || mode == ReaderWriter {
		_, err := os.Stat(mif.fnModuleInfo + ".lock")
		if err == nil {
			log.Printf("Veda not started: component [%s] already open, or not deleted lock file\n",
				mif.fnModuleInfo)
			return nil
		}
	}

	mif.isReady = true

	return mif
}

func IsLock(moduleName string) bool {
	_, err := os.Stat(moduleInfoPath + "/" + moduleName + "_info.lock")
	if err == nil {
		return true
	}

	return false
}

func (mif *ModuleInfoFile) IsReady() bool {
	return mif.isReady
}

func (mif *ModuleInfoFile) openWriter() bool {
	if mif.mode != Writer && mif.mode != ReaderWriter {
		return false
	}

	ioutil.WriteFile(mif.fnModuleInfo+".lock", []byte("0"), 0666)

	_, err := os.Stat(mif.fnModuleInfo)
	if os.IsNotExist(err) {
		mif.ffModuleInfoW, err = os.Create(mif.fnModuleInfo)
		if err != nil {
			log.Println("@ERR CREATING ffModuleInfoW: ", err)
			return false
		}
		mif.isWriterOpen = true

		return true
	} else if err == nil {
		mif.ffModuleInfoW, err = os.OpenFile(mif.fnModuleInfo, os.O_RDWR, 0666)
		if err != nil {
			log.Println("@ERR OPENING ffModuleInfoW: ", err)
			return false
		}
		return true
	}

	return false
}

func (mif *ModuleInfoFile) removeLock() {
	if mif.mode != Writer && mif.mode != ReaderWriter {
		return
	}

	err := os.Remove(mif.fnModuleInfo + ".lock")
	if err == nil {
		log.Printf("module_info:remove lock file %s\n", mif.fnModuleInfo+".lock")
	} else {
		log.Println("@ERR DELETING LOCK ", err)
	}
}

func (mif *ModuleInfoFile) close() {
	if mif.mode == Reader && mif.ffModuleInfoR != nil {
		mif.ffModuleInfoR.Close()
	}

	if mif.mode == Reader || mif.mode == ReaderWriter {
		if mif.ffModuleInfoW != nil {
			mif.ffModuleInfoW.Close()
		}
		mif.removeLock()
	}
}

func (mif *ModuleInfoFile) openReader() {
	var err error
	if mif.mode != Reader && mif.mode != ReaderWriter {
		return
	}

	mif.ffModuleInfoR, err = os.OpenFile(mif.fnModuleInfo, os.O_RDONLY, 0666)
	if err != nil {
		log.Println("@ERR OPENING ffModuleInfoR: ", err)
		return
	}

	mif.isReaderOpen = true
}

func (mif *ModuleInfoFile) PutInfo(opID int64, commitedOpID int64) bool {
	if !mif.isReady {
		return false
	}

	if !mif.isWriterOpen {
		mif.openWriter()
		if !mif.isReaderOpen {
			return false
		}
	}

	data := fmt.Sprint("%s;%d;%d;", mif.moduleName, opID, commitedOpID)
	hashStr := hex.EncodeToString(crc32.NewIEEE().Sum([]byte(data)))

	mif.ffModuleInfoW.Seek(0, 0)
	_, err := mif.ffModuleInfoW.Write([]byte(data))
	if err != nil {
		log.Println("@ERR WRITING DATA TO MODULE FILE INFO ", err)
		return false
	}
	_, err = mif.ffModuleInfoW.Write([]byte(hashStr + "\n"))
	if err != nil {
		log.Println("@ERR WRITING HASH TO MODULE FILE INFO ", err)
		return false
	}

	mif.ffModuleInfoW.Sync()
	return true
}

func (mif *ModuleInfoFile) GetInfo() MInfo {
	var res MInfo
	if !mif.isReaderOpen {
		mif.openReader()
		if !mif.isReaderOpen {
			return res
		}
	}

	res.IsOk = false

	mif.ffModuleInfoR.Seek(0, 0)

	// strBuf, err := ioutil.ReadAll(mif.ffModuleInfoR)
	if len(mif.buff) == 0 {
		mif.buff = make([]byte, maxModuleInfoFileSize)
	}
	_, err := mif.ffModuleInfoR.Read(mif.buff)
	if err != nil {
		log.Println("@ERR READING MODULE INFO FILE ", err)
	}

	str := string(mif.buff)

	if len(str) > 2 {
		if len(str) < 10 {
			return res
		}

		ch := strings.Split(str, ";")
		if len(ch) < 3 {
			return res
		}

		res.Name = ch[0]
		res.OpID, _ = strconv.ParseInt(ch[1], 10, 64)
		res.CommittedOpID, _ = strconv.ParseInt(ch[2], 10, 64)
		res.IsOk = true
	}

	return res
}
