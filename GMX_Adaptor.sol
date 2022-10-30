// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeERC20, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PositionRouter } from "@gmx-contracts/contracts/core/PositionManager.sol";
import { Router } from "@gmx-contracts/contracts/core/Router.sol";
import { Reader } from "@gmx-contracts/contracts/peripherals/Reader.sol";
import { RewardRouter } from "@gmx-contracts/contracts/staking/RewardRouter.sol";
import { Vault } from "@gmx-contracts/contracts/core/Vault.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title GMX Adaptor - Arbitrum
 * @notice Allows Cellars to hold and interact with GMX Positions on Arbitrum.
 * @authors golfcm6, ash3156, nyle-g
 */
contract GMXAdaptor is BaseAdaptor {
    using SafeERC20 for ERC20;
    using Math for uint256;
    using SafeCast for uint256;
    using Address for address;


    //============================================ Global Functions ===========================================

    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("GMX Adaptor V 0.0"));
    }

    /**
     * @notice The GMX PositionRouter contract on Arbitrum Mainnet.
     */
    function positionRouter() internal pure returns (PositionRouter) {
        return PositionRouter(0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868);
    }

    /**
     * @notice The GMX Router contract on Arbitrum Mainnet.
     */
    function router() internal pure returns (Router) {
        return PositionRouter(0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868);
    }

    /**
     * @notice The GMX Reader contract on Arbitrum Mainnet.
     */
    function reader() internal pure returns (Reader){
        return Reader(0x22199a49A999c351eF7927602CFB187ec3cae489);
    }

    /**
     * @notice The GMX Reward Router contract on Arbitrum Mainnet (used for staking).
     */
    function rewardRouter() internal pure returns (RewardRouter){
        return RewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    }

    /**
     * @notice The GMX Vault contract on Arbitrum Mainnet.
     */
    function vault() internal pure returns (Vault){
        return Vault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    }

     //============================================ Implement Base Functions ===========================================
    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice User withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // adaptorData must include arrays of types of tokens - in order to be properly decoded, need to specify this length (hard coded to 5 for now)

        uint256[] positionBalances;
        uint256 tokenLengths = 5;
        (address[] memory _collateralTokens, address[] memory _indexTokens, bool[] memory _isLong) = abi.decode(adaptorData, (tokenLengths, tokenLengths, tokenLengths));


        // call the getPositions function for the given values to see all positions for the user
        uint256[] memory allPositions = reader.getPositions(address(Vault), msg.sender(), _collateralTokens, _indexTokens, _isLong);

        // position we want is found in same way getPositionKey in Vault.sol works
        // current value of position is under size (see https://gmxio.gitbook.io/gmx/contracts), which is index 0
        return allPositions[keccak256(abi.encodePacked(
                                            msg.sender(),
                                            _collateralToken,
                                            _indexToken,
                                            _isLong))][0];
        
    }

    /**
     * @notice Returns `token0`
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategist to open or increase positions (GMX uses the same function for either).
     * @param addingCollateral true if adding collateral (must be true where opening position)
     * @param token the token you are trading with
     * @param collateralToken if opening up a position (or adding more collateral), the collateral token you are using
     * @param indexToken address of the token you want to long or short
     * @param amount amount of tokenIn you want to deposit as collateral
     * @param minOut the min amount of collateralToken to swap for
     * @param sizeDelta the USD value of the change in position size 
     * @param isLong long or shorting
     * @param acceptablePrice the USD value of the max (for longs) or min (for shorts) index price accepted when opening the position
     * @param executionFee execution fee, normally set to PositionRouter.minExecutionFee
     * @param referralCode referral code for GMX
     * @param callbackTarget callback address if action fails (can leave address(0))
     */
    function openIncreasePosition(
        bool addingCollateral,
        ERC20 tokenIn,
        ERC20 collateralToken,
        ERC20 indexToken,
        uint256 amount,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        bytes32 referralCode,
        address callbackTarget
    ) public {
        // Approve PositionRouter to spend `token`
        tokenIn.safeApprove(address(positionRouter()), amount);
        address [] memory path;

        // check if adding collateral
        if (addingCollateral){
            path = [address(tokenIn), address(collateralToken)];
        }
        else {
            path = [address(tokenIn)];
        }

        // call function through Position Router
        PositionRouter.createIncreasePosition(
            path,
            address(indexToken),
            amount,
            minOut,
            sizeDelta,
            isLong,
            acceptablePrice,
            executionFee,
            referralCode,
            callbackTarget            
        );


    }


    /**
     * @notice Allows strategist to close or decrease position.
     * @param path path the strategist is taking for position
     * @param collateralToken the collateral token of the position
     * @param indexToken the index token of the position
     * @param collateralDelta the amount of collateral in USD value to withdraw
     * @param sizeDelta the USD value of the change in position size
     * @param isLong whether the position is a long or short
     * @param receiver the receiver's address
     * @param acceptablePrice the USD value of the max (for longs) or min (for shorts) index price accepted when opening the position
     * @param minOut see above function for increasing position
     * @param executionFee see above function for increasing position
     * @param withdrawEth whether to withdraw decreased position in Ethereum
     * @param callbackTarget see above function for increasing position
     */
    function closeDecreasePosition(
        address[] path,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        bool withdrawETH,
        address callbackTarget
    ) public {
        // Decrease liquidity in pool.
        PositionRouter.createDecreasePosition(
            path,
            indexToken,
            collateralDelta,
            sizeDelta,
            isLong,
            receiver,
            acceptablePrice,
            minOut,
            executionFee,
            withdrawETH,
            callbackTarget
        );
    }



    /**
     * @notice Allows strategist to swap tokens on GMX.
     * @param tokenIn token being swapped in
     * @param tokenOut token being swapped for
     * @param amountIn amount of tokenIn being swapped for tokenOut
     * @param minOut minimum of tokenOut being required for swap to happen
     * @param receiver address of receiver of swap
     */
    function swap(
        ERC20 tokenIn,
        ERC20 tokenOut,
        uint256 amountIn,
        uint128 minOut,
        address receiver
    ) public {
        // Approve tokens
        tokenIn.safeApprove(address(router()), amountIn);
        
        
        // call Router swap function
        Router.swap(
            [tokenIn, tokenOut],
            amountIn,
            minOut,
            receiver
        );
    }

    /**
     * @notice Returns to strategists info on the maximum amnt of TokenIn that can be swapped
     * @param vault address of vault strategist is working with
     * @param tokenIn token being swapped in
     * @param tokenOut token being swapped for
     */
    function getMaxAmountIn(
        address vault,
        ERC20 tokenIn,
        ERC20 tokenOut
    ) public returns (uint256) {
        return Reader.getMaxAmountIn(
            vault,
            address(tokenIn),
            address(tokenOut)
        );
    }
    /**
     * @notice Returns to strategists info on a) how much of tokenOut you'd get swapping with tokenIn, b) amount in fees.
     * @param vault address of vault strategist is working with
     * @param tokenIn token being swapped in
     * @param tokenOut token being swapped for
     * @param amountIn amount of tokenIn being swapped
     */
    // two values returned, the first is amount returned after fees and the second value is the fee amount
    function getAmountOut(
        address vault,
        ERC20 tokenIn,
        ERC20 tokenOut,
        uint256 amountIn
    ) public returns (uint256, uint256){
        return Reader.getAmountOut(
            vault,
            address(tokenIn),
            address(tokenOut),
            amountIn
        );
    }

    /**
     * @notice Returns to strategists info on current positions held by user in vault.
     * @param vault address of vault strategist is working with
     * @param user address of user
     * @param collateralTokens list of collateral tokens being queried
     * @param indexTokens list of index tokens being queried
     * @param isLongs list of long/short positions
     */
    function getCurrentPositions(
        address vault,
        address user,
        address [] memory collateralTokens,
        address [] memory indexTokens,
        bool [] memory isLongs
    ) public returns (uint256[] memory){
        uint256 [] memory amounts = Reader.getPositions(
            vault,
            user,
            collateralTokens,
            indexTokens,
            isLongs
        );
        return amounts;
    }

    /**
     * @notice Allows strategist to stake GMX.
     * @param receiver receiver address of staked rewards
     * @param amount amount of GMX to stake
     */
    function stakingGMX(
        address receiver,
        uint256 amount
    ) public {
        RewardRouter.stakeGMXForAccount(
            receiver,
            amount
        );
    }

    /**
     * @notice Gives strategist information on amount of tokens in different pools.
     * @param token token strategist is interested in
     * @param poolOrReserved looking either for number of tokens in pool or reserved number of tokens
     */
    function queryAmounts(
        ERC20 token,
        bool poolOrReserved
    ) public returns (uint256) {
        if (poolOrReserved){
            return Vault.poolAmounts[address(token)];
        }
        else{
            return Vault.reservedAmounts[address(token)];
        }
    }
}