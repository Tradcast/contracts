// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC20Permit } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract TradCastGame2 is ReentrancyGuard, Pausable, AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public immutable SEED;
    address public constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IERC20Mintable public tradCastPointToken;
    mapping(address => uint256) public priceByToken;

    // gameSessions[sessionId] = msg.sender;
    struct GameSession {
        address player;
        bool isEnded;
        uint256 points;
    }
    mapping(uint256 => GameSession) public gameSessions;

    event GameSessionStarted(uint256 sessionId, address player);
    event GameSessionEnded(uint256 sessionId, address player, uint256 points);

    constructor(address defaultAdmin, address tokenAddress, bytes32 seed) {
        require(tokenAddress != address(0));
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, defaultAdmin);
        _grantRole(SIGNER_ROLE, defaultAdmin);
        tradCastPointToken = IERC20Mintable(tokenAddress);
        SEED = seed;
    }

    function startGameSession(uint256 sessionId) public payable nonReentrant whenNotPaused {
        require(priceByToken[NATIVE_TOKEN_ADDRESS] > 0, "Token not supported");
        require(msg.value >= priceByToken[NATIVE_TOKEN_ADDRESS], "Insufficient payment");
        require(gameSessions[sessionId].player == address(0), "Session already started");
        gameSessions[sessionId] = GameSession({
            player: msg.sender,
            isEnded: false,
            points: 0
        });
        emit GameSessionStarted(sessionId, msg.sender);
    }

    function startGameSessionWithTransfer(uint256 sessionId, address token) public payable nonReentrant whenNotPaused {
        uint256 price = priceByToken[token];
        require(price > 0, "Token not supported");
        require(gameSessions[sessionId].player == address(0), "Session already started");
        IERC20(token).transferFrom(msg.sender, address(this), price);
        gameSessions[sessionId] = GameSession({
            player: msg.sender,
            isEnded: false,
            points: 0
        });
        emit GameSessionStarted(sessionId, msg.sender);
    }

    function startGameSessionWithPermit(
        uint256 sessionId,
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external {
        uint256 price = priceByToken[token];
        require(price > 0, "Token not supported");
        require(amount >= price, "Insufficient payment");
        IERC20Permit(token).permit(msg.sender, address(this), amount, deadline, v, r, s);
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        gameSessions[sessionId] = GameSession({
            player: msg.sender,
            isEnded: false,
            points: 0
        });
        emit GameSessionStarted(sessionId, msg.sender);
    }

    function endGameSession(uint256 sessionId, uint256 points, bytes memory signature) public nonReentrant whenNotPaused {
        bytes32 hash = keccak256(abi.encodePacked(SEED, sessionId, points));
        hash = MessageHashUtils.toEthSignedMessageHash(hash);
        (address signer, ECDSA.RecoverError error, ) = ECDSA.tryRecover(hash, signature);
        require(error == ECDSA.RecoverError.NoError && hasRole(SIGNER_ROLE, signer), "invalid signature");

        require(gameSessions[sessionId].player == msg.sender, "Not the session owner");
        require(!gameSessions[sessionId].isEnded, "Session already ended");
        gameSessions[sessionId].isEnded = true;
        gameSessions[sessionId].points = points;
        tradCastPointToken.mint(msg.sender, points);
        emit GameSessionEnded(sessionId, msg.sender, points);
    }

    // ----- Admin functions -----
    function setPriceByToken(address token, uint256 price) public onlyRole(DEFAULT_ADMIN_ROLE) {
        priceByToken[token] = price;
    }

    function withdraw(
        address to,
        address _token,
        uint256 _amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool success) {
        if (_token == NATIVE_TOKEN_ADDRESS) {
            (bool result, ) = to.call{value: _amount}("");
            return result;
        }
        IERC20(_token).transfer(to, _amount);
        return true;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}

