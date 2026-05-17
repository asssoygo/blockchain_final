// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AMM} from "./AMM.sol";

/// @title  AMMFactory
/// @notice Deploys and registers AMM trading pairs. Provides two deployment strategies:
///           - {createPair}  — uses the EVM CREATE opcode (address determined by sender + nonce).
///           - {createPair2} — uses the EVM CREATE2 opcode (address determined by salt + initcode
///             hash), enabling off-chain address prediction via {predictPairAddress}.
///
/// @dev    Token pairs are stored bi-directionally so callers need not sort tokens before lookup.
///         Only the owner may deploy new pairs to prevent permissionless pool spam.
contract AMMFactory is Ownable {
    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Maps (token0 => token1) to the deployed pair address (both orderings registered).
    mapping(address => mapping(address => address)) public getPair;

    /// @notice Ordered list of all deployed pair addresses.
    address[] public allPairs;

    /// @notice True if the given address is a pair deployed by this factory.
    mapping(address => bool) public isPair;

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress();

    /// @notice Thrown when both token addresses in a pair are identical.
    error IdenticalTokens();

    /// @notice Thrown when a pair for the given token combination already exists.
    error PairExists();

    /// @notice Thrown when a CREATE2 deployment returns the zero address.
    error DeploymentFailed();

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted whenever a new AMM pair is deployed.
    /// @param token0    Lower-address token of the pair (canonical order).
    /// @param token1    Higher-address token of the pair (canonical order).
    /// @param pair      Address of the newly deployed AMM contract.
    /// @param pairIndex Zero-based index of the pair in {allPairs}.
    /// @param salt      CREATE2 salt used; bytes32(0) for CREATE deployments.
    /// @param create2   True if the pair was deployed with CREATE2.
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256 indexed pairIndex,
        bytes32 salt,
        bool create2
    );

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @notice Deploys the factory and assigns ownership.
    /// @param _owner Address that will own this contract.
    constructor(address _owner) Ownable(_owner) {
        if (_owner == address(0)) revert ZeroAddress();
    }

    // ─── External Functions ───────────────────────────────────────────────────

    /// @notice Deploys a new AMM pair using the standard CREATE opcode.
    /// @dev    Tokens are sorted canonically (lower address first) before deployment.
    /// @param tokenA Address of the first token.
    /// @param tokenB Address of the second token.
    /// @return pair  Address of the newly deployed AMM.
    function createPair(address tokenA, address tokenB) external onlyOwner returns (address pair) {
        if (tokenA == tokenB) revert IdenticalTokens();
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (getPair[token0][token1] != address(0)) revert PairExists();

        pair = address(new AMM(token0, token1));

        _register(token0, token1, pair);
        emit PairCreated(token0, token1, pair, allPairs.length - 1, bytes32(0), false);
    }

    /// @notice Deploys a new AMM pair using the CREATE2 opcode and a caller-supplied salt.
    /// @dev    The deployed address can be predicted off-chain with {predictPairAddress}.
    /// @param tokenA Address of the first token.
    /// @param tokenB Address of the second token.
    /// @param salt   Arbitrary bytes32 value that determines the deployed address.
    /// @return pair  Address of the newly deployed AMM.
    function createPair2(address tokenA, address tokenB, bytes32 salt) external onlyOwner returns (address pair) {
        if (tokenA == tokenB) revert IdenticalTokens();
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (getPair[token0][token1] != address(0)) revert PairExists();

        pair = address(new AMM{salt: salt}(token0, token1));
        if (pair == address(0)) revert DeploymentFailed();

        _register(token0, token1, pair);
        emit PairCreated(token0, token1, pair, allPairs.length - 1, salt, true);
    }

    /// @notice Computes the address a CREATE2 deployment would produce for the given parameters.
    /// @dev    Uses the standard CREATE2 address formula:
    ///           keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))[12:]
    /// @param tokenA Address of the first token (will be sorted before computing).
    /// @param tokenB Address of the second token.
    /// @param salt   The same salt that would be passed to {createPair2}.
    /// @return       The predicted pair address.
    function predictPairAddress(address tokenA, address tokenB, bytes32 salt) external view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes memory initCode = abi.encodePacked(type(AMM).creationCode, abi.encode(token0, token1));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(initCode)));
        return address(uint160(uint256(hash)));
    }

    /// @notice Returns the total number of pairs deployed by this factory.
    /// @return Length of the {allPairs} array.
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    /// @dev Registers a newly deployed pair in all registry data structures.
    function _register(address token0, address token1, address pair) internal {
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        isPair[pair] = true;
    }
}
