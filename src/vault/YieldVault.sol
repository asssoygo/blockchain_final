// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title  YieldVault
/// @notice ERC-4626 tokenised yield vault whose share price grows whenever the owner injects
///         harvested yield via {harvest}. Depositors receive "dVS" shares that appreciate as
///         totalAssets increases relative to totalSupply.
///
/// @dev    All four ERC-4626 entry-points (deposit / mint / withdraw / redeem) are explicitly
///         overridden to:
///           1. Add custom zero-value and zero-address guards.
///           2. Emit the protocol-specific {DepositWithReceipt} / {WithdrawWithReceipt} events
///              in addition to the standard ERC-4626 Deposit / Withdraw events.
///           3. Apply {ReentrancyGuard} (ERC-4626 itself has no guard).
///
///         Inheritance order: ERC20 → ERC4626 → Ownable → ReentrancyGuard
contract YieldVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Cumulative yield injected into the vault via {harvest}.
    uint256 public totalHarvested;

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @notice Thrown when a required address is the zero address.
    error ZeroAddress();

    /// @notice Thrown when a required amount is zero.
    error ZeroAmount();

    /// @notice Thrown when the harvest transfer fails (unused but declared per spec).
    error HarvestFailed();

    /// @notice Thrown when a caller holds fewer shares than required.
    error InsufficientShares();

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when the owner pushes yield into the vault.
    /// @param caller       Address that initiated the harvest (owner).
    /// @param amount       Amount of underlying asset injected.
    /// @param newTotalAssets Total assets in the vault after the harvest.
    event Harvested(address indexed caller, uint256 amount, uint256 newTotalAssets);

    /// @notice Emitted on every deposit or mint operation (supplements the standard Deposit event).
    /// @param caller    msg.sender of the transaction.
    /// @param receiver  Address that received the minted shares.
    /// @param assets    Amount of underlying asset deposited.
    /// @param shares    Amount of vault shares minted.
    event DepositWithReceipt(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);

    /// @notice Emitted on every withdraw or redeem operation (supplements the standard Withdraw event).
    /// @param caller    msg.sender of the transaction.
    /// @param receiver  Address that received the underlying asset.
    /// @param owner     Address whose shares were burned.
    /// @param assets    Amount of underlying asset returned.
    /// @param shares    Amount of vault shares burned.
    event WithdrawWithReceipt(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @notice Deploys the vault with the given underlying asset and owner.
    /// @dev    ERC20 must be initialised before ERC4626 in the parent chain.
    /// @param _asset ERC20 token that this vault accepts as the underlying asset.
    /// @param _owner Address that will own this contract.
    constructor(IERC20 _asset, address _owner) ERC20("DeFi Vault Share", "dVS") ERC4626(_asset) Ownable(_owner) {
        if (_asset == IERC20(address(0)) || _owner == address(0)) revert ZeroAddress();
    }

    // ─── Explicit Deposit / Mint Overrides ────────────────────────────────────

    /// @notice Deposits `assets` of the underlying token and mints proportional shares to `receiver`.
    /// @dev    Adds zero-value / zero-address guards and emits {DepositWithReceipt}. The actual
    ///         asset transfer and share minting delegate to {ERC4626.deposit}.
    /// @param assets   Amount of underlying asset to deposit.
    /// @param receiver Address that receives the minted vault shares.
    /// @return shares  Number of vault shares minted.
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        shares = super.deposit(assets, receiver);
        emit DepositWithReceipt(msg.sender, receiver, assets, shares);
    }

    /// @notice Mints exactly `shares` vault shares by pulling the required assets from the caller.
    /// @dev    Adds zero-value / zero-address guards and emits {DepositWithReceipt}. The actual
    ///         asset transfer and share minting delegate to {ERC4626.mint}.
    /// @param shares   Number of vault shares to mint.
    /// @param receiver Address that receives the minted vault shares.
    /// @return assets  Amount of underlying asset transferred from the caller.
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        assets = super.mint(shares, receiver);
        emit DepositWithReceipt(msg.sender, receiver, assets, shares);
    }

    // ─── Explicit Withdraw / Redeem Overrides ─────────────────────────────────

    /// @notice Withdraws exactly `assets` of the underlying token and burns the required shares.
    /// @dev    Adds zero-value / zero-address guards and emits {WithdrawWithReceipt}. The actual
    ///         share burning and asset transfer delegate to {ERC4626.withdraw}.
    /// @param assets   Exact amount of underlying asset to withdraw.
    /// @param receiver Address that receives the underlying asset.
    /// @param owner    Address whose shares are burned (must equal msg.sender or have given allowance).
    /// @return shares  Number of vault shares burned.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        shares = super.withdraw(assets, receiver, owner);
        emit WithdrawWithReceipt(msg.sender, receiver, owner, assets, shares);
    }

    /// @notice Redeems exactly `shares` vault shares and transfers the proportional assets to `receiver`.
    /// @dev    Adds zero-value / zero-address guards and emits {WithdrawWithReceipt}. The actual
    ///         share burning and asset transfer delegate to {ERC4626.redeem}.
    /// @param shares   Number of vault shares to burn.
    /// @param receiver Address that receives the underlying asset.
    /// @param owner    Address whose shares are burned (must equal msg.sender or have given allowance).
    /// @return assets  Amount of underlying asset transferred to `receiver`.
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        assets = super.redeem(shares, receiver, owner);
        emit WithdrawWithReceipt(msg.sender, receiver, owner, assets, shares);
    }

    // ─── Yield Injection ──────────────────────────────────────────────────────

    /// @notice Injects `amount` of the underlying asset into the vault to simulate harvested yield.
    /// @dev    Pulling tokens from the owner into the vault raises {ERC4626.totalAssets} (which
    ///         returns asset().balanceOf(address(this))). A higher totalAssets with an unchanged
    ///         totalSupply means every existing share is now worth more assets — share price
    ///         appreciates for all current depositors.
    ///
    ///         Only the contract owner may call this. The owner must have pre-approved the vault.
    ///
    /// @param amount Amount of underlying asset to inject as yield.
    function harvest(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert ZeroAmount();

        totalHarvested += amount;
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        emit Harvested(msg.sender, amount, totalAssets());
    }
}
