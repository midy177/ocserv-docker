#!/bin/bash
set -euo pipefail

# =============================================================================
# OCServ Entrypoint Script - Optimized Version
# Features: Certificate caching, idempotent operations, better error handling
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly CERT_DIR="/opt/certs"
readonly CONFIG_DIR="/etc/ocserv"
readonly LOCK_FILE="/tmp/ocserv-init.lock"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# =============================================================================
# Utility Functions
# =============================================================================

# Generate random string (more secure than original)
gen_rand() {
    local length="${1:-32}"
    openssl rand -hex "$((length/2))" 2>/dev/null || \
        tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

# Check if file exists and is not empty
file_exists_and_not_empty() {
    [[ -f "$1" && -s "$1" ]]
}

# Atomic file operation (avoid race conditions)
atomic_file_write() {
    local temp_file="$1.tmp"
    local final_file="$1"
    
    cat > "$temp_file" && \
    mv "$temp_file" "$final_file"
}

# =============================================================================
# Certificate Management
# =============================================================================

generate_certificates() {
    log_info "Generating certificates..."
    
    # Use environment variables or generate defaults
    readonly CA_CN="${CA_CN:-ocserv-ca-$(gen_rand 8)}"
    readonly CA_ORG="${CA_ORG:-$(gen_rand 16)}"
    readonly SERV_DOMAIN="${SERV_DOMAIN:-$(gen_rand 12)}.local"
    readonly SERV_ORG="${SERV_ORG:-$(gen_rand 16)}"
    readonly USER_ID="${USER_ID:-$(gen_rand 8)}"
    readonly CERT_P12_PASS="${CERT_P12_PASS:-616}"

    log_info "Certificate parameters:"
    log_info "  CA_CN: $CA_CN"
    log_info "  CA_ORG: $CA_ORG"
    log_info "  SERV_DOMAIN: $SERV_DOMAIN"
    log_info "  SERV_ORG: $SERV_ORG"
    log_info "  USER_ID: $USER_ID"

    # Create certificates with proper error handling
    local cert_files=(
        "$CERT_DIR/ca-key.pem"
        "$CERT_DIR/ca-cert.pem"
        "$CERT_DIR/server-key.pem"
        "$CERT_DIR/server-cert.pem"
        "$CERT_DIR/user-key.pem"
        "$CERT_DIR/user-cert.pem"
        "$CERT_DIR/user.p12"
    )

    # CA Certificate
    log_info "Generating CA certificate..."
    certtool --generate-privkey --outfile "$CERT_DIR/ca-key.pem" || {
        log_error "Failed to generate CA private key"
        return 1
    }
    
    certtool --generate-self-signed \
        --load-privkey "$CERT_DIR/ca-key.pem" \
        --template "$CERT_DIR/ca-tmp" \
        --outfile "$CERT_DIR/ca-cert.pem" || {
        log_error "Failed to generate CA certificate"
        return 1
    }

    # Server Certificate
    log_info "Generating server certificate..."
    certtool --generate-privkey --outfile "$CERT_DIR/server-key.pem" || {
        log_error "Failed to generate server private key"
        return 1
    }
    
    certtool --generate-certificate \
        --load-privkey "$CERT_DIR/server-key.pem" \
        --load-ca-certificate "$CERT_DIR/ca-cert.pem" \
        --load-ca-privkey "$CERT_DIR/ca-key.pem" \
        --template "$CERT_DIR/serv-tmp" \
        --outfile "$CERT_DIR/server-cert.pem" || {
        log_error "Failed to generate server certificate"
        return 1
    }

    # User Certificate
    log_info "Generating user certificate..."
    certtool --generate-privkey --outfile "$CERT_DIR/user-key.pem" || {
        log_error "Failed to generate user private key"
        return 1
    }
    
    certtool --generate-certificate \
        --load-privkey "$CERT_DIR/user-key.pem" \
        --load-ca-certificate "$CERT_DIR/ca-cert.pem" \
        --load-ca-privkey "$CERT_DIR/ca-key.pem" \
        --template "$CERT_DIR/user-tmp" \
        --outfile "$CERT_DIR/user-cert.pem" || {
        log_error "Failed to generate user certificate"
        return 1
    }

    # PKCS12 certificate
    log_info "Generating PKCS12 certificate..."
    openssl pkcs12 -export \
        -inkey "$CERT_DIR/user-key.pem" \
        -in "$CERT_DIR/user-cert.pem" \
        -certfile "$CERT_DIR/ca-cert.pem" \
        -out "$CERT_DIR/user.p12" \
        -passout "pass:$CERT_P12_PASS" || {
        log_error "Failed to generate PKCS12 certificate"
        return 1
    }

    # Set proper permissions
    chmod 600 "$CERT_DIR"/*.pem
    chmod 644 "$CERT_DIR"/*.p12
    chmod 600 "$CERT_DIR"/*.key

    log_info "Certificates generated successfully"
}

# =============================================================================
# Network Setup Functions
# =============================================================================

setup_ipv4_forwarding() {
    log_info "Enabling IPv4 forwarding..."
    
    local current_value
    current_value=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    
    if [[ "$current_value" != "1" ]]; then
        sysctl -w net.ipv4.ip_forward=1 || {
            log_warn "Failed to enable IPv4 forwarding"
            return 1
        }
        log_info "IPv4 forwarding enabled (was: $current_value)"
    else
        log_info "IPv4 forwarding already enabled"
    fi
}

setup_tun_device() {
    log_info "Setting up TUN device..."
    
    if [[ ! -e /dev/net/tun ]]; then
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200 || {
            log_error "Failed to create /dev/net/tun device"
            return 1
        }
        chmod 600 /dev/net/tun
        log_info "TUN device created"
    else
        log_info "TUN device already exists"
    fi
}

# =============================================================================
# IPTables Management (Idempotent)
# =============================================================================

setup_iptables() {
    log_info "Setting up iptables rules..."
    
    # Extract VPN_CIDR from config
    local vpn_cidr
    vpn_cidr=$(extract_vpn_cidr_from_config)
    
    if [[ -z "$vpn_cidr" ]]; then
        log_warn "Could not extract VPN_CIDR from config"
        return 1
    fi
    
    log_info "Using VPN_CIDR: $vpn_cidr"
    
    # Setup NAT rules (idempotent)
    setup_nat_rules "$vpn_cidr"
    
    # Setup FORWARD rules (idempotent)
    setup_forward_rules "$vpn_cidr"
    
    # Setup MSS clamping (idempotent)
    setup_mss_clamping
    
    log_info "iptables rules configured"
}

setup_nat_rules() {
    local vpn_cidr="$1"
    
    # MASQUERADE rule (always at the end)
    if ! iptables -t nat -C POSTROUTING -s "$vpn_cidr" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -s "$vpn_cidr" -j MASQUERADE || {
            log_warn "Failed to add MASQUERADE rule for $vpn_cidr"
        }
        log_info "Added MASQUERADE rule for $vpn_cidr"
    else
        log_info "MASQUERADE rule already exists for $vpn_cidr"
    fi
    
    # Route mode NAT exemptions (if ROUTE_CIDRS is set)
    if [[ -n "${ROUTE_CIDRS:-}" ]]; then
        log_info "Route mode: Adding NAT exemptions"
        
        local route_cidr
        for route_cidr in $ROUTE_CIDRS; do
            if ! iptables -t nat -C POSTROUTING -s "$vpn_cidr" -d "$route_cidr" -j RETURN 2>/dev/null; then
                # Insert at position 1 to be evaluated before MASQUERADE
                iptables -t nat -I POSTROUTING 1 -s "$vpn_cidr" -d "$route_cidr" -j RETURN || {
                    log_warn "Failed to add RETURN rule for $route_cidr"
                }
                log_info "Added RETURN rule: $vpn_cidr -> $route_cidr"
            else
                log_info "RETURN rule already exists: $vpn_cidr -> $route_cidr"
            fi
        done
    fi
}

setup_forward_rules() {
    local vpn_cidr="$1"
    
    # Set default policies to ACCEPT first
    iptables -P INPUT ACCEPT 2>/dev/null || true
    iptables -P FORWARD ACCEPT 2>/dev/null || true
    iptables -P OUTPUT ACCEPT 2>/dev/null || true
    
    # Route mode specific FORWARD rules
    if [[ -n "${ROUTE_CIDRS:-}" ]]; then
        local route_cidr
        for route_cidr in $ROUTE_CIDRS; do
            if ! iptables -C FORWARD -s "$vpn_cidr" -d "$route_cidr" -j ACCEPT 2>/dev/null; then
                iptables -I FORWARD 1 -s "$vpn_cidr" -d "$route_cidr" -j ACCEPT || {
                    log_warn "Failed to add FORWARD rule for $route_cidr"
                }
                log_info "Added FORWARD rule: $vpn_cidr -> $route_cidr"
            fi
        done
    fi
}

setup_mss_clamping() {
    if ! iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
        iptables -t mangle -I FORWARD 1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || {
            log_warn "Failed to add MSS clamping rule"
        }
        log_info "Added TCP MSS clamping rule"
    fi
}

# =============================================================================
# Config Extraction (Improved)
# =============================================================================

extract_vpn_cidr_from_config() {
    local config_file="$CONFIG_DIR/ocserv.conf"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi
    
    # Try different methods to extract VPN CIDR
    local vpn_cidr
    
    # Method 1: Direct CIDR
    vpn_cidr=$(grep -E '^\.?cidr\s*=' "$config_file" | awk -F '=' '{gsub(/[[:space:]]+/, "", $2); print $2}' | head -1)
    
    # Method 2: ipv4-network + ipv4-netmask conversion
    if [[ -z "$vpn_cidr" ]]; then
        local network=$(grep -E '^\.?ipv4-network\s*=' "$config_file" | awk -F '=' '{gsub(/[[:space:]]+/, "", $2); print $2}' | head -1)
        local netmask=$(grep -E '^\.?ipv4-netmask\s*=' "$config_file" | awk -F '=' '{gsub(/[[:space:]]+/, "", $2); print $2}' | head -1)
        
        if [[ -n "$network" && -n "$netmask" ]]; then
            vpn_cidr=$(ipcalc "$network" "$netmask" | grep -E '^Network:' | awk '{print $2}' 2>/dev/null || echo "")
        fi
    fi
    
    # Method 3: Environment variable fallback
    if [[ -z "$vpn_cidr" && -n "${VPN_CIDR:-}" ]]; then
        vpn_cidr="$VPN_CIDR"
        log_info "Using VPN_CIDR from environment: $vpn_cidr"
    fi
    
    echo "$vpn_cidr"
}

# =============================================================================
# LDAP Setup (Improved)
# =============================================================================

setup_ldap() {
    log_info "Setting up LDAP configuration..."
    
    # Link LDAP config if exists
    local ldap_configs=(
        "$CONFIG_DIR/ldap.conf:/etc/ldap.conf"
        "$CONFIG_DIR/nslcd.conf:/etc/nslcd.conf"
    )
    
    local config_pair
    for config_pair in "${ldap_configs[@]}"; do
        local src="${config_pair%:*}"
        local dst="${config_pair#*:}"
        
        if [[ -f "$src" ]]; then
            ln -sf "$src" "$dst" && log_info "Linked $src to $dst"
        fi
    done
    
    # Start nslcd if config exists
    if [[ -f "$CONFIG_DIR/nslcd.conf" ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable nslcd 2>/dev/null || true
            systemctl start nslcd || log_warn "Failed to start nslcd"
        elif command -v service >/dev/null 2>&1; then
            service nslcd start || log_warn "Failed to start nslcd"
        else
            log_warn "No service manager found, please start nslcd manually"
        fi
    fi
}

# =============================================================================
# DNSMasq Setup (Optional)
# =============================================================================

setup_dnsmasq() {
    if ! command -v dnsmasq >/dev/null 2>&1; then
        log_info "dnsmasq not found. Skipping."
        return 0
    fi
    
    log_info "Setting up dnsmasq..."
    
    local dnsmasq_conf="/usr/local/etc/dnsmasq.conf"
    if [[ -f "$dnsmasq_conf" ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable dnsmasq 2>/dev/null || true
            systemctl start dnsmasq || log_warn "Failed to start dnsmasq"
        elif command -v service >/dev/null 2>&1; then
            service dnsmasq start || log_warn "Failed to start dnsmasq"
        else
            dnsmasq -C "$dnsmasq_conf" || log_warn "Failed to start dnsmasq"
        fi
    else
        log_info "dnsmasq config not found. Skipping."
    fi
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    log_info "Starting OCServ initialization..."
    
    # Check if already running (prevent concurrent execution)
    if [[ -f "$LOCK_FILE" ]]; then
        log_error "Another instance is already running"
        exit 1
    fi
    
    # Create lock file
    touch "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
    
    # Certificate generation (only if needed)
    if ! file_exists_and_not_empty "$CERT_DIR/server-cert.pem"; then
        generate_certificates
    else
        log_info "Certificates already exist. Skipping generation."
    fi
    
    # Network setup
    setup_ipv4_forwarding
    setup_tun_device
    
    # IPTables setup
    setup_iptables
    
    # LDAP setup
    setup_ldap
    
    # DNSMasq setup
    setup_dnsmasq
    
    log_info "OCServ initialization completed successfully"
    
    # Start OCServ
    log_info "Starting OpenConnect server..."
    exec ocserv -c "$CONFIG_DIR/ocserv.conf" -f "$@"
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi