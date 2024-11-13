// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Library for the Byzantine Auction Mathematics
/// @dev The library is used to calculate the Validation Credit price, the bid price, the (average) auction scores and a cluster id
library ByzantineAuctionMath {

    uint256 private constant _WAD = 1e18;
    uint256 private constant _RAY = 1e27;
    uint240 private constant _DURATION_WEIGHT = 10001;
    uint16 private constant _DISCOUNT_RATE_SCALE = 1e4;

    /**
     * @notice Calculate and returns the daily Validation Credit price (in WEI)
     * @param _expectedDailyReturnWei: expected Ethereum daily staking return (in WEI). Changes over time depending on the Ethereum state
     * @param _discountRate: discount rate (i.e the desired profit margin) in percentage (scale from 0 to _DISCOUNT_RATE_SCALE)
     * @param _clusterSize: number of nodes in the Distributed Validator the operator is willing to join
     * @dev vc_price = dailyPosRewards*(1 - discount_rate)/cluster_size
     */
    function calculateVCPrice(
        uint256 _expectedDailyReturnWei,
        uint16 _discountRate,
        uint8 _clusterSize
    ) internal pure returns (uint256) {
        return (_expectedDailyReturnWei * (_DISCOUNT_RATE_SCALE - _discountRate)) / (_clusterSize * _DISCOUNT_RATE_SCALE);
    }

    /**
     * @notice Calculate and returns the bid price that should be paid by the node operator (in WEI)
     * @param _timeInDays: duration committed to be a validator, in days
     * @param _dailyVcPrice: daily Validation Credit price (in WEI)
     * @dev bid_price = time_in_days * vc_price
     */
    function calculateBidPrice(
        uint32 _timeInDays,
        uint256 _dailyVcPrice
    ) internal pure returns (uint256) {
        return _timeInDays * _dailyVcPrice;
    }

    /**
     * @notice Calculate and returns the auction score of a node operator
     * @notice The equation incentivize the node operators to commit for a longer duration
     * @param _dailyVcPrice: daily Validation Credit price (in WEI)
     * @param _timeInDays: duration committed to be a validator, in days
     * @param _reputation: reputation score of the operator
     * @dev powerValue = 1.0001**_timeInDays
     * @dev The result is divided by 1e18 to downscaled from 1e36 to 1e18
     */
    function calculateAuctionScore(
        uint256 _dailyVcPrice,
        uint32 _timeInDays,
        uint32 _reputation
    ) internal pure returns (uint256) {
        uint256 powerValue = _pow(_timeInDays);
        return (_dailyVcPrice * powerValue * _reputation) / _WAD;
    }

    /**
     * @notice Calculate the average auction score from an array of scores
     * @param _auctionScores An array of auction scores
     */
    function calculateAverageAuctionScore(uint256[] memory _auctionScores) internal pure returns (uint256) {        
        uint256 sum = 0;
        for (uint256 i = 0; i < _auctionScores.length;) {
            sum += _auctionScores[i];
            unchecked {
                ++i;
            }
        }
        return sum / _auctionScores.length;
    }

    /**
     * @notice Generate a unique cluster ID based on timestamp, addresses, and average auction score
     * @param _timestamp The current block timestamp during the cluster creation
     * @param _addresses The addresses making up the cluster
     * @param _averageAuctionScore The average auction score of the cluster
     * @return bytes32 The generated cluster ID
     */
    function generateClusterId(
        uint256 _timestamp,
        address[] memory _addresses,
        uint256 _averageAuctionScore
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_timestamp, _averageAuctionScore, _addresses));
    }

    /* ===================== PRIVATE HELPERS ===================== */

    /**
     * @notice Calculate the power value of 1.0001**_timeInDays
     * @dev The result is divided by 1e9 to downscaled to 1e18 as the return value of `rpow` is upscaled to 1e27
     */
    function _pow(uint32 _timeIndays) private pure returns (uint256) {
        uint256 fixedPoint = _DURATION_WEIGHT * 1e23;
        return _rpow(fixedPoint, uint256(_timeIndays)) / 1e9;
    }

    // This famous algorithm is called "exponentiation by squaring"
    // and calculates x^n with x as fixed-point and n as regular unsigned.
    //
    // It's O(log n), instead of O(n) for naive repeated multiplication.
    //
    // These facts are why it works:
    //
    //  If n is even, then x^n = (x^2)^(n/2).
    //  If n is odd,  then x^n = x * x^(n-1),
    //   and applying the equation for even x gives
    //    x^n = x * (x^2)^((n-1) / 2).
    //
    //  Also, EVM division is flooring and
    //    floor[(n-1) / 2] = floor[n / 2].
    //
    function _rpow(uint256 x, uint256 n) private pure returns (uint256 z) {
        z = n % 2 != 0 ? x : _RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = _rmul(x, x);

            if (n % 2 != 0) {
                z = _rmul(z, x);
            }
        }
    }

    //rounds to zero if x*y < WAD / 2
    function _rmul(uint256 x, uint256 y) private pure returns (uint256 z) {
        z = _add(_mul(x, y), _RAY / 2) / _RAY;
    }

    function _add(uint256 x, uint256 y) private pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function _mul(uint256 x, uint256 y) private pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
}