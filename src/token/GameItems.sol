// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title  GameItems
/// @notice ERC-1155 multi-token contract for the DeFi Super-App gaming layer. Fungible resources
///         (GOLD, WOOD, IRON) can be crafted into unique NFTs (LEGENDARY_SWORD, DRAGON_SHIELD)
///         by burning the required amounts. The DAO can distribute items via {mint} and {mintBatch}.
///
/// @dev    Explicitly overrides {safeTransferFrom} and {safeBatchTransferFrom} to add pause guards
///         and custom validation. Mint and craft functions are owned / paused-aware.
///         Custom per-token-id supply tracking is maintained in {totalSupply} (not automatic in
///         ERC-1155) so the DAO can enforce caps and uniqueness invariants on-chain.
contract GameItems is ERC1155, Ownable, Pausable, ReentrancyGuard {
    // ─── Token ID Constants ───────────────────────────────────────────────────

    /// @notice Fungible resource: Gold.
    uint256 public constant GOLD = 1;

    /// @notice Fungible resource: Wood.
    uint256 public constant WOOD = 2;

    /// @notice Fungible resource: Iron.
    uint256 public constant IRON = 3;

    /// @notice Unique NFT: Legendary Sword (max supply 1).
    uint256 public constant LEGENDARY_SWORD = 100;

    /// @notice Unique NFT: Dragon Shield (max supply 1).
    uint256 public constant DRAGON_SHIELD = 101;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Per-token-id cumulative supply (mint increases, burn decreases).
    mapping(uint256 => uint256) public totalSupply;

    /// @notice True for token IDs that are unique NFTs (enforced max supply of 1).
    mapping(uint256 => bool) public isNFT;

    /// @notice Per-token-id maximum supply cap (0 = no cap).
    mapping(uint256 => uint256) public maxSupply;

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @notice Thrown when a required address is the zero address.
    error ZeroAddress();

    /// @notice Thrown when a required amount or array length is zero.
    error ZeroAmount();

    /// @notice Thrown when `ids` and `amounts` arrays have different lengths.
    error ArrayLengthMismatch();

    /// @notice Thrown when a mint would exceed the per-token max supply.
    /// @param id        Token ID that would be exceeded.
    /// @param requested Amount requested to mint.
    /// @param available Remaining capacity under the cap.
    error MaxSupplyExceeded(uint256 id, uint256 requested, uint256 available);

    /// @notice Thrown when a crafter does not hold enough of a required resource.
    /// @param id       Resource token ID that is short.
    /// @param required Amount required by the recipe.
    /// @param has      Amount the crafter actually holds.
    error InsufficientResources(uint256 id, uint256 required, uint256 has);

    /// @notice Thrown when {craft} is called with a non-NFT token ID.
    /// @param id Token ID that is not registered as an NFT.
    error NotNFT(uint256 id);

    /// @notice Thrown when {mint} or {craft} would exceed the max-supply-of-1 for a unique NFT.
    /// @param id Token ID of the NFT that is already minted.
    error NFTAlreadyMinted(uint256 id);

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when a single item is minted by the owner.
    event ItemMinted(address indexed to, uint256 indexed id, uint256 amount);

    /// @notice Emitted when a batch of items is minted by the owner.
    event ItemBatchMinted(address indexed to, uint256[] ids, uint256[] amounts);

    /// @notice Emitted when a player crafts an NFT by burning resources.
    /// @param crafter        Address that performed the craft.
    /// @param nftId          Token ID of the NFT that was minted.
    /// @param burnedIds      Token IDs of resources that were burned.
    /// @param burnedAmounts  Corresponding burn amounts.
    event ItemCrafted(address indexed crafter, uint256 indexed nftId, uint256[] burnedIds, uint256[] burnedAmounts);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @notice Deploys the contract and registers the two unique NFTs.
    /// @param _owner Address that will own this contract.
    constructor(address _owner) ERC1155("https://defi-superapp.game/items/{id}.json") Ownable(_owner) {
        if (_owner == address(0)) revert ZeroAddress();

        // Register unique NFTs with a max supply of 1 each.
        isNFT[LEGENDARY_SWORD] = true;
        maxSupply[LEGENDARY_SWORD] = 1;

        isNFT[DRAGON_SHIELD] = true;
        maxSupply[DRAGON_SHIELD] = 1;
    }

    // ─── Owner Mint Functions ─────────────────────────────────────────────────

    /// @notice Mints `amount` of token `id` to `to`. Enforces NFT uniqueness and max-supply caps.
    /// @dev    Updates {totalSupply} before calling the underlying ERC-1155 mint so on-chain
    ///         supply accounting is always consistent.
    /// @param to     Recipient address.
    /// @param id     Token ID to mint.
    /// @param amount Number of tokens to mint.
    function mint(address to, uint256 id, uint256 amount) external onlyOwner whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (isNFT[id] && totalSupply[id] + amount > 1) revert NFTAlreadyMinted(id);
        if (maxSupply[id] > 0 && totalSupply[id] + amount > maxSupply[id]) {
            revert MaxSupplyExceeded(id, amount, maxSupply[id] - totalSupply[id]);
        }

        totalSupply[id] += amount;
        _mint(to, id, amount, "");
        emit ItemMinted(to, id, amount);
    }

    /// @notice Mints a batch of items in a single transaction. Applies the same caps as {mint}.
    /// @param to      Recipient address.
    /// @param ids     Array of token IDs to mint.
    /// @param amounts Corresponding amounts for each token ID.
    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts)
        external
        onlyOwner
        whenNotPaused
    {
        if (to == address(0)) revert ZeroAddress();
        if (ids.length != amounts.length) revert ArrayLengthMismatch();
        if (ids.length == 0) revert ZeroAmount();

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            if (amount == 0) revert ZeroAmount();
            if (isNFT[id] && totalSupply[id] + amount > 1) revert NFTAlreadyMinted(id);
            if (maxSupply[id] > 0 && totalSupply[id] + amount > maxSupply[id]) {
                revert MaxSupplyExceeded(id, amount, maxSupply[id] - totalSupply[id]);
            }

            totalSupply[id] += amount;
        }

        _mintBatch(to, ids, amounts, "");
        emit ItemBatchMinted(to, ids, amounts);
    }

    // ─── Transfer Overrides ───────────────────────────────────────────────────

    /// @notice Transfers `value` of token `id` from `from` to `to`.
    /// @dev    Adds pause guard, zero-address check, and zero-amount check on top of the ERC-1155
    ///         base implementation which handles balance and approval validation.
    /// @param from  Token holder.
    /// @param to    Recipient.
    /// @param id    Token ID to transfer.
    /// @param value Amount to transfer.
    /// @param data  Arbitrary data forwarded to the receiver hook.
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data)
        public
        override
        whenNotPaused
    {
        if (to == address(0)) revert ZeroAddress();
        if (value == 0) revert ZeroAmount();
        super.safeTransferFrom(from, to, id, value, data);
    }

    /// @notice Transfers a batch of tokens from `from` to `to`.
    /// @dev    Adds pause guard, zero-address check, and array-length validation on top of the
    ///         ERC-1155 base implementation.
    /// @param from    Token holder.
    /// @param to      Recipient.
    /// @param ids     Array of token IDs.
    /// @param amounts Corresponding amounts.
    /// @param data    Arbitrary data forwarded to the receiver hook.
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (ids.length != amounts.length) revert ArrayLengthMismatch();
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    // ─── Crafting ─────────────────────────────────────────────────────────────

    /// @notice Burns the required resources from the caller's balance and mints a unique NFT.
    /// @dev    Recipes are hardcoded:
    ///           - LEGENDARY_SWORD: 10 GOLD + 5 IRON
    ///           - DRAGON_SHIELD:   15 WOOD + 5 IRON
    ///
    ///         Follows checks-effects-interactions:
    ///           1. Check recipe validity and balances.
    ///           2. Update totalSupply state (effects) before _burn / _mint calls (interactions).
    ///
    /// @param nftIdToMint Token ID of the NFT to craft. Must be a registered NFT with a recipe.
    function craft(uint256 nftIdToMint) external whenNotPaused nonReentrant {
        if (!isNFT[nftIdToMint]) revert NotNFT(nftIdToMint);
        if (totalSupply[nftIdToMint] >= 1) revert NFTAlreadyMinted(nftIdToMint);

        uint256[] memory burnedIds = new uint256[](2);
        uint256[] memory burnedAmounts = new uint256[](2);

        if (nftIdToMint == LEGENDARY_SWORD) {
            uint256 goldNeeded = 10;
            uint256 ironNeeded = 5;

            uint256 goldHas = balanceOf(msg.sender, GOLD);
            uint256 ironHas = balanceOf(msg.sender, IRON);

            if (goldHas < goldNeeded) revert InsufficientResources(GOLD, goldNeeded, goldHas);
            if (ironHas < ironNeeded) revert InsufficientResources(IRON, ironNeeded, ironHas);

            burnedIds[0] = GOLD;
            burnedIds[1] = IRON;
            burnedAmounts[0] = goldNeeded;
            burnedAmounts[1] = ironNeeded;

            totalSupply[GOLD] -= goldNeeded;
            totalSupply[IRON] -= ironNeeded;
            totalSupply[nftIdToMint] = 1;

            _burn(msg.sender, GOLD, goldNeeded);
            _burn(msg.sender, IRON, ironNeeded);
            _mint(msg.sender, nftIdToMint, 1, "");
        } else if (nftIdToMint == DRAGON_SHIELD) {
            uint256 woodNeeded = 15;
            uint256 ironNeeded = 5;

            uint256 woodHas = balanceOf(msg.sender, WOOD);
            uint256 ironHas = balanceOf(msg.sender, IRON);

            if (woodHas < woodNeeded) revert InsufficientResources(WOOD, woodNeeded, woodHas);
            if (ironHas < ironNeeded) revert InsufficientResources(IRON, ironNeeded, ironHas);

            burnedIds[0] = WOOD;
            burnedIds[1] = IRON;
            burnedAmounts[0] = woodNeeded;
            burnedAmounts[1] = ironNeeded;

            totalSupply[WOOD] -= woodNeeded;
            totalSupply[IRON] -= ironNeeded;
            totalSupply[nftIdToMint] = 1;

            _burn(msg.sender, WOOD, woodNeeded);
            _burn(msg.sender, IRON, ironNeeded);
            _mint(msg.sender, nftIdToMint, 1, "");
        } else {
            revert NotNFT(nftIdToMint);
        }

        emit ItemCrafted(msg.sender, nftIdToMint, burnedIds, burnedAmounts);
    }

    // ─── Pause Controls ───────────────────────────────────────────────────────

    /// @notice Pauses all mint, transfer, and craft operations.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resumes all operations.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ─── Metadata ─────────────────────────────────────────────────────────────

    /// @notice Returns the URI for token `id`. The base URI contains the `{id}` placeholder
    ///         which clients replace with the hex-encoded token ID per the ERC-1155 metadata spec.
    /// @param id Token ID to query.
    /// @return   The metadata URI string.
    function uri(uint256 id) public view override returns (string memory) {
        return super.uri(id);
    }
}
