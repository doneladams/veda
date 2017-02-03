#include <errno.h>
#include <strings.h>
#include <tarantool/module.h>
#include <unistd.h>

#define MP_SOURCE 1

#include "msgpuck.h"

#define MAX_URI_LEN 		1024

#define MEMBERSHIP_PREFIX 	'M'
#define PERMISSION_PREFIX 	'P'

#define ACCESS_CAN_CREATE 	(1U << 0)
#define ACCESS_CAN_READ 	(1U << 1)
#define ACCESS_CAN_UPDATE 	(1U << 2)
#define ACCESS_CAN_DELETE 	(1U << 3)
#define DEFAULT_ACCESS		15U
#define ACCESS_NUMBER		4

#define MAX_RIGHTS 	50
#define MAX_BUF_SIZE	1024
#define MAX_BUF_SIZE2	(8388608*2)

struct Right {
	char id[MAX_URI_LEN];
	const char *buf;
	char buf_start[MAX_BUF_SIZE];
	int32_t id_len;	
	int32_t i, nelems, parent, nchildren;
	uint8_t access;
};

uint32_t main_space_id, main_index_id, cache_space_id, cache_index_id;

uint32_t access_arr[] = { ACCESS_CAN_CREATE, ACCESS_CAN_READ, ACCESS_CAN_UPDATE, 
	ACCESS_CAN_DELETE };

int
get_tuple(char *key_start, char *key_end, char *outbuf)
{
	size_t tuple_size;
	box_tuple_t *result;

	if (box_index_count(cache_space_id, cache_index_id, ITER_EQ, key_start, key_end) > 0) {
		box_index_get(cache_space_id, cache_index_id, key_start, key_end, &result);
		tuple_size = box_tuple_bsize(result);	
		box_tuple_to_buf(result, outbuf, tuple_size);
		return 1;
	} else if (box_index_count(main_space_id, main_index_id, ITER_EQ, key_start, key_end) > 0) {
		box_index_get(main_space_id, main_index_id, key_start, key_end, &result);
		tuple_size = box_tuple_bsize(result);	
		box_tuple_to_buf(result, outbuf, tuple_size);
	//	printf("here");
		box_insert(cache_space_id, outbuf, outbuf + tuple_size, NULL);
		return 1;
	}
	return 0;
}

int
rights_comparator(const void *ptr1, const void *ptr2)
{
	struct Right *r1, *r2;

	r1 = (struct Right *)ptr1;
	r2 = (struct Right *)ptr2;

	// printf("%s %s %d\n", r1->id, r2->id, strcmp(r1->id, r2->id));

	if (strcmp(r1->id, r2->id) > 0)
		return 1;
	else if (strcmp(r1->id, r2->id) < 0)
		return -1;
	else 
		return 0;
}

//think about return value
int
get_groups(const char *uri, uint8_t access, struct Right rights[MAX_RIGHTS])
{
	char key_start[MAX_URI_LEN], *key_end;
	int32_t rights_count = 0, curr = 0;
	int gone_previous = 0;


	rights[curr].parent = -1;
	rights[curr].access =  access;
	rights[curr].buf = rights[curr].buf_start;
	rights[curr].nchildren = 0;
	rights[curr].id_len =  strlen(uri);
	
	key_end = key_start;
	key_end = mp_encode_array(key_end, 1);
	key_end = mp_encode_str(key_end, uri, rights[curr].id_len);
	if (get_tuple(key_start, key_end, (char *)rights[curr].buf) == 0) {
		memcpy(rights[curr].id, uri, rights[curr].id_len);
		rights[curr].id[rights[curr].id_len]  = '\0';
		return 1;
	}
	//return 0;
	rights_count = 1;
	// printf("field count %u\n", box_tuple_field_count(result));

	while (curr != -1) {
		int got_next = 0;
		int i;
		uint32_t len;
		const char *tmp;
		if (!gone_previous) {
			// printf("---------------\nbuf\n%s\n-----------------\n", rights[curr].buf);
			rights[curr].nelems = mp_decode_array(&rights[curr].buf);
			// printf("curr nelems %d\n", rights[curr].nelems);
			tmp = mp_decode_str(&rights[curr].buf, &len);
			memcpy(rights[curr].id, tmp, len);
			rights[curr].id[len] = '\0';
			rights[curr].id_len = len;
			// printf("%d %s\n", curr, rights[curr].id);
			rights[curr].i = 0;
		}

		gone_previous = 0;
		
		for (; rights[curr].i < rights[curr].nelems - 1; rights[curr].i++) {
			int32_t next;
			uint8_t right_access;

			next = rights_count++;
			tmp = mp_decode_str(&rights[curr].buf, &len);
			memcpy(rights[next].id + 1, tmp, len);
			rights[next].id[0] = MEMBERSHIP_PREFIX;
			right_access = rights[next].id[len	] - 1;
			// printf("\tnext uri %s len=%d\n", rights[next].id, len);
			rights[next].access = rights[curr].access & right_access;
			rights[next].id[len] = '\0';
			rights[next].id_len = len;
			// printf("\tnext uri %s\n", rights[next].id);
			/*printf("\tcurr=%u next=%u right_access=%u\n", rights[curr].access, 
				rights[next].access, right_access);*/

			for (i = 0; i < rights_count - 1; i++) {
				//  printf("\tvisit check: %s %s\n", rights[i].id, rights[next].id);
				if (strcmp(rights[i].id, rights[next].id) == 0) {
					rights_count--;
					break;	
				}
			}
			if (i < rights_count - 1) {
				// printf("\twas visited, skip\n");
				continue;
			}

			rights[next].parent = curr;
		
			// printf("\tnew uri %s\n", rights[next].id);
			key_end = key_start;
			key_end = mp_encode_array(key_end, 1);
			key_end = mp_encode_str(key_end, rights[next].id, rights[next].id_len);
			rights[next].buf = rights[next].buf_start;
			if (get_tuple(key_start, key_end, (char *)rights[next].buf) == 0)
				continue;
		
			rights[curr].i++;
			curr = next;
			got_next = 1;
			break;
		}
		if (!got_next) {
			curr = rights[curr].parent;
			gone_previous = 1;
			/*printf("\t go previous\n");
			if (curr != -1) {
				printf("\t prev uri %s number %d\n", rights[curr].id, curr);
				printf("buf %s\n", rights[curr].buf);
			}*/	
		}
	}

	return rights_count;
}

int
subject_search(struct Right subject_rights[MAX_RIGHTS], int32_t subject_rights_count, char *id)
{
	int i;

	for (i = 0; i < subject_rights_count; i++)
		if (strcmp(id, subject_rights[i].id) == 0)
			return i;

	return -1;
}

int
get_rights(struct Right object_rights[MAX_RIGHTS], int32_t object_rights_count,
	struct Right subject_rights[MAX_RIGHTS], int32_t subject_rights_count, uint8_t desired_access)
{
	int i, j, nperms;
	uint8_t result_access = 0;
	char perm_buf_start[MAX_BUF_SIZE2];
	char key_start[MAX_URI_LEN], *key_end;

	for (i = 0; i < object_rights_count; i++) {	
		const char *perm_buf;
		uint32_t len;
		uint8_t object_access;

		object_access = object_rights[i].access;
		object_rights[i].id[0] = PERMISSION_PREFIX;
		key_end = key_start;
		key_end = mp_encode_array(key_end, 1);
		key_end = mp_encode_str(key_end, object_rights[i].id, object_rights[i].id_len);
		// printf("%s %d\n", object_rights[i].id, object_rights[i].access);	
		// printf("key %s\n", key_start);
		perm_buf = perm_buf_start;
		if (get_tuple(key_start, key_end, (char *)perm_buf) == 0) {
			continue;
		}

		nperms = mp_decode_array(&perm_buf);
		nperms--;
		// printf("nperms=%d\n", nperms);
		mp_decode_str(&perm_buf, &len);
		// printf("len=%u\n", len);
			
		// printf("%s\n", perm_buf);	
	//	printf("%s\n", perm_buf);		
		for (j = 0; j < nperms; j++) {	
			char perm_obj_uri[MAX_URI_LEN];
			const char *tmp;
			int idx, k;
			uint8_t perm_access;

			tmp = mp_decode_str(&perm_buf, &len);
			memcpy(perm_obj_uri + 1, tmp, len);
			perm_obj_uri[0] = MEMBERSHIP_PREFIX;
			perm_access = (perm_obj_uri[len] - 1);
			perm_obj_uri[len] = '\0';
			// printf("\t%s\n", perm_obj_uri);
			// printf("\t%s %d\n", perm_obj_uri, perm_access);
		//	printf("%d\n", perm_access);
			
			idx = subject_search(subject_rights, subject_rights_count, perm_obj_uri);

			//printf("idx=%d\n", idx);
			if (idx >= 0) {
				// printf("\t+%s\n", perm_obj_uri);
				// printf("\t%d\n", perm_access);
				for (k = 0; k < ACCESS_NUMBER; k++) {
					if ((desired_access & access_arr[k] & object_access) > 0) {
						uint8_t set_bit;

						set_bit = access_arr[k] & perm_access;
						if (set_bit > 0)
							result_access |= set_bit;
					}
				}
			}			
		}
	}

	return result_access;
}


int
authorize(lua_State *L)
{
	/*const char *subject, *object;
    subject = lua_tostring(L, -2);
    object = lua_tostring(L, -1);
	printf("%s %s\n", subject, object);*/

	int i;
	struct Right object_rights[MAX_RIGHTS], subject_rights[MAX_RIGHTS];
	int32_t object_rights_count, subject_rights_count;
	int result;
	const char *subject, *object;

    subject = lua_tostring(L, -2);
    object = lua_tostring(L, -1);

//	printf("%s %s\n", subject, object);

	if ((main_space_id = box_space_id_by_name("subjects", strlen("subjects"))) == BOX_ID_NIL) {
		fprintf(stderr, "No such space");
		return 0;
	}

	main_index_id = box_index_id_by_name(main_space_id, "primary", strlen("primary"));

	if ((cache_space_id = box_space_id_by_name("cache", strlen("cache"))) == BOX_ID_NIL) {
		fprintf(stderr, "No such space");
		return 0;
	}

	cache_index_id = box_index_id_by_name(cache_space_id, "primary", strlen("primary"));

	
//	printf("index id %u\n", index_id);

	subject_rights_count = get_groups(subject, DEFAULT_ACCESS, subject_rights);
	object_rights_count = get_groups(object, DEFAULT_ACCESS, object_rights);

	memcpy(object_rights[object_rights_count].id, "Mv-s:AllResourcesGroup", 22);
	object_rights[object_rights_count].id[22] = '\0';
	object_rights[object_rights_count].id_len = 22;
	object_rights[object_rights_count++].access = DEFAULT_ACCESS;

	//printf("subject_rights_count=%d\n", subject_rights_count);
	//printf("object_rights_count=%d\n\n", object_rights_count);

	if (subject_rights_count == 0) {
	//	printf("No such user %s\n", subject);
		lua_pushnumber(L, 0);
		return 1;
	}

	if (object_rights_count == 0) {
	//	printf("No such object\n");
		lua_pushnumber(L, 0);
		return 1;
	}

/*		printf("\n\n\nURI MEMBERSHIPS\n");
		for (i = 0; i < object_rights_count; i++)
			printf("\t%s %d\n", object_rights[i].id, object_rights[i].access);
		printf("USER MEMBERSHIPS\n");
		for (i = 0; i < subject_rights_count; i++)
			printf("\t%s %d\n", subject_rights[i].id, subject_rights[i].access);
		printf("\n\n");*/

//	lua_pushnumber(L, 1);
//	return 1;

	

	result = get_rights(object_rights, object_rights_count, subject_rights, subject_rights_count, 
		DEFAULT_ACCESS);
//	printf("result=%d\n", result);

	lua_pushnumber(L, result);	

	return 1;
}

int 
luaopen_authorize(lua_State *L)
{
	lua_register(L, "authorize", authorize);  
	return 0;
}