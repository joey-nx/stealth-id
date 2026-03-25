// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "erc8004/IdentityRegistryUpgradeable.sol";
import "erc8004/ReputationRegistryUpgradeable.sol";
import "erc8004/ValidationRegistryUpgradeable.sol";
import "erc8004/HardhatMinimalUUPS.sol";
import "erc8004/ERC1967Proxy.sol";

/**
 * @title ERC8004IntegrationTest
 * @notice StealthID의 ERC-8004 통합 테스트
 *         Upgradeable proxy pattern으로 배포 후 Agent 등록, 메타데이터, 평판, 검증 flow 검증
 */
contract ERC8004IntegrationTest is Test {
    IdentityRegistryUpgradeable public identity;
    ReputationRegistryUpgradeable public reputation;
    ValidationRegistryUpgradeable public validation;

    address public deployer = address(0x1);
    address public agentOwner = address(0x2);
    address public serviceA = address(0x3);
    address public validator = address(0x4);

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy implementations
        HardhatMinimalUUPS minimalImpl = new HardhatMinimalUUPS();
        IdentityRegistryUpgradeable identityImpl = new IdentityRegistryUpgradeable();
        ReputationRegistryUpgradeable reputationImpl = new ReputationRegistryUpgradeable();
        ValidationRegistryUpgradeable validationImpl = new ValidationRegistryUpgradeable();

        // Deploy proxies with MinimalUUPS
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

        // Upgrade to real implementations
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

        // Cast proxies to their interfaces
        identity = IdentityRegistryUpgradeable(address(identityProxy));
        reputation = ReputationRegistryUpgradeable(address(reputationProxy));
        validation = ValidationRegistryUpgradeable(address(validationProxy));

        vm.stopPrank();
    }

    // ============ Identity Registry ============

    function test_RegisterAgent() public {
        vm.startPrank(agentOwner);

        uint256 agentId = identity.register("https://example.com/agent.json");

        assertEq(identity.ownerOf(agentId), agentOwner);
        assertEq(identity.tokenURI(agentId), "https://example.com/agent.json");
        assertEq(identity.getVersion(), "2.0.0");

        vm.stopPrank();
    }

    function test_RegisterAgentWithMetadata() public {
        vm.startPrank(agentOwner);

        IdentityRegistryUpgradeable.MetadataEntry[] memory metadata =
            new IdentityRegistryUpgradeable.MetadataEntry[](2);
        metadata[0] = IdentityRegistryUpgradeable.MetadataEntry("type", abi.encode("stealth-id-agent"));
        metadata[1] = IdentityRegistryUpgradeable.MetadataEntry("version", abi.encode("1.0.0"));

        uint256 agentId = identity.register("https://example.com/agent.json", metadata);

        assertEq(
            abi.decode(identity.getMetadata(agentId, "type"), (string)),
            "stealth-id-agent"
        );
        assertEq(
            abi.decode(identity.getMetadata(agentId, "version"), (string)),
            "1.0.0"
        );

        vm.stopPrank();
    }

    function test_SetMetadata_SponsorCommitment() public {
        vm.startPrank(agentOwner);

        uint256 agentId = identity.register("https://example.com/agent.json");

        // StealthID-specific: store sponsor commitment hash as metadata
        bytes32 sponsorCommitment = keccak256(abi.encode("sponsor-identity-hash"));
        identity.setMetadata(agentId, "sponsorCommitment", abi.encode(sponsorCommitment));

        bytes32 stored = abi.decode(identity.getMetadata(agentId, "sponsorCommitment"), (bytes32));
        assertEq(stored, sponsorCommitment);

        vm.stopPrank();
    }

    function test_UpdateAgentURI() public {
        vm.startPrank(agentOwner);

        uint256 agentId = identity.register("https://old.com/agent.json");
        identity.setAgentURI(agentId, "https://new.com/agent.json");

        assertEq(identity.tokenURI(agentId), "https://new.com/agent.json");

        vm.stopPrank();
    }

    function test_AgentWallet() public {
        vm.startPrank(agentOwner);

        uint256 agentId = identity.register("https://example.com/agent.json");

        // agentWallet should be auto-set to msg.sender on register
        assertEq(identity.getAgentWallet(agentId), agentOwner);

        vm.stopPrank();
    }

    function test_RegisterMultipleAgents() public {
        vm.startPrank(agentOwner);

        uint256 agent1 = identity.register("https://example.com/agent1.json");
        uint256 agent2 = identity.register("https://example.com/agent2.json");

        assertTrue(agent1 != agent2);

        vm.stopPrank();
    }

    function test_OnlyOwnerCanSetMetadata() public {
        vm.prank(agentOwner);
        uint256 agentId = identity.register("https://example.com/agent.json");

        // Non-owner should revert
        vm.prank(serviceA);
        vm.expectRevert("Not authorized");
        identity.setMetadata(agentId, "key", abi.encode("value"));
    }

    // ============ Reputation Registry ============

    function test_GiveFeedback() public {
        vm.prank(agentOwner);
        uint256 agentId = identity.register("https://example.com/agent.json");

        // Service A gives positive feedback
        vm.prank(serviceA);
        reputation.giveFeedback(
            agentId,
            85,     // value: 85/100
            0,      // decimals
            "reliability",
            "stealth-id",
            "https://service-a.com",
            "",
            bytes32(0)
        );

        // Check feedback was recorded
        (uint64 count, int128 summaryValue, uint8 summaryDecimals) = reputation.getSummary(
            agentId,
            _toAddressArray(serviceA),
            "reliability",
            "stealth-id"
        );
        assertEq(count, 1);
        assertEq(summaryValue, 85);
        assertEq(summaryDecimals, 0);
    }

    function test_SelfFeedbackReverts() public {
        vm.prank(agentOwner);
        uint256 agentId = identity.register("https://example.com/agent.json");

        // Owner trying to give self-feedback should revert
        vm.prank(agentOwner);
        vm.expectRevert("Self-feedback not allowed");
        reputation.giveFeedback(agentId, 100, 0, "", "", "", "", bytes32(0));
    }

    // ============ Validation Registry ============

    function test_ValidationFlow() public {
        vm.prank(agentOwner);
        uint256 agentId = identity.register("https://example.com/agent.json");

        bytes32 requestHash = keccak256(abi.encode("validation-request-1"));

        // Owner requests validation
        vm.prank(agentOwner);
        validation.validationRequest(
            validator,
            agentId,
            "https://example.com/request",
            requestHash
        );

        // Validator responds
        vm.prank(validator);
        validation.validationResponse(
            requestHash,
            100,    // 100 = pass
            "https://example.com/response",
            keccak256(abi.encode("response-data")),
            "stealth-id-kyc"
        );

        // Check validation status
        (,,uint8 response,,,) = validation.getValidationStatus(requestHash);
        assertEq(response, 100);
    }

    function test_UnauthorizedValidationRequestReverts() public {
        vm.prank(agentOwner);
        uint256 agentId = identity.register("https://example.com/agent.json");

        bytes32 requestHash = keccak256(abi.encode("unauth-request"));

        // Non-owner trying to request validation should revert
        vm.prank(serviceA);
        vm.expectRevert("Not authorized");
        validation.validationRequest(validator, agentId, "", requestHash);
    }

    // ============ StealthID-Specific Integration ============

    function test_AgentRegistrationWithDelegation() public {
        // 1. Human sponsor registers an agent
        vm.startPrank(agentOwner);

        IdentityRegistryUpgradeable.MetadataEntry[] memory metadata =
            new IdentityRegistryUpgradeable.MetadataEntry[](3);
        metadata[0] = IdentityRegistryUpgradeable.MetadataEntry("protocol", abi.encode("stealth-id"));
        metadata[1] = IdentityRegistryUpgradeable.MetadataEntry(
            "sponsorCommitment",
            abi.encode(keccak256(abi.encode("human-identity-commitment")))
        );
        metadata[2] = IdentityRegistryUpgradeable.MetadataEntry(
            "delegationScope",
            abi.encode("defi-trading")
        );

        uint256 agentId = identity.register("https://agent.stealth-id.xyz/meta.json", metadata);

        // 2. Verify all metadata is accessible
        assertEq(
            abi.decode(identity.getMetadata(agentId, "protocol"), (string)),
            "stealth-id"
        );
        assertEq(
            abi.decode(identity.getMetadata(agentId, "delegationScope"), (string)),
            "defi-trading"
        );

        // 3. Owner requests validation
        bytes32 reqHash = keccak256(abi.encode("validate-agent", agentId));
        validation.validationRequest(validator, agentId, "", reqHash);

        vm.stopPrank();

        // 4. Validator responds
        vm.prank(validator);
        validation.validationResponse(reqHash, 100, "", bytes32(0), "delegation-check");

        // 5. Service gives reputation feedback
        vm.prank(serviceA);
        reputation.giveFeedback(
            agentId, 90, 0,
            "delegation-compliance", "stealth-id",
            "", "", bytes32(0)
        );

        // Verify the full flow
        (,,uint8 resp,,,) = validation.getValidationStatus(reqHash);
        assertEq(resp, 100);
    }

    // ============ Proxy Verification ============

    function test_VersionAfterUpgrade() public view {
        assertEq(identity.getVersion(), "2.0.0");
        assertEq(reputation.getVersion(), "2.0.0");
        assertEq(validation.getVersion(), "2.0.0");
    }

    function test_ReputationLinkedToIdentity() public view {
        assertEq(reputation.getIdentityRegistry(), address(identity));
    }

    function test_ValidationLinkedToIdentity() public view {
        assertEq(validation.getIdentityRegistry(), address(identity));
    }

    // ============ Helpers ============

    function _toAddressArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }
}
