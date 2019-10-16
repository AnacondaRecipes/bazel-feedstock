load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
     "feature",
     "flag_group",
     "flag_set",
     "tool_path")

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")

def _impl(ctx):
    tool_paths = [
        tool_path(
            name = "gcc",
            path = "cc_wrapper.sh",
        ),
        tool_path(
            name = "ld",
            path = "${LD}",
        ),
        tool_path(
            name = "ar",
            path = "${LIBTOOL}",
        ),
        tool_path(
            name = "cpp",
            path = "/usr/bin/cpp",
        ),
        tool_path(
            name = "gcov",
            path = "/usr/bin/gcov",
        ),
        tool_path(
            name = "nm",
            path = "${NM}",
        ),
        tool_path(
            name = "objdump",
            path = "/usr/bin/objdump",
        ),
        tool_path(
            name = "strip",
            path = "${STRIP}",
        ),
    ]
    toolchain_include_directories_feature = feature(
        name = "toolchain_include_directories",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.assemble,
                    ACTION_NAMES.preprocess_assemble,
                    ACTION_NAMES.linkstamp_compile,
                    ACTION_NAMES.c_compile,
                    ACTION_NAMES.cpp_compile,
                    ACTION_NAMES.cpp_header_parsing,
                    ACTION_NAMES.cpp_module_compile,
                    ACTION_NAMES.cpp_module_codegen,
                    ACTION_NAMES.lto_backend,
                    ACTION_NAMES.clif_match,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-isystem",
                            "${BUILD_PREFIX}/include/c++/v1",
                            "-isystem",
                            "${BUILD_PREFIX}/lib/clang/4.0.1/include",
                            "-isystem",
                            "${CONDA_BUILD_SYSROOT}/usr/include",
                            "-isystem",
                            "${CONDA_BUILD_SYSROOT}/System/Library/Frameworks",
                        ],
                    ),
                ],
            ),
        ],
    )

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "local",
        host_system_name = "local",
        target_system_name = "local",
        target_cpu = "same_as_host",
        target_libc = "macosx",
        compiler = "compiler",
        abi_version = "local",
        abi_libc_version = "local",
        tool_paths = tool_paths,
        features = [toolchain_include_directories_feature],
    )

cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {},
    provides = [CcToolchainConfigInfo],
)
