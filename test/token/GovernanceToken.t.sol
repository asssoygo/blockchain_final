// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../../src/token/GovernanceToken.sol";

contract GovernanceTokenTest is Test {
    GovernanceToken internal token;

    address internal owner;
    address internal treasury;
    address internal airdrop;
    address internal liquidity;

    uint256 internal constant MAX_SUPPLY = 1_000_000e18;
    uint256 internal constant TEAM_AMOUNT = MAX_SUPPLY * 40 / 100; // 400_000e18
    uint256 internal constant TREASURY_AMOUNT = MAX_SUPPLY * 30 / 100; // 300_000e18
    uint256 internal constant AIRDROP_AMOUNT = MAX_SUPPLY * 20 / 100; // 200_000e18
    uint256 internal constant LIQUIDITY_AMOUNT = MAX_SUPPLY * 10 / 100; // 100_000e18

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        airdrop = makeAddr("airdrop");
        liquidity = makeAddr("liquidity");

        vm.prank(owner);
        token = new GovernanceToken(treasury, airdrop, liquidity);
    }

    // ─── 1. Initial distribution ───────────────────────────────────────────────

    /// @dev Each allocation bucket must receive exactly its percentage of MAX_SUPPLY.
    function test_InitialDistribution() public view {
        assertEq(token.balanceOf(owner), TEAM_AMOUNT, "owner team slice");
        assertEq(token.balanceOf(treasury), TREASURY_AMOUNT, "treasury slice");
        assertEq(token.balanceOf(airdrop), AIRDROP_AMOUNT, "airdrop slice");
        assertEq(token.balanceOf(liquidity), LIQUIDITY_AMOUNT, "liquidity slice");
    }

    // ─── 2. Total supply ──────────────────────────────────────────────────────

    /// @dev Sum of all minted slices must equal the hard cap exactly.
    function test_TotalSupplyEqualsMaxSupply() public view {
        assertEq(token.totalSupply(), MAX_SUPPLY);
    }

    // ─── 3. Zero address reverts ──────────────────────────────────────────────

    /// @dev A zero treasury address must revert with ZeroAddress.
    function test_RevertWhen_ZeroTreasuryAddress() public {
        vm.expectRevert(GovernanceToken.ZeroAddress.selector);
        new GovernanceToken(address(0), airdrop, liquidity);
    }

    // ─── 4. Self-delegation ───────────────────────────────────────────────────

    /// @dev After self-delegation, getVotes must equal the holder's balance.
    function test_SelfDelegation() public {
        vm.prank(owner);
        token.delegate(owner);

        assertEq(token.getVotes(owner), TEAM_AMOUNT);
    }

    // ─── 5. Delegation to another address ────────────────────────────────────

    /// @dev Delegating to a third party must transfer all voting power to that party.
    function test_Delegation() public {
        address delegatee = makeAddr("delegatee");

        vm.prank(owner);
        token.delegate(delegatee);

        assertEq(token.getVotes(delegatee), TEAM_AMOUNT, "delegatee votes");
        assertEq(token.getVotes(owner), 0, "owner loses votes");
    }

    // ─── 6. Delegation tracking after a transfer ──────────────────────────────

    /// @dev A transfer must move voting units away from the sender's delegatee.
    function test_DelegationTransferTracking() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address charlie = makeAddr("charlie");

        // Give alice some tokens from owner
        vm.prank(owner);
        token.transfer(alice, 1_000e18);

        // Alice delegates all her votes to charlie
        vm.prank(alice);
        token.delegate(charlie);
        assertEq(token.getVotes(charlie), 1_000e18, "charlie pre-transfer votes");

        // Alice transfers half her balance; charlie's votes must shrink
        vm.prank(alice);
        token.transfer(bob, 500e18);

        assertEq(token.getVotes(charlie), 500e18, "charlie post-transfer votes");
    }

    // ─── 7. Voting power snapshot ─────────────────────────────────────────────

    /// @dev getPastVotes must return the votes recorded at a past block number.
    function test_VotingPowerSnapshot() public {
    address voter = airdrop;

    vm.prank(voter);
    token.delegate(voter);

    vm.roll(block.number + 2);

    uint256 pastBlock = block.number - 1;
    uint256 votes = token.getPastVotes(voter, pastBlock);

    assertEq(votes, token.balanceOf(voter));
}
    // ─── 8. EIP-2612 permit ───────────────────────────────────────────────────

    /// @dev A valid permit signature must set the allowance without an approval tx.
    function test_Permit() public {
        uint256 signerKey = 0xA11CE;
        address signerAddr = vm.addr(signerKey);
        address spender = makeAddr("spender");
        uint256 permitAmount = 1_000e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(signerAddr);

        bytes32 permitTypehash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(permitTypehash, signerAddr, spender, permitAmount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        token.permit(signerAddr, spender, permitAmount, deadline, v, r, s);

        assertEq(token.allowance(signerAddr, spender), permitAmount, "allowance set");
        assertEq(token.nonces(signerAddr), 1, "nonce incremented");
    }

    // ─── 9. setVestingContract can only be called once ────────────────────────

    /// @dev A second call to setVestingContract must revert with VestingAlreadyInitialized.
    function test_SetVestingContractOnlyOnce() public {
        address vesting1 = makeAddr("vesting1");
        address vesting2 = makeAddr("vesting2");

        vm.startPrank(owner);
        token.setVestingContract(vesting1);

        vm.expectRevert(GovernanceToken.VestingAlreadyInitialized.selector);
        token.setVestingContract(vesting2);
        vm.stopPrank();
    }

    // ─── 10. setVestingContract: only owner ───────────────────────────────────

    /// @dev A non-owner call must revert with OwnableUnauthorizedAccount.
    function test_SetVestingContractOnlyOwner() public {
        address attacker = makeAddr("attacker");

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        token.setVestingContract(makeAddr("vesting"));
    }

    // ─── 11. setVestingContract: transfers team tokens ────────────────────────

    /// @dev After registration, the vesting address holds exactly the team allocation.
    function test_SetVestingContract_TransfersTeamTokens() public {
        address vesting = makeAddr("vesting");

        vm.prank(owner);
        token.setVestingContract(vesting);

        assertEq(token.balanceOf(vesting), TEAM_AMOUNT, "vesting receives team tokens");
        assertEq(token.balanceOf(owner), 0, "owner balance drained");
        assertTrue(token.vestingInitialized(), "flag set");
    }

    // ─── 12. mint: reverts when it would exceed MAX_SUPPLY ────────────────────

    /// @dev Minting any amount when supply is already at the cap must revert.
    function test_Mint_RevertWhen_ExceedsMaxSupply() public {
        // totalSupply() == MAX_SUPPLY after construction; available == 0
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(GovernanceToken.MaxSupplyExceeded.selector, 1e18, uint256(0)));
        token.mint(owner, 1e18);
    }

    // ─── 13. mint: only owner ─────────────────────────────────────────────────

    /// @dev A non-owner call to mint must revert with OwnableUnauthorizedAccount.
    function test_Mint_OnlyOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        token.mint(attacker, 1e18);
    }

    // ─── 14. burn ─────────────────────────────────────────────────────────────

    /// @dev Burning tokens must reduce both the holder's balance and totalSupply.
    function test_Burn() public {
        uint256 burnAmount = 100e18;
        uint256 supplyBefore = token.totalSupply();

        vm.prank(owner);
        token.burn(burnAmount);

        assertEq(token.balanceOf(owner), TEAM_AMOUNT - burnAmount, "owner balance after burn");
        assertEq(token.totalSupply(), supplyBefore - burnAmount, "totalSupply after burn");
    }

    // ─── 15. burn: reverts on insufficient balance ────────────────────────────

    /// @dev Burning more than one's balance must revert with ERC20InsufficientBalance.
    function test_Burn_RevertWhen_InsufficientBalance() public {
        address alice = makeAddr("alice");
        // alice has 0 tokens
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", alice, uint256(0), 1e18)
        );
        token.burn(1e18);
    }
}
