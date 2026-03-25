# ERC-8004 Local Development
# ===========================

-include .env

ANVIL_RPC     := http://127.0.0.1:8545
ANVIL_KEY     := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEPLOY_SCRIPT := script/DeployERC8004.s.sol:DeployERC8004

.PHONY: build test anvil deploy alias clean addresses local gas

## Build contracts
build:
	forge build

## Run all tests
test:
	forge test -vv

## Start local Anvil node (foreground)
anvil:
	anvil --host 0.0.0.0 --block-time 1

## Deploy ERC-8004 registries to local Anvil
deploy: build
	@mkdir -p deployments
	PRIVATE_KEY=$(ANVIL_KEY) forge script $(DEPLOY_SCRIPT) \
		--rpc-url $(ANVIL_RPC) \
		--broadcast \
		-vvv

## Alias deployed proxies to official 0x8004... vanity addresses
alias:
	./script/alias-vanity.sh

## Full local setup: deploy + alias to vanity addresses
local: deploy alias
	@echo ""
	@echo "Ready! Use these addresses:"
	@echo "  IdentityRegistry:   0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"
	@echo "  ReputationRegistry: 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63"
	@echo "  ValidationRegistry: 0x8004Cc8439f36fd5F9F049D9fF86523Df6dAAB58"

## Clean build artifacts
clean:
	forge clean
	rm -rf out cache

## Show deployed addresses
addresses:
	@cat deployments/local.json 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "No deployment found. Run 'make local' first."

## Run gas report
gas:
	forge test --gas-report
