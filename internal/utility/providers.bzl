FsInfo = provider(
    doc = "",
    fields = {
        "files": "",
        "dbfs_files_path": "List with path in dbfs of uploaded files",
        "stamp_file":"",
    },
)

ConfigureInfo = provider(
    fields = {
        "profile" : 'The profile defined in the databricks configure',
        "cluster_name": "The name of the cluster that the rules will interact with.",
        "debug": "Shows full stack trace on error",
        "config_file_info": ""
    }
)
