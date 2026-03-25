// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "erc8004/IdentityRegistryUpgradeable.sol";
import "erc8004/ReputationRegistryUpgradeable.sol";
import "erc8004/ValidationRegistryUpgradeable.sol";
import "erc8004/HardhatMinimalUUPS.sol";
import "erc8004/ERC1967Proxy.sol";

/**
 * @title DeployERC8004
 * @notice Deploy ERC-8004 registries to local Anvil at official mainnet vanity addresses.
 *
 * Official ERC-8004 mainnet addresses:
 *   IdentityRegistry:   0x8004A169FB4a3325136EB29fA0ceB6D2e539a432
 *   ReputationRegistry: 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63
 *   ValidationRegistry: 0x8004Cc8439f36fd5F9F049D9fF86523Df6dAAB58
 *
 * Strategy: Deploy normally, then use Anvil cheatcodes to place the proxy
 * bytecode + storage at the vanity addresses.
 *
 * Usage:
 *   anvil &
 *   forge script script/DeployERC8004.s.sol:DeployERC8004 \
 *     --rpc-url http://127.0.0.1:8545 --broadcast
 *   ./script/alias-vanity.sh   # copies to vanity addresses
 */
contract DeployERC8004 is Script {
    // Official ERC-8004 mainnet vanity addresses
    address constant VANITY_IDENTITY   = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant VANITY_REPUTATION = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63;
    address constant VANITY_VALIDATION = 0x8004Cc8439f36fd5F9F049D9fF86523Df6dAAB58;

    function run() external {
        // Anvil default account #0
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // ============================================================
        // Step 1: Deploy implementations
        // ============================================================
        HardhatMinimalUUPS minimalImpl = new HardhatMinimalUUPS();
        IdentityRegistryUpgradeable identityImpl = new IdentityRegistryUpgradeable();
        ReputationRegistryUpgradeable reputationImpl = new ReputationRegistryUpgradeable();
        ValidationRegistryUpgradeable validationImpl = new ValidationRegistryUpgradeable();

        // ============================================================
        // Step 2: Deploy proxies
        // ============================================================
        ERC1967Proxy identityProxy = new ERC1967Proxy(
            address(minimalImpl),
            abi.encodeCall(HardhatMinimalUUPS.initialize, (address(0)))
        );

        ERC1967Proxy reputationProxy = new ERC1967Proxy(
            address(minimalImpl),
            abi.encodeCall(HardhatMinimalUUPS.initialize, (address(identityProxy)))
        );

        ERC1967Proxy validationProxy = new ERC1967Proxy(
            address(minimalImpl),
            abi.encodeCall(HardhatMinimalUUPS.initialize, (address(identityProxy)))
        );

        // ============================================================
        // Step 3: Upgrade proxies to real implementations
        // ============================================================
        HardhatMinimalUUPS(address(identityProxy)).upgradeToAndCall(
            address(identityImpl),
            abi.encodeCall(IdentityRegistryUpgradeable.initialize, ())
        );

        HardhatMinimalUUPS(address(reputationProxy)).upgradeToAndCall(
            address(reputationImpl),
            abi.encodeCall(ReputationRegistryUpgradeable.initialize, (address(identityProxy)))
        );

        HardhatMinimalUUPS(address(validationProxy)).upgradeToAndCall(
            address(validationImpl),
            abi.encodeCall(ValidationRegistryUpgradeable.initialize, (address(identityProxy)))
        );

        vm.stopBroadcast();

        // ============================================================
        // Output
        // ============================================================
        console.log("\n=== ERC-8004 Local Deployment ===");
        console.log("Deployer:                ", deployer);
        console.log("");
        console.log("--- Staging Proxies (temporary) ---");
        console.log("IdentityRegistry:        ", address(identityProxy));
        console.log("ReputationRegistry:      ", address(reputationProxy));
        console.log("ValidationRegistry:      ", address(validationProxy));
        console.log("");
        console.log("--- Target Vanity Addresses ---");
        console.log("IdentityRegistry:        ", VANITY_IDENTITY);
        console.log("ReputationRegistry:      ", VANITY_REPUTATION);
        console.log("ValidationRegistry:      ", VANITY_VALIDATION);
        console.log("");
        console.log("--- Verification ---");
        console.log("Identity version:   ", IdentityRegistryUpgradeable(address(identityProxy)).getVersion());
        console.log("Reputation version: ", ReputationRegistryUpgradeable(address(reputationProxy)).getVersion());
        console.log("Validation version: ", ValidationRegistryUpgradeable(address(validationProxy)).getVersion());

        // Write both staging and vanity addresses to JSON
        string memory json = "deployment";
        vm.serializeAddress(json, "deployer", deployer);
        vm.serializeAddress(json, "identityRegistryImpl", address(identityImpl));
        vm.serializeAddress(json, "reputationRegistryImpl", address(reputationImpl));
        vm.serializeAddress(json, "validationRegistryImpl", address(validationImpl));
        // Staging addresses (actual deployed)
        vm.serializeAddress(json, "identityRegistryStaging", address(identityProxy));
        vm.serializeAddress(json, "reputationRegistryStaging", address(reputationProxy));
        vm.serializeAddress(json, "validationRegistryStaging", address(validationProxy));
        // Vanity addresses (what consumers should use)
        vm.serializeAddress(json, "identityRegistry", VANITY_IDENTITY);
        vm.serializeAddress(json, "reputationRegistry", VANITY_REPUTATION);
        string memory output = vm.serializeAddress(json, "validationRegistry", VANITY_VALIDATION);
        vm.writeJson(output, "./deployments/local.json");
        console.log("\nAddresses written to deployments/local.json");
        console.log("\nRun './script/alias-vanity.sh' to copy to vanity addresses");
    }
}
