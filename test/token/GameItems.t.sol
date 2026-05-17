// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {GameItems} from "../../src/token/GameItems.sol";

contract GameItemsTest is Test {
    GameItems internal gameItems;

    address internal owner;
    address internal alice;
    address internal bob;

    uint256 internal constant GOLD = 1;
    uint256 internal constant WOOD = 2;
    uint256 internal constant IRON = 3;
    uint256 internal constant LEGENDARY_SWORD = 100;
    uint256 internal constant DRAGON_SHIELD = 101;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.prank(owner);
        gameItems = new GameItems(owner);
    }

    // ─── 1. Initial state ─────────────────────────────────────────────────────

    function test_InitialState() public view {
        assertEq(gameItems.totalSupply(GOLD), 0, "GOLD supply");
        assertEq(gameItems.totalSupply(WOOD), 0, "WOOD supply");
        assertEq(gameItems.totalSupply(IRON), 0, "IRON supply");
        assertEq(gameItems.totalSupply(LEGENDARY_SWORD), 0, "LEGENDARY_SWORD supply");
        assertEq(gameItems.totalSupply(DRAGON_SHIELD), 0, "DRAGON_SHIELD supply");
        assertTrue(gameItems.isNFT(LEGENDARY_SWORD), "LEGENDARY_SWORD is NFT");
        assertTrue(gameItems.isNFT(DRAGON_SHIELD), "DRAGON_SHIELD is NFT");
    }

    // ─── 2. Mint fungible resource ────────────────────────────────────────────

    function test_Mint_FungibleResource() public {
        vm.prank(owner);
        gameItems.mint(alice, GOLD, 100);

        assertEq(gameItems.balanceOf(alice, GOLD), 100, "alice GOLD balance");
        assertEq(gameItems.totalSupply(GOLD), 100, "GOLD total supply");
    }

    // ─── 3. Mint unique NFT once succeeds ─────────────────────────────────────

    function test_Mint_NFT_Once_Succeeds() public {
        vm.prank(owner);
        gameItems.mint(alice, LEGENDARY_SWORD, 1);

        assertEq(gameItems.balanceOf(alice, LEGENDARY_SWORD), 1, "alice owns the sword");
        assertEq(gameItems.totalSupply(LEGENDARY_SWORD), 1, "sword supply is 1");
    }

    // ─── 4. Mint NFT twice reverts ────────────────────────────────────────────

    function test_Mint_RevertWhen_NFTAlreadyMinted() public {
        vm.prank(owner);
        gameItems.mint(alice, LEGENDARY_SWORD, 1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(GameItems.NFTAlreadyMinted.selector, LEGENDARY_SWORD));
        gameItems.mint(bob, LEGENDARY_SWORD, 1);
    }

    // ─── 5. Mint is restricted to owner ──────────────────────────────────────

    function test_Mint_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        gameItems.mint(alice, GOLD, 100);
    }

    // ─── 6. Batch mint multiple resources ─────────────────────────────────────

    function test_MintBatch_MultipleResources() public {
        uint256[] memory ids = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        ids[0] = GOLD;
        ids[1] = WOOD;
        ids[2] = IRON;
        amounts[0] = 50;
        amounts[1] = 200;
        amounts[2] = 30;

        vm.prank(owner);
        gameItems.mintBatch(alice, ids, amounts);

        assertEq(gameItems.balanceOf(alice, GOLD), 50, "GOLD");
        assertEq(gameItems.balanceOf(alice, WOOD), 200, "WOOD");
        assertEq(gameItems.balanceOf(alice, IRON), 30, "IRON");
        assertEq(gameItems.totalSupply(GOLD), 50, "GOLD supply");
    }

    // ─── 7. Batch mint reverts on mismatched arrays ───────────────────────────

    function test_MintBatch_RevertWhen_ArrayLengthMismatch() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](3);
        ids[0] = GOLD;
        ids[1] = WOOD;
        amounts[0] = 10;
        amounts[1] = 20;
        amounts[2] = 30;

        vm.prank(owner);
        vm.expectRevert(GameItems.ArrayLengthMismatch.selector);
        gameItems.mintBatch(alice, ids, amounts);
    }

    // ─── 8. safeTransferFrom works correctly ─────────────────────────────────

    function test_SafeTransferFrom_Works() public {
        vm.prank(owner);
        gameItems.mint(alice, GOLD, 100);

        vm.prank(alice);
        gameItems.safeTransferFrom(alice, bob, GOLD, 50, "");

        assertEq(gameItems.balanceOf(alice, GOLD), 50, "alice remaining GOLD");
        assertEq(gameItems.balanceOf(bob, GOLD), 50, "bob received GOLD");
    }

    // ─── 9. safeBatchTransferFrom works correctly ─────────────────────────────

    function test_SafeBatchTransferFrom_Works() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory mintAmounts = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = WOOD;
        mintAmounts[0] = 100;
        mintAmounts[1] = 200;

        vm.prank(owner);
        gameItems.mintBatch(alice, ids, mintAmounts);

        uint256[] memory transferAmounts = new uint256[](2);
        transferAmounts[0] = 40;
        transferAmounts[1] = 80;

        vm.prank(alice);
        gameItems.safeBatchTransferFrom(alice, bob, ids, transferAmounts, "");

        assertEq(gameItems.balanceOf(alice, GOLD), 60, "alice GOLD after transfer");
        assertEq(gameItems.balanceOf(bob, GOLD), 40, "bob received GOLD");
        assertEq(gameItems.balanceOf(alice, WOOD), 120, "alice WOOD after transfer");
        assertEq(gameItems.balanceOf(bob, WOOD), 80, "bob received WOOD");
    }

    // ─── 10. Craft LEGENDARY_SWORD burns resources and mints NFT ─────────────

    function test_Craft_LegendarySword() public {
        // Give alice exactly the recipe resources.
        vm.startPrank(owner);
        gameItems.mint(alice, GOLD, 10);
        gameItems.mint(alice, IRON, 5);
        vm.stopPrank();

        vm.prank(alice);
        gameItems.craft(LEGENDARY_SWORD);

        // Alice should hold the NFT.
        assertEq(gameItems.balanceOf(alice, LEGENDARY_SWORD), 1, "alice holds the sword");

        // Resources should be fully consumed.
        assertEq(gameItems.balanceOf(alice, GOLD), 0, "GOLD burned");
        assertEq(gameItems.balanceOf(alice, IRON), 0, "IRON burned");

        // Supply tracking must be updated.
        assertEq(gameItems.totalSupply(LEGENDARY_SWORD), 1, "sword supply");
        assertEq(gameItems.totalSupply(GOLD), 0, "GOLD supply");
        assertEq(gameItems.totalSupply(IRON), 0, "IRON supply");
    }

    // ─── 11. Craft reverts when insufficient resources ────────────────────────

    function test_Craft_RevertWhen_InsufficientResources() public {
        // Alice only has 5 GOLD (needs 10) and 5 IRON.
        vm.startPrank(owner);
        gameItems.mint(alice, GOLD, 5);
        gameItems.mint(alice, IRON, 5);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GameItems.InsufficientResources.selector, GOLD, uint256(10), uint256(5)));
        gameItems.craft(LEGENDARY_SWORD);
    }

    // ─── 12. Craft reverts when target is not an NFT ─────────────────────────

    function test_Craft_RevertWhen_NotNFT() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GameItems.NotNFT.selector, GOLD));
        gameItems.craft(GOLD);
    }

    // ─── 13. Pause blocks mint and transfer ───────────────────────────────────

    function test_Pause_BlocksMintAndTransfer() public {
        // Give alice some tokens before pausing.
        vm.prank(owner);
        gameItems.mint(alice, GOLD, 100);

        // Pause.
        vm.prank(owner);
        gameItems.pause();

        // Mint should revert.
        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        gameItems.mint(alice, GOLD, 10);

        // Transfer should revert.
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        gameItems.safeTransferFrom(alice, bob, GOLD, 10, "");

        // Unpause.
        vm.prank(owner);
        gameItems.unpause();

        // Mint works again.
        vm.prank(owner);
        gameItems.mint(alice, GOLD, 10);
        assertEq(gameItems.balanceOf(alice, GOLD), 110, "mint works after unpause");
    }

    // ─── 14. URI contains the {id} placeholder ────────────────────────────────

    function test_UriContainsIdPlaceholder() public view {
        string memory tokenUri = gameItems.uri(GOLD);
        assertEq(tokenUri, "https://defi-superapp.game/items/{id}.json", "URI matches template");

        // Same base URI for all token IDs (clients replace {id}).
        assertEq(gameItems.uri(LEGENDARY_SWORD), tokenUri, "same URI for all token IDs");
    }
}
