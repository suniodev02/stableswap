pragma solidity >=0.6.0 <0.8.0;

import "../staker/utils/IERC20.sol";
import "../staker/utils/SafeERC20.sol";
import "../staker/utils/Ownable.sol";

interface IStableSwap {
    function exchange(uint128 i, uint128 j, uint dx, uint min_dy) external;

    function coins(uint i) external returns (IERC20);
}

interface IMultiFeeDistribution {
    function burn(IERC20 rewardsToken) external returns (bool);
}

contract FeeConverter2Pool is Ownable {
    using SafeERC20 for IERC20;

    address public feeDistributor;
    mapping(address => bool) public _pools;


    function setFeeDistributor(address distributor) external onlyOwner {
        feeDistributor = distributor;
    }


    function convertFees(uint i, uint j) external {
        IERC20 inputCoin = IStableSwap(msg.sender).coins(i);
        IERC20 outputCoin = IStableSwap(msg.sender).coins(j);

        uint256 balance = inputCoin.balanceOf(address(this));
        inputCoin.safeApprove(msg.sender, balance);
        IStableSwap(msg.sender).exchange(uint128(i), uint128(j), balance, 0);
    }

    function notify(IERC20 coin) external {
        uint256 balance = coin.balanceOf(address(this));
        coin.safeApprove(feeDistributor, balance);
        IMultiFeeDistribution(feeDistributor).burn(coin);
    }

}
