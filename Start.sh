#!/bin/bash

################################################################################
# OpenClaw Startup Script untuk Railway
# Didesain untuk menjalankan OpenClaw gateway di container environment
# UPDATED: Kompatibel dengan OpenClaw v2026.3.8 config format
################################################################################

set -e  # Exit jika ada error

# ============================================================================
# WARNA OUTPUT (untuk logging yang lebih readable)
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# FUNCTIONS UNTUK LOGGING
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ️  INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}❌ ERROR:${NC} $1"
}

log_divider() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============================================================================
# KONFIGURASI DASAR
# ============================================================================

# Port yang akan digunakan (ganti jika ada conflict)
PORT=${PORT:-3000}

# Direktori config
CONFIG_DIR="/data/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"

# Direktori workspace
WORKSPACE_DIR="/data/workspace"

# Gateway mode: "local" atau "remote"
GATEWAY_MODE="local"

# Gateway bind mode untuk v2026.3.8: "lan" (bukan "0.0.0.0")
GATEWAY_BIND="lan"

# Timeout untuk health check (detik)
HEALTH_CHECK_TIMEOUT=30

log_divider
echo -e "${BLUE}🦞 OPENCLAW STARTUP SCRIPT 🦞${NC}"
echo -e "${BLUE}Version: OpenClaw v2026.3.8${NC}"
log_divider

# ============================================================================
# STEP 1: PERSIAPAN AWAL
# ============================================================================

log_info "Step 1: Persiapan awal..."

# Create directories jika belum ada
log_info "  - Membuat direktori..."
mkdir -p "${CONFIG_DIR}"
mkdir -p "${WORKSPACE_DIR}"
log_success "  Direktori siap"

# ============================================================================
# STEP 2: KILL PROCESS LAMA (jika ada)
# ============================================================================

log_info "Step 2: Membersihkan process lama..."

EXISTING_PROCESS=$(pgrep -f "openclaw gateway" || true)

if [ ! -z "$EXISTING_PROCESS" ]; then
    log_warning "  Ditemukan process OpenClaw lama (PID: $EXISTING_PROCESS)"
    log_info "  Menghentikan process..."
    killall openclaw 2>/dev/null || true
    sleep 2
    log_success "  Process lama dihentikan"
else
    log_info "  Tidak ada process lama yang ditemukan"
fi

# ============================================================================
# STEP 3: VERIFIKASI DAN SETUP KONFIGURASI (v2026.3.8 FORMAT)
# ============================================================================

log_info "Step 3: Setup konfigurasi OpenClaw v2026.3.8..."

if [ -f "${CONFIG_FILE}" ]; then
    log_warning "  File config sudah ada"
    log_info "  Backup ke: ${CONFIG_FILE}.backup"
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup"
    log_success "  Backup dibuat"
fi

# ============================================================================
# PENTING: Config format untuk OpenClaw v2026.3.8
# ============================================================================
# ✅ Format BENAR:
# - gateway.mode: "local" atau "remote"
# - gateway.bind: "lan" (BUKAN "0.0.0.0")
# - Jangan include: "port", "wrapper" (sudah deprecated)
#
# ❌ Format LAMA (tidak support lagi):
# - gateway.bind: "0.0.0.0"
# - Keys: "port", "wrapper"
# ============================================================================

# Create config baru dengan format v2026.3.8
log_info "  Membuat config baru dengan format v2026.3.8"

cat > "${CONFIG_FILE}" <<'EOF'
{
  "gateway": {
    "mode": "local",
    "bind": "lan"
  }
}
EOF

log_success "  Config file dibuat: ${CONFIG_FILE}"

# Verifikasi config dibuat dengan benar
if [ -f "${CONFIG_FILE}" ]; then
    log_success "  ✓ Config file verified"
    log_info "  Config content:"
    cat "${CONFIG_FILE}" | sed 's/^/    /'
else
    log_error "  ✗ Gagal membuat config file!"
    exit 1
fi

# ============================================================================
# STEP 4: JALANKAN OPENCLAW DOCTOR
# ============================================================================

log_info "Step 4: Menjalankan OpenClaw doctor..."

# Wait sebentar agar config file di-detect
sleep 1

if openclaw doctor --fix 2>&1; then
    log_success "  Doctor fix berhasil"
else
    # Jangan exit, warning saja
    log_warning "  Doctor fix menghasilkan warning (melanjutkan...)"
fi

log_info "  Hasil doctor check:"
openclaw doctor 2>&1 | sed 's/^/    /' || true

# ============================================================================
# STEP 5: VERIFIKASI CONFIG SETELAH DOCTOR
# ============================================================================

log_info "Step 5: Verifikasi config setelah doctor..."

if [ -f "${CONFIG_FILE}" ]; then
    log_info "  Config final:"
    cat "${CONFIG_FILE}" | sed 's/^/    /'
    
    # Check format
    if grep -q '"bind".*"lan"' "${CONFIG_FILE}"; then
        log_success "  ✓ Config format v2026.3.8 correct"
    else
        log_warning "  ⚠ Config bind format mungkin berubah"
    fi
else
    log_error "  ✗ Config file hilang!"
    exit 1
fi

# ============================================================================
# STEP 6: INFORMASI STARTUP
# ============================================================================

log_divider
log_info "📊 INFORMASI STARTUP:"
log_info "  - Port: ${PORT}"
log_info "  - Gateway Mode: ${GATEWAY_MODE}"
log_info "  - Gateway Bind: ${GATEWAY_BIND} (v2026.3.8 format)"
log_info "  - Config File: ${CONFIG_FILE}"
log_info "  - Workspace: ${WORKSPACE_DIR}"
log_info "  - Environment: Railway Container"
log_divider

# ============================================================================
# STEP 7: START GATEWAY
# ============================================================================

log_info "Step 7: Menjalankan OpenClaw Gateway..."
log_info "  Gateway akan dijalankan di FOREGROUND mode"
log_info "  (Ini normal untuk container environment)"
log_divider

# Display startup message
echo -e "${GREEN}"
echo "███████████████████████████████████████████████████████████"
echo "█                                                           █"
echo "█  🦞 OPENCLAW GATEWAY STARTING 🦞                        █"
echo "█                                                           █"
echo "█  Version: OpenClaw v2026.3.8                             █"
echo "█  Gateway Mode: ${GATEWAY_MODE}                              █"
echo "█  Gateway Bind: ${GATEWAY_BIND}                                █"
echo "█  Port: ${PORT}                                             █"
echo "█                                                           █"
echo "█  Press CTRL+C untuk stop                                 █"
echo "█                                                           █"
echo "███████████████████████████████████████████████████████████"
echo -e "${NC}"

log_info "Starting gateway in 2 seconds..."
sleep 2

# Start gateway dalam foreground
# Menggunakan exec agar process ini replace shell script
log_info "Launching: openclaw gateway start"
exec openclaw gateway start

# Note: Jika sampai sini, berarti gateway error atau exit
log_error "Gateway telah berhenti!"
exit 1
