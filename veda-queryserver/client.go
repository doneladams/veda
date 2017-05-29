package main

import (
	"fmt"
	"log"
	"net"
	"sync"
)

func callSocket(i int, wg *sync.WaitGroup) {
	// var socket *nanomsg.Socket
	socket, err := net.Dial("tcp", "127.0.0.1:11112")
	if err != nil {
		fmt.Println("@ERR ON CREATING SOCKET ", err, i)
		wg.Done()
		return
	}

	request := fmt.Sprintf("THREAD %v", i)
	requestSize := uint32(len(request))
	buf := make([]byte, 4)
	buf[0] = byte((requestSize >> 24) & 0xFF)
	buf[1] = byte((requestSize >> 16) & 0xFF)
	buf[2] = byte((requestSize >> 8) & 0xFF)
	buf[3] = byte(requestSize & 0xFF)

	_, err = socket.Write(buf)
	if err != nil {
		log.Println("@WRITE SIZE ", err)
	}

	_, err = socket.Write([]byte(request))
	if err != nil {
		log.Println("@WRITE REQUEST ", err)
	}

	socket.Read(buf)

	responseSize := uint32(0)
	for i := 0; i < 4; i++ {
		responseSize = (responseSize << 8) + uint32(buf[i])
	}

	response := make([]byte, responseSize)
	socket.Read(response)
	if err != nil {
		log.Println("@READ", err)
	}

	fmt.Printf("THREAD %v RESPONSE %v \n", i, string(response))
	wg.Done()
}

func main() {
	var maxThreads = 500

	wg := new(sync.WaitGroup)
	for i := 0; i < maxThreads; i++ {
		wg.Add(1)
		go callSocket(i, wg)
	}

	log.Println("@WAIT")
	wg.Wait()

	log.Println("@END MAIN")
}
