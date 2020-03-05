load(":providers.bzl", "FsInfo", "ConfigureInfo")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("//internal/utils:utils.bzl", "utils", "join_path", "resolve_stamp", "toolchain_properties")
load("//internal/utils:common.bzl", "DBFS_PROPERTIES", "CMD_CONFIG_FILE_STATUS")
_DATABRICKS_TOOLCHAIN = "@rules_databricks//toolchain/databricks:toolchain_type"

def _aspect_files(ctx):

    return struct(
        bazel_files = [file for file in ctx.files.files],
        dbfs_files_dirname =  join_path(
            DBFS_PROPERTIES["dbfs_basepath_jars"], DBFS_PROPERTIES["dbfs_prefix_filepath"]
        )
    )

_common_attr  = {
    "_script_tpl": attr.label(
        default = Label("//internal/utility:script.sh.tpl"),
        allow_single_file = True,
    ),
    "_stamper": attr.label(
        default = Label("//internal/utils/stamper:stamper.par"),
        executable = True,
        cfg = "host",
    ),
    "_api": attr.string(
        default = "fs",
    ),
    "files": attr.label_list(
        mandatory = True,
        allow_files = [".jar", ".py", ".sh"],
        allow_empty = False,
    ),
    "configure": attr.label(
        mandatory = True,
        providers = [ConfigureInfo]
    ),
    "stamp" : attr.string(
        default = ""
    ),
}

def _impl(ctx):
    properties = toolchain_properties(ctx, _DATABRICKS_TOOLCHAIN)
    aspects = _aspect_files(ctx)
    api_cmd = ctx.attr._command
    cmd=[]
    runfiles = []
    configure_info = ctx.attr.configure[ConfigureInfo]

    print (configure_info)
    variables = [
        'CLI="%s"' % properties.cli,
        'JQ_TOOL="%s"'% properties.jq_tool,
        'DEFAULT_OPTIONS="--profile %s %s"'% (configure_info.profile, configure_info.debug),
        'CMD="%s %s"' % (ctx.attr._api,api_cmd),
        'CLUSTER_NAME="%s"' % configure_info.cluster_name,
    ]

    config_file_info = configure_info.config_file_info
    runfiles.append(config_file_info)
    variables.append('CONFIG_FILE_INFO="$(cat %s)"' % config_file_info.short_path)

    fsinfo_stampfile=""

    if ctx.attr.stamp:
        stamp_file = ctx.actions.declare_file(ctx.attr.name + ".stamp")
        runfiles.append(stamp_file)
        fsinfo_stampfile = stamp_file
        resolve_stamp(ctx, ctx.attr.stamp.strip(), stamp_file)
        variables.append('STAMP="$(cat %s)"' % stamp_file.short_path)

    fsinfo_file=[]
    fsinfo_filespath=[]

    for aspect in aspects.bazel_files:
        file_basename = aspect.basename
        fsinfo_file.append(aspect.path)
        runfiles.append(aspect)
        if ctx.attr.stamp:
            file_basename = "${STAMP}-" + aspect.basename

        dbfs_filepath = aspects.dbfs_files_dirname + aspect.dirname + "/" + file_basename
        fsinfo_filespath.append(dbfs_filepath)

        OPTIONS=""
        ARGS=""

        if api_cmd == "ls":
            OPTIONS = "-l --absolute"
            ARGS = "%s" % (dbfs_filepath)

        if api_cmd == "rm":
            ARGS = "%s" % (dbfs_filepath)

        if api_cmd == "cp":
            OPTIONS = "--overwrite"
            ARGS = "%s %s" % (aspect.path,dbfs_filepath)

        cmd.append("$CLI $CMD $DEFAULT_OPTIONS {OPTIONS} {ARGS}".format(OPTIONS = OPTIONS, ARGS = ARGS))

    ctx.actions.expand_template(
        is_executable = True,
        output = ctx.outputs.executable,
        template = ctx.file._script_tpl,
        substitutions = {
            "%{VARIABLES}": '\n'.join(variables),
            "%{CONDITIONS}": CMD_CONFIG_FILE_STATUS,
            "%{CMD}": ' && '.join(cmd)
        }
    )

    return [
        DefaultInfo(
            runfiles = ctx.runfiles(
                files = runfiles,
                transitive_files = depset(
                    properties.toolchain_info_file_list + properties.jq_info_file_list
                )
            ),
            executable = ctx.outputs.executable
        ),
        FsInfo(
            files = fsinfo_file,
            dbfs_files_path = fsinfo_filespath,
            stamp_file = fsinfo_stampfile
        )
    ]


_fs_ls = rule(
    executable = True,
    toolchains = [_DATABRICKS_TOOLCHAIN],
    implementation = _impl,
    attrs = utils.add_dicts(
        _common_attr,
        {
            "_command": attr.string(default = "ls")
        },
    ),
)

_fs_cp = rule(
    implementation = _impl,
    executable = True,
    toolchains = [_DATABRICKS_TOOLCHAIN],
    attrs = utils.add_dicts(
        _common_attr,
        {
            "_command": attr.string(default = "cp")
        },
    ),
)

_fs_rm = rule(
    implementation = _impl,
    executable = True,
    toolchains = [_DATABRICKS_TOOLCHAIN],
    attrs = utils.add_dicts(
        _common_attr,
        {
            "_command": attr.string(default = "rm")
        },
    ),
)

def fs(name, **kwargs):

    if "stamp" in kwargs:
        stamp = kwargs["stamp"].strip()
        if not stamp:
            fail ("The stamp attribute cannot be an empty string.")

        if not (
                (
                    stamp.count('{') == 1 and stamp.rindex("{") == 0) and (
                    stamp.count('}') == 1 and stamp.rindex("}") == stamp.find('}')
                )
            ):
            fail ("The stamp string is badly formatted (eg {BUILD_TIMESTAMP}):\n" + str(stamp))

    _fs_ls(name = name, **kwargs)
    _fs_ls(name = name + ".ls", **kwargs)
    _fs_cp(name = name + ".cp",**kwargs)
    _fs_rm(name = name + ".rm",**kwargs)
