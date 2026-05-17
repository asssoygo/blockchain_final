// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title  GovernanceToken
/// @notice ERC20Votes governance token for the DeFi Super-App DAO with a hard supply cap of 1 million tokens.
/// @dev    Inherits ERC20, ERC20Permit (EIP-2612 gasless approvals), ERC20Votes (on-chain vote checkpoints),
///         and Ownable from OpenZeppelin v5. The diamond inheritance between ERC20 and ERC20Votes is resolved
///         via explicit overrides of {_update} and {nonces}.
///
///         Initial distribution (at construction):
///           - 40 % → deployer (team allocation, held until vesting is configured)
///           - 30 % → treasury
///           - 20 % → airdrop
///           - 10 % → liquidity
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice Hard cap on the total token supply: 1,000,000 tokens with 18 decimals.
    uint256 public constant MAX_SUPPLY = 1_000_000e18;

    /// @notice Percentage of MAX_SUPPLY allocated to the team (held by deployer until vesting).
    uint256 public constant TEAM_PERCENT = 40;

    /// @notice Percentage of MAX_SUPPLY allocated to the protocol treasury.
    uint256 public constant TREASURY_PERCENT = 30;

    /// @notice Percentage of MAX_SUPPLY allocated to community airdrop.
    uint256 public constant AIRDROP_PERCENT = 20;

    /// @notice Percentage of MAX_SUPPLY allocated to initial liquidity provision.
    uint256 public constant LIQUIDITY_PERCENT = 10;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice True once {setVestingContract} has been called; prevents re-initialisation.
    bool public vestingInitialized;

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress();

    /// @notice Thrown when {setVestingContract} is called a second time.
    error VestingAlreadyInitialized();

    /// @notice Thrown when a {mint} call would push totalSupply above MAX_SUPPLY.
    /// @param requested The amount that was requested to mint.
    /// @param available The remaining mintable capacity (MAX_SUPPLY − totalSupply).
    error MaxSupplyExceeded(uint256 requested, uint256 available);

    /// @notice Thrown by the compile-time sanity check if the four allocation percentages
    ///         do not sum to exactly 100.
    error InvalidPercentageSum();

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when the vesting contract is registered and team tokens are sent to it.
    /// @param vestingContract The address of the vesting contract that received the tokens.
    /// @param amount          The number of tokens transferred (TEAM_PERCENT % of MAX_SUPPLY).
    event VestingContractSet(address indexed vestingContract, uint256 amount);

    /// @notice Emitted after a successful owner-initiated mint.
    /// @param to     Recipient of the newly minted tokens.
    /// @param amount Number of tokens minted.
    event TokensMinted(address indexed to, uint256 amount);

    /// @notice Emitted after a holder burns their own tokens.
    /// @param from   Address whose tokens were burned.
    /// @param amount Number of tokens destroyed.
    event TokensBurned(address indexed from, uint256 amount);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @notice Deploys the token and distributes the full MAX_SUPPLY according to the
    ///         allocation percentages. The deployer (msg.sender) receives the team slice
    ///         and must later call {setVestingContract} to hand it to the vesting contract.
    /// @dev    Reverts with {ZeroAddress} if any of the three recipient addresses is zero.
    ///         Reverts with {InvalidPercentageSum} if the four allocation constants do not
    ///         add up to 100 (compile-time guard against accidental misconfiguration).
    /// @param treasury  Address that receives 30 % of MAX_SUPPLY.
    /// @param airdrop   Address that receives 20 % of MAX_SUPPLY.
    /// @param liquidity Address that receives 10 % of MAX_SUPPLY.
    constructor(address treasury, address airdrop, address liquidity)
        ERC20("Governance Token", "GOV")
        ERC20Permit("Governance Token")
        Ownable(msg.sender)
    {
        if (treasury == address(0) || airdrop == address(0) || liquidity == address(0)) {
            revert ZeroAddress();
        }
        // Sanity-check: allocation constants must sum to 100.
        if (TEAM_PERCENT + TREASURY_PERCENT + AIRDROP_PERCENT + LIQUIDITY_PERCENT != 100) {
            revert InvalidPercentageSum();
        }

        _mint(msg.sender, MAX_SUPPLY * TEAM_PERCENT / 100);
        _mint(treasury, MAX_SUPPLY * TREASURY_PERCENT / 100);
        _mint(airdrop, MAX_SUPPLY * AIRDROP_PERCENT / 100);
        _mint(liquidity, MAX_SUPPLY * LIQUIDITY_PERCENT / 100);
    }

    // ─── Owner Functions ──────────────────────────────────────────────────────

    /// @notice Registers the vesting contract and atomically transfers the team allocation to it.
    /// @dev    Uses the internal {_transfer} so that ERC20Votes checkpoints are updated correctly
    ///         for any delegatees the owner may have set. Can only be called once (guarded by
    ///         {vestingInitialized}). Reverts with {ZeroAddress} if `_vesting` is the zero address,
    ///         and with {VestingAlreadyInitialized} on a second invocation.
    /// @param _vesting Address of the deployed vesting contract.
    function setVestingContract(address _vesting) external onlyOwner {
        if (_vesting == address(0)) revert ZeroAddress();
        if (vestingInitialized) revert VestingAlreadyInitialized();

        vestingInitialized = true;

        uint256 amount = MAX_SUPPLY * TEAM_PERCENT / 100;
        _transfer(msg.sender, _vesting, amount);

        emit VestingContractSet(_vesting, amount);
    }

    /// @notice Mints `amount` new tokens to `to`, subject to the MAX_SUPPLY hard cap.
    /// @dev    Only the owner may call this. Reverts with {ZeroAddress} if `to` is zero,
    ///         and with {MaxSupplyExceeded} if the mint would breach MAX_SUPPLY.
    /// @param to     Recipient of the minted tokens.
    /// @param amount Number of tokens to create.
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 available = MAX_SUPPLY - totalSupply();
        if (totalSupply() + amount > MAX_SUPPLY) revert MaxSupplyExceeded(amount, available);
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /// @notice Burns `amount` tokens from the caller's own balance.
    /// @dev    Reverts via the underlying ERC20InsufficientBalance error if the caller
    ///         holds fewer tokens than `amount`.
    /// @param amount Number of tokens to destroy.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }

    // ─── Required Overrides ───────────────────────────────────────────────────

    /// @notice Internal hook invoked on every transfer, mint, and burn.
    /// @dev    Resolves the diamond-inheritance conflict between {ERC20._update} and
    ///         {ERC20Votes._update}. Calling `super._update` routes through ERC20Votes
    ///         (which checkpoints voting power) and then to ERC20 (which updates balances).
    /// @param from  Token sender; address(0) on a mint.
    /// @param to    Token recipient; address(0) on a burn.
    /// @param value Number of tokens moved.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /// @notice Returns the current EIP-2612 nonce for `owner`.
    /// @dev    Resolves the diamond-inheritance conflict between {ERC20Permit.nonces} and
    ///         {Nonces.nonces} that arises because both ERC20Permit and ERC20Votes (via Votes)
    ///         inherit from Nonces.
    /// @param owner Address whose nonce is queried.
    /// @return The current nonce for `owner`.
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
