#!/bin/bash

set -euxo pipefail

if [[ "${target_platform}" == osx-* ]]; then
  export LDFLAGS="${LDFLAGS} -framework IOKit"
  # See also https://gitlab.kitware.com/cmake/cmake/-/issues/25755
  export CFLAGS="${CFLAGS} -fno-define-target-os-macros"
else
  export LDFLAGS="${LDFLAGS} -lpthread -labsl_synchronization -lm"
fi

# gen-bazel-toolchain runs `$CC -v | head -1 | cut -f3` to locate clang's resource
# directory. If CC isn't on PATH yet, stderr is "... command not found" and field 3
# becomes "not", which breaks rules_cc header validation (e.g. @@zlib+//:z).
if [[ "${c_compiler:-}" == "clang" && -x "${BUILD_PREFIX}/bin/${HOST}-clang" ]]; then
  export CC="${BUILD_PREFIX}/bin/${HOST}-clang"
  export CXX="${BUILD_PREFIX}/bin/${HOST}-clang++"
  export CLANG="${CC##*/}"
fi

# Generate toolchain and set necessary environment variables
source gen-bazel-toolchain

_clang_resource_dir="$(basename "$(ls -d "${BUILD_PREFIX}"/lib/clang/[0-9]* 2>/dev/null | sort -V | tail -1)")"
for cfg in bazel_toolchain/cc_toolchain_config.bzl bazel_toolchain/cc_toolchain_build_config.bzl; do
  sed -ie "s|/lib/clang/not/include|/lib/clang/${_clang_resource_dir}/include|g" "${cfg}"
done

# Replace the abseil, grpc and protobuf modules with systemlibs stubs that link
# the conda libraries. absl and protobuf come from their -bazel-systemlib
# packages, grpc from recipe/grpc; complete them with the Starlark rules shipped
# by protobuf-bazel-rules and grpc-bazel-rules.
# cp -ap preserves the packaged files' read-only mode, so make the tree writable
# for the sed substitutions below.
mkdir -p third_party/systemlibs
cp -a "${PREFIX}/share/bazel/systemlibs/absl" third_party/systemlibs/
cp -a "${PREFIX}/share/bazel/systemlibs/protobuf" third_party/systemlibs/
cp -ap "${RECIPE_DIR}/grpc" third_party/systemlibs/grpc
cp -ap "${PREFIX}/share/bazel/protobuf/bazel" third_party/systemlibs/protobuf/
# bazel/upb_*.bzl forward to //upb/bazel:*, which grpc's build rules load.
# protobuf-bazel-rules installs upb at share/bazel/upb/, not share/bazel/protobuf/upb/.
cp -ap "${PREFIX}/share/bazel/upb" third_party/systemlibs/protobuf/
cp -ap "${PREFIX}/share/bazel/grpc/bazel" third_party/systemlibs/grpc/
# Make the grpc rules repository-local
sed -i 's/\@com_github_grpc_grpc//' third_party/systemlibs/grpc/bazel/*.bzl

if [[ "${target_platform}" == "osx-64" ]]; then
  export TARGET_CPU="darwin"
fi

# For debugging purposes, you can add
# --logging=6 --subcommands --verbose_failures
# This is though too much log output for Travis CI.
# Extract minor.patch from libprotobuf version, that is the protoc version
# The protobuf-java needs to be manually bumped if necessary
# See https://protobuf.dev/support/version-support/
export PROTOC=$BUILD_PREFIX/bin/protoc
export ABSEIL_VERSION=$(conda list -p $PREFIX --json libabseil | python3 -c "import json, sys; print(json.load(sys.stdin)[0][\"version\"])")
export GRPC_VERSION=$(conda list -p $PREFIX --json libgrpc | python3 -c "import json, sys; print(json.load(sys.stdin)[0][\"version\"])")
# grpc-java is not released for every grpc version (the BCR has no 1.83.0), so pick
# the newest BCR release that is not newer than libgrpc.
export GRPC_JAVA_VERSION="1.82.0"
export PROTOC_VERSION=$(conda list -p $PREFIX --json libprotobuf | python3 -c "import json, sys; print(json.load(sys.stdin)[0][\"version\"].split(\".\", 1)[1])")
export PROTOBUF_JAVA_MAJOR_VERSION="4"
export BAZEL_BUILD_OPTS="--crosstool_top=//bazel_toolchain:toolchain --define=PROTOBUF_INCLUDE_PATH=${PREFIX}/include --cpu=${TARGET_CPU} --cxxopt=-std=c++17"
export BAZEL_BUILD_OPTS="${BAZEL_BUILD_OPTS} --define=PROTOC_PREFIX=${BUILD_PREFIX}"
export BAZEL_BUILD_OPTS="${BAZEL_BUILD_OPTS} --host_action_env=PATH=${BUILD_PREFIX}/bin:/bin:/usr/bin:/usr/local/bin"
export BAZEL_BUILD_OPTS="${BAZEL_BUILD_OPTS} --platforms=//bazel_toolchain:target_platform --host_platform=//bazel_toolchain:build_platform --extra_toolchains=//bazel_toolchain:cc_cf_toolchain --extra_toolchains=//bazel_toolchain:cc_cf_host_toolchain --noincompatible_enable_proto_toolchain_resolution --toolchain_resolution_debug='.*'"
export EXTRA_BAZEL_ARGS="--tool_java_runtime_version=21 --java_runtime_version=21"
sed -i "s:\${INSTALL_NAME_TOOL}:${INSTALL_NAME_TOOL:-install_name_tool}:" src/BUILD
sed -i "s:\${PREFIX}:${PREFIX}:" src/BUILD
sed -i "s:\${BUILD_PREFIX}:${BUILD_PREFIX}:" \
  third_party/grpc/BUILD \
  third_party/systemlibs/grpc/BUILD \
  third_party/ijar/BUILD \
  src/tools/singlejar/BUILD
sed -i "s:TARGET_CPU:${TARGET_CPU}:" compile.sh
sed -i "s:BUILD_CPU:${BUILD_CPU}:" compile.sh
# The packaged module files already pin their own version; only the placeholder
# in the root MODULE.bazel and protobuf's dependency on abseil need substituting.
sed -i "s:ABSEIL_VERSION:${ABSEIL_VERSION}:" \
  MODULE.bazel \
  third_party/systemlibs/protobuf/MODULE.bazel
sed -i "s:GRPC_JAVA_VERSION:${GRPC_JAVA_VERSION}:" MODULE.bazel
sed -i "s:GRPC_VERSION:${GRPC_VERSION}:" \
  MODULE.bazel \
  third_party/systemlibs/grpc/MODULE.bazel
sed -i "s:PROTOC_VERSION:${PROTOC_VERSION}:" \
  MODULE.bazel \
  third_party/systemlibs/grpc/MODULE.bazel
sed -i "s:PROTOBUF_JAVA_MAJOR_VERSION:${PROTOBUF_JAVA_MAJOR_VERSION}:" \
  third_party/systemlibs/protobuf/MODULE.bazel

# compile.sh defaults the label to the first `version =` in MODULE.bazel, which
# upstream doesn't always bump (the 8.8.2 tag still says 8.8.1, 9.3.1 says 9.3.0).
export EMBED_LABEL="${PKG_VERSION}"
./compile.sh

mkdir -p $PREFIX/bin/
cp ${RECIPE_DIR}/bazel-wrapper.sh $PREFIX/bin/bazel
chmod +x $PREFIX/bin/bazel
mv output/bazel $PREFIX/bin/bazel-real

# Explicitly unpack the contents of the bazel binary. This is normally done
# on demand during runtime. Then this is extracted to a random location and
# we cannot fix the RPATHs reliably.
#
# conda's binary relocation logic sadly doesn't work otherwise as
#  * The binaries are zipped into the main executable.
#  * Modifying the binaries changes their mtime and then bazel rejects them
#    as corrupted.
if [[ "${target_platform}" == linux-* ]]; then
  patchelf --set-rpath '$ORIGIN/../lib' $PREFIX/bin/bazel-real
fi
mkdir -p $PREFIX/share/bazel/install
mkdir -p install-archive
pushd install-archive
  unzip $PREFIX/bin/bazel-real
  export INSTALL_BASE_KEY=$(cat install_base_key)
popd
# The archive of Bazel >= 9.3 carries no unix modes. When the client extracts the
# archive itself it writes every file as 0755, so do the same for this copy.
find install-archive -type f -exec chmod 0755 {} +
mv install-archive $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}
chmod -R a+w $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}
# The Starlark CPU profiler is a JNI shared object that lands in this same
# directory (libcpu_profiler.so / libcpu_profiler.dylib). It needs the same
# RPATH treatment as the tools below, otherwise it keeps the build-host prefix
# (…/_h_env_placehold…/lib:…/_build_env/lib) baked in and leaks it into the package.
if [[ "${target_platform}" == osx-* ]]; then
  relocatables=("daemonize" "linux-sandbox" "process-wrapper" "libcpu_profiler.dylib")
else
  relocatables=("daemonize" "linux-sandbox" "process-wrapper" "libcpu_profiler.so")
fi
for executable in "${relocatables[@]}"; do
  if [[ "${target_platform}" == osx-* ]]; then
    ${INSTALL_NAME_TOOL} -rpath ${PREFIX}/lib '@loader_path/../../../../lib' $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}/$executable
  else
    patchelf --set-rpath '$ORIGIN/../../../../lib' $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}/$executable
  fi
done

# Set timestamps to untampered, otherwise bazel will reject the modified files as corrupted.
find $PREFIX/share/bazel/install/${INSTALL_BASE_KEY} -type f | xargs touch -mt $(($(date '+%Y') + 10))10101010
chmod -R a-w $PREFIX/share/bazel/install/${INSTALL_BASE_KEY}
