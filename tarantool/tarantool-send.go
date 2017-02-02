package main

import (
	"cbor"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/tarantool/go-tarantool"
)

const (
	ACCESS_CAN_CREATE = 1 << 0
	ACCESS_CAN_READ   = 1 << 1
	ACCESS_CAN_UPDATE = 1 << 2
	ACCESS_CAN_DELETE = 1 << 3
)

type Right struct {
	Id        string
	Access    uint8
	IsDeleted bool
}

type RightSet struct {
	data map[string]*Right
}

var client *tarantool.Connection

func newRightPointer(Id string, Access uint8, IsDeleted bool) *Right {
	right := new(Right)
	right.Id = Id
	right.Access = Access
	right.IsDeleted = IsDeleted

	return right
}

func peekFromTarantool(inKey string) []interface{} {

	schema := client.Schema
	space := schema.Spaces["subjects"]
	if space == nil {
		log.Fatalf("no such space")
	}
	spaceId := space.Id
	index := space.Indexes["primary"]
	if index == nil {
		log.Fatalf("No such index")
	}
	indexId := index.Id

	resp, err := client.Select(spaceId, indexId, 0, 1, tarantool.IterEq, []interface{}{inKey})
	if err != nil || resp.Code != 0 {
		log.Fatalf("Error on select: ", err)
	}

	if len(resp.Data) == 0 {
		return nil
	}

	tuple := resp.Data[0].([]interface{})
	//fmt.Println(tuple)
	return tuple
}

func rightsFromTarantool(tuple []interface{}, newRightSet *RightSet) {
	for i := 1; i < len(tuple) && tuple[i] != nil; i++ {
		rightsInterface := tuple[i].([]interface{})
		uri := rightsInterface[0].(string)
		access := uint8(0)
		canCreate := rightsInterface[1].(bool)
		canRead := rightsInterface[2].(bool)
		canUpdate := rightsInterface[3].(bool)
		canDelete := rightsInterface[4].(bool)

		if canCreate {
			access |= ACCESS_CAN_CREATE
		}

		if canRead {
			access |= ACCESS_CAN_READ
		}

		if canUpdate {
			access |= ACCESS_CAN_UPDATE
		}

		if canDelete {
			access |= ACCESS_CAN_DELETE
		}

		newRightSet.data[uri] = new(Right)
		newRightSet.data[uri].Access = access
		newRightSet.data[uri].Id = uri
	}
}

func pushRightSetToTarantool(prefix string, inKey string, newRights RightSet, mustReplace bool) {
	var resp *tarantool.Response
	var err error

	space := client.Schema.Spaces["subjects"]
	if space == nil {
		log.Fatalf("no such space")
	}
	spaceId := space.Id

	tuple := make([]interface{}, len(newRights.data)+1)
	i := 0
	tuple[i] = inKey
	i++

	for _, right := range newRights.data {
		if !right.IsDeleted {
			rightSlice := make([]interface{}, 5)
			rightSlice[0] = right.Id
			rightSlice[1] = (right.Access & ACCESS_CAN_CREATE) > 0
			rightSlice[2] = (right.Access & ACCESS_CAN_READ) > 0
			rightSlice[3] = (right.Access & ACCESS_CAN_UPDATE) > 0
			rightSlice[4] = (right.Access & ACCESS_CAN_DELETE) > 0
			tuple[i] = rightSlice
			i++
		}
	}

	realElemsLast := 0
	for i := 0; i < len(tuple); i++ {
		if tuple[i] == nil {
			break
		}
		realElemsLast++
	}

	if inKey == "Mcfg:ClientSettings" {
		fmt.Println(tuple)
	}

	/*	fmt.Println(spaceId)
		fmt.Println(mustReplace)
		fmt.Println(tuple[1] == nil)*/
	if !mustReplace {
		if tuple[1] != nil {
			resp, err = client.Insert(spaceId, tuple[0:realElemsLast])
			//	fmt.Println("Inserting done")
		}
	} else {
		if tuple[1] != nil {
			resp, err = client.Replace(spaceId, tuple[0:realElemsLast])
			//	fmt.Println("Replacing done")
		} else {
			if space.Indexes["primary"] == nil {
				log.Fatalf("no such index")
			}
			indexId := space.Indexes["primary"].Id
			//	fmt.Println(tuple)
			resp, err = client.Delete(spaceId, indexId, []interface{}{tuple[0]})
			//			fmt.Println("Deleting done")
		}
	}

	if err != nil {
		panic(err)
	}

	if resp != nil && resp.Code != 0 {
		log.Fatalf("Error on inserting")
	}
}

//  queue_reader - routine that read queue, and transmits information about the update to collector_updateInfo routine
func prepareRightSet(individ *Individual, defaultAccess uint8, resource []Resource,
	inSet []Resource, prefix string) {
	var isDeleted bool
	var access uint8

	isDeleted = false
	if individ.getFirstResource("v-s:deleted").data != nil &&
		individ.getFirstResource("v-s:deleted").data.(bool) == true {
		isDeleted = true
	}
	//fmt.Println(isDeleted)
	//fmt.Println(access)

	if individ.getFirstResource("v-s:canCreate").data != nil {
		if individ.getFirstResource("v-s:canCreate").data.(bool) == true {
			access |= ACCESS_CAN_CREATE
		}
	}

	if individ.getFirstResource("v-s:canRead").data != nil {
		if individ.getFirstResource("v-s:canRead").data.(bool) == true {
			access |= ACCESS_CAN_READ
		}
	}

	if individ.getFirstResource("v-s:canUpdate").data != nil {
		if individ.getFirstResource("v-s:canUpdate").data.(bool) == true {
			access |= ACCESS_CAN_UPDATE
		}
	}

	if individ.getFirstResource("v-s:canDelete").data != nil {
		if individ.getFirstResource("v-s:canDelete").data.(bool) == true {
			access |= ACCESS_CAN_DELETE
		}
	}
	//	fmt.Println(access)

	if access == 0 {
		access = defaultAccess
	}
	for _, resourceData := range resource {
		var newRightSet RightSet
		// var prevRightSet RightSet
		//	var deltaRightSet RightSet

		//prevRightSet.data = make(map[string]*Right)
		newRightSet.data = make(map[string]*Right)
		//	deltaRightSet.data = make(map[string]*Right)

		resourceUri := fmt.Sprintf("%v", resourceData.data.(string))
		key := prefix + resourceUri
		mustReplace := false
		tuple := peekFromTarantool(key)
		//fmt.Println(tuple)
		if tuple != nil {
			mustReplace = true
			// rightsFromTarantool(tuple, &prevRightSet)
			rightsFromTarantool(tuple, &newRightSet)
		}

		for _, inSetData := range inSet {
			inSetUri := fmt.Sprintf("%v", inSetData.data.(string))
			rr := newRightSet.data[inSetUri]
			//fmt.Println(rr)
			if rr != nil {
				rr.IsDeleted = isDeleted
				rr.Access |= access
				newRightSet.data[inSetUri] = rr
			} else {
				newRightSet.data[inSetUri] = newRightPointer(inSetUri, access,
					isDeleted)

			}

			/*			if inSetUri == "cfg:ClientSettings" || resourceUri == "cfg:ClientSettings" {
						fmt.Println(individ)
						fmt.Println(newRightSet)
					}*/

			//	newRightSet.data[inSetUri] = newRightPointer(inSetUri, access, isDeleted)
		}

		if resourceUri == "cfg:ClientSettings" {
			fmt.Println(prefix)
			fmt.Println(individ)
			fmt.Println(newRightSet)
		}

		// fmt.Println(len(newRightSet.data))
		// fmt.Println(len(deltaRightSet.data))

		pushRightSetToTarantool(prefix, key, newRightSet, mustReplace)
		// pushRightSetToTarantool(prefix, key, deltaRightSet, mustReplace)
	}
}

func queue_reader() {
	var err error
	main_queue_name := "individuals-flow"
	var main_queue *Queue
	var main_cs *Consumer

	server := "127.0.0.1:3308"
	opts := tarantool.Opts{
		Timeout:       5000 * time.Millisecond,
		Reconnect:     1 * time.Second,
		MaxReconnects: 3,
	}

	client, err = tarantool.Connect(server, opts)
	if err != nil {
		panic(err)
	}

	main_queue = NewQueue(main_queue_name, R)
	main_queue.open(CURRENT)

	main_cs = NewConsumer(main_queue, "CCUS")
	main_cs.open()

	data := ""
	main_queue.reopen_reader()
	count := 0
	for true {
		data = main_cs.pop()
		if data == "" {
			break
		}
		//			log.Printf("@1 data=[%s].length=%d", data, len (data))
		ring := cbor.NewDecoder(strings.NewReader(data))
		var cborObject interface{}
		err := ring.Decode(&cborObject)
		if err != nil {
			log.Fatalf("error decoding cbor: %v", err)
			continue
		}

		var individual *Individual = NewIndividual()

		cbor2individual(individual, cborObject)

		newStateText := individual.getFirstResource("new_state")

		//	fmt.Println("------------\n", newStateText, "\n-------------------------")
		reader := strings.NewReader(newStateText.data.(string))
		if reader == nil {
			continue
		}
		ring = cbor.NewDecoder(reader)
		err = ring.Decode(&cborObject)
		if err != nil {
			log.Fatalf("error decoding cbor: %v", err)
			continue
		}
		var individualNewState *Individual = NewIndividual()
		cbor2individual(individualNewState, cborObject)
		//	fmt.Println(individual)
		/*if individualNewState.getFirstResource("v-s:permissionObject").data != nil &&
			individualNewState.getFirstResource("v-s:permissionObject").
				data.(string) == "cfg:AllUsersGroup" {
			fmt.Println(individualNewState)
		}*/
		if individualNewState.getFirstResource("rdf:type").data != nil {
			if individualNewState.getFirstResource("rdf:type").data.(string) ==
				"v-s:PermissionStatement" {
				resourceData := individualNewState.getResources("v-s:permissionObject")
				inSetData := individualNewState.getResources("v-s:permissionSubject")
				// fmt.Println(resourceData)
				// fmt.Println(inSetData)
				prepareRightSet(individualNewState, 15, resourceData, inSetData, "P")
				count++
			}
		}

		if individualNewState.getFirstResource("rdf:type").data != nil {
			if individualNewState.getFirstResource("rdf:type").data.(string) ==
				"v-s:Membership" {
				resourceData := individualNewState.getResources("v-s:resource")
				inSetData := individualNewState.getResources("v-s:memberOf")
				// fmt.Println(resourceData)
				// fmt.Println(inSetData)
				// resourceData := individualNewState.getFirstResource(
				// "v-s:resource").data.(string)
				// inSetData := individualNewState.getFirstResource(
				// "v-s:memberOf").data.(string)
				prepareRightSet(individualNewState, 15, resourceData, inSetData, "M")
				count++
			}
		}

		//fmt.Println(count)

		main_cs.commit_and_next(false)
		//	break
	}

	// client.Close()
}

func main() {
	fmt.Println("here\n")
	queue_reader()
}
