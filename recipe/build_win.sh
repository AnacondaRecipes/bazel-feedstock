#!/bin/bash

set -euxo pipefail

# conda's $ARCH is "64" for win-64 and "arm64" for win-arm64, while Bazel's
# release artifacts use "x86_64"/"arm64".
if [[ ${ARCH} == arm64 ]]; then
	BAZEL_ARCH=arm64
	ARCH_ARGS=(--config=windows_arm64)
else
	BAZEL_ARCH=x86_64
	ARCH_ARGS=()
fi

BAZEL_BOOTSTRAP=${SRC_DIR}/bazel-${PKG_VERSION}-windows-${BAZEL_ARCH}.exe

${BAZEL_BOOTSTRAP} --output_base=${SRC_DIR}/out build \
	"${ARCH_ARGS[@]}" \
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
timeout 30 ${BAZEL_BOOTSTRAP} --output_base=${SRC_DIR}/out shutdown || true
exit 0