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

  /**
   * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
   * reverts when dividing by zero.
   */
  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0, "SafeMath#mod: DIVISION_BY_ZERO");
    return a % b;
  }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

}

interface ITRC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ITRCLP20 {
    function getTokenToTrxInputPrice(uint256 tokens_sold) external view returns (uint256);
    function tokenAddress() external view returns (ITRC20);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface TRC20LPPool{
    function earned(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    // function rewardRate() external view returns (uint256);
    function rewardsPerSecond() external view returns (uint256);
    function tokenAddr() external view returns (ITRCLP20);
}

interface Ivote{
    struct VotedSlope{
    uint256 slope;
    uint256 power;
    uint256 end;
    }
    
    function vote_user_power(address arg0) external view returns(uint256);
    function vote_user_slopes(address arg0,address arg1) external view returns(VotedSlope memory);
}


interface ISspStaker{
    struct LockedBalance {
        uint256 amount;
        uint256 unlockTime;
    }
    function userLocks(address) external view returns(LockedBalance[] memory);
}

interface IGague{
    function working_supply() external view returns (uint256);
    function working_balances(address account) external view returns (uint256); 
    function sub_pool() external view returns(address);
    function claimable_reward_for(address) external view returns(uint256);
    function claimable_tokens(address) external view returns(uint256);
    function boostedBalanceOf(address) external view returns(uint256);
    function totalBoostedSupply() external view returns(uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);

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
    function flexibleCanClaim() external view returns (bool);
    function lockCanClaim() external view returns (bool);

}



interface IVesun{
    function balanceOf(bytes32) external view returns (uint256);
}



contract ValuesAggregator {

    using SafeMath for uint256;
    struct tokenInfo{
        uint256 token_balance;
        uint256 token_allowance;
    }
    constructor() public{
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // function periodFinish (ISubPool pool) internal view returns (uint) {
    //     return pool.periodFinish();
    // }

    // function rewardPerTokenStored(ISubPool pool) internal view returns (uint) {
    //     return pool.rewardPerTokenStored();
    // }

    function lastTimeRewardApplicable(ISubPool pool, uint256 time) public view returns (uint256) { 
        return min(time, pool.periodFinish());
    }

    function rewardPerToken(ISubPool pool) public view returns (uint256) {
        return
        pool.rewardPerTokenStored().add(
            pool.lastTimeRewardApplicable()
            .sub(pool.lastUpdateTime())
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

    function getALL(ISubPool pool, address[] memory _user) public view returns(uint _total, uint256[] memory _amount){
        uint len = _user.length;
        _amount = new uint[](len);
        uint _rewardPerToken = rewardPerToken(pool);

        for(uint i = 0; i < len; i++){
            address _u = _user[i];
            uint _earn = earned(pool, _u, _rewardPerToken);
            _amount[i] = _earn;
            _total += _earn;
        }
        
    }

    function getSuperGaugeInfo(address[] memory _pools,address _user) public view returns(
        uint256[] memory _totalSupply, uint256[] memory _userLockAmount, 
        uint256[] memory _lockRewards,uint256[] memory _remainingTime, 
        uint256[] memory _lockDuration, bool[] memory _flexibleCanClaim,
        bool[] memory _lockCanClaim){
        
        uint256 length = _pools.length;
        _totalSupply = new uint256[](length);
        _userLockAmount = new uint256[](length);
        // _governanceRewards = new uint256[](length);
        _remainingTime = new uint256[](length);
        _lockRewards = new uint256[](length);
        _lockDuration = new uint256[](length);
        _flexibleCanClaim = new bool[](length);
        _lockCanClaim = new bool[](length);
        for(uint256 i = 0; i < length; i++){
            //查询出subPool合约
            address subPool = IGague(_pools[i]).sub_pool();

            _totalSupply[i] = IGague(_pools[i]).totalSupply();
            _userLockAmount[i] = IGague(_pools[i]).balanceOf(address(_user));
            // _governanceRewards[i] = IGague(_pools[i]).claimable_tokens(_user);
            _lockRewards[i] = IGague(_pools[i]).claimable_reward_for(_user);
            _remainingTime[i] = ISubPool(subPool).getLatestEndTime(_user);
            _lockDuration[i] = ISubPool(subPool).userInfo(_user).lockDuration;
            _flexibleCanClaim[i] = ISubPool(subPool).flexibleCanClaim();
            _lockCanClaim[i] = ISubPool(subPool).lockCanClaim();
            //uint256 lockDuration = ISubPool(subPool).userInfo(_user).lockDuration;
            // uint256 lockEndTime = 0;
            // if(lockDuration == 0){
            //      _remainingTime[i] = 0;
            // }else{
            //     uint256 lockStartTime = ISubPool(subPool).userInfo(_user).lockStartTime;
            //     lockEndTime  = lockStartTime + lockDuration;
            //     while(lockEndTime < block.timestamp){
            //         lockEndTime += lockDuration;
            //     }
            //     _remainingTime[i] = lockEndTime;
            // }
            
        }

    }


    // 锁定池加速倍数
    function calculateBoosted(address[] memory _pools, address _user, address _vesun) public view returns(uint256[] memory _multiple, uint256[] memory _currentAmount, uint256[] memory _futureAmount){
        uint256 length = _pools.length;
        _multiple = new uint256[](length);
        _currentAmount = new uint256[](length);
        _futureAmount = new uint256[](length);
        for(uint256 i = 0; i < length; i++){
            uint256 balance = IGague(_pools[i]).balanceOf(address(_user));
            uint256 boostedBalance = IGague(_pools[i]).boostedBalanceOf(_user);
            if(balance == 0 || boostedBalance ==0){
                _multiple[i] =  0;
            }else{
                _multiple[i] = boostedBalance * 1e18 / balance;
            }
            (_currentAmount[i], _futureAmount[i]) = _current(_pools[i], _user, _vesun);
        }

    }

    // function _calculateBoosted(uint256 amount, uint256 lockDuration) public view returns (uint256) {
    //     if (lockDuration == 0) {
    //         return amount;
    //     }
    //     uint256 boostWeight = (lockDuration * 2000 * 1e10) / 365 days;
    //     return amount + amount * boostWeight / 1e12;
    // }


   
       // vote 投票权查询
    function getVotePower(address _vote,address _user, address[] memory _votetoAddress) public view returns(uint256 userUsedPower,uint256[] memory votePower){
        uint256 _voteCount = _votetoAddress.length;
        votePower = new uint256[](_voteCount);
        userUsedPower = Ivote(_vote).vote_user_power(_user);
        for(uint256 i = 0; i < _voteCount; i++){
            Ivote.VotedSlope memory _info = Ivote(_vote).vote_user_slopes(_user,_votetoAddress[i]);
            votePower[i] = _info.power;
        }
    }

    // guage 查询, 未登录时
    function getGaugeTotalsupply(address[] memory _pools) public view returns(uint256[] memory _totalSupply,uint256[] memory _working_supply){
        uint256 length = _pools.length;
        _totalSupply = new uint256[](length);
        _working_supply = new uint256[](length);
        for(uint256 i = 0; i < length; i++){
            _totalSupply[i] = ITRC20(_pools[i]).totalSupply();
            _working_supply[i] = IGague(_pools[i]).working_supply();
        }

    }

    function getGaugeInfo(address[] memory _pools,address _user,address _vesun) public view returns(
        uint256[] memory _totalSupply, uint256[] memory _userDepositAmount,uint256[] memory _currentAmount, uint256[] memory _futureAmount){
        uint256 length = _pools.length;
        _totalSupply = new uint256[](length);
        _userDepositAmount = new uint256[](length);
        _currentAmount = new uint256[](length);
        _futureAmount = new uint256[](length);
        for(uint256 i = 0; i < length; i++){
            _totalSupply[i] = ITRC20(_pools[i]).totalSupply();
            _userDepositAmount[i] = ITRC20(_pools[i]).balanceOf(address(_user));
            (_currentAmount[i], _futureAmount[i]) = _current(_pools[i], _user, _vesun);
        }

    }

    // voting_balance, voting_total, working_balance, working_supply, gaugeBalance - l ,gaugeTotalsupply  -L
    function calcBoost(address _vesun, address _pool, address _user) public view returns(uint256[] memory info){
        info = new uint256[](6);
        info[0] = IVesun(_vesun).balanceOf(bytes32(uint256(_user)));
        info[1] = ITRC20(_vesun).totalSupply();
        info[2] = IGague(_pool).working_balances(_user);
        info[3] = IGague(_pool).working_supply();
        info[4] = IGague(_pool).boostedBalanceOf(_user);
        info[5] = IGague(_pool).totalBoostedSupply();
        
    }
    // 定期存款挖矿
    function _current(address  _pool, address _user, address _vesun) public view returns(uint256 current,uint256 future){
        uint256 working_balance = IGague(_pool).working_balances(_user);
        uint256 working_supply = IGague(_pool).working_supply();
        uint256 gaugeBalance = IGague(_pool).boostedBalanceOf(_user);
        uint256 gaugeTotalsupply = IGague(_pool).totalBoostedSupply();
        uint256 voting_balance = IVesun(_vesun).balanceOf(bytes32(uint256(_user)));
        uint256 voting_total = ITRC20(_vesun).totalSupply();
        // uint256 TOTAL = gaugeTotalsupply + gaugeBalance; 
        if( working_supply > 0 && voting_total > 0 && gaugeBalance > 0){
            uint256 A = working_balance * 1e18 / working_supply;
            uint256 B = (gaugeBalance*40* 1e18/100) /(working_supply - working_balance + 40*gaugeBalance/100);
            if(B == 0){
                B = 1;
            }
            current = A * 1e18 /B;
            uint256 lim = gaugeBalance*40/100;
            lim += gaugeTotalsupply * voting_balance/voting_total*60/100;
            lim = gaugeBalance.min(lim);
            
            uint256 C = lim * 1e18/(working_supply - working_balance + lim);
            
            future = C * 1e18 / B;
        }
    }



    function getBalanceAndApprove2(address _user , address[] memory _tokens , address[] memory _pools) public view returns(tokenInfo[] memory info){
        uint256 _tokenCount = _tokens.length;
        require(_tokenCount == _pools.length,'array length not matched');
        info = new tokenInfo[](_tokenCount);
        for(uint256 i = 0; i < _tokenCount; i++){
            uint256 token_amount = 0;
            uint256 token_allowance = 0;
            if(address(0) == _tokens[i]){
                token_amount = address(_user).balance;
                token_allowance = uint256(-1);
            }else{
                ( bool success, bytes memory data) = _tokens[i].staticcall(abi.encodeWithSelector(0x70a08231, _user));
                success;
                token_amount = 0;
                if(data.length != 0){
                    token_amount = abi.decode(data,(uint256));
                }
                token_allowance = ITRC20(_tokens[i]).allowance(_user,address(_pools[i]));
            }
            info[i] = tokenInfo(token_amount,token_allowance);
        }
    }


    function getBalanceAndApprove(address _user , address[] memory _tokens , address[] memory _pools) public view returns(uint256[] memory info, uint256[] memory _allowance){
        uint256 _tokenCount = _tokens.length;
        require(_tokenCount == _pools.length,'array length not matched');
        info = new uint256[](_tokenCount);
        for(uint256 i = 0; i < _tokenCount; i++){
            uint256 token_amount = 0;
            uint256 token_allowance = 0;
            if(address(0) == _tokens[i]){
                token_amount = address(_user).balance;
                token_allowance = uint256(-1);
            }else{
                ( bool success, bytes memory data) = _tokens[i].staticcall(abi.encodeWithSelector(0x70a08231, _user));
                success;
                token_amount = 0;
                if(data.length != 0){
                    token_amount = abi.decode(data,(uint256));
                }
                token_allowance = ITRC20(_tokens[i]).allowance(_user,address(_pools[i]));
            }
            info[i] = uint256(token_amount);
            _allowance[i] = uint256(token_allowance);
        }
    }


    function getBalance(address _user , address[] memory _tokens) public view returns(uint256[] memory info){
        uint256 _tokenCount = _tokens.length;
        info = new uint256[](_tokenCount);
        for(uint256 i = 0; i < _tokenCount; i++){
            uint256 token_amount = 0;
            if(address(0) == _tokens[i]){
                token_amount = address(_user).balance;
            }else{
                ( bool success, bytes memory data) = _tokens[i].staticcall(abi.encodeWithSelector(0x70a08231, _user));
                success;
                token_amount = 0;
                if(data.length != 0){
                    token_amount = abi.decode(data,(uint256));
                }
            }
            info[i] = uint256(token_amount);
        }
    }



}
