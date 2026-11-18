#!/bin/bash
# Generate self-signed certificates for Federator Suite
# Usage: ./scripts/generate-certs.sh [org] [secrets-file]
#
# org should be: org1 (BCC), org2 (ENV), org3 (HEG), or LOCAL (default)
#
# This script generates:
# - CA certificate and key
# - Server keystore (JKS) and P12
# - Client keystore (JKS) and P12
# - Truststore (JKS) with CA certificate
#
# All files are output to ./certs/ directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ============================================
# Configuration
# ============================================
ORG="${1:-LOCAL}"
SECRETS_FILE="${2:-${ROOT_DIR}/values/overrides/local/secrets.yaml}"

CERTS_DIR="${ROOT_DIR}/certs/${ORG}"
VALIDITY_DAYS=365
KEY_SIZE=2048

# Passwords are loaded from the overrides secrets file (not hardcoded)
CA_PASSWORD=""
SERVER_KEYSTORE_PASSWORD=""
SERVER_P12_PASSWORD=""
CLIENT_KEYSTORE_PASSWORD=""
CLIENT_P12_PASSWORD=""
TRUSTSTORE_PASSWORD=""

# Certificate details
CA_SUBJECT="/C=UK/ST=England/L=London/O=NDTP/OU=Federation/CN=Federator CA ${ORG}"
SERVER_SUBJECT="/C=UK/ST=England/L=London/O=NDTP/OU=Federation/CN=federator-server.ia-federation.svc.cluster.local"
CLIENT_SUBJECT="/C=UK/ST=England/L=London/O=NDTP/OU=Federation/CN=federator-client-${ORG}"

# ============================================
# Functions
# ============================================

log() {
    echo "==> $1"
}

error() {
    echo "ERROR: $1" >&2
    exit 1
}
check_dependencies() {
    local missing=0
    
    if ! command -v openssl &> /dev/null; then
        echo "ERROR: openssl is not installed"
        missing=1
    fi
    
    if ! command -v keytool &> /dev/null; then
        echo "ERROR: keytool is not installed (install JDK)"
        missing=1
    fi

    if ! command -v yq &> /dev/null; then
        echo "ERROR: yq is not installed (https://mikefarah.gitbook.io/yq/)"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        error "Missing required dependencies"
    fi
}

load_passwords_from_secrets() {
    log "Loading certificate passwords from ${SECRETS_FILE}"

    SERVER_KEYSTORE_PASSWORD="$(yq -e '.secrets.certificates.external.serverKeystorePassword' "${SECRETS_FILE}")"
    SERVER_P12_PASSWORD="$(yq -e '.secrets.certificates.external.serverP12Password' "${SECRETS_FILE}")"
    CLIENT_KEYSTORE_PASSWORD="$(yq -e '.secrets.certificates.external.clientKeystorePassword' "${SECRETS_FILE}")"
    CLIENT_P12_PASSWORD="$(yq -e '.secrets.certificates.external.clientP12Password' "${SECRETS_FILE}")"
    TRUSTSTORE_PASSWORD="$(yq -e '.secrets.certificates.external.truststorePassword' "${SECRETS_FILE}")"
}

create_ca() {
    log "Creating Certificate Authority (CA)"
    
    # Generate CA private key
    openssl genrsa -out "${CERTS_DIR}/ca-key.pem" ${KEY_SIZE}
    
    # Generate CA certificate
    openssl req -new -x509 \
        -key "${CERTS_DIR}/ca-key.pem" \
        -out "${CERTS_DIR}/ca-cert.pem" \
        -days ${VALIDITY_DAYS} \
        -subj "${CA_SUBJECT}"
    
    log "✓ CA certificate created"
}

create_server_certs() {
    log "Creating Server certificates"
    
    # Generate server private key
    openssl genrsa -out "${CERTS_DIR}/server-key.pem" ${KEY_SIZE}
    
    # Generate server certificate signing request (CSR)
    openssl req -new \
        -key "${CERTS_DIR}/server-key.pem" \
        -out "${CERTS_DIR}/server.csr" \
        -subj "${SERVER_SUBJECT}"
    
    # Create extensions file for SAN
    cat > "${CERTS_DIR}/server-ext.cnf" <<EOF
subjectAltName = @alt_names
[alt_names]
DNS.1 = federator-server
DNS.2 = federator-server.ia-federation
DNS.3 = federator-server.ia-federation.svc
DNS.4 = federator-server.ia-federation.svc.cluster.local
DNS.5 = localhost
IP.1 = 127.0.0.1
EOF
    
    # Sign server certificate with CA
    openssl x509 -req \
        -in "${CERTS_DIR}/server.csr" \
        -CA "${CERTS_DIR}/ca-cert.pem" \
        -CAkey "${CERTS_DIR}/ca-key.pem" \
        -CAcreateserial \
        -out "${CERTS_DIR}/server-cert.pem" \
        -days ${VALIDITY_DAYS} \
        -extfile "${CERTS_DIR}/server-ext.cnf"
    
    # Create PKCS12 bundle (server cert + key)
    openssl pkcs12 -export \
        -in "${CERTS_DIR}/server-cert.pem" \
        -inkey "${CERTS_DIR}/server-key.pem" \
        -out "${CERTS_DIR}/dev-ndtp.p12" \
        -name "server" \
        -password "pass:${SERVER_P12_PASSWORD}"
    
    # Convert PKCS12 to JKS keystore
    keytool -importkeystore \
        -srckeystore "${CERTS_DIR}/dev-ndtp.p12" \
        -srcstoretype PKCS12 \
        -srcstorepass "${SERVER_P12_PASSWORD}" \
        -destkeystore "${CERTS_DIR}/ndtp-keystore.jks" \
        -deststoretype JKS \
        -deststorepass "${SERVER_KEYSTORE_PASSWORD}" \
        -noprompt
    
    log "✓ Server certificates created"
}

create_client_certs() {
    log "Creating Client certificates"
    
    # Generate client private key
    openssl genrsa -out "${CERTS_DIR}/client-key.pem" ${KEY_SIZE}
    
    # Generate client CSR
    openssl req -new \
        -key "${CERTS_DIR}/client-key.pem" \
        -out "${CERTS_DIR}/client.csr" \
        -subj "${CLIENT_SUBJECT}"
    
    # Sign client certificate with CA
    openssl x509 -req \
        -in "${CERTS_DIR}/client.csr" \
        -CA "${CERTS_DIR}/ca-cert.pem" \
        -CAkey "${CERTS_DIR}/ca-key.pem" \
        -CAcreateserial \
        -out "${CERTS_DIR}/client-cert.pem" \
        -days ${VALIDITY_DAYS}
    
    # Create PKCS12 bundle (client cert + key)
    openssl pkcs12 -export \
        -in "${CERTS_DIR}/client-cert.pem" \
        -inkey "${CERTS_DIR}/client-key.pem" \
        -out "${CERTS_DIR}/client-${ORG}.p12" \
        -name "client" \
        -password "pass:${CLIENT_P12_PASSWORD}"
    
    # Convert PKCS12 to JKS keystore (IDP keystore)
    keytool -importkeystore \
        -srckeystore "${CERTS_DIR}/client-${ORG}.p12" \
        -srcstoretype PKCS12 \
        -srcstorepass "${CLIENT_P12_PASSWORD}" \
        -destkeystore "${CERTS_DIR}/client-${ORG}-keystore.jks" \
        -deststoretype JKS \
        -deststorepass "${CLIENT_KEYSTORE_PASSWORD}" \
        -noprompt
    
    log "✓ Client certificates created"
}

create_truststore() {
    log "Creating Truststore"

    # Always recreate to avoid alias conflicts on reruns
    if [ -f "${CERTS_DIR}/keycloak.truststore.jks" ]; then
        rm -f "${CERTS_DIR}/keycloak.truststore.jks"
    fi
    
    # Import CA certificate into truststore
    keytool -import \
        -file "${CERTS_DIR}/ca-cert.pem" \
        -alias "ca" \
        -keystore "${CERTS_DIR}/keycloak.truststore.jks" \
        -storepass "${TRUSTSTORE_PASSWORD}" \
        -noprompt
    
    log "✓ Truststore created"
}

generate_base64_values() {
        log "Generating base64 encoded values and updating ${SECRETS_FILE}"

        local output_file="${CERTS_DIR}/secrets-base64.txt"

        TRUSTSTORE_JKS="$(base64 -w 0 "${CERTS_DIR}/keycloak.truststore.jks")"
        SERVER_KEYSTORE_JKS="$(base64 -w 0 "${CERTS_DIR}/ndtp-keystore.jks")"
        CLIENT_KEYSTORE_JKS="$(base64 -w 0 "${CERTS_DIR}/client-${ORG}-keystore.jks")"
        CLIENT_P12="$(base64 -w 0 "${CERTS_DIR}/client-${ORG}.p12")"
        SERVER_P12="$(base64 -w 0 "${CERTS_DIR}/dev-ndtp.p12")"

        export TRUSTSTORE_JKS SERVER_KEYSTORE_JKS CLIENT_KEYSTORE_JKS CLIENT_P12 SERVER_P12 \
                TRUSTSTORE_PASSWORD SERVER_KEYSTORE_PASSWORD CLIENT_KEYSTORE_PASSWORD CLIENT_P12_PASSWORD SERVER_P12_PASSWORD

        yq -i '
            .secrets.certificates.external.truststoreJks = strenv(TRUSTSTORE_JKS) |
            .secrets.certificates.external.truststorePassword = strenv(TRUSTSTORE_PASSWORD) |
            .secrets.certificates.external.serverKeystoreJks = strenv(SERVER_KEYSTORE_JKS) |
            .secrets.certificates.external.serverKeystorePassword = strenv(SERVER_KEYSTORE_PASSWORD) |
            .secrets.certificates.external.clientKeystoreJks = strenv(CLIENT_KEYSTORE_JKS) |
            .secrets.certificates.external.clientKeystorePassword = strenv(CLIENT_KEYSTORE_PASSWORD) |
            .secrets.certificates.external.clientP12 = strenv(CLIENT_P12) |
            .secrets.certificates.external.clientP12Password = strenv(CLIENT_P12_PASSWORD) |
            .secrets.certificates.external.serverP12 = strenv(SERVER_P12) |
            .secrets.certificates.external.serverP12Password = strenv(SERVER_P12_PASSWORD)
        ' "${SECRETS_FILE}"

        cat > "${output_file}" <<EOF
# Base64 encoded certificate values
# Copied automatically into ${SECRETS_FILE}; keep for reference only.

secrets:
    certificates:
        external:
            truststoreJks: "${TRUSTSTORE_JKS}"
            truststorePassword: "${TRUSTSTORE_PASSWORD}"
            serverKeystoreJks: "${SERVER_KEYSTORE_JKS}"
            serverKeystorePassword: "${SERVER_KEYSTORE_PASSWORD}"
            clientKeystoreJks: "${CLIENT_KEYSTORE_JKS}"
            clientKeystorePassword: "${CLIENT_KEYSTORE_PASSWORD}"
            clientP12: "${CLIENT_P12}"
            clientP12Password: "${CLIENT_P12_PASSWORD}"
            serverP12: "${SERVER_P12}"
            serverP12Password: "${SERVER_P12_PASSWORD}"
EOF

        log "✓ Updated ${SECRETS_FILE} and wrote reference copy to ${output_file}"
}

display_summary() {
    log "Certificate Generation Complete!"
    echo ""
    echo "Generated files in ${CERTS_DIR}:"
    echo "  CA:"
    echo "    - ca-cert.pem"
    echo "    - ca-key.pem"
    echo ""
    echo "  Server:"
    echo "    - ndtp-keystore.jks (password: ${SERVER_KEYSTORE_PASSWORD})"
    echo "    - dev-ndtp.p12 (password: ${SERVER_P12_PASSWORD})"
    echo "    - server-cert.pem"
    echo "    - server-key.pem"
    echo ""
    echo "  Client:"
    echo "    - client-${ORG}-keystore.jks (password: ${CLIENT_KEYSTORE_PASSWORD})"
    echo "    - client-${ORG}.p12 (password: ${CLIENT_P12_PASSWORD})"
    echo "    - client-cert.pem"
    echo "    - client-key.pem"
    echo ""
    echo "  Truststore:"
    echo "    - keycloak.truststore.jks (password: ${TRUSTSTORE_PASSWORD})"
    echo ""
    echo "Base64 values:"
    echo "  - Updated in: ${SECRETS_FILE}"
    echo "  - Reference copy: ${CERTS_DIR}/secrets-base64.txt"
    echo ""
    echo "Next steps:"
    echo "  1. Review ${SECRETS_FILE} (already updated)"
    echo "  2. Deploy with: make deploy-local"
}

# ============================================
# Main
# ============================================

main() {
    log "Generating certificates for organization: ${ORG}"
    
    # Check dependencies
    check_dependencies

    # Load passwords from the overrides secrets file
    load_passwords_from_secrets
    
    # Create output directory
    mkdir -p "${CERTS_DIR}"
    
    # Generate certificates
    create_ca
    create_server_certs
    create_client_certs
    create_truststore
    
    # Generate base64 encoded values
    generate_base64_values
    
    # Display summary
    display_summary
}

main
