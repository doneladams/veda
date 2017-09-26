/**
 * define
 */
module define;

const string   attachments_db_path = "./data/files";
const string   docs_onto_path      = "./public/docs/onto";
const string   dbs_backup          = "./backup";
const string   dbs_data            = "./data";
const string   individuals_db_path = "./data/lmdb-individuals";
const string   tickets_db_path     = "./data/lmdb-tickets";
const string   acl_indexes_db_path = "./data/acl-indexes";
const string   uris_db_path        = "./data/uris";
const string   tmp_path            = "./data/tmp";
const string   queue_db_path       = "./data/queue";
const string   onto_path           = "./ontology";
const string   xapian_info_path    = "./data/xapian-info";
const string   module_info_path    = "./data/module-info";
const string   trails_path         = "./data/trails";
const string   logs_path           = "./logs";

const string   main_queue_name 	     = "individuals-flow";
const string   ft_indexer_queue_name = "fulltext_indexer0";

const string[] paths_list          =
[
    tmp_path, logs_path, attachments_db_path, docs_onto_path, dbs_backup, dbs_data, individuals_db_path, uris_db_path, tickets_db_path,
    acl_indexes_db_path, queue_db_path,
    xapian_info_path, module_info_path, trails_path
];

