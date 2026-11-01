#!/usr/bin/env bash
# BadVPN UDPGW installer with binary compatibility validation and MUSL static fallback.

BADVPN_DIST_DIR="${SCRIPT_DIR}/opt/badvpn/dist"
BADVPN_RUNTIME_ENV_FILE="${BADVPN_RUNTIME_ENV_FILE:-/etc/default/badvpn-udpgw}"
BADVPN_RUNTIME_ENV_TEMPLATE="${SETUP_TEMPLATE_SRC_DIR}/config/badvpn-runtime.env"
BADVPN_SERVICE_TEMPLATE="${SETUP_TEMPLATE_SRC_DIR}/systemd/badvpn-udpgw.service"
BADVPN_BIN_INSTALL_PATH="${BADVPN_BIN_INSTALL_PATH:-/usr/local/bin/badvpn-udpgw}"
BADVPN_LAUNCHER_SRC="${SCRIPT_DIR}/opt/setup/bin/badvpn-udpgw-launcher.sh"
BADVPN_LAUNCHER_INSTALL_PATH="${BADVPN_LAUNCHER_INSTALL_PATH:-/usr/local/bin/badvpn-udpgw-launcher}"
BADVPN_SERVICE_NAME="${BADVPN_SERVICE_NAME:-badvpn-udpgw.service}"
BADVPN_UDPGW_PORTS_DEFAULT="${BADVPN_UDPGW_PORTS_DEFAULT:-7300 7400 7500 7600 7700 7800 7900}"
BADVPN_SOURCE_DIR="${BADVPN_SOURCE_DIR:-/usr/local/src/badvpn}"
BADVPN_BUILD_DIR="${BADVPN_BUILD_DIR:-/usr/local/src/badvpn/build-musl}"

badvpn_arch_label() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) return 1 ;;
  esac
}

badvpn_expected_binary_path() {
  local arch
  arch="$(badvpn_arch_label)" || return 1
  printf '%s/badvpn-udpgw-linux-%s\n' "${BADVPN_DIST_DIR}" "${arch}"
}

# Validates that a candidate is an executable ELF and has no unresolved
# shared-library/GLIBC requirement. Static MUSL binaries are preferred.
badvpn_binary_compatible() {
  local bin="$1" info deps
  [[ -f "${bin}" && -x "${bin}" ]] || return 1
  command -v file >/dev/null 2>&1 || return 1
  info="$(file -b "${bin}" 2>/dev/null || true)"
  [[ "${info}" == *ELF* ]] || return 1

  if command -v ldd >/dev/null 2>&1; then
    deps="$(ldd "${bin}" 2>&1 || true)"
    [[ "${deps}" != *"not found"* ]] || return 1
    [[ "${deps}" != *"GLIBC_"*"not found"* ]] || return 1
  fi

  # A quick execution check catches wrong-architecture and loader failures.
  command -v timeout >/dev/null 2>&1 || return 1
  timeout 5 "${bin}" --help >/dev/null 2>&1
}

badvpn_prebuilt_ready() {
  local bin
  bin="$(badvpn_expected_binary_path)" || return 1
  badvpn_binary_compatible "${bin}"
}

badvpn_runtime_expected() {
  badvpn_prebuilt_ready || badvpn_binary_compatible "${BADVPN_BIN_INSTALL_PATH}"
}

badvpn_install_build_dependencies() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates git cmake build-essential musl-tools file
}

badvpn_prepare_source() {
  if [[ ! -f "${BADVPN_SOURCE_DIR}/CMakeLists.txt" ]]; then
    install -d -m 0755 "$(dirname "${BADVPN_SOURCE_DIR}")"
    git clone --depth 1 https://github.com/ambrop72/badvpn.git "${BADVPN_SOURCE_DIR}" \
      || die "Gagal mengambil source BadVPN dari repository resmi."
  fi
  [[ -f "${BADVPN_SOURCE_DIR}/CMakeLists.txt" ]] \
    || die "Source BadVPN tidak valid: ${BADVPN_SOURCE_DIR}"
}

badvpn_build_musl_static() {
  local built="${BADVPN_BUILD_DIR}/udpgw/badvpn-udpgw"
  warn "Binary BadVPN prebuilt tidak kompatibel. Menyiapkan build MUSL static."

  badvpn_install_build_dependencies
  command -v musl-gcc >/dev/null 2>&1 \
    || die "musl-gcc tidak tersedia setelah instalasi musl-tools."
  badvpn_prepare_source

  rm -rf "${BADVPN_BUILD_DIR}"
  cmake -S "${BADVPN_SOURCE_DIR}" -B "${BADVPN_BUILD_DIR}" \
    -DBUILD_NOTHING_BY_DEFAULT=1 \
    -DBUILD_UDPGW=1 \
    -DCMAKE_C_COMPILER=musl-gcc \
    -DCMAKE_EXE_LINKER_FLAGS="-static" \
    -DCMAKE_BUILD_TYPE=Release \
    || die "Konfigurasi CMake BadVPN MUSL gagal."

  cmake --build "${BADVPN_BUILD_DIR}" --parallel "$(nproc)" \
    || die "Kompilasi BadVPN MUSL gagal."

  [[ -x "${built}" ]] || die "Binary hasil build tidak ditemukan: ${built}"
  badvpn_binary_compatible "${built}" \
    || die "Binary hasil build MUSL gagal validasi kompatibilitas/eksekusi."

  printf '%s\n' "${built}"
}

badvpn_resolve_binary() {
  local prebuilt built
  prebuilt="$(badvpn_expected_binary_path 2>/dev/null || true)"
  if [[ -n "${prebuilt}" ]] && badvpn_binary_compatible "${prebuilt}"; then
    printf '%s\n' "${prebuilt}"
    return 0
  fi

  # Reuse a previously built static binary if it still passes validation.
  built="${BADVPN_BUILD_DIR}/udpgw/badvpn-udpgw"
  if badvpn_binary_compatible "${built}"; then
    printf '%s\n' "${built}"
    return 0
  fi

  badvpn_build_musl_static
}

write_badvpn_runtime_env() {
  if [[ -f "${BADVPN_RUNTIME_ENV_TEMPLATE}" ]]; then
    render_setup_template_or_die "config/badvpn-runtime.env" "${BADVPN_RUNTIME_ENV_FILE}" 0644
  else
    cat > "${BADVPN_RUNTIME_ENV_FILE}" <<'EOF'
BADVPN_UDPGW_PORTS="7300 7400 7500 7600 7700 7800 7900"
BADVPN_UDPGW_MAX_CLIENTS=512
BADVPN_UDPGW_MAX_CONNECTIONS_FOR_CLIENT=8
BADVPN_UDPGW_BUFFER_SIZE=1048576
EOF
    chmod 0644 "${BADVPN_RUNTIME_ENV_FILE}"
  fi
}

install_badvpn_udpgw_stack() {
  local bin src_name tmp_bin
  [[ -f "${BADVPN_SERVICE_TEMPLATE}" ]] \
    || die "Template service BadVPN UDPGW tidak ditemukan: ${BADVPN_SERVICE_TEMPLATE}"
  [[ -f "${BADVPN_LAUNCHER_SRC}" ]] \
    || die "Launcher BadVPN tidak ditemukan: ${BADVPN_LAUNCHER_SRC}"

  bin="$(badvpn_resolve_binary)" || die "Tidak dapat menyediakan binary BadVPN yang kompatibel."
  src_name="$(basename "${bin}")"

  install -d -m 0755 "$(dirname "${BADVPN_BIN_INSTALL_PATH}")"
  if [[ -f "${BADVPN_BIN_INSTALL_PATH}" ]]; then
    cp -a "${BADVPN_BIN_INSTALL_PATH}" \
      "${BADVPN_BIN_INSTALL_PATH}.backup.$(date +%Y%m%d%H%M%S)"
  fi
  tmp_bin="${BADVPN_BIN_INSTALL_PATH}.new"
  install -o root -g root -m 0755 "${bin}" "${tmp_bin}"
  badvpn_binary_compatible "${tmp_bin}" \
    || { rm -f "${tmp_bin}"; die "Binary BadVPN gagal validasi setelah disalin."; }
  mv -f "${tmp_bin}" "${BADVPN_BIN_INSTALL_PATH}"

  install -o root -g root -m 0755 "${BADVPN_LAUNCHER_SRC}" "${BADVPN_LAUNCHER_INSTALL_PATH}"
  write_badvpn_runtime_env

  render_setup_template_or_die \
    "systemd/badvpn-udpgw.service" \
    "/etc/systemd/system/${BADVPN_SERVICE_NAME}" \
    0644 \
    "BADVPN_BIN_INSTALL_PATH=${BADVPN_BIN_INSTALL_PATH}" \
    "BADVPN_LAUNCHER_INSTALL_PATH=${BADVPN_LAUNCHER_INSTALL_PATH}" \
    "BADVPN_RUNTIME_ENV_FILE=${BADVPN_RUNTIME_ENV_FILE}"

  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable "${BADVPN_SERVICE_NAME}" --now >/dev/null 2>&1 \
    || die "Gagal mengaktifkan ${BADVPN_SERVICE_NAME}"
  systemctl is-active --quiet "${BADVPN_SERVICE_NAME}" \
    || die "${BADVPN_SERVICE_NAME} tidak active."
  ok "BadVPN UDPGW aktif (${src_name})"
}
