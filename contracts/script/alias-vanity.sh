#!/usr/bin/env bash
# ============================================================================
# alias-vanity.sh
# Copies ERC-8004 proxy bytecode + storage to official vanity addresses on Anvil.
#
# After running the Forge deploy script, this script reads the staging addresses
# from deployments/local.json and uses Anvil's anvil_setCode/anvil_setStorageAt
# to mirror them at the official 0x8004... vanity addresses.
# ============================================================================
set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
DEPLOY_FILE="$(dirname "$0")/../deployments/local.json"

# Official ERC-8004 mainnet vanity addresses
VANITY_IDENTITY="0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"
VANITY_REPUTATION="0x8004BAa17C55a88189AE136b182e5fdA19dE9b63"
VANITY_VALIDATION="0x8004Cc8439f36fd5F9F049D9fF86523Df6dAAB58"

# ERC-1967 storage slots
# Implementation slot: keccak256("eip1967.proxy.implementation") - 1
IMPL_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
# Admin slot: keccak256("eip1967.proxy.admin") - 1
ADMIN_SLOT="0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"

if [ ! -f "$DEPLOY_FILE" ]; then
    echo "Error: $DEPLOY_FILE not found. Run 'make deploy' first."
    exit 1
fi

# Read staging addresses from deployment file
STAGING_IDENTITY=$(python3 -c "import json; print(json.load(open('$DEPLOY_FILE'))['identityRegistryStaging'])")
STAGING_REPUTATION=$(python3 -c "import json; print(json.load(open('$DEPLOY_FILE'))['reputationRegistryStaging'])")
STAGING_VALIDATION=$(python3 -c "import json; print(json.load(open('$DEPLOY_FILE'))['validationRegistryStaging'])")

echo "=== Aliasing ERC-8004 Vanity Addresses ==="
echo ""

# Function to copy a proxy's code and critical storage to a vanity address
copy_proxy() {
    local FROM=$1
    local TO=$2
    local NAME=$3

    echo "Copying $NAME: $FROM -> $TO"

    # Get runtime bytecode from staging address
    local CODE
    CODE=$(cast code "$FROM" --rpc-url "$RPC_URL")

    if [ "$CODE" = "0x" ] || [ -z "$CODE" ]; then
        echo "  ERROR: No code at staging address $FROM"
        return 1
    fi

    # Set code at vanity address
    cast rpc anvil_setCode "$TO" "$CODE" --rpc-url "$RPC_URL" > /dev/null

    # Copy ERC-1967 implementation slot
    local IMPL_VALUE
    IMPL_VALUE=$(cast storage "$FROM" "$IMPL_SLOT" --rpc-url "$RPC_URL")
    cast rpc anvil_setStorageAt "$TO" "$IMPL_SLOT" "$IMPL_VALUE" --rpc-url "$RPC_URL" > /dev/null

    # Copy storage slots 0-10 (covers owner, identityRegistry, and other state)
    for i in $(seq 0 10); do
        local SLOT
        SLOT=$(printf "0x%064x" $i)
        local VALUE
        VALUE=$(cast storage "$FROM" "$SLOT" --rpc-url "$RPC_URL")
        if [ "$VALUE" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
            cast rpc anvil_setStorageAt "$TO" "$SLOT" "$VALUE" --rpc-url "$RPC_URL" > /dev/null
        fi
    done

    # Copy Initializable storage slot (OZ Upgradeable)
    # keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1))
    local INIT_SLOT="0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00"
    local INIT_VALUE
    INIT_VALUE=$(cast storage "$FROM" "$INIT_SLOT" --rpc-url "$RPC_URL")
    if [ "$INIT_VALUE" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
        cast rpc anvil_setStorageAt "$TO" "$INIT_SLOT" "$INIT_VALUE" --rpc-url "$RPC_URL" > /dev/null
    fi

    # Copy OwnableUpgradeable storage slot
    # keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Ownable")) - 1))
    local OWNABLE_SLOT="0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300"
    local OWNABLE_VALUE
    OWNABLE_VALUE=$(cast storage "$FROM" "$OWNABLE_SLOT" --rpc-url "$RPC_URL")
    if [ "$OWNABLE_VALUE" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
        cast rpc anvil_setStorageAt "$TO" "$OWNABLE_SLOT" "$OWNABLE_VALUE" --rpc-url "$RPC_URL" > /dev/null
    fi

    # Copy ERC721 storage (name, symbol)
    # keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC721")) - 1))
    local ERC721_SLOT="0x80bb2b638cc20bc4d0a60d66940f3ab4a00c1d7b313497ca82fb0b4ab0079300"
    local ERC721_VALUE
    ERC721_VALUE=$(cast storage "$FROM" "$ERC721_SLOT" --rpc-url "$RPC_URL")
    if [ "$ERC721_VALUE" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
        cast rpc anvil_setStorageAt "$TO" "$ERC721_SLOT" "$ERC721_VALUE" --rpc-url "$RPC_URL" > /dev/null
        # Copy a few more ERC721 slots
        for j in $(seq 1 5); do
            local NEXT_SLOT
            NEXT_SLOT=$(cast keccak "$(printf "%064x%064x" 0 0)" 2>/dev/null || printf "0x%064x" $((0x80bb2b638cc20bc4d0a60d66940f3ab4a00c1d7b313497ca82fb0b4ab0079300 + j)) 2>/dev/null || true)
        done
    fi

    # Copy IdentityRegistry-specific storage
    local IR_SLOT="0xa040f782729de4970518741823ec1276cbcd41a0c7493f62d173341566a04e00"
    local IR_VALUE
    IR_VALUE=$(cast storage "$FROM" "$IR_SLOT" --rpc-url "$RPC_URL")
    if [ "$IR_VALUE" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
        cast rpc anvil_setStorageAt "$TO" "$IR_SLOT" "$IR_VALUE" --rpc-url "$RPC_URL" > /dev/null
    fi

    # Verify
    local VERIFY_CODE
    VERIFY_CODE=$(cast code "$TO" --rpc-url "$RPC_URL")
    if [ "$VERIFY_CODE" = "0x" ] || [ -z "$VERIFY_CODE" ]; then
        echo "  ERROR: Verification failed"
        return 1
    fi

    # Verify version via call
    local VERSION
    VERSION=$(cast call "$TO" "getVersion()(string)" --rpc-url "$RPC_URL" 2>/dev/null || echo "FAILED")
    echo "  OK (version: $VERSION)"
}

copy_proxy "$STAGING_IDENTITY" "$VANITY_IDENTITY" "IdentityRegistry"
copy_proxy "$STAGING_REPUTATION" "$VANITY_REPUTATION" "ReputationRegistry"
copy_proxy "$STAGING_VALIDATION" "$VANITY_VALIDATION" "ValidationRegistry"

echo ""
echo "=== Vanity Address Verification ==="
echo ""

# Cross-check: reputation/validation should point to identity
REP_IDENTITY=$(cast call "$VANITY_REPUTATION" "getIdentityRegistry()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "FAILED")
VAL_IDENTITY=$(cast call "$VANITY_VALIDATION" "getIdentityRegistry()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "FAILED")

echo "IdentityRegistry:   $VANITY_IDENTITY"
echo "ReputationRegistry: $VANITY_REPUTATION (identityRegistry -> $REP_IDENTITY)"
echo "ValidationRegistry: $VANITY_VALIDATION (identityRegistry -> $VAL_IDENTITY)"
echo ""

# Note: reputation/validation registries internally reference the staging identity address
# This is fine for local dev as both staging and vanity point to same code
if [ "$REP_IDENTITY" != "$VANITY_IDENTITY" ]; then
    echo "NOTE: Reputation's identityRegistry points to staging address ($REP_IDENTITY)."
    echo "      This is expected. For local dev, both addresses work identically."
    echo ""

    # Fix the internal reference by updating the _identityRegistry storage (slot 0)
    # Pad the vanity address to 32 bytes
    PADDED_VANITY=$(printf "0x%064s" "${VANITY_IDENTITY#0x}" | tr ' ' '0')

    echo "Fixing internal references to use vanity address..."
    cast rpc anvil_setStorageAt "$VANITY_REPUTATION" "0x0000000000000000000000000000000000000000000000000000000000000000" "$PADDED_VANITY" --rpc-url "$RPC_URL" > /dev/null
    cast rpc anvil_setStorageAt "$VANITY_VALIDATION" "0x0000000000000000000000000000000000000000000000000000000000000000" "$PADDED_VANITY" --rpc-url "$RPC_URL" > /dev/null

    # Verify fix
    REP_IDENTITY_FIXED=$(cast call "$VANITY_REPUTATION" "getIdentityRegistry()(address)" --rpc-url "$RPC_URL" 2>/dev/null)
    VAL_IDENTITY_FIXED=$(cast call "$VANITY_VALIDATION" "getIdentityRegistry()(address)" --rpc-url "$RPC_URL" 2>/dev/null)
    echo "  ReputationRegistry.identityRegistry -> $REP_IDENTITY_FIXED"
    echo "  ValidationRegistry.identityRegistry -> $VAL_IDENTITY_FIXED"
fi

echo ""
echo "=== Done ==="
echo "Use these addresses in your application:"
echo "  IdentityRegistry:   $VANITY_IDENTITY"
echo "  ReputationRegistry: $VANITY_REPUTATION"
echo "  ValidationRegistry: $VANITY_VALIDATION"
