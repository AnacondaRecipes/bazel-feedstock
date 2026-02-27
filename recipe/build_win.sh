#!/bin/bash

set -euxo pipefail

${SRC_DIR}/bazel-${PKG_VERSION}-windows-x86_64.exe --output_base=${SRC_DIR}/out build \
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
timeout 30 ${SRC_DIR}/bazel-${PKG_VERSION}-windows-x86_64.exe --output_base=${SRC_DIR}/out shutdown || true
taskkill //F //FI "USERNAME eq $USERNAME" //IM java.exe 2>/dev/null || true
tasklist //FI "USERNAME eq $USERNAME" 2>/dev/null || true
exit 0