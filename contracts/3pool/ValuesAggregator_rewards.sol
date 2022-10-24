pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;


/**
 * @title SafeMath
 * @dev Unsigned math operations with safety checks that revert on error
 */
library SafeMath {

    /**
     * @dev Multiplies two unsigned integers, reverts on overflow.
   */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath#mul: OVERFLOW");

        return c;
    }

    /**
     * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
   */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, "SafeMath#div: DIVISION_BY_ZERO");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
   */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath#sub: UNDERFLOW");
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Adds two unsigned integers, reverts on overflow.
   */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath#add: OVERFLOW");

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }

}


interface ISubPool{
    struct UserInfo {
        uint256 boostedBalance;
        uint256 rewardPerTokenPaid;
        uint256 rewards;
        uint256 prevRewards; // rewards till current lastActionTime.
        uint256 lockStartTime; // lock start time.
        uint256 lockDuration; //lock duration.
        uint256 lastActionTime;
    }
    function periodFinish() external view returns(uint) ;
    function rewardRate() external view returns(uint) ;
    function lastUpdateTime() external view returns(uint) ;
    function rewardPerTokenStored() external view returns(uint) ;
    function totalBoostedSupply() external view returns(uint) ;
    function lastTimeRewardApplicable() external view returns(uint) ;
    function boostedBalanceOf(address account) external view returns (uint256);

    function userInfo(address) external view returns(UserInfo memory);
    function overdueDuration(address account) external view returns (bool, uint256, uint256, uint256, uint256);
    function getLatestEndTime(address) external view returns (uint256);
    function maintenanceDuration() external view returns (uint256);
    function flexibleCanClaim() external view returns (bool);
    function lockCanClaim() external view returns (bool);

}

contract ValuesAggregator {
    using SafeMath for uint256;

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    function rewardPerToken(ISubPool pool, uint256 time) public view returns (uint256) {
        return
        pool.rewardPerTokenStored().add(time.sub(pool.lastUpdateTime())
            .mul(pool.rewardRate())
            .mul(1e18)
            .div(pool.totalBoostedSupply())
        );
    }

    function userInfo(ISubPool pool, address user) internal view returns(ISubPool.UserInfo memory) {
        return pool.userInfo(user);
    }

    function earned(ISubPool pool, address account, uint _rewardPerToken) public view returns (uint256) {
        ISubPool.UserInfo memory _userInfo = userInfo(pool, account);
        return
        pool.boostedBalanceOf(account)
        .mul(_rewardPerToken.sub(_userInfo.rewardPerTokenPaid))
        .div(1e18)
        .add(_userInfo.rewards);
    }

    function getALL(ISubPool pool, uint256 time, address[] memory _user) public view returns(uint _total, uint256[] memory _amount){
        uint len = _user.length;
        _amount = new uint[](len);
        uint _rewardPerToken = rewardPerToken(pool,time);

        for(uint i = 0; i < len; i++){
            address _u = _user[i];
            uint _earn = earned(pool, _u, _rewardPerToken);
            _amount[i] = _earn;
            _total += _earn;
        }
        
    }


    function overdueDuration(ISubPool pool, address account, uint256 time) public view returns (bool, bool, uint256){
        ISubPool.UserInfo memory _userInfo = userInfo(pool, account);
        uint _maintenanceDuration = pool.maintenanceDuration();
        uint256 duration = _userInfo.lockDuration;
        if (duration == 0) {
            return (true, true, 0);
        }
        uint256 totalTime = time.sub(_userInfo.lockStartTime);
        uint256 round = totalTime.div(duration);
        uint256 overdue = totalTime.mod(duration);
        if (round < 1 || overdue > _maintenanceDuration || time < _userInfo.lastActionTime) {
            return (false, false, 0);
        }
        return (true, false, overdue);
    }


    function getLockALL(ISubPool pool, uint256 timeFrom, uint256 timeTo, address[] memory _user) public view returns(uint _totalFlexible, uint _totalLock,  uint256[] memory _amount){
        uint len = _user.length;
        _amount = new uint256[](len);
        uint256 _rewardPerToken = 0;
        for(uint256 i = 0; i < len; i++){
            address _u = _user[i];
            uint256 time = 0;
            {
                (bool LockAllow,bool flexible,) = overdueDuration(pool, _u, timeTo);
                if(LockAllow){
                    time = timeTo;
                }else{
                    (LockAllow,,) = overdueDuration(pool, _u, timeFrom);
                    if(LockAllow){
                        time = timeFrom;
                    }
                }
                
                if(time > 0){
                {
                    _rewardPerToken = rewardPerToken(pool,time);
                    uint _earn = earned(pool, _u, _rewardPerToken);
                    _amount[i] = _earn;
                    // _total += _earn;
                    if(flexible){
                        _totalFlexible += _earn;
                    }else{
                        _totalLock += _earn;
                    }
                }
                }
            }
        }

    }

}