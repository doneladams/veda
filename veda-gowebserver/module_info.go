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

const (
	Reader       OpenMode = 1
	Writer       OpenMode = 2
	ReaderWriter OpenMode = 3
)

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
	if mode == Reader || mode == ReaderWriter {
		_, err := os.Stat(mif.fnModuleInfo + ".lock")
		if os.IsNotExist(err) {
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
	if os.IsNotExist(err) {
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
	if mif.mode != Reader || mif.mode != ReaderWriter {
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

	strBuf, err := ioutil.ReadAll(mif.ffModuleInfoR)
	if err != nil {
		log.Println("@ERR READING MODULE INFO FILE ", err)
	}

	str := string(strBuf)

	if len(str) > 2 {
		if len(str) < 10 {
			return res
		}

		ch := strings.Split(strings.Trim(str, "\n"), ";")
		if len(ch) != 4 {
			return res
		}

		res.Name = ch[0]
		res.OpID, _ = strconv.ParseInt(ch[1], 10, 64)
		res.CommittedOpID, _ = strconv.ParseInt(ch[2], 10, 64)
		res.IsOk = true
	}

	return res
}
