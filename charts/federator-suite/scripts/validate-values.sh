#!/bin/bash
# Script to automatically set kafka.enabled and valkey.enabled based on external flag
# Usage: source this before helm install/upgrade

set -e

VALUES_FILE="${1:-values/kafka.yaml}"

# Function to auto-set enabled flag
auto_set_enabled() {
    local component=$1
    local values_file=$2
    
    if ! command -v yq &> /dev/null; then
        echo "WARNING: yq not found. Cannot auto-set ${component}.enabled flag."
        echo "Please manually ensure ${component}.enabled = !${component}.external"
        return 0
    fi
    
    # Read external flag
    external=$(yq eval ".${component}.external" "$values_file" 2>/dev/null || echo "false")
    
    # Set enabled to inverse of external
    if [ "$external" = "true" ]; then
        enabled="false"
    else
        enabled="true"
    fi
    
    echo "Auto-setting ${component}.enabled=${enabled} (based on ${component}.external=${external})"
    yq eval -i ".${component}.enabled = ${enabled}" "$values_file"
}

# Process kafka and valkey
if [ -f "values/kafka.yaml" ]; then
    auto_set_enabled "kafka" "values/kafka.yaml"
fi

if [ -f "values/valkey.yaml" ]; then
    auto_set_enabled "valkey" "values/valkey.yaml"
fi

echo "Values validation complete"
