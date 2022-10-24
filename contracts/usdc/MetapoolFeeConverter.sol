pragma solidity 0.6.2;

import "../staker/utils/IERC20.sol";
import "../staker/utils/SafeERC20.sol";
import "../staker/utils/Ownable.sol";


interface IMultiFeeDistribution {
    function notifyRewardAmount(IERC20 rewardsToken, uint256 reward) external;
}

interface I3PSwap {
    function token() external view returns (IERC20);

    function exchange(uint128 i, uint128 j, uint dx, uint min_dy) external;

    function coins(uint i) external returns (IERC20);

    function remove_liquidity_one_coin(uint256 amount, uint128 i, uint256 min_amount) external;

}

interface IStableSwap {
    function exchange(int128 i, int128 j, uint dx, uint min_dy) external;

    function coins(uint i) external returns (IERC20);

    function base_pool() external returns (I3PSwap);

    function remove_liquidity_one_coin(uint256 amount, int128 i, uint256 min_amount) external;
}


contract MetapoolFeeConverter {
    using SafeERC20 for IERC20;

    address public feeDistributor;

    function setFeeDistributor(address distributor) external {
        require(feeDistributor == address(0));
        feeDistributor = distributor;
    }

    function convertFees() external {
        IERC20 inputCoin = IStableSwap(msg.sender).coins(0);
        IERC20 outputCoin = IStableSwap(msg.sender).coins(1);

        uint256 balance = inputCoin.balanceOf(address(this));
        inputCoin.safeApprove(msg.sender, balance);
        IStableSwap(msg.sender).exchange(0, 1, balance, 0);
        balance = outputCoin.balanceOf(address(this));

        I3PSwap basePool = IStableSwap(msg.sender).base_pool();
        outputCoin = basePool.coins(1);

        IERC20 _3sun = basePool.token();
        _3sun.safeApprove(address(basePool), balance);


        basePool.remove_liquidity_one_coin(balance, 1, 0);
        balance = outputCoin.balanceOf(address(this));
        outputCoin.approve(feeDistributor, balance);
        IMultiFeeDistribution(feeDistributor).notifyRewardAmount(outputCoin, balance);
    }

}