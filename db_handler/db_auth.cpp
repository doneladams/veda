#include <errno.h>
#include <strings.h>
#include <tarantool/module.h>

#define MP_SOURCE 1

#include "db_globals.h"
#include "msgpuck.h"

#define MAX_URI_LEN 		4096

#define MEMBERSHIP_PREFIX 	'M'
#define PERMISSION_PREFIX 	'P'

#define ACCESS_CAN_CREATE 		(1U << 0)
#define ACCESS_CAN_READ 		(1U << 1)
#define ACCESS_CAN_UPDATE 		(1U << 2)
#define ACCESS_CAN_DELETE	 	(1U << 3)
#define ACCESS_CAN_NOT_CREATE 	(1U << 4)
#define ACCESS_CAN_NOT_READ		(1U << 5)
#define ACCESS_CAN_NOT_UPDATE 	(1U << 6)
#define ACCESS_CAN_NOT_DELETE 	(1U << 7)


#define DEFAULT_ACCESS		15U
#define ACCESS_NUMBER		8

#define MAX_RIGHTS		100
#define MAX_BUF_SIZE	65536

#define LISTEN_MAX		10000
#define IDS_DELIM		';'
#define MAX_IDS			2048

struct Right {
	char id[MAX_URI_LEN];
	const char *buf;
	char buf_start[MAX_BUF_SIZE];
	int32_t id_len;	
	int32_t i, nelems, parent, nchildren;
	uint8_t access;
};

int cache_size = 0;

int socket_fd, client_socket_fd;
uint8_t access_arr[] = { ACCESS_CAN_CREATE, ACCESS_CAN_READ, ACCESS_CAN_UPDATE, 
	ACCESS_CAN_DELETE };

int
get_tuple(const char *key, int32_t key_len, char *outbuf)
{
	char key_start[MAX_URI_LEN], *key_end;
	size_t tuple_size = 0;
	box_tuple_t *result;

	key_end = key_start;
	key_end = mp_encode_array(key_end, 1);
	key_end = mp_encode_str(key_end, key, key_len);
	box_index_get(cache_space_id, cache_index_id, key_start, key_end, &result);

	if (result != NULL) {
		if (box_tuple_field_count(result) == 1)
			return 0;
		tuple_size = box_tuple_bsize(result);	
		// fprintf(stderr, "tuple_size=%zu\n", tuple_size);	
		box_tuple_to_buf(result, outbuf, tuple_size);
		return 1;
	} else {
		box_index_get(acl_space_id, acl_index_id, key_start, key_end, &result);
		if (result == NULL) {
			key_end = key_start;
			key_end = mp_encode_array(key_end, 1);
			key_end = mp_encode_str(key_end, key, key_len);
			box_insert(cache_space_id, key_start, key_end, NULL);
			return 0;
		}
		tuple_size = box_tuple_bsize(result);	
		// fprintf(stderr, "tuple_size=%zu\n", tuple_size);	
		box_tuple_to_buf(result, outbuf, tuple_size);
		box_insert(cache_space_id, outbuf, outbuf + tuple_size, NULL);
		return 1;
	}
	return 0;
}

//think about return value
int
get_groups(const char *uri, uint8_t access, struct Right rights[MAX_RIGHTS])
{
	// char key_start[MAX_URI_LEN], *key_end;
	int32_t rights_count = 0, curr = 0;
	int gone_previous = 0;

	rights[curr].parent = -1;
	rights[curr].access =  access;
	rights[curr].buf = rights[curr].buf_start;
	rights[curr].nchildren = 0;
	rights[curr].id_len =  strlen(uri);
	
	// fprintf(stderr, "REQUEST URI %s\n", uri);
	if (get_tuple(uri, rights[curr].id_len, (char *)rights[curr].buf) == 0) {
		memcpy(rights[curr].id, uri, rights[curr].id_len);
		rights[curr].id[rights[curr].id_len]  = '\0';
		return 1;
		
	}
	rights_count = 1;

	while (curr != -1) {
		int got_next = 0;
		int i;
		uint32_t len;
		const char *tmp;
		if (!gone_previous) {
			// fprintf (stderr, "---------------\nbuf\n%s\n-----------------\n", rights[curr].buf);
			rights[curr].nelems = mp_decode_array(&rights[curr].buf);
			// fprintf (stderr, "curr nelems %d\n", rights[curr].nelems);
			// fprintf(stderr, "\ttry decode key\n");
			tmp = mp_decode_str(&rights[curr].buf, &len);
			memcpy(rights[curr].id, tmp, len);
			rights[curr].id[len] = '\0';
			rights[curr].id_len = len;
			// fprintf (stderr, "%d %s\n", curr, rights[curr].id);
			rights[curr].i = 0;
		}

		gone_previous = 0;
		
		for (; rights[curr].i < rights[curr].nelems - 1; rights[curr].i += 2) {
			int32_t next;
			uint8_t right_access;

			if (rights_count == MAX_RIGHTS) {
				fprintf(stderr, "@RIGHTS MAX LIMIT REACHED\n");
				return -1;
			}
			next = rights_count++;
			// fprintf(stderr, "\ti=%d nelems=%d\n", rights[curr].i, rights[curr].nelems - 1);
			// fprintf(stderr, "\ttry decode new node\n");
			tmp = mp_decode_str(&rights[curr].buf, &len);
			memcpy(rights[next].id + 1, tmp, len);
			rights[next].id[0] = MEMBERSHIP_PREFIX;
			right_access = mp_decode_uint(&rights[curr].buf);
			// fprintf (stderr, "\tnext uri %s len=%d\n", rights[next].id, len);
			rights[next].access = rights[curr].access & right_access;
			rights[next].id[len + 1] = '\0';
			rights[next].id_len = len + 1;
			/*fprintf (stderr, "\tnext uri %s\n", rights[next].id);
			fprintf (stderr, "\tcurr=%u next=%u right_access=%u\n", rights[curr].access, 
				rights[next].access, right_access);*/
			for (i = 0; i < rights_count - 1; i++)
				if (strcmp(rights[i].id, rights[next].id) == 0)
					break;	

			if (i < rights_count - 1) {
				rights_count--;
				continue;
			}

			rights[next].parent = curr;

			// fprintf (stderr, "\tnew uri %s\n", rights[next].id);
			rights[next].buf = rights[next].buf_start;
			// fprintf(stderr, "REQUEST URI %s\n", rights[next].id);
			if (get_tuple(rights[next].id, rights[next].id_len, (char *)rights[next].buf) == 0)
				continue;
			
			rights[curr].i += 2;
			curr = next;
			got_next = 1;
			break;
		}
		if (!got_next) {
			curr = rights[curr].parent;
			gone_previous = 1;
			/*fprintf (stderr, "\t go previous\n");
			if (curr != -1) {
				fprintf (stderr, "\t prev uri %s number %d\n", rights[curr].id, curr);
				fprintf (stderr, "buf %s\n", rights[curr].buf);
			}	*/
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

uint8_t
get_rights(struct Right object_rights[MAX_RIGHTS], int32_t object_rights_count,
	struct Right subject_rights[MAX_RIGHTS], int32_t subject_rights_count, uint8_t desired_access)
{
	int i, j, nperms;
	uint8_t result_access = 0;
	char perm_buf_start[MAX_BUF_SIZE];
	// char key_start[MAX_URI_LEN], *key_end;

	for (i = 0; i < object_rights_count; i++) {
		const char *perm_buf;
		uint32_t len;
		uint8_t object_access;

		object_access = object_rights[i].access;
		object_rights[i].id[0] = PERMISSION_PREFIX;
		perm_buf = perm_buf_start;
		// fprintf(stderr, "%s\n", object_rights[i].id);
		if (get_tuple(object_rights[i].id, object_rights[i].id_len, (char *)perm_buf) == 0) 
			continue;
		
		// fprintf(stderr, "\tfound in base\n");

		nperms = mp_decode_array(&perm_buf);
		nperms--;
		mp_decode_str(&perm_buf, &len);
		for (j = 0; j < nperms; j += 2) {	
			char perm_obj_uri[MAX_URI_LEN];
			const char *tmp;
			int idx, k;
			uint8_t perm_access;

			tmp = mp_decode_str(&perm_buf, &len);
			memcpy(perm_obj_uri + 1, tmp, len);
			perm_obj_uri[0] = MEMBERSHIP_PREFIX;
			perm_access = mp_decode_uint(&perm_buf);
			perm_access = (((perm_access & 0xF0) >> 4) ^ 0x0F) & perm_access;
			perm_obj_uri[len + 1] = '\0';
			// fprintf (stderr, "\t%s %d %d\n", perm_obj_uri, perm_access, object_access);
			
			idx = subject_search(subject_rights, subject_rights_count, perm_obj_uri);

			if (idx >= 0) {
				// fprintf (stderr, "\t\t+%s\n", perm_obj_uri);
				for (k = 0; k < ACCESS_NUMBER; k++) {
					if ((desired_access & access_arr[k] & object_access) > 0) {
						uint8_t set_bit;
						
						set_bit = access_arr[k] & perm_access;
						if (set_bit > 0) {
							result_access |= set_bit;
							// fprintf (stderr, "\t\t\tadd access=%d\n", access_arr[k]);
						}
					}
				}
			}
		}
	}

	return result_access;
}

int
db_auth(const char *user_id, size_t user_id_len, const char *res_uri, size_t res_uri_len)
{
	struct Right object_rights[MAX_RIGHTS], subject_rights[MAX_RIGHTS], extra_membership;
	int32_t object_rights_count, subject_rights_count;
    char subject[MAX_URI_LEN], object[MAX_URI_LEN];
	uint8_t auth_result;
	

	memcpy(extra_membership.id, "Mv-s:AllResourcesGroup", 22);
	extra_membership.id[22] = '\0';
	extra_membership.id_len = 22;
	extra_membership.access = DEFAULT_ACCESS;
	
    subject[0] = MEMBERSHIP_PREFIX;
    memcpy(subject + 1, user_id, user_id_len);
    subject[user_id_len + 1] = '\0';

    object[0] = MEMBERSHIP_PREFIX;
    memcpy(object + 1, res_uri, res_uri_len);
    object[res_uri_len + 1] = '\0';

    // fprintf (stderr, "%s %s\n", subject, object);

	subject_rights_count = get_groups(subject, DEFAULT_ACCESS, subject_rights);
	object_rights_count = get_groups(object, DEFAULT_ACCESS, object_rights);
	if (object_rights_count < 0 || subject_rights_count < 0)
		return -1;

	if (object_rights_count == MAX_RIGHTS) {
		fprintf(stderr, "@RIGHTS MAX LIMIT REACHED\n");
		return -1;
	}
	object_rights[object_rights_count++] = extra_membership;

	/*fprintf (stderr, "\n\n\nURI MEMBERSHIPS\n");
	for (int i = 0; i < object_rights_count; i++)
		fprintf (stderr, "\t%s %d\n", object_rights[i].id, object_rights[i].access);
	fprintf (stderr, "USER MEMBERSHIPS\n");
	for (int i = 0; i < subject_rights_count; i++)
		fprintf (stderr, "\t%s %d\n", subject_rights[i].id, subject_rights[i].access);
	fprintf (stderr, "\n\n");*/

	auth_result = get_rights(object_rights, object_rights_count, subject_rights, subject_rights_count, 
		DEFAULT_ACCESS);
	return auth_result;

}