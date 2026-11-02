#!/usr/bin/env bash

BADVPN_DIST_DIR="${SCRIPT_DIR}/opt/badvpn/dist"
BADVPN_RUNTIME_ENV_FILE="${BADVPN_RUNTIME_ENV_FILE:-/etc/default/badvpn-udpgw}"
BADVPN_RUNTIME_ENV_TEMPLATE="${SETUP_TEMPLATE_SRC_DIR}/config/badvpn-runtime.env"
BADVPN_SERVICE_TEMPLATE="${SETUP_TEMPLATE_SRC_DIR}/systemd/badvpn-udpgw.service"
BADVPN_BIN_INSTALL_PATH="${BADVPN_BIN_INSTALL_PATH:-/usr/local/bin/badvpn-udpgw}"
BADVPN_LAUNCHER_SRC="${SCRIPT_DIR}/opt/setup/bin/badvpn-udpgw-launcher.sh"
BADVPN_LAUNCHER_INSTALL_PATH="${BADVPN_LAUNCHER_INSTALL_PATH:-/usr/local/bin/badvpn-udpgw-launcher}"
BADVPN_SERVICE_NAME="${BADVPN_SERVICE_NAME:-badvpn-udpgw.service}"
BADVPN_UDPGW_PORTS_DEFAULT="${BADVPN_UDPGW_PORTS_DEFAULT:-7300 7400 7500 7600 7700 7800 7900}"
BADVPN_SOURCE_DIR="${BADVPN_SOURCE_DIR:-/usr/local/src/dlgst-badvpn-source}"
BADVPN_BUILD_DIR="${BADVPN_BUILD_DIR:-/usr/local/src/dlgst-badvpn-build-musl}"

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

# AMD64 wajib static agar tidak bergantung pada versi GLIBC host (Debian 12 = 2.36).
# ARM64 tetap menerima binary dinamis selama semua dependensinya tersedia.
badvpn_binary_is_static() {
  local bin="$1" program_headers
  [[ -x "${bin}" && -f "${bin}" ]] || return 1

  if command -v readelf >/dev/null 2>&1; then
    program_headers="$(readelf -l "${bin}" 2>/dev/null)" || return 1
    ! grep -q 'INTERP' <<<"${program_headers}"
    return $?
  fi

  if command -v ldd >/dev/null 2>&1; then
    local deps
    deps="$(ldd "${bin}" 2>&1 || true)"
    grep -Eqi 'not a dynamic executable|statically linked' <<<"${deps}"
    return $?
  fi

  # Jangan mengklaim kompatibel jika static binary tidak dapat diverifikasi.
  return 1
}

# Cek dependensi runtime, format linkage, dan eksekusi binary.
badvpn_binary_usable() {
  local bin="$1" deps arch
  [[ -x "${bin}" && -f "${bin}" ]] || return 1

  if command -v ldd >/dev/null 2>&1; then
    deps="$(ldd "${bin}" 2>&1 || true)"
    if grep -Eqi 'not found|GLIBC_[0-9.]+ not found' <<<"${deps}"; then
      return 1
    fi
  fi

  arch="$(badvpn_arch_label 2>/dev/null || true)"
  if [[ "${arch}" == "amd64" ]] && ! badvpn_binary_is_static "${bin}"; then
    return 1
  fi

  timeout 5 "${bin}" --help >/dev/null 2>&1
}

badvpn_prebuilt_ready() {
  local bin
  bin="$(badvpn_expected_binary_path)" || return 1
  [[ -f "${bin}" && -x "${bin}" ]]
}

badvpn_install_build_dependencies() {
  command -v apt-get >/dev/null 2>&1 || die "Build BadVPN otomatis saat ini membutuhkan apt-get (Debian/Ubuntu)."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update >&2
  apt-get install -y --no-install-recommends \
    ca-certificates git cmake build-essential musl-tools >&2
  command -v musl-gcc >/dev/null 2>&1 || die "musl-gcc tidak ditemukan setelah instalasi musl-tools."
}

badvpn_prepare_source() {
  if [[ -f "${BADVPN_SOURCE_DIR}/CMakeLists.txt" ]]; then
    return 0
  fi

  install -d -m 0755 "$(dirname "${BADVPN_SOURCE_DIR}")"
  rm -rf "${BADVPN_SOURCE_DIR}.download"
  git clone --depth 1 https://github.com/ambrop72/badvpn.git "${BADVPN_SOURCE_DIR}.download" \
    || die "Gagal mengambil source BadVPN dari GitHub."
  [[ -f "${BADVPN_SOURCE_DIR}.download/CMakeLists.txt" ]] \
    || die "Source BadVPN tidak memiliki CMakeLists.txt."
  rm -rf "${BADVPN_SOURCE_DIR}"
  mv "${BADVPN_SOURCE_DIR}.download" "${BADVPN_SOURCE_DIR}"
}

badvpn_build_musl_static() {
  local built="${BADVPN_BUILD_DIR}/udpgw/badvpn-udpgw"
  printf "[INFO] Binary BadVPN prebuilt tidak kompatibel/tersedia. Build MUSL static dimulai.\n" >&2

  badvpn_install_build_dependencies
  badvpn_prepare_source

  rm -rf "${BADVPN_BUILD_DIR}"
  cmake -S "${BADVPN_SOURCE_DIR}" -B "${BADVPN_BUILD_DIR}" \
    -DBUILD_NOTHING_BY_DEFAULT=1 \
    -DBUILD_UDPGW=1 \
    -DCMAKE_C_COMPILER=musl-gcc \
    -DCMAKE_C_FLAGS="-O2 -pipe" \
    -DCMAKE_EXE_LINKER_FLAGS="-static" >&2 \
    || die "Konfigurasi CMake BadVPN MUSL gagal."

  cmake --build "${BADVPN_BUILD_DIR}" --parallel "$(nproc)" >&2 \
    || die "Kompilasi BadVPN MUSL gagal."

  [[ -x "${built}" ]] || die "Binary hasil build tidak ditemukan: ${built}"
  badvpn_binary_usable "${built}" \
    || die "Binary BadVPN hasil MUSL build gagal validasi eksekusi."

  if command -v ldd >/dev/null 2>&1; then
    local deps
    deps="$(ldd "${built}" 2>&1 || true)"
    if ! grep -Eqi 'not a dynamic executable|statically linked' <<<"${deps}"; then
      warn "ldd tidak mengonfirmasi static secara eksplisit; hasil tetap diuji dengan eksekusi --help." >&2
    fi
  fi

  printf '%s\n' "${built}"
}

badvpn_select_binary() {
  local prebuilt=""
  if prebuilt="$(badvpn_expected_binary_path 2>/dev/null)" && badvpn_binary_usable "${prebuilt}"; then
    printf '%s\n' "${prebuilt}"
    return 0
  fi

  badvpn_build_musl_static
}

badvpn_runtime_expected() {
  badvpn_binary_usable "${BADVPN_BIN_INSTALL_PATH}"
}

write_badvpn_runtime_env() {
  # Jangan menimpa konfigurasi port/limit milik pengguna pada instalasi ulang.
  if [[ -s "${BADVPN_RUNTIME_ENV_FILE}" ]]; then
    chmod 0644 "${BADVPN_RUNTIME_ENV_FILE}" 2>/dev/null || true
    return 0
  fi

  install -d -m 0755 "$(dirname "${BADVPN_RUNTIME_ENV_FILE}")"
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
  if [[ ! -f "${BADVPN_SERVICE_TEMPLATE}" ]]; then
    die "Template service BadVPN UDPGW tidak ditemukan: ${BADVPN_SERVICE_TEMPLATE}"
  fi
  [[ -f "${BADVPN_LAUNCHER_SRC}" && -r "${BADVPN_LAUNCHER_SRC}" ]] || die "Source launcher BadVPN tidak ditemukan/tidak bisa dibaca: ${BADVPN_LAUNCHER_SRC}"

  bin="$(badvpn_select_binary)" || die "Tidak dapat menyediakan binary BadVPN yang kompatibel."
  src_name="$(basename "${bin}")"

  install -d -m 0755 "$(dirname "${BADVPN_BIN_INSTALL_PATH}")"
  tmp_bin="${BADVPN_BIN_INSTALL_PATH}.new.$$"
  install -o root -g root -m 0755 "${bin}" "${tmp_bin}"
  badvpn_binary_usable "${tmp_bin}" || {
    rm -f "${tmp_bin}"
    die "Validasi binary BadVPN sementara gagal; binary lama tidak diubah."
  }

  if [[ -e "${BADVPN_BIN_INSTALL_PATH}" ]]; then
    cp -a "${BADVPN_BIN_INSTALL_PATH}" "${BADVPN_BIN_INSTALL_PATH}.backup.$(date +%Y%m%d%H%M%S)"
  fi
  mv -f "${tmp_bin}" "${BADVPN_BIN_INSTALL_PATH}"
  chown root:root "${BADVPN_BIN_INSTALL_PATH}" 2>/dev/null || true

  install -m 0755 "${BADVPN_LAUNCHER_SRC}" "${BADVPN_LAUNCHER_INSTALL_PATH}"
  chown root:root "${BADVPN_LAUNCHER_INSTALL_PATH}" 2>/dev/null || true

  write_badvpn_runtime_env
  render_setup_template_or_die \
    "systemd/badvpn-udpgw.service" \
    "/etc/systemd/system/${BADVPN_SERVICE_NAME}" \
    0644 \
    "BADVPN_BIN_INSTALL_PATH=${BADVPN_BIN_INSTALL_PATH}" \
    "BADVPN_LAUNCHER_INSTALL_PATH=${BADVPN_LAUNCHER_INSTALL_PATH}" \
    "BADVPN_RUNTIME_ENV_FILE=${BADVPN_RUNTIME_ENV_FILE}"

  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable "${BADVPN_SERVICE_NAME}" >/dev/null 2>&1 \
    || die "Gagal enable ${BADVPN_SERVICE_NAME}"
  systemctl restart "${BADVPN_SERVICE_NAME}" \
    || die "Gagal menjalankan ulang ${BADVPN_SERVICE_NAME}"
  systemctl is-active --quiet "${BADVPN_SERVICE_NAME}" \
    || die "${BADVPN_SERVICE_NAME} tidak active."

  ok "BadVPN UDPGW aktif (${src_name}); runtime config dipertahankan."
}
