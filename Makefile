.PHONY: build test test-gas coverage fmt fmt-check slither clean deploy-arb

build:
	forge build

test:
	forge test -vvv

test-gas:
	forge test --gas-report

coverage:
	forge coverage --report summary --report lcov

fmt:
	forge fmt

fmt-check:
	forge fmt --check

slither:
	slither src/ --filter-paths lib/

clean:
	forge clean

deploy-arb:
	forge script script/Deploy.s.sol --rpc-url arbitrum_sepolia --broadcast --verify
