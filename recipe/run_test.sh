# Test by building an example from the tutorial.
# https://github.com/bazelbuild/examples/
# https://docs.bazel.build/versions/master/tutorial/cpp.html
set -exuo pipefail

cp -r ${RECIPE_DIR}/tutorial .
cd tutorial

# Same gen-bazel-toolchain footgun as recipe/build.sh: CC must be an absolute path
# or clang's resource dir is detected as "not" and header validation fails.
if [[ "${c_compiler:-}" == "clang" && -x "${CONDA_PREFIX}/bin/${HOST}-clang" ]]; then
  export CC="${CONDA_PREFIX}/bin/${HOST}-clang"
  export CXX="${CONDA_PREFIX}/bin/${HOST}-clang++"
  export CLANG="${CC##*/}"
fi

source gen-bazel-toolchain

_clang_resource_dir="$(basename "$(ls -d "${CONDA_PREFIX}"/lib/clang/[0-9]* 2>/dev/null | sort -V | tail -1)")"
for cfg in bazel_toolchain/cc_toolchain_config.bzl bazel_toolchain/cc_toolchain_build_config.bzl; do
  sed -ie "s|/lib/clang/not/include|/lib/clang/${_clang_resource_dir}/include|g" "${cfg}"
done

bazel build --logging=6 --subcommands --verbose_failures //main:hello-world \
  --platforms=//bazel_toolchain:target_platform \
  --host_platform=//bazel_toolchain:build_platform \
  --extra_toolchains=//bazel_toolchain:cc_cf_toolchain \
  --extra_toolchains=//bazel_toolchain:cc_cf_host_toolchain
