# Adapted from https://docs.bazel.build/versions/0.26.0/tutorial/cc-toolchain-config.html
# https://docs.bazel.build/versions/master/skylark/lib/cc_common.html#create_cc_toolchain_config_info
# pulling in options from old CROSSTOOL.template

load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
     "feature",
     "flag_group",
     "flag_set",
     "tool_path",
     "with_feature_set",
     )

load("@bazel_tools//tools/build_defs/cc:action_names.bzl",
     "ACTION_NAMES")

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

    compiler_flags = feature(
        name = "compiler_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.c_compile,
                    ACTION_NAMES.cpp_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-march=core2",
                            "-mtune=haswell",
                            "-mssse3",
                            "-ftree-vectorize",
                            "-fPIC",
                            "-fPIE",
                            "-fstack-protector-strong",
                            "-O2",
                            "-pipe",
                            "-fno-lto"
                            ],
                    ),
                ],
            ),
        ],
    )

    cxx_flags = feature(
        name = "cxx_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cpp_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-stdlib=libc++",
                            "-fvisibility-inlines-hidden",
                            "-std=c++14",
                            "-fmessage-length=0"
                            ],
                    ),
                ],
            ),
        ],
    )

    linker_flags = feature(
        name = "linker_flags",
        flag_sets = [
            flag_set (
                actions = [
                    "ACTION_NAMES.cpp_link_static_library",
                    "ACTION_NAMES.cpp_link_dynamic_library",
                    "ACTION_NAMES.cpp_link_executable",
                    "ACTION_NAMES.cpp_link_nodeps_dynamic_library",
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-Wl,-pie",
                            "-headerpad_max_install_names",
                            "-Wl,-dead_strip_dylibs",
                            "-undefined",
                            "dynamic_lookup",
                            "-force_load",
                            "${BUILD_PREFIX}/lib/libc++.a",
                            "-force_load",
                            "${BUILD_PREFIX}/lib/libc++abi.a",
                            "-nostdlib",
                            "-lc",
                            "-isysroot${CONDA_BUILD_SYSROOT}",
                            ]
                    ),
                ],
            ),
        ],
    )

    supports_pic_feature = feature(
        name = "supports_pic",
        enabled = True
        )

    supports_dynamic_linker = feature(
        name = "supports_dynamic_linker",
        enabled = True
        )

    opt = feature(
        name = "opt",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.c_compile,
                    ACTION_NAMES.cpp_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-g0",
                            "-O2",
                            "-D_FORTIFY_SOURCE=1",
                            "-DNDEBUG",
                            "-ffunction-sections",
                            "-fdata-sections",
                        ],
                    ),
                ],
            ),
        ],
    )

    dbg = feature(
        name = "dbg",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.c_compile,
                    ACTION_NAMES.cpp_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-g"
                        ],
                    ),
                ],
            ),
        ],
    )

    cxx_builtin_include_directories = [
        "${CONDA_BUILD_SYSROOT}/System/Library/Frameworks",
        "${CONDA_BUILD_SYSROOT}/usr/include",
        "${BUILD_PREFIX}/lib/clang/4.0.1/include",
        "${BUILD_PREFIX}/include/c++/v1",
    ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "local",
        host_system_name = "local",
        target_system_name = "local",
        target_cpu = "darwin",
        target_libc = "macosx",
        compiler = "compiler",
        abi_version = "local",
        abi_libc_version = "local",
        tool_paths = tool_paths,
        cxx_builtin_include_directories = cxx_builtin_include_directories,
        features = [compiler_flags, cxx_flags, supports_pic_feature, linker_flags, supports_dynamic_linker],
    )

cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {},
    provides = [CcToolchainConfigInfo],
)
