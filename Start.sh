#!/bin/bash

################################################################################
# OpenClaw Startup Script untuk Railway
# Didesain untuk menjalankan OpenClaw gateway di container environment
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

# Timeout untuk health check (detik)
HEALTH_CHECK_TIMEOUT=30

log_divider
echo -e "${BLUE}🦞 OPENCLAW STARTUP SCRIPT 🦞${NC}"
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
# STEP 3: VERIFIKASI DAN SETUP KONFIGURASI
# ============================================================================

log_info "Step 3: Setup konfigurasi OpenClaw..."

if [ -f "${CONFIG_FILE}" ]; then
    log_warning "  File config sudah ada"
    log_info "  Backup ke: ${CONFIG_FILE}.backup"
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup"
    log_success "  Backup dibuat"
fi

# Create config baru
log_info "  Membuat config baru dengan port: ${PORT}"

cat > "${CONFIG_FILE}" <<EOF
{
  "port": ${PORT},
  "wrapper": {
    "node": "v22.22.2",
    "port": ${PORT},
    "publicPortEnv": "${PORT}",
    "stateDir": "${CONFIG_DIR}",
    "workspaceDir": "${WORKSPACE_DIR}",
    "configured": true
  },
  "gateway": {
    "mode": "${GATEWAY_MODE}",
    "bind": "0.0.0.0"
  }
}
EOF

log_success "  Config file dibuat: ${CONFIG_FILE}"

# Verifikasi config
if [ -f "${CONFIG_FILE}" ]; then
    log_success "  ✓ Config file verified"
else
    log_error "  ✗ Gagal membuat config file!"
    exit 1
fi

# ============================================================================
# STEP 4: JALANKAN OPENCLAW DOCTOR
# ============================================================================

log_info "Step 4: Menjalankan OpenClaw doctor..."

if openclaw doctor --fix; then
    log_success "  Doctor fix berhasil"
else
    log_warning "  Doctor fix menghasilkan warning (melanjutkan...)"
fi

log_info "  Hasil doctor check:"
openclaw doctor 2>&1 | sed 's/^/    /'

# ============================================================================
# STEP 5: VALIDASI PORT
# ============================================================================

log_info "Step 5: Validasi port ${PORT}..."

# Fungsi untuk cek port (menggunakan nc atau bash)
check_port() {
    if command -v nc &> /dev/null; then
        nc -z 127.0.0.1 $1 2>/dev/null && return 0 || return 1
    elif command -v timeout &> /dev/null; then
        timeout 1 bash -c "echo >/dev/tcp/127.0.0.1/$1" 2>/dev/null && return 0 || return 1
    else
        return 1
    fi
}

if check_port "${PORT}"; then
    log_warning "  Port ${PORT} sedang terpakai"
    log_info "  Mencoba port alternatif..."
    
    for ALT_PORT in 3001 3002 8000 8001 5000; do
        if ! check_port "${ALT_PORT}"; then
            log_success "  Port ${ALT_PORT} tersedia, switch menggunakan port ini"
            PORT="${ALT_PORT}"
            
            # Update config dengan port baru
            sed -i "s/\"port\": [0-9]*,/\"port\": ${PORT},/g" "${CONFIG_FILE}"
            break
        fi
    done
fi

log_success "  Port ${PORT} siap digunakan"

# ============================================================================
# STEP 6: INFORMASI STARTUP
# ============================================================================

log_divider
log_info "📊 INFORMASI STARTUP:"
log_info "  - Port: ${PORT}"
log_info "  - Gateway Mode: ${GATEWAY_MODE}"
log_info "  - Config: ${CONFIG_FILE}"
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
echo "█  Listening on: http://0.0.0.0:${PORT}                     █"
echo "█  Gateway Mode: ${GATEWAY_MODE}                              █"
echo "█                                                           █"
echo "█  Press CTRL+C untuk stop                                 █"
echo "█                                                           █"
echo "███████████████████████████████████████████████████████████"
echo -e "${NC}"

# Start gateway dalam foreground
# Menggunakan exec agar process ini replace shell script
exec openclaw gateway start

# Note: Jika sampai sini, berarti gateway error atau exit
log_error "Gateway telah berhenti!"
exit 1
