#!/bin/bash

set -euxo pipefail

# The x86_64 bootstrap is used for both Windows targets, including win-arm64.
# On Windows ARM64 it runs under x86_64 emulation, which is deliberate:
#
#  1. grpc's BUILD selects its Windows implementation with the legacy cpu setting
#     `config_setting(name = "windows", values = {"cpu": "x64_windows"})`, and
#     `if_windows`/`if_not_windows` key off it too. A native arm64 server reports
#     --cpu=arm64_windows (see AutoCpuConverter), *no* Windows config_setting
#     matches, grpc falls back to "//conditions:default" (the POSIX event engine)
#     and the build then fails with undeclared inclusions of
#     windows_engine.h / windows_endpoint.h. The x86_64 server reports
#     --cpu=x64_windows, so grpc picks the Windows code paths, exactly as it does
#     when upstream cross-compiles its arm64 releases from an x64 host.
#
#  2. The native arm64 bootstrap embeds Zulu 25+36 (JAVA_VERSION_DATE 2025-09-16),
#     which deadlocks in the JVM's Windows ARM64 selector while fetching
#     repositories, so the build never gets past "Fetching repository ...".
#     See https://github.com/bazelbuild/bazel/issues/28520. The x86_64 server runs
#     on the bootstrap's own x86_64 JDK and does not hit it.
#
# The output is still built for ARM64: --config=windows_arm64 expands to
# --platforms=//:windows_arm64 and
# --extra_toolchains=@local_config_cc//:cc-toolchain-arm64_windows (see .bazelrc),
# so the launcher and the embedded windows_jni.dll are arm64.
#
# Note: declare the arrays, an undeclared empty array aborts under `set -u`.
declare -a BUILD_ARGS=()
if [[ ${ARCH} == arm64 ]]; then
	BUILD_ARGS=(--config=windows_arm64)
fi

BAZEL_BOOTSTRAP=${SRC_DIR}/bazel-${PKG_VERSION}-windows-x86_64.exe

${BAZEL_BOOTSTRAP} --output_base=${SRC_DIR}/out build \
	"${BUILD_ARGS[@]}" \
	--cxxopt=/std:c++17 \
	--action_env=PATH \
	--remote_download_outputs=all \
	--spawn_strategy=standalone \
	--nojava_header_compilation \
	--strategy=Javac=worker \
	--worker_quit_after_build \
	--compilation_mode=opt \
	--enable_bzlmod \
	--check_direct_dependencies=error \
	--lockfile_mode=update \
	--host_copt=-Iexternal/protobuf+/src \
    --host_copt=-Iexternal/protobuf+/src/google \
    src:bazel_nojdk.exe

# bazel-bin is a link and 'cp' command cannot find the file for this path for some reason
# cp ${SRC_DIR}/bazel-bin/src/bazel_nojdk.exe ${LIBRARY_PREFIX}/bin/bazel.exe
python -c "
import shutil, os
src = os.path.join(os.environ['SRC_DIR'], 'bazel-bin', 'src', 'bazel_nojdk.exe')
dst = os.path.join(os.environ['LIBRARY_PREFIX'], 'bin', 'bazel.exe')
print('src exists:', os.path.exists(src))
shutil.copy2(src, dst)
"
# Guard the cross-compile: an x86_64 bazel.exe in a win-arm64 package builds fine
# but then dies at runtime with "Can't load AMD 64-bit .dll on a ARM 64-bit
# platform" when the arm64 JDK loads the embedded x86_64 windows_jni.dll.
python -c "
import os, struct
path = os.path.join(os.environ['LIBRARY_PREFIX'], 'bin', 'bazel.exe')
with open(path, 'rb') as f:
    data = f.read(1024)
pe = struct.unpack_from('<I', data, 0x3C)[0]
machine = struct.unpack_from('<H', data, pe + 4)[0]
target = os.environ.get('target_platform', '')
expected = 0xAA64 if target.endswith('arm64') else 0x8664
print('bazel.exe PE machine 0x%04x, expected 0x%04x for %s' % (machine, expected, target))
if machine != expected:
    raise SystemExit('ERROR: bazel.exe architecture does not match %s' % target)
"
timeout 30 ${BAZEL_BOOTSTRAP} --output_base=${SRC_DIR}/out shutdown || true
exit 0
