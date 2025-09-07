
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// ================================================================================================
// 📚 LIBRARIES
// ================================================================================================

/**
 * @title PillarMath
 * @notice Mathematical utilities for Pillar Protocol
 */
library PillarMath {
    using SafeMath for uint256;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant WAD = 1e18;
    uint256 public constant RAY = 1e27;
    uint256 public constant HALF_WAD = 0.5e18;
    uint256 public constant HALF_RAY = 0.5e27;

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function wmul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mul(b).add(HALF_WAD).div(WAD);
    }

    function wdiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mul(WAD).add(b.div(2)).div(b);
    }

    function rmul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mul(b).add(HALF_RAY).div(RAY);
    }

    function rdiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mul(RAY).add(b.div(2)).div(b);
    }

    function rayToWad(uint256 a) internal pure returns (uint256) {
        return a.add(5e8).div(1e9);
    }

    function wadToRay(uint256 a) internal pure returns (uint256) {
        return a.mul(1e9);
    }

    /**
     * @notice Calculate linear interest
     */
    function calculateLinearInterest(
        uint256 rate,
        uint256 lastUpdateTimestamp
    ) internal view returns (uint256) {
        uint256 timeDifference = block.timestamp.sub(lastUpdateTimestamp);
        return rate.mul(timeDifference).div(365 days).add(RAY);
    }

    /**
     * @notice Calculate percentage
     */
    function percentMul(uint256 value, uint256 percentage) internal pure returns (uint256) {
        if (value == 0 || percentage == 0) {
            return 0;
        }
        return value.mul(percentage).div(BASIS_POINTS);
    }

    /**
     * @notice Calculate percentage division
     */
    function percentDiv(uint256 value, uint256 percentage) internal pure returns (uint256) {
        return value.mul(BASIS_POINTS).div(percentage);
    }
}

/**
 * @title RangeCalculator
 * @notice Range calculation utilities for dynamic LP positions
 */
library RangeCalculator {
    using SafeMath for uint256;
    using PillarMath for uint256;

    /**
     * @notice Calculate price range based on leverage
     */
    function calculateRangeFromLeverage(uint256 leverageBps) internal pure returns (uint256) {
        if (leverageBps <= 10000) return 5000; // 1x = ±50%
        if (leverageBps <= 20000) return 2500; // 2x = ±25%
        if (leverageBps <= 30000) return 1666; // 3x = ±16.66%
        if (leverageBps <= 50000) return 1000; // 5x = ±10%
        if (leverageBps <= 100000) return 500; // 10x = ±5%
        return 250; // >10x = ±2.5%
    }

    /**
     * @notice Calculate position bounds
     */
    function calculatePositionBounds(
        uint256 centerPrice,
        uint256 rangeWidthBps
    ) internal pure returns (uint256 lowerBound, uint256 upperBound) {
        uint256 rangeAmount = centerPrice.percentMul(rangeWidthBps);
        lowerBound = centerPrice.sub(rangeAmount);
        upperBound = centerPrice.add(rangeAmount);
    }

    /**
     * @notice Check if price is within range
     */
    function isWithinRange(
        uint256 currentPrice,
        uint256 lowerBound,
        uint256 upperBound
    ) internal pure returns (bool) {
        return currentPrice >= lowerBound && currentPrice <= upperBound;
    }

    /**
     * @notice Calculate new center price for rebalancing
     */
    function calculateNewCenterPrice(
        uint256 currentPrice,
        uint256 /* rangeWidthBps */  // Unused parameter commented to silence warning
    ) internal pure returns (uint256) {
        return currentPrice;
    }

    /**
     * @notice Apply meme token range adjustment
     */
    function applyMemeTokenAdjustment(
        uint256 baseRange,
        uint8 memeTokenTier
    ) internal pure returns (uint256) {
        if (memeTokenTier == 1) { // Bronze
            return baseRange.mul(80).div(100); // -20%
        } else if (memeTokenTier == 2) { // Silver
            return baseRange.mul(90).div(100); // -10%
        } else if (memeTokenTier == 3) { // Gold
            return baseRange.mul(95).div(100); // -5%
        }
        return baseRange;
    }
}

/**
 * @title LiquidationLib
 * @notice Liquidation calculation utilities
 */
library LiquidationLib {
    using SafeMath for uint256;
    using PillarMath for uint256;

    /**
     * @notice Calculate health ratio
     */
    function calculateHealthRatio(
        uint256 collateralValueUSD,
        uint256 debtValueUSD
    ) internal pure returns (uint256) {
        if (debtValueUSD == 0) return type(uint256).max;
        return collateralValueUSD.mul(10000).div(debtValueUSD);
    }

    /**
     * @notice Check if position can be liquidated
     */
    function canLiquidate(
        uint256 healthRatio,
        uint256 threshold,
        uint256 lastUpdateTime,
        uint256 gracePeriod
    ) internal view returns (bool) {
        if (healthRatio > threshold) return false;
        return block.timestamp.sub(lastUpdateTime) >= gracePeriod;
    }

    /**
     * @notice Calculate liquidation penalty
     */
    function calculateLiquidationPenalty(
        uint256 debtAmount,
        uint256 penaltyBps
    ) internal pure returns (uint256) {
        return debtAmount.percentMul(penaltyBps);
    }

    /**
     * @notice Calculate liquidation amounts
     */
    function calculateLiquidationAmounts(
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 maxLiquidationBps
    ) internal pure returns (
        uint256 collateralToLiquidate,
        uint256 debtToRepay
    ) {
        uint256 maxCollateral = collateralAmount.percentMul(maxLiquidationBps);
        uint256 maxDebt = debtAmount.percentMul(maxLiquidationBps);
        
        collateralToLiquidate = PillarMath.min(maxCollateral, collateralAmount);
        debtToRepay = PillarMath.min(maxDebt, debtAmount);
    }
}

// ================================================================================================
// 🔮 MOCK ERC20 TOKEN FOR TESTING
// ================================================================================================

contract MockERC20 is IERC20, Ownable {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string public name;
    string public symbol;
    uint8 public decimals;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        _totalSupply = initialSupply;
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        _transfer(from, to, amount);

        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(from, msg.sender, currentAllowance - amount);
        }

        return true;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(to != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

// ================================================================================================
// 🔮 PUMP.FUN ORACLE SYSTEM
// ================================================================================================

/**
 * @title PumpFunOracle
 * @notice Oracle for tracking meme token metrics from Pump.fun style data
 */
contract PumpFunOracle is Ownable {
    using SafeMath for uint256;

    struct TokenMetrics {
        uint256 volumeUSD24h;
        uint256 liquidityUSD;
        uint256 holders;
        uint256 marketCapUSD;
        uint256 priceUSD; // 18 decimals
        int256 priceChange24h; // BPS, can be negative
        uint256 lastUpdate;
        bool isTracking;
    }

    mapping(address => TokenMetrics) public tokenMetrics;
    mapping(address => bool) public authorizedUpdaters;
    
    uint256 public constant UPDATE_COOLDOWN = 300; // 5 minutes
    uint256 public constant MAX_PRICE_CHANGE = 10000; // 100% max change per update
    
    event TokenMetricsUpdated(
        address indexed token,
        uint256 volumeUSD24h,
        uint256 liquidityUSD,
        uint256 holders,
        uint256 marketCapUSD,
        uint256 priceUSD,
        int256 priceChange24h
    );
    
    event TrackerAdded(address indexed token);
    event TrackerRemoved(address indexed token);
    event UpdaterAuthorized(address indexed updater);
    event UpdaterRevoked(address indexed updater);

    modifier onlyAuthorizedUpdater() {
        require(authorizedUpdaters[msg.sender] || msg.sender == owner(), "PumpOracle: Unauthorized");
        _;
    }

    constructor() {
        authorizedUpdaters[msg.sender] = true;
    }

    /**
     * @notice Start tracking a new token
     */
    function startTrackingToken(address _token) external onlyOwner {
        require(_token != address(0), "PumpOracle: Invalid token");
        require(!tokenMetrics[_token].isTracking, "PumpOracle: Already tracking");
        
        tokenMetrics[_token].isTracking = true;
        tokenMetrics[_token].lastUpdate = block.timestamp;
        
        emit TrackerAdded(_token);
    }

    /**
     * @notice Stop tracking a token
     */
    function stopTrackingToken(address _token) external onlyOwner {
        require(tokenMetrics[_token].isTracking, "PumpOracle: Not tracking");
        
        tokenMetrics[_token].isTracking = false;
        
        emit TrackerRemoved(_token);
    }

    /**
     * @notice Update token metrics (called by authorized updaters/bots)
     */
    function updateTokenMetrics(
        address _token,
        uint256 _volumeUSD24h,
        uint256 _liquidityUSD,
        uint256 _holders,
        uint256 _marketCapUSD,
        uint256 _priceUSD,
        int256 _priceChange24h
    ) external onlyAuthorizedUpdater {
        require(tokenMetrics[_token].isTracking, "PumpOracle: Token not tracked");
        require(
            block.timestamp.sub(tokenMetrics[_token].lastUpdate) >= UPDATE_COOLDOWN,
            "PumpOracle: Update too frequent"
        );
        require(
            _priceChange24h >= -int256(MAX_PRICE_CHANGE) && _priceChange24h <= int256(MAX_PRICE_CHANGE),
            "PumpOracle: Price change too extreme"
        );

        TokenMetrics storage metrics = tokenMetrics[_token];
        
        metrics.volumeUSD24h = _volumeUSD24h;
        metrics.liquidityUSD = _liquidityUSD;
        metrics.holders = _holders;
        metrics.marketCapUSD = _marketCapUSD;
        metrics.priceUSD = _priceUSD;
        metrics.priceChange24h = _priceChange24h;
        metrics.lastUpdate = block.timestamp;

        emit TokenMetricsUpdated(
            _token,
            _volumeUSD24h,
            _liquidityUSD,
            _holders,
            _marketCapUSD,
            _priceUSD,
            _priceChange24h
        );
    }

    /**
     * @notice Check if token is being tracked
     */
    function isTrackingToken(address _token) external view returns (bool) {
        return tokenMetrics[_token].isTracking;
    }

    /**
     * @notice Get token metrics
     */
    function getTokenMetrics(address _token) external view returns (TokenMetrics memory) {
        return tokenMetrics[_token];
    }

    /**
     * @notice Check if token data is fresh
     */
    function isDataFresh(address _token, uint256 _maxAge) external view returns (bool) {
        return (block.timestamp.sub(tokenMetrics[_token].lastUpdate)) <= _maxAge;
    }

    /**
     * @notice Get current price with freshness check
     */
    function getPrice(address _token) external view returns (uint256 price, bool isFresh) {
        TokenMetrics memory metrics = tokenMetrics[_token];
        price = metrics.priceUSD;
        isFresh = (block.timestamp.sub(metrics.lastUpdate)) <= 1800; // 30 minutes
    }

    /**
     * @notice Authorize new updater
     */
    function authorizeUpdater(address _updater) external onlyOwner {
        authorizedUpdaters[_updater] = true;
        emit UpdaterAuthorized(_updater);
    }

    /**
     * @notice Revoke updater authorization
     */
    function revokeUpdater(address _updater) external onlyOwner {
        authorizedUpdaters[_updater] = false;
        emit UpdaterRevoked(_updater);
    }
}

// ================================================================================================
// 🎮 MEME TOKEN REGISTRY
// ================================================================================================

/**
 * @title MemeTokenRegistry
 * @notice Registry for whitelisted meme tokens with tier-based leverage limits
 */
contract MemeTokenRegistry is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    PumpFunOracle public immutable pumpOracle;
    
    struct TokenInfo {
        bool isWhitelisted;
        uint8 tier; // 1: Bronze, 2: Silver, 3: Gold
        uint256 maxLeverageBps; // Max leverage in BPS (20000 = 2x)
        uint256 volumeUSD24h;
        uint256 liquidityUSD;
        uint256 holders;
        uint256 marketCapUSD;
        uint256 whitelistTime;
        string websiteUrl;
        uint256 whitelistFee; // Fee paid for whitelist
    }

    struct TierRequirements {
        uint256 minVolumeUSD24h;
        uint256 minLiquidityUSD;
        uint256 minHolders;
        uint256 minMarketCapUSD;
        uint256 maxLeverageBps;
    }

    mapping(address => TokenInfo) public tokenInfo;
    mapping(uint8 => TierRequirements) public tierRequirements;
    
    address[] public whitelistedTokens;
    
    uint256 public whitelistBaseFee = 0.1 ether; // Base fee to apply for whitelist
    uint256 public constant EVALUATION_PERIOD = 7 days; // Minimum data collection period
    uint256 public constant RE_EVALUATION_PERIOD = 30 days; // Re-evaluation cycle
    
    event TokenWhitelisted(address indexed token, uint8 tier, uint256 maxLeverageBps);
    event TokenDelisted(address indexed token, string reason);
    event TierUpdated(address indexed token, uint8 oldTier, uint8 newTier);
    event WhitelistRequested(address indexed token, address indexed requester, string websiteUrl);
    event TierRequirementsUpdated(uint8 tier, uint256 minVolume, uint256 minLiquidity, uint256 minHolders, uint256 minMarketCap);

    constructor(address _pumpOracle) {
        require(_pumpOracle != address(0), "MemeRegistry: Invalid oracle");
        pumpOracle = PumpFunOracle(_pumpOracle);
        
        // Initialize tier requirements
        _initializeTierRequirements();
    }

    function _initializeTierRequirements() internal {
        // Bronze tier: Entry level meme tokens
        tierRequirements[1] = TierRequirements({
            minVolumeUSD24h: 50000e18,    // $50K volume
            minLiquidityUSD: 25000e18,    // $25K liquidity
            minHolders: 100,              // 100 holders
            minMarketCapUSD: 100000e18,   // $100K market cap
            maxLeverageBps: 15000         // 1.5x leverage
        });

        // Silver tier: Established meme tokens
        tierRequirements[2] = TierRequirements({
            minVolumeUSD24h: 200000e18,   // $200K volume
            minLiquidityUSD: 100000e18,   // $100K liquidity
            minHolders: 500,              // 500 holders
            minMarketCapUSD: 500000e18,   // $500K market cap
            maxLeverageBps: 20000         // 2.0x leverage
        });

        // Gold tier: Top tier meme tokens
        tierRequirements[3] = TierRequirements({
            minVolumeUSD24h: 1000000e18,  // $1M volume
            minLiquidityUSD: 500000e18,   // $500K liquidity
            minHolders: 2000,             // 2000 holders
            minMarketCapUSD: 2000000e18,  // $2M market cap
            maxLeverageBps: 25000         // 2.5x leverage
        });
    }

    /**
     * @notice Request token whitelist (pays fee)
     */
    function requestWhitelist(
        address _token,
        string calldata _websiteUrl
    ) external payable nonReentrant {
        require(_token != address(0), "MemeRegistry: Invalid token");
        require(msg.value >= whitelistBaseFee, "MemeRegistry: Insufficient fee");
        require(!tokenInfo[_token].isWhitelisted, "MemeRegistry: Already whitelisted");
        require(bytes(_websiteUrl).length > 0, "MemeRegistry: Website required");

        // Start tracking in oracle if not already
        if (!pumpOracle.isTrackingToken(_token)) {
            pumpOracle.startTrackingToken(_token);
        }

        // Store request info (not whitelisted yet)
        tokenInfo[_token] = TokenInfo({
            isWhitelisted: false,
            tier: 0,
            maxLeverageBps: 0,
            volumeUSD24h: 0,
            liquidityUSD: 0,
            holders: 0,
            marketCapUSD: 0,
            whitelistTime: 0,
            websiteUrl: _websiteUrl,
            whitelistFee: msg.value
        });

        emit WhitelistRequested(_token, msg.sender, _websiteUrl);
    }

    /**
     * @notice Evaluate and whitelist token (owner only, after evaluation period)
     */
    function evaluateAndWhitelistToken(address _token) external onlyOwner {
        require(tokenInfo[_token].whitelistFee > 0, "MemeRegistry: No whitelist request");
        require(!tokenInfo[_token].isWhitelisted, "MemeRegistry: Already whitelisted");

        // Get current metrics from oracle
        PumpFunOracle.TokenMetrics memory metrics = pumpOracle.getTokenMetrics(_token);

        require(metrics.volumeUSD24h > 0, "MemeRegistry: No trading data");

        // Determine tier based on metrics
        uint8 tier = _determineTier(metrics.volumeUSD24h, metrics.liquidityUSD, metrics.holders, metrics.marketCapUSD);
        require(tier > 0, "MemeRegistry: Does not meet minimum requirements");

        // Update token info
        TokenInfo storage info = tokenInfo[_token];
        info.isWhitelisted = true;
        info.tier = tier;
        info.maxLeverageBps = tierRequirements[tier].maxLeverageBps;
        info.volumeUSD24h = metrics.volumeUSD24h;
        info.liquidityUSD = metrics.liquidityUSD;
        info.holders = metrics.holders;
        info.marketCapUSD = metrics.marketCapUSD;
        info.whitelistTime = block.timestamp;

        whitelistedTokens.push(_token);

        emit TokenWhitelisted(_token, tier, info.maxLeverageBps);
    }

    /**
     * @notice Determine tier based on metrics
     */
    function _determineTier(
        uint256 volumeUSD24h,
        uint256 liquidityUSD,
        uint256 holders,
        uint256 marketCapUSD
    ) internal view returns (uint8) {
        // Check Gold tier first (highest requirements)
        TierRequirements memory gold = tierRequirements[3];
        if (volumeUSD24h >= gold.minVolumeUSD24h &&
            liquidityUSD >= gold.minLiquidityUSD &&
            holders >= gold.minHolders &&
            marketCapUSD >= gold.minMarketCapUSD) {
            return 3; // Gold
        }

        TierRequirements memory silver = tierRequirements[2];
        if (volumeUSD24h >= silver.minVolumeUSD24h &&
            liquidityUSD >= silver.minLiquidityUSD &&
            holders >= silver.minHolders &&
            marketCapUSD >= silver.minMarketCapUSD) {
            return 2; // Silver
        }

        TierRequirements memory bronze = tierRequirements[1];
        if (volumeUSD24h >= bronze.minVolumeUSD24h &&
            liquidityUSD >= bronze.minLiquidityUSD &&
            holders >= bronze.minHolders &&
            marketCapUSD >= bronze.minMarketCapUSD) {
            return 1; // Bronze
        }

        return 0; // Does not qualify
    }

    // ================================================================================================
    // VIEW FUNCTIONS
    // ================================================================================================

    function isTokenWhitelisted(address _token) external view returns (bool) {
        return tokenInfo[_token].isWhitelisted;
    }

    function getTokenInfo(address _token) external view returns (TokenInfo memory) {
        return tokenInfo[_token];
    }

    function getTokenTier(address _token) external view returns (uint8) {
        return tokenInfo[_token].tier;
    }

    function getMaxLeverageForToken(address _token) external view returns (uint256) {
        return tokenInfo[_token].maxLeverageBps;
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return whitelistedTokens;
    }

    function getTierRequirements(uint8 _tier) external view returns (TierRequirements memory) {
        return tierRequirements[_tier];
    }

    // ================================================================================================
    // ADMIN FUNCTIONS
    // ================================================================================================

    function updateWhitelistFee(uint256 _newFee) external onlyOwner {
        whitelistBaseFee = _newFee;
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "MemeRegistry: No fees to withdraw");
        payable(owner()).transfer(balance);
    }
}

// ================================================================================================
// 🏦 PILLAR LENDING VAULT
// ================================================================================================

/**
 * @title PillarLendingVault
 * @notice Isolated lending pools with jump interest rate model
 */
contract PillarLendingVault is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using PillarMath for uint256;

    struct AssetData {
        bool isActive;
        uint256 totalSupply;
        uint256 totalBorrows;
        uint256 borrowIndex;
        uint256 supplyIndex;
        uint256 lastUpdateTimestamp;
        uint256 reserveFactor; // Percentage of interest going to reserves (BPS)
        uint256 reserves; // Accumulated reserves
        
        // Interest rate model parameters
        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 jumpMultiplierPerYear;
        uint256 optimalUtilizationRate;
    }

    struct UserAssetData {
        uint256 principalSupply;
        uint256 principalBorrow;
        uint256 supplyIndex;
        uint256 borrowIndex;
    }

    mapping(address => AssetData) public assets;
    mapping(address => mapping(address => UserAssetData)) public userAssetData;
    mapping(address => bool) public authorizedVaults;
    
    address public immutable pillarToken;
    address public treasury;
    
    uint256 public constant INVALID_ASSET_THRESHOLD = 1e12; // Minimum asset amount
    uint256 public constant MAX_RESERVE_FACTOR = 5000; // 50%
    
    address[] public supportedAssets;

    event AssetAdded(address indexed asset, uint256 baseRate, uint256 multiplier, uint256 jumpMultiplier, uint256 optimalUtilization, uint256 reserveFactor);
    event Deposited(address indexed user, address indexed asset, uint256 amount, uint256 newSupplyIndex);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount, uint256 newSupplyIndex);
    event Borrowed(address indexed borrower, address indexed asset, uint256 amount, uint256 newBorrowIndex);
    event Repaid(address indexed borrower, address indexed asset, uint256 amount, uint256 newBorrowIndex);
    event ReservesWithdrawn(address indexed asset, uint256 amount, address indexed treasury);
    event VaultAuthorized(address indexed vault, bool authorized);

    modifier onlyAuthorizedVault() {
        require(authorizedVaults[msg.sender], "PillarLending: Unauthorized vault");
        _;
    }

    modifier validAsset(address asset) {
        require(assets[asset].isActive, "PillarLending: Invalid asset");
        require(asset != pillarToken, "PillarLending: Cannot use PLLAR as collateral");
        _;
    }

    constructor(address _pillarToken, address _treasury) {
        require(_treasury != address(0), "PillarLending: Invalid treasury");
        
        pillarToken = _pillarToken;
        treasury = _treasury;
    }

    // ================================================================================================
    // ADMIN FUNCTIONS
    // ================================================================================================

    /**
     * @notice Add a new asset to lending pool
     */
    function addAsset(
        address _asset,
        uint256 _baseRatePerYear,
        uint256 _multiplierPerYear,
        uint256 _jumpMultiplierPerYear,
        uint256 _optimalUtilizationRate,
        uint256 _reserveFactor
    ) external onlyOwner {
        require(_asset != address(0), "PillarLending: Invalid asset");
        require(_asset != pillarToken, "PillarLending: Cannot add PLLAR token");
        require(!assets[_asset].isActive, "PillarLending: Asset already added");
        require(_reserveFactor <= MAX_RESERVE_FACTOR, "PillarLending: Reserve factor too high");
        require(_optimalUtilizationRate <= PillarMath.WAD, "PillarLending: Invalid optimal utilization");

        assets[_asset] = AssetData({
            isActive: true,
            totalSupply: 0,
            totalBorrows: 0,
            borrowIndex: PillarMath.RAY,
            supplyIndex: PillarMath.RAY,
            lastUpdateTimestamp: block.timestamp,
            reserveFactor: _reserveFactor,
            reserves: 0,
            baseRatePerYear: _baseRatePerYear,
            multiplierPerYear: _multiplierPerYear,
            jumpMultiplierPerYear: _jumpMultiplierPerYear,
            optimalUtilizationRate: _optimalUtilizationRate
        });

        supportedAssets.push(_asset);

        emit AssetAdded(_asset, _baseRatePerYear, _multiplierPerYear, _jumpMultiplierPerYear, _optimalUtilizationRate, _reserveFactor);
    }

    /**
     * @notice Set vault authorization for borrowing
     */
    function setVaultAuthorization(address _vault, bool _authorized) external onlyOwner {
        authorizedVaults[_vault] = _authorized;
        emit VaultAuthorized(_vault, _authorized);
    }

    // ================================================================================================
    // USER FUNCTIONS
    // ================================================================================================

    /**
     * @notice Supply assets to earn interest
     */
    function supply(address _asset, uint256 _amount) 
        external 
        nonReentrant 
        whenNotPaused 
        validAsset(_asset) 
    {
        require(_amount > 0, "PillarLending: Amount must be greater than 0");
        
        _accrueInterest(_asset);
        
        AssetData storage asset = assets[_asset];
        UserAssetData storage userData = userAssetData[msg.sender][_asset];

        // Transfer tokens to contract
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        // Update user's supply balance
        userData.principalSupply = userData.principalSupply.add(_amount.rdiv(asset.supplyIndex));
        userData.supplyIndex = asset.supplyIndex;

        // Update global supply
        asset.totalSupply = asset.totalSupply.add(_amount);

        emit Deposited(msg.sender, _asset, _amount, asset.supplyIndex);
    }

    /**
     * @notice Withdraw supplied assets
     */
    function withdraw(address _asset, uint256 _amount) 
        external 
        nonReentrant 
        whenNotPaused 
        validAsset(_asset) 
    {
        _accrueInterest(_asset);

        AssetData storage asset = assets[_asset];
        UserAssetData storage userData = userAssetData[msg.sender][_asset];

        uint256 userSupplyBalance = userData.principalSupply.rmul(userData.supplyIndex);
        
        // If amount is 0, withdraw full balance
        if (_amount == 0) {
            _amount = userSupplyBalance;
        }
        
        require(_amount <= userSupplyBalance, "PillarLending: Insufficient supply balance");
        require(_amount <= getTotalLiquidity(_asset), "PillarLending: Insufficient liquidity");

        // Update user's supply balance
        userData.principalSupply = userData.principalSupply.sub(_amount.rdiv(userData.supplyIndex));
        userData.supplyIndex = asset.supplyIndex;

        // Update global supply
        asset.totalSupply = asset.totalSupply.sub(_amount);

        // Transfer tokens to user
        IERC20(_asset).safeTransfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _asset, _amount, asset.supplyIndex);
    }

    /**
     * @notice Borrow assets (only authorized vaults)
     */
    function borrow(address _asset, uint256 _amount) 
        external 
        nonReentrant 
        whenNotPaused 
        validAsset(_asset) 
        onlyAuthorizedVault 
    {
        require(_amount > 0, "PillarLending: Amount must be greater than 0");
        require(_amount <= getTotalLiquidity(_asset), "PillarLending: Insufficient liquidity");

        _accrueInterest(_asset);

        AssetData storage asset = assets[_asset];
        UserAssetData storage userData = userAssetData[msg.sender][_asset];

        // Update user's borrow balance
        userData.principalBorrow = userData.principalBorrow.add(_amount.rdiv(asset.borrowIndex));
        userData.borrowIndex = asset.borrowIndex;

        // Update global borrows
        asset.totalBorrows = asset.totalBorrows.add(_amount);

        // Transfer tokens to borrower
        IERC20(_asset).safeTransfer(msg.sender, _amount);

        emit Borrowed(msg.sender, _asset, _amount, asset.borrowIndex);
    }

    /**
     * @notice Repay borrowed assets
     */
    function repay(address _asset, uint256 _amount) 
        external 
        nonReentrant 
        whenNotPaused 
        validAsset(_asset) 
        onlyAuthorizedVault 
    {
        _accrueInterest(_asset);

        AssetData storage asset = assets[_asset];
        UserAssetData storage userData = userAssetData[msg.sender][_asset];

        uint256 userBorrowBalance = userData.principalBorrow.rmul(userData.borrowIndex);
        
        // If amount is 0, repay full balance
        if (_amount == 0) {
            _amount = userBorrowBalance;
        }
        
        require(_amount <= userBorrowBalance, "PillarLending: Amount exceeds borrow balance");

        // Transfer tokens from borrower
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        // Update user's borrow balance
        userData.principalBorrow = userData.principalBorrow.sub(_amount.rdiv(userData.borrowIndex));
        userData.borrowIndex = asset.borrowIndex;

        // Update global borrows
        asset.totalBorrows = asset.totalBorrows.sub(_amount);

        emit Repaid(msg.sender, _asset, _amount, asset.borrowIndex);
    }

    // ================================================================================================
    // INTEREST RATE FUNCTIONS
    // ================================================================================================

    /**
     * @notice Accrue interest for an asset
     */
    function _accrueInterest(address _asset) internal {
        AssetData storage asset = assets[_asset];
        
        if (block.timestamp == asset.lastUpdateTimestamp) {
            return;
        }

        uint256 borrowRate = _getBorrowRate(_asset);
        uint256 interestFactor = PillarMath.calculateLinearInterest(borrowRate, asset.lastUpdateTimestamp);

        // Update borrow index
        asset.borrowIndex = asset.borrowIndex.rmul(interestFactor);
        
        // Calculate reserves
        uint256 totalInterest = asset.totalBorrows.rmul(interestFactor.sub(PillarMath.RAY));
        uint256 reserveAmount = totalInterest.percentMul(asset.reserveFactor);
        asset.reserves = asset.reserves.add(reserveAmount);

        // Update supply index
        if (asset.totalSupply > 0) {
            uint256 netInterest = totalInterest.sub(reserveAmount);
            uint256 supplyInterestFactor = netInterest.rdiv(asset.totalSupply).add(PillarMath.RAY);
            asset.supplyIndex = asset.supplyIndex.rmul(supplyInterestFactor);
        }

        asset.lastUpdateTimestamp = block.timestamp;
    }

    /**
     * @notice Calculate borrow rate for an asset
     */
    function _getBorrowRate(address _asset) internal view returns (uint256) {
        AssetData memory asset = assets[_asset];
        
        if (asset.totalSupply == 0) {
            return asset.baseRatePerYear;
        }

        uint256 utilizationRate = getUtilizationRate(_asset);
        
        if (utilizationRate <= asset.optimalUtilizationRate) {
            // Below optimal: linear increase
            return asset.baseRatePerYear.add(
                utilizationRate.mul(asset.multiplierPerYear).div(asset.optimalUtilizationRate)
            );
        } else {
            // Above optimal: jump rate model
            uint256 baseRate = asset.baseRatePerYear.add(asset.multiplierPerYear);
            uint256 excessUtilization = utilizationRate.sub(asset.optimalUtilizationRate);
            uint256 maxExcessUtilization = PillarMath.WAD.sub(asset.optimalUtilizationRate);
            
            return baseRate.add(
                excessUtilization.mul(asset.jumpMultiplierPerYear).div(maxExcessUtilization)
            );
        }
    }

    // ================================================================================================
    // VIEW FUNCTIONS
    // ================================================================================================

    function getBorrowRate(address _asset) external view validAsset(_asset) returns (uint256) {
        return _getBorrowRate(_asset);
    }

    function getUtilizationRate(address _asset) public view validAsset(_asset) returns (uint256) {
        AssetData memory asset = assets[_asset];
        
        if (asset.totalSupply == 0) {
            return 0;
        }
        
        return asset.totalBorrows.mul(PillarMath.WAD).div(asset.totalSupply);
    }

    function getTotalLiquidity(address _asset) public view validAsset(_asset) returns (uint256) {
        return IERC20(_asset).balanceOf(address(this)).sub(assets[_asset].reserves);
    }

    function getUserBalance(address _user, address _asset) 
        external 
        view 
        validAsset(_asset) 
        returns (uint256 principal, uint256 interest) 
    {
        UserAssetData memory userData = userAssetData[_user][_asset];
        AssetData memory asset = assets[_asset];
        
        principal = userData.principalSupply;
        
        if (principal > 0) {
            uint256 currentSupplyIndex = asset.supplyIndex;
            uint256 totalBalance = userData.principalSupply.rmul(currentSupplyIndex);
            interest = totalBalance > principal ? totalBalance.sub(principal) : 0;
        }
    }

    function totalSupply(address _asset) external view returns (uint256) {
        return assets[_asset].totalSupply;
    }

    function totalBorrows(address _asset) external view returns (uint256) {
        return assets[_asset].totalBorrows;
    }

    // ================================================================================================
    // EMERGENCY FUNCTIONS
    // ================================================================================================

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

// ================================================================================================
// 🚀 DYNAMIC RANGE VAULT (CORE)
// ================================================================================================

/**
 * @title DynamicRangeVault  
 * @notice Core contract for leveraged dynamic range LP positions
 */
contract DynamicRangeVault is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using PillarMath for uint256;
    using RangeCalculator for uint256;
    using LiquidationLib for uint256;

    enum PositionStatus { ACTIVE, OUT_OF_RANGE, LIQUIDATED, CLOSED }
    enum MarginType { CROSS, ISOLATED }

    struct Position {
        address owner;
        address baseAsset;      // Collateral asset (e.g., USDC)
        address targetAsset;    // Target LP asset (e.g., WETH, PEPE)
        uint256 collateralAmount;
        uint256 leverageBps;    // Leverage in basis points (20000 = 2x)
        uint256 rangeWidthBps;  // Range width in basis points (2500 = ±25%)
        uint256 centerPrice;    // Center price when opened
        uint256 priceLowerBound;
        uint256 priceUpperBound;
        uint256 debtAmount;     // Borrowed amount from LendingVault
        uint256 accruedFees;    // Accumulated LP fees
        uint256 lastUpdateTime;
        uint8 marginType;       // 0: CROSS, 1: ISOLATED
        uint8 status;           // PositionStatus enum
        uint8 feeTier;          // Fee tier (0: 0.01%, 1: 0.3%, 2: 1%)
    }

    struct RangePreview {
        uint256 leverageBps;
        uint256 allowedRangeBps;     // legal (orange) band width in bps
        uint256 finalRangeBps;       // user/custom adjusted + meme adjustment (white)
        uint256 centerPrice;         // current price from oracle/mock
        uint256 lowerBound;
        uint256 upperBound;
        uint256 borrowAmount;
        bool isMeme;
        uint8 memeTier;
        uint256 maxMemeLeverageBps;  // 0 if not meme or not whitelisted
        bool ok;
        string reason;
    }

    PillarLendingVault public immutable lendingVault;
    MemeTokenRegistry public immutable memeRegistry;
    
    mapping(uint256 => Position) public positions;
    mapping(address => uint256[]) public userPositions;
    mapping(uint256 => uint256) public leverageToMaxRange; // leverage BPS => max range BPS
    
    uint256 public nextPositionId = 1;
    address public treasury;
    address public liquidationEngine;
    
    // Protocol parameters
    uint256 public constant MAX_LEVERAGE_BPS = 100000; // 10x leverage
    uint256 public constant MIN_COLLATERAL_USD = 100e6; // \$100 minimum
    uint256 public constant PERFORMANCE_FEE_BPS = 1000; // 10% performance fee
    uint256 public constant REBALANCE_FEE_BPS = 50; // 0.5% rebalance fee
    
    // Asset tier configurations
    enum AssetTier { BLUE_CHIP, MAJOR_ALT, MEME }
    mapping(address => AssetTier) public assetTiers;
    mapping(AssetTier => uint256) public maxLeverageByTier;

    event PositionOpened(
        uint256 indexed positionId,
        address indexed owner,
        address baseAsset,
        address targetAsset,
        uint256 collateralAmount,
        uint256 leverageBps,
        uint256 rangeWidthBps,
        uint8 marginType
    );
    
    event PositionClosed(
        uint256 indexed positionId,
        address indexed owner,
        uint256 finalCollateralAmount,
        uint256 realizedPnl
    );
    
    event PositionRebalanced(
        uint256 indexed positionId,
        uint256 newCenterPrice,
        uint256 newLowerBound,
        uint256 newUpperBound,
        uint256 rebalanceFee
    );
    
    event FeesHarvested(
        uint256 indexed positionId,
        uint256 harvestedAmount,
        uint256 performanceFee,
        uint256 compoundedAmount
    );
    
    event PositionLiquidated(
        uint256 indexed positionId,
        address indexed liquidator,
        uint256 liquidationPenalty,
        uint256 remainingCollateral
    );

    modifier validPosition(uint256 _positionId) {
        require(_positionId > 0 && _positionId < nextPositionId, "DynamicVault: Invalid position ID");
        require(positions[_positionId].owner != address(0), "DynamicVault: Position does not exist");
        _;
    }

    modifier onlyPositionOwner(uint256 _positionId) {
        require(positions[_positionId].owner == msg.sender, "DynamicVault: Not position owner");
        _;
    }

    modifier onlyLiquidationEngine() {
        require(msg.sender == liquidationEngine, "DynamicVault: Only liquidation engine");
        _;
    }

    constructor(
        address _lendingVault,
        address _memeRegistry,
        address _treasury
    ) {
        require(_lendingVault != address(0), "DynamicVault: Invalid lending vault");
        require(_memeRegistry != address(0), "DynamicVault: Invalid meme registry");
        require(_treasury != address(0), "DynamicVault: Invalid treasury");

        lendingVault = PillarLendingVault(_lendingVault);
        memeRegistry = MemeTokenRegistry(_memeRegistry);
        treasury = _treasury;

        _initializeLeverageRangeMatrix();
        _initializeAssetTiers();
    }

    function _initializeLeverageRangeMatrix() internal {
        leverageToMaxRange[10000] = 5000;  // 1x = ±50%
        leverageToMaxRange[20000] = 2500;  // 2x = ±25%
        leverageToMaxRange[30000] = 1666;  // 3x = ±16.66%
        leverageToMaxRange[40000] = 1250;  // 4x = ±12.5%
        leverageToMaxRange[50000] = 1000;  // 5x = ±10%
        leverageToMaxRange[100000] = 500;  // 10x = ±5%
    }

    function _initializeAssetTiers() internal {
        // Blue chip assets (WETH, WBTC, etc.) - Max 10x leverage
        maxLeverageByTier[AssetTier.BLUE_CHIP] = 100000;
        
        // Major altcoins (SOL, MATIC, etc.) - Max 5x leverage  
        maxLeverageByTier[AssetTier.MAJOR_ALT] = 50000;
        
        // Meme tokens - Max leverage determined by registry
        maxLeverageByTier[AssetTier.MEME] = 25000; // Default 2.5x, overridden by registry
    }

    // ================================================================================================
    // POSITION MANAGEMENT
    // ================================================================================================

    /**
     * @notice Open a new leveraged dynamic range position
     */
    function openDynamicPosition(
        address _baseAsset,       // Collateral asset (USDC, etc.)
        address _targetAsset,     // Target asset (WETH, PEPE, etc.)
        uint256 _collateralAmount,
        uint256 _leverageBps,     // Leverage in BPS (20000 = 2x)
        uint8 _marginType,        // 0: CROSS, 1: ISOLATED
        uint256 _customRangeBps,  // 0 for auto, or custom range
        uint8 _feeTier            // 0: 0.01%, 1: 0.3%, 2: 1%
    ) external nonReentrant whenNotPaused returns (uint256 positionId) {
        require(_collateralAmount >= MIN_COLLATERAL_USD, "DynamicVault: Collateral too small");
        require(_leverageBps >= 10000 && _leverageBps <= MAX_LEVERAGE_BPS, "DynamicVault: Invalid leverage");
        require(_feeTier <= 2, "DynamicVault: Invalid fee tier");

        // Validate leverage against asset tier
        _validateLeverageForAsset(_targetAsset, _leverageBps);

        // Calculate range width
        uint256 rangeWidthBps = _customRangeBps == 0 ? 
            RangeCalculator.calculateRangeFromLeverage(_leverageBps) : _customRangeBps;

        // Apply meme token adjustment if needed
        if (memeRegistry.isTokenWhitelisted(_targetAsset)) {
            uint8 memeTokenTier = memeRegistry.getTokenTier(_targetAsset);
            rangeWidthBps = RangeCalculator.applyMemeTokenAdjustment(rangeWidthBps, memeTokenTier);
        }

        // Validate custom range doesn't exceed leverage limit
        uint256 maxAllowedRange = leverageToMaxRange[_leverageBps];
        require(rangeWidthBps <= maxAllowedRange, "DynamicVault: Range too wide for leverage");

        // Transfer collateral from user
        IERC20(_baseAsset).safeTransferFrom(msg.sender, address(this), _collateralAmount);

        // Calculate borrowed amount
        uint256 borrowAmount = _collateralAmount.mul(_leverageBps.sub(10000)).div(10000);
        
        // Borrow from lending vault
        if (borrowAmount > 0) {
            lendingVault.borrow(_baseAsset, borrowAmount);
        }

        // Get current price (simplified - would use oracle)
        uint256 currentPrice = _getCurrentPrice(_targetAsset);
        
        // Calculate position bounds
        (uint256 lowerBound, uint256 upperBound) = RangeCalculator.calculatePositionBounds(
            currentPrice, rangeWidthBps
        );

        // Create position
        positionId = nextPositionId++;
        Position storage position = positions[positionId];
        
        position.owner = msg.sender;
        position.baseAsset = _baseAsset;
        position.targetAsset = _targetAsset;
        position.collateralAmount = _collateralAmount;
        position.leverageBps = _leverageBps;
        position.rangeWidthBps = rangeWidthBps;
        position.centerPrice = currentPrice;
        position.priceLowerBound = lowerBound;
        position.priceUpperBound = upperBound;
        position.debtAmount = borrowAmount;
        position.lastUpdateTime = block.timestamp;
        position.marginType = _marginType;
        position.status = uint8(PositionStatus.ACTIVE);
        position.feeTier = _feeTier;

        // Add to user positions
        userPositions[msg.sender].push(positionId);

        emit PositionOpened(
            positionId,
            msg.sender,
            _baseAsset,
            _targetAsset,
            _collateralAmount,
            _leverageBps,
            rangeWidthBps,
            _marginType
        );
    }

    /**
     * @notice Close an existing position
     */
    function closePosition(uint256 _positionId) 
        external 
        nonReentrant 
        whenNotPaused 
        validPosition(_positionId) 
        onlyPositionOwner(_positionId)
    {
        Position storage position = positions[_positionId];
        require(position.status == uint8(PositionStatus.ACTIVE) || 
                position.status == uint8(PositionStatus.OUT_OF_RANGE), 
                "DynamicVault: Cannot close this position");

        // Harvest any pending fees first
        _harvestFees(_positionId);

        // Calculate final amounts (simplified)
        uint256 finalCollateralAmount = position.collateralAmount.add(position.accruedFees);
        uint256 realizedPnl = 0; // Would calculate based on LP position performance

        // Repay debt to lending vault
        if (position.debtAmount > 0) {
            IERC20(position.baseAsset).safeApprove(address(lendingVault), position.debtAmount);
            lendingVault.repay(position.baseAsset, position.debtAmount);
        }

        // Calculate remaining collateral after debt repayment
        uint256 remainingCollateral = finalCollateralAmount > position.debtAmount ? 
            finalCollateralAmount.sub(position.debtAmount) : 0;

        // Return remaining collateral to user
        if (remainingCollateral > 0) {
            IERC20(position.baseAsset).safeTransfer(msg.sender, remainingCollateral);
        }

        // Mark position as closed
        position.status = uint8(PositionStatus.CLOSED);

        emit PositionClosed(_positionId, msg.sender, remainingCollateral, realizedPnl);
    }

    /**
     * @notice Harvest fees and compound into position
     */
    function harvestAndCompound(uint256 _positionId) 
        external 
        nonReentrant 
        whenNotPaused 
        validPosition(_positionId) 
        onlyPositionOwner(_positionId)
    {
        _harvestFees(_positionId);
    }

    function _harvestFees(uint256 _positionId) internal {
        Position storage position = positions[_positionId];
        require(position.status == uint8(PositionStatus.ACTIVE), "DynamicVault: Position not active");

        // Simulate fee accrual based on time and leverage
        uint256 timeElapsed = block.timestamp.sub(position.lastUpdateTime);
        uint256 baseAPR = 500; // 5% base APR
        uint256 leverageMultiplier = position.leverageBps.div(10000);
        
        uint256 simulatedFees = position.collateralAmount
            .mul(baseAPR)
            .mul(leverageMultiplier)
            .mul(timeElapsed)
            .div(365 days)
            .div(10000);

        if (simulatedFees > 0) {
            // Take performance fee
            uint256 performanceFee = simulatedFees.percentMul(PERFORMANCE_FEE_BPS);
            uint256 netFees = simulatedFees.sub(performanceFee);

            // Add to position
            position.accruedFees = position.accruedFees.add(netFees);
            position.lastUpdateTime = block.timestamp;

            emit FeesHarvested(_positionId, simulatedFees, performanceFee, netFees);
        }
    }

    /**
     * @notice Force liquidate position (only liquidation engine)
     */
    function forceLiquidatePosition(uint256 _positionId) 
        external 
        nonReentrant 
        onlyLiquidationEngine 
        validPosition(_positionId)
    {
        Position storage position = positions[_positionId];
        require(position.status != uint8(PositionStatus.LIQUIDATED) && 
                position.status != uint8(PositionStatus.CLOSED), 
                "DynamicVault: Position already closed/liquidated");

        // Calculate liquidation amounts
        uint256 liquidationPenalty = position.collateralAmount.percentMul(300); // 3% penalty
        uint256 remainingCollateral = position.collateralAmount > liquidationPenalty ? 
            position.collateralAmount.sub(liquidationPenalty) : 0;

        // Repay debt
        if (position.debtAmount > 0) {
            lendingVault.repay(position.baseAsset, position.debtAmount);
        }

        // Mark as liquidated
        position.status = uint8(PositionStatus.LIQUIDATED);

        emit PositionLiquidated(_positionId, msg.sender, liquidationPenalty, remainingCollateral);
    }

    // ================================================================================================
    // VALIDATION & HELPER FUNCTIONS
    // ================================================================================================

    function _validateLeverageForAsset(address _asset, uint256 _leverageBps) internal view {
        AssetTier tier = assetTiers[_asset];
        
        if (tier == AssetTier.MEME && memeRegistry.isTokenWhitelisted(_asset)) {
            uint256 maxMemeTokenLeverage = memeRegistry.getMaxLeverageForToken(_asset);
            require(_leverageBps <= maxMemeTokenLeverage, "DynamicVault: Exceeds meme token leverage limit");
        } else {
            uint256 maxTierLeverage = maxLeverageByTier[tier];
            require(_leverageBps <= maxTierLeverage, "DynamicVault: Exceeds tier leverage limit");
        }
    }

    function _getCurrentPrice(address _asset) internal view returns (uint256) {  // Changed from pure to view
        // Mock prices for testing
        if (_asset == address(0x1)) return 2000e18; // Mock WETH price
        if (_asset == address(0x2)) return 100e18;  // Mock SOL price
        if (_asset == address(0x3)) return 1e15;    // Mock PEPE price (0.001)
        return 1e18; // Default $1
    }

    // ================================================================================================
    // VIEW FUNCTIONS
    // ================================================================================================

    function getPositionDetails(uint256 _positionId) 
        external 
        view 
        validPosition(_positionId) 
        returns (Position memory) 
    {
        return positions[_positionId];
    }

    function getUserPositions(address _user) external view returns (uint256[] memory) {
        return userPositions[_user];
    }

    function getPositionHealthRatio(uint256 _positionId) 
        external 
        view 
        validPosition(_positionId) 
        returns (uint256) 
    {
        Position memory position = positions[_positionId];
        uint256 collateralValueUSD = position.collateralAmount.add(position.accruedFees);
        return LiquidationLib.calculateHealthRatio(collateralValueUSD, position.debtAmount);
    }

    function getAllowedRange(uint256 _leverageBps) public view returns (uint256) {
        uint256 v = leverageToMaxRange[_leverageBps];
        if (v == 0) {
            // Fallback to library rule so 1.5x, 2.5x, etc. still work
            v = _leverageBps.calculateRangeFromLeverage();
        }
        return v;
    }

    function isPositionInRange(uint256 _positionId) 
        external 
        view 
        validPosition(_positionId) 
        returns (bool) 
    {
        Position memory position = positions[_positionId];
        uint256 currentPrice = _getCurrentPrice(position.targetAsset);
        return RangeCalculator.isWithinRange(
            currentPrice, 
            position.priceLowerBound, 
            position.priceUpperBound
        );
    }

    function previewOpenPosition(
        address _baseAsset,
        address _targetAsset,
        uint256 _collateralAmount,
        uint256 _leverageBps,
        uint8   _marginType,        // 0 CROSS, 1 ISOLATED (present for parity)
        uint256 _customRangeBps,    // 0 = auto
        uint8   _feeTier            // present for parity
    ) external view returns (RangePreview memory r) {
        r.leverageBps = _leverageBps;
        if (_collateralAmount < MIN_COLLATERAL_USD) {
            r.ok = false; r.reason = "Collateral too small"; return r;
        }
        if (_leverageBps < 10000 || _leverageBps > MAX_LEVERAGE_BPS) {
            r.ok = false; r.reason = "Invalid leverage"; return r;
        }

        // Tier / meme checks
        AssetTier tier = assetTiers[_targetAsset];
        uint256 maxTierLev = maxLeverageByTier[tier];
        bool isWL = false;
        uint8 memeTier = 0;
        uint256 maxMemeLev = 0;

        if (tier == AssetTier.MEME && memeRegistry.isTokenWhitelisted(_targetAsset)) {
            isWL = true;
            memeTier = memeRegistry.getTokenTier(_targetAsset);
            maxMemeLev = memeRegistry.getMaxLeverageForToken(_targetAsset);
            if (_leverageBps > maxMemeLev) {
                r.ok = false; r.reason = "Exceeds meme leverage limit"; 
                r.isMeme = true; r.memeTier = memeTier; r.maxMemeLeverageBps = maxMemeLev;
                return r;
            }
        } else if (_leverageBps > maxTierLev) {
            r.ok = false; r.reason = "Exceeds tier leverage limit"; return r;
        }

        r.allowedRangeBps = getAllowedRange(_leverageBps);

        // Base range (auto or custom)
        uint256 baseRange = _customRangeBps == 0 
            ? _leverageBps.calculateRangeFromLeverage()
            : _customRangeBps;

        // The user's base choice may not exceed the legal band
        if (baseRange > r.allowedRangeBps) {
            r.ok = false; r.reason = "Custom range exceeds legal band";
            return r;
        }

        // Meme adjustment
        if (isWL) {
            baseRange = RangeCalculator.applyMemeTokenAdjustment(baseRange, memeTier);
        }
        r.finalRangeBps = baseRange;
        r.isMeme = isWL;
        r.memeTier = memeTier;
        r.maxMemeLeverageBps = maxMemeLev;

        // Price + bounds
        r.centerPrice = _getCurrentPrice(_targetAsset);
        (r.lowerBound, r.upperBound) = RangeCalculator.calculatePositionBounds(
            r.centerPrice, r.finalRangeBps
        );

        // Borrow
        r.borrowAmount = _collateralAmount * (_leverageBps - 10000) / 10000;

        r.ok = true;
        r.reason = "OK";
    }

    // ================================================================================================
    // ADMIN FUNCTIONS
    // ================================================================================================

    function setLiquidationEngine(address _liquidationEngine) external onlyOwner {
        liquidationEngine = _liquidationEngine;
    }

    function setAssetTier(address _asset, AssetTier _tier) external onlyOwner {
        assetTiers[_asset] = _tier;
    }

    function updateLeverageRange(uint256 _leverageBps, uint256 _maxRangeBps) external onlyOwner {
        leverageToMaxRange[_leverageBps] = _maxRangeBps;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

// ================================================================================================
// 🔥 LIQUIDATION ENGINE
// ================================================================================================

/**
 * @title PillarLiquidationEngine
 * @notice Handles position liquidations with dual-trigger system
 */
contract PillarLiquidationEngine is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using PillarMath for uint256;
    using LiquidationLib for uint256;

    DynamicRangeVault public immutable dynamicVault;
    PillarLendingVault public immutable lendingVault;
    MemeTokenRegistry public immutable memeRegistry;
    
    address public treasury;
    address public insuranceFund;

    // Liquidation parameters
    mapping(address => uint256) public liquidationThresholds; // asset => threshold BPS
    uint256 public constant DEFAULT_LIQUIDATION_THRESHOLD = 8500; // 85%
    uint256 public constant MEME_LIQUIDATION_THRESHOLD = 9000; // 90%
    uint256 public constant GRACE_PERIOD = 1800; // 30 minutes
    uint256 public constant MAX_LIQUIDATIONS_PER_DAY = 100;
    uint256 public constant DAILY_LIQUIDATION_LIMIT_BPS = 2000; // 20% of TVL

    // Rewards
    uint256 public constant KEEPER_REWARD_BPS = 200; // 2%
    uint256 public constant INSURANCE_FUND_BPS = 100; // 1%
    uint256 public constant PROTOCOL_FEE_BPS = 100; // 1%

    // Daily limits tracking
    mapping(uint256 => uint256) public dailyLiquidationCount;
    mapping(uint256 => uint256) public dailyLiquidationVolume;
    
    event LiquidationExecuted(
        uint256 indexed positionId,
        address indexed liquidator,
        uint256 collateralLiquidated,
        uint256 debtRepaid,
        uint256 keeperReward,
        uint256 penalty
    );
    
    event LiquidationThresholdUpdated(address indexed asset, uint256 oldThreshold, uint256 newThreshold);
    event DailyLimitReached(uint256 date, uint256 liquidationCount, uint256 liquidationVolume);

    constructor(
        address _dynamicVault,
        address _lendingVault,
        address _memeRegistry,
        address _treasury,
        address _insuranceFund
    ) {
        require(_dynamicVault != address(0), "LiquidationEngine: Invalid dynamic vault");
        require(_lendingVault != address(0), "LiquidationEngine: Invalid lending vault");
        require(_memeRegistry != address(0), "LiquidationEngine: Invalid meme registry");
        require(_treasury != address(0), "LiquidationEngine: Invalid treasury");
        require(_insuranceFund != address(0), "LiquidationEngine: Invalid insurance fund");

        dynamicVault = DynamicRangeVault(_dynamicVault);
        lendingVault = PillarLendingVault(_lendingVault);
        memeRegistry = MemeTokenRegistry(_memeRegistry);
        treasury = _treasury;
        insuranceFund = _insuranceFund;
    }

    // ================================================================================================
    // LIQUIDATION FUNCTIONS
    // ================================================================================================

    /**
     * @notice Check if position can be liquidated
     */
    function canLiquidate(uint256 _positionId) 
        external 
        view 
        returns (bool canLiq, string memory reason) 
    {
        DynamicRangeVault.Position memory position = dynamicVault.getPositionDetails(_positionId);
        
        if (position.owner == address(0)) {
            return (false, "Position does not exist");
        }
        
        if (position.status == 2 || position.status == 3) { // LIQUIDATED or CLOSED
            return (false, "Position already liquidated/closed");
        }

        // Check daily limits
        uint256 today = block.timestamp / 86400;
        if (dailyLiquidationCount[today] >= MAX_LIQUIDATIONS_PER_DAY) {
            return (false, "Daily liquidation limit reached");
        }

        // Trigger 1: Health ratio check
        uint256 healthRatio = dynamicVault.getPositionHealthRatio(_positionId);
        uint256 threshold = _getLiquidationThreshold(position.targetAsset);
        
        bool healthRatioTrigger = healthRatio < threshold;
        
        // Trigger 2: Range exit check
        bool rangeExitTrigger = !dynamicVault.isPositionInRange(_positionId);
        
        if (!healthRatioTrigger && !rangeExitTrigger) {
            return (false, "Position is healthy and in range");
        }

        // Check grace period
        bool gracePeriodExpired = block.timestamp.sub(position.lastUpdateTime) >= GRACE_PERIOD;
        
        if (!gracePeriodExpired) {
            return (false, "Grace period not expired");
        }

        return (true, "Position can be liquidated");
    }

    /**
     * @notice Liquidate a position
     */
    function liquidatePosition(uint256 _positionId) 
        external 
        nonReentrant 
    {
        (bool canLiq, string memory reason) = this.canLiquidate(_positionId);
        require(canLiq, reason);

        DynamicRangeVault.Position memory position = dynamicVault.getPositionDetails(_positionId);
        
        // Execute liquidation through DynamicVault
        dynamicVault.forceLiquidatePosition(_positionId);

        // Update daily tracking
        uint256 today = block.timestamp / 86400;
        dailyLiquidationCount[today] = dailyLiquidationCount[today].add(1);

        emit LiquidationExecuted(
            _positionId,
            msg.sender,
            position.collateralAmount,
            position.debtAmount,
            position.collateralAmount.percentMul(KEEPER_REWARD_BPS),
            position.collateralAmount.percentMul(300)
        );
    }

    /**
     * @notice Calculate liquidation reward for keeper
     */
    function calculateLiquidationReward(uint256 _positionId) 
        external 
        view 
        returns (uint256 keeperReward, uint256 protocolFee) 
    {
        DynamicRangeVault.Position memory position = dynamicVault.getPositionDetails(_positionId);
        
        keeperReward = position.collateralAmount.percentMul(KEEPER_REWARD_BPS);
        protocolFee = position.collateralAmount.percentMul(PROTOCOL_FEE_BPS);
    }

    function _getLiquidationThreshold(address _asset) internal view returns (uint256) {
        if (liquidationThresholds[_asset] != 0) {
            return liquidationThresholds[_asset];
        }
        
        // Use meme token threshold if applicable
        if (memeRegistry.isTokenWhitelisted(_asset)) {
            return MEME_LIQUIDATION_THRESHOLD;
        }
        
        return DEFAULT_LIQUIDATION_THRESHOLD;
    }

    // ================================================================================================
    // ADMIN FUNCTIONS
    // ================================================================================================

    function setLiquidationThreshold(address _asset, uint256 _threshold) external onlyOwner {
        require(_threshold >= 5000 && _threshold <= 9500, "LiquidationEngine: Invalid threshold");
        
        uint256 oldThreshold = liquidationThresholds[_asset];
        liquidationThresholds[_asset] = _threshold;
        
        emit LiquidationThresholdUpdated(_asset, oldThreshold, _threshold);
    }

    function updateTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "LiquidationEngine: Invalid treasury");
        treasury = _newTreasury;
    }

    function updateInsuranceFund(address _newInsuranceFund) external onlyOwner {
        require(_newInsuranceFund != address(0), "LiquidationEngine: Invalid insurance fund");
        insuranceFund = _newInsuranceFund;
    }
}
