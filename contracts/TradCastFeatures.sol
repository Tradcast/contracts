// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface IERC20MintBurn is IERC20 {
    function mint(address to, uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
}

contract TradCastFeatures is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    // ======================== Roles ========================

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    // ======================== Immutables ========================

    bytes32 public immutable SEED;
    IERC20MintBurn public immutable tradCastPointToken;

    // ======================== Constants ========================

    uint256 public constant CLAIM_COOLDOWN = 84600; // 23.5 hours in seconds
    uint256 public constant MAX_PAYMENT_TOKENS = 10;

    // ======================== Payment Token Registry ========================

    struct PaymentToken {
        address token;
        uint8 decimals;
    }
    PaymentToken[] public paymentTokens;
    mapping(address => uint8) public tokenDecimals;
    mapping(address => bool) public isPaymentToken;

    // ======================== Energy ========================

    struct EnergyTier {
        uint256 energyAmount;
        uint256 priceInCents;
    }
    EnergyTier[] public energyTiers;

    // ======================== Boost ========================

    struct BoostOption {
        uint256 multiplier;
        uint256 durationSeconds;
        uint256 priceInCents;
    }
    BoostOption[] public boostOptions;

    struct ActiveBoost {
        uint256 multiplier;
        uint256 startTime;
        uint256 endTime;
        uint256 optionIndex;
    }
    mapping(address => ActiveBoost) public activeBoosts;

    // ======================== Payout ========================

    struct PayoutOption {
        uint256 tpointAmount;
        uint256 payoutInCents;
    }
    PayoutOption[] public payoutOptions;
    uint256 public minTreasuryBalanceCents = 1500; // $15

    // ======================== Treal Access ========================

    uint256 public trealBurnAmount = 2_000_000 ether; // 2M TPOINTs (18 decimals)
    mapping(address => uint256) public trealAccessExpiry;

    // ======================== Streak Claims ========================

    mapping(address => uint256) public lastStreakClaim;
    mapping(address => uint256) public streakClaimNonce;
    uint256 public maxStreakMint = 5_000 ether; // 5k TPOINTs

    // ======================== Invitation Claims ========================

    mapping(address => uint256) public lastInvitationClaim;
    mapping(address => uint256) public invitationClaimNonce;
    uint256 public maxInvitationMint = 10_000 ether; // 10k TPOINTs

    // ======================== Username ========================

    mapping(address => string) public usernames;
    mapping(address => bool) public hasChangedUsername;
    uint256 public usernameChangePriceCents = 5; // 5 cents

    // ======================== Lottery ========================

    uint256 public lotteryPriceCents = 50; // $0.50
    uint256 public currentLotteryRound;
    mapping(uint256 => mapping(address => bool)) public lotteryEntries;

    // ======================== Events ========================

    event EnergyPurchased(address indexed user, uint256 energyAmount, uint256 priceInCents, address token);
    event BoostPurchased(
        address indexed user,
        uint256 multiplier,
        uint256 startTime,
        uint256 endTime,
        uint256 optionIndex,
        address token
    );
    event PayoutExecuted(
        address indexed user,
        uint256 tpointBurned,
        uint256 payoutCents,
        address payoutToken,
        uint256 payoutAmount
    );
    event TrealAccessPurchased(address indexed user, uint256 expiry);
    event StreakRewardClaimed(address indexed user, uint256 amount, uint256 nonce);
    event InvitationRewardClaimed(address indexed user, uint256 amount, uint256 nonce);
    event UsernameChanged(address indexed user, string newName, uint256 paidCents);
    event LotteryJoined(address indexed user, uint256 round, address token);
    event LotteryRoundStarted(uint256 round);
    event PaymentTokenAdded(address token, uint8 decimals);
    event PaymentTokenRemoved(address token);

    // ======================== Constructor ========================

    constructor(address defaultAdmin, address tokenAddress, bytes32 seed) {
        require(tokenAddress != address(0), "Invalid token");
        require(defaultAdmin != address(0), "Invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, defaultAdmin);
        _grantRole(SIGNER_ROLE, defaultAdmin);

        tradCastPointToken = IERC20MintBurn(tokenAddress);
        SEED = seed;

        // Default energy tiers: (energyAmount, priceInCents)
        energyTiers.push(EnergyTier(5, 2));
        energyTiers.push(EnergyTier(10, 4));
        energyTiers.push(EnergyTier(20, 7));
        energyTiers.push(EnergyTier(50, 15));

        // Default boost options: (multiplier, durationSeconds, priceInCents)
        boostOptions.push(BoostOption(10, 20 minutes, 30));
        boostOptions.push(BoostOption(10, 1 hours, 70));
        boostOptions.push(BoostOption(10, 2 hours, 100));
        boostOptions.push(BoostOption(10, 4 hours, 175));
        boostOptions.push(BoostOption(25, 15 minutes, 100));

        // Default payout options: (tpointAmount in wei, payoutInCents)
        payoutOptions.push(PayoutOption(200_000 ether, 90));
        payoutOptions.push(PayoutOption(500_000 ether, 280));
        payoutOptions.push(PayoutOption(1_000_000 ether, 600));
        payoutOptions.push(PayoutOption(2_000_000 ether, 1400));
    }

    // ======================== Internal Helpers ========================

    function _centsToTokenAmount(uint256 cents, uint8 decimals) internal pure returns (uint256) {
        return (cents * (10 ** uint256(decimals))) / 100;
    }

    function _tokenAmountToCents(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return (amount * 100) / (10 ** uint256(decimals));
    }

    function _collectPayment(address from, address token, uint256 cents) internal {
        require(isPaymentToken[token], "Token not supported");
        uint256 rawAmount = _centsToTokenAmount(cents, tokenDecimals[token]);
        require(rawAmount > 0, "Amount too small");
        IERC20(token).safeTransferFrom(from, address(this), rawAmount);
    }

    function _getTreasuryBalanceCents() internal view returns (uint256 totalCents) {
        for (uint256 i = 0; i < paymentTokens.length; i++) {
            uint256 balance = IERC20(paymentTokens[i].token).balanceOf(address(this));
            totalCents += _tokenAmountToCents(balance, paymentTokens[i].decimals);
        }
    }

    function _findHighestBalanceToken() internal view returns (address bestToken, uint8 bestDecimals) {
        uint256 highestCents;
        for (uint256 i = 0; i < paymentTokens.length; i++) {
            uint256 balance = IERC20(paymentTokens[i].token).balanceOf(address(this));
            uint256 balanceCents = _tokenAmountToCents(balance, paymentTokens[i].decimals);
            if (balanceCents > highestCents) {
                highestCents = balanceCents;
                bestToken = paymentTokens[i].token;
                bestDecimals = paymentTokens[i].decimals;
            }
        }
        require(bestToken != address(0), "No tokens in treasury");
    }

    function _verifySigner(bytes32 messageHash, bytes memory signature) internal view {
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (address signer, ECDSA.RecoverError error,) = ECDSA.tryRecover(ethHash, signature);
        require(error == ECDSA.RecoverError.NoError && hasRole(SIGNER_ROLE, signer), "Invalid signature");
    }

    // ======================== Energy ========================

    function buyEnergy(uint256 tierIndex, address token) external nonReentrant whenNotPaused {
        require(tierIndex < energyTiers.length, "Invalid tier");
        EnergyTier storage tier = energyTiers[tierIndex];
        _collectPayment(msg.sender, token, tier.priceInCents);
        emit EnergyPurchased(msg.sender, tier.energyAmount, tier.priceInCents, token);
    }

    // ======================== Boost ========================

    function buyBoost(uint256 optionIndex, address token) external nonReentrant whenNotPaused {
        require(optionIndex < boostOptions.length, "Invalid option");
        BoostOption storage opt = boostOptions[optionIndex];
        _collectPayment(msg.sender, token, opt.priceInCents);

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + opt.durationSeconds;
        activeBoosts[msg.sender] = ActiveBoost(opt.multiplier, startTime, endTime, optionIndex);

        emit BoostPurchased(msg.sender, opt.multiplier, startTime, endTime, optionIndex, token);
    }

    // ======================== Payout ========================

    function payout(uint256 optionIndex) external nonReentrant whenNotPaused {
        require(optionIndex < payoutOptions.length, "Invalid option");
        PayoutOption storage opt = payoutOptions[optionIndex];

        uint256 treasuryCents = _getTreasuryBalanceCents();
        require(treasuryCents >= minTreasuryBalanceCents, "Treasury balance too low");

        (address bestToken, uint8 bestDecimals) = _findHighestBalanceToken();
        uint256 payoutRaw = _centsToTokenAmount(opt.payoutInCents, bestDecimals);
        require(IERC20(bestToken).balanceOf(address(this)) >= payoutRaw, "Insufficient token balance");

        tradCastPointToken.burnFrom(msg.sender, opt.tpointAmount);
        IERC20(bestToken).safeTransfer(msg.sender, payoutRaw);

        emit PayoutExecuted(msg.sender, opt.tpointAmount, opt.payoutInCents, bestToken, payoutRaw);
    }

    // ======================== Treal Access ========================

    function purchaseTrealAccess() external nonReentrant whenNotPaused {
        tradCastPointToken.burnFrom(msg.sender, trealBurnAmount);

        // If user has unexpired access, extend from current expiry; otherwise start from now
        uint256 currentExpiry = trealAccessExpiry[msg.sender];
        uint256 baseTime = (currentExpiry > block.timestamp) ? currentExpiry : block.timestamp;
        uint256 newExpiry = baseTime + 30 days;
        trealAccessExpiry[msg.sender] = newExpiry;

        emit TrealAccessPurchased(msg.sender, newExpiry);
    }

    function hasTrealAccess(address user) external view returns (bool) {
        return block.timestamp < trealAccessExpiry[user];
    }

    // ======================== Streak Claims ========================

    function claimStreakReward(uint256 amount, bytes calldata signature) external nonReentrant whenNotPaused {
        require(amount > 0 && amount <= maxStreakMint, "Invalid amount");
        require(block.timestamp >= lastStreakClaim[msg.sender] + CLAIM_COOLDOWN, "Cooldown active");

        uint256 nonce = streakClaimNonce[msg.sender];
        bytes32 hash = keccak256(abi.encodePacked(SEED, "STREAK", msg.sender, amount, nonce));
        _verifySigner(hash, signature);

        lastStreakClaim[msg.sender] = block.timestamp;
        streakClaimNonce[msg.sender] = nonce + 1;
        tradCastPointToken.mint(msg.sender, amount);

        emit StreakRewardClaimed(msg.sender, amount, nonce);
    }

    // ======================== Invitation Claims ========================

    function claimInvitationReward(uint256 amount, bytes calldata signature) external nonReentrant whenNotPaused {
        require(amount > 0 && amount <= maxInvitationMint, "Invalid amount");
        require(block.timestamp >= lastInvitationClaim[msg.sender] + CLAIM_COOLDOWN, "Cooldown active");

        uint256 nonce = invitationClaimNonce[msg.sender];
        bytes32 hash = keccak256(abi.encodePacked(SEED, "INVITE", msg.sender, amount, nonce));
        _verifySigner(hash, signature);

        lastInvitationClaim[msg.sender] = block.timestamp;
        invitationClaimNonce[msg.sender] = nonce + 1;
        tradCastPointToken.mint(msg.sender, amount);

        emit InvitationRewardClaimed(msg.sender, amount, nonce);
    }

    // ======================== Username ========================

    function changeUsername(string calldata newName, address token) external nonReentrant whenNotPaused {
        uint256 nameLen = bytes(newName).length;
        require(nameLen > 0 && nameLen <= 32, "Invalid name length");

        uint256 paidCents = 0;
        if (hasChangedUsername[msg.sender]) {
            _collectPayment(msg.sender, token, usernameChangePriceCents);
            paidCents = usernameChangePriceCents;
        }

        hasChangedUsername[msg.sender] = true;
        usernames[msg.sender] = newName;

        emit UsernameChanged(msg.sender, newName, paidCents);
    }

    // ======================== Lottery ========================

    function joinLottery(address token) external nonReentrant whenNotPaused {
        require(currentLotteryRound > 0, "No active lottery");
        require(!lotteryEntries[currentLotteryRound][msg.sender], "Already entered");

        _collectPayment(msg.sender, token, lotteryPriceCents);
        lotteryEntries[currentLotteryRound][msg.sender] = true;

        emit LotteryJoined(msg.sender, currentLotteryRound, token);
    }

    // ======================== View Functions ========================

    function getActiveBoost(address user)
        external
        view
        returns (uint256 multiplier, uint256 startTime, uint256 endTime, bool isActive)
    {
        ActiveBoost storage boost = activeBoosts[user];
        return (boost.multiplier, boost.startTime, boost.endTime, block.timestamp < boost.endTime);
    }

    function getTreasuryBalanceCents() external view returns (uint256) {
        return _getTreasuryBalanceCents();
    }

    function getEnergyTierCount() external view returns (uint256) {
        return energyTiers.length;
    }

    function getBoostOptionCount() external view returns (uint256) {
        return boostOptions.length;
    }

    function getPayoutOptionCount() external view returns (uint256) {
        return payoutOptions.length;
    }

    function getPaymentTokenCount() external view returns (uint256) {
        return paymentTokens.length;
    }

    // ======================== Admin Functions ========================

    function addPaymentToken(address token, uint8 decimals) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(!isPaymentToken[token], "Already added");
        require(paymentTokens.length < MAX_PAYMENT_TOKENS, "Too many tokens");
        require(decimals > 0, "Invalid decimals");

        paymentTokens.push(PaymentToken(token, decimals));
        tokenDecimals[token] = decimals;
        isPaymentToken[token] = true;

        emit PaymentTokenAdded(token, decimals);
    }

    function removePaymentToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isPaymentToken[token], "Not registered");

        isPaymentToken[token] = false;
        tokenDecimals[token] = 0;

        for (uint256 i = 0; i < paymentTokens.length; i++) {
            if (paymentTokens[i].token == token) {
                paymentTokens[i] = paymentTokens[paymentTokens.length - 1];
                paymentTokens.pop();
                break;
            }
        }

        emit PaymentTokenRemoved(token);
    }

    function setEnergyTiers(uint256[] calldata amounts, uint256[] calldata prices) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amounts.length == prices.length, "Length mismatch");
        delete energyTiers;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0 && prices[i] > 0, "Invalid tier");
            energyTiers.push(EnergyTier(amounts[i], prices[i]));
        }
    }

    function setBoostOptions(
        uint256[] calldata multipliers,
        uint256[] calldata durations,
        uint256[] calldata prices
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(multipliers.length == durations.length && durations.length == prices.length, "Length mismatch");
        delete boostOptions;
        for (uint256 i = 0; i < multipliers.length; i++) {
            require(multipliers[i] > 0 && durations[i] > 0 && prices[i] > 0, "Invalid option");
            boostOptions.push(BoostOption(multipliers[i], durations[i], prices[i]));
        }
    }

    function setPayoutOptions(
        uint256[] calldata tpointAmounts,
        uint256[] calldata payoutCents
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tpointAmounts.length == payoutCents.length, "Length mismatch");
        delete payoutOptions;
        for (uint256 i = 0; i < tpointAmounts.length; i++) {
            require(tpointAmounts[i] > 0 && payoutCents[i] > 0, "Invalid option");
            payoutOptions.push(PayoutOption(tpointAmounts[i], payoutCents[i]));
        }
    }

    function setMinTreasuryBalanceCents(uint256 _minCents) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minTreasuryBalanceCents = _minCents;
    }

    function setTrealBurnAmount(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amount > 0, "Invalid amount");
        trealBurnAmount = _amount;
    }

    function setMaxStreakMint(uint256 _max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxStreakMint = _max;
    }

    function setMaxInvitationMint(uint256 _max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxInvitationMint = _max;
    }

    function setUsernameChangePriceCents(uint256 _cents) external onlyRole(DEFAULT_ADMIN_ROLE) {
        usernameChangePriceCents = _cents;
    }

    function setLotteryPriceCents(uint256 _cents) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_cents > 0, "Invalid price");
        lotteryPriceCents = _cents;
    }

    function startNewLotteryRound() external onlyRole(DEFAULT_ADMIN_ROLE) {
        currentLotteryRound++;
        emit LotteryRoundStarted(currentLotteryRound);
    }

    function withdraw(
        address to,
        address _token,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        require(to != address(0), "Invalid recipient");
        if (_token == address(0)) {
            (bool success,) = to.call{value: _amount}("");
            return success;
        }
        IERC20(_token).safeTransfer(to, _amount);
        return true;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    receive() external payable {}
}
