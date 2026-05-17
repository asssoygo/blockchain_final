// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {GovernanceToken} from "../src/token/GovernanceToken.sol";
import {GameItems} from "../src/token/GameItems.sol";
import {TokenVesting} from "../src/token/TokenVesting.sol";

import {AMMFactory} from "../src/amm/AMMFactory.sol";
import {MockERC20} from "../src/amm/MockERC20.sol";

import {YieldVault} from "../src/vault/YieldVault.sol";

import {PriceOracle} from "../src/oracle/PriceOracle.sol";

import {TreasuryV1} from "../src/treasury/TreasuryV1.sol";
import {TreasuryV2} from "../src/treasury/TreasuryV2.sol";

import {ProtocolTimelock} from "../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../src/governance/ProtocolGovernor.sol";
import {Box} from "../src/governance/Box.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deploy is Script {
    uint256 public constant TIMELOCK_DELAY = 2 days;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        MockERC20 asset = new MockERC20("Mock USD", "mUSD");
        MockERC20 tokenA = new MockERC20("Token A", "TKA");
        MockERC20 tokenB = new MockERC20("Token B", "TKB");

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        ProtocolTimelock timelock =
            new ProtocolTimelock(TIMELOCK_DELAY, proposers, executors, deployer);

        GovernanceToken govToken =
            new GovernanceToken(address(timelock), deployer, deployer);

        ProtocolGovernor governor =
            new ProtocolGovernor(govToken, timelock);

        TreasuryV1 treasuryImpl = new TreasuryV1();

        bytes memory initData =
            abi.encodeWithSelector(TreasuryV1.initialize.selector, address(timelock));

        ERC1967Proxy treasuryProxy =
            new ERC1967Proxy(address(treasuryImpl), initData);

        TreasuryV2 treasuryV2Impl = new TreasuryV2();

        AMMFactory ammFactory = new AMMFactory(address(timelock));

        GameItems gameItems = new GameItems(address(timelock));

        YieldVault vault =
            new YieldVault(IERC20(address(asset)), address(timelock));

        Box box = new Box(address(timelock));

        PriceOracle oracle = new PriceOracle(
    0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165,  // ETH/USD Arbitrum Sepolia
    3600,
    "ETH/USD",
    address(timelock)
);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, deployer);

        vm.stopBroadcast();

        console2.log("Deployer:", deployer);
        console2.log("Mock asset:", address(asset));
        console2.log("Token A:", address(tokenA));
        console2.log("Token B:", address(tokenB));
        console2.log("Timelock:", address(timelock));
        console2.log("GovernanceToken:", address(govToken));
        console2.log("Governor:", address(governor));
        console2.log("TreasuryV1 impl:", address(treasuryImpl));
        console2.log("Treasury proxy:", address(treasuryProxy));
        console2.log("TreasuryV2 impl:", address(treasuryV2Impl));
        console2.log("AMMFactory:", address(ammFactory));
        console2.log("GameItems:", address(gameItems));
        console2.log("YieldVault:", address(vault));
        console2.log("Box:", address(box));
        console2.log("PriceOracle:", address(oracle));
    }
}