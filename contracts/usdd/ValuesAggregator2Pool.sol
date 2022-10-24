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

interface IStableSwap{
    function balances(uint256) external view returns (uint256);
    function token() external view returns(address);
}

interface ILpTokenStaker{
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }
    struct PoolInfo {
        ITRC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardTime; // Last second that reward distribution occurs.
        uint256 accRewardPerShare; // Accumulated rewards per share, times 1e12. See below.
        uint256 shareWeight; //Pool speed share points.
    }
    function userInfo(uint256,address)  external view returns(UserInfo memory);
    function poolInfo(uint256) external view returns (PoolInfo memory);
    function poolLength() external view returns (uint256);
    function lockedSupply() external view returns(uint256);
    function claimableReward(uint256 _pid, address _user) external view returns(uint256);
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
}

interface IVesun{
    function balanceOf(bytes32) external view returns (uint256);
}

contract ValuesAggregator2Pool {
    //SSP Exchange LP
    //ITRCLP20 public sspTokenLP = ITRCLP20(0x388f4cb3F6927EaD070F4888eCbd3AE2977159a2);//todo:

    using SafeMath for uint256;
    struct tokenInfo{
        uint256 token_balance;
        uint256 token_allowance;
    }
    address public stableSwap;

    constructor(address _stableSwap) public{
        stableSwap = _stableSwap;
    }
   
    function getToken() public view returns (address) {
        return IStableSwap(stableSwap).token();
    }
    function getSwapBalance() public view returns(uint256[] memory balances){
        balances = new uint256[](2);
        for(uint256 i = 0; i < 2; i++){
            balances[i] = IStableSwap(stableSwap).balances(i);
        }
    }

    function getBalancedProportion(address _sun3swap, address _usdcswap, address usdclp) public view 
        returns(uint256 usdcLpTotalSupply,uint256 sun3TotalSupply, uint256[] memory balances3pool, uint256[] memory balancesUsdc){
        balances3pool = new uint256[](3);
        balancesUsdc = new uint256[](2);

        for(uint256 i = 0; i < 3; i++){
            balances3pool[i] = IStableSwap(_sun3swap).balances(i);
        }

        for(uint256 i = 0; i < 2; i++){
            balancesUsdc[i] = IStableSwap(_usdcswap).balances(i);
        }

        address token = IStableSwap(_sun3swap).token();
        sun3TotalSupply = ITRC20(token).totalSupply();
        usdcLpTotalSupply = ITRC20(usdclp).totalSupply();

    }
    function getUSDCSwapBalance(address _usdc) public view returns(uint256[] memory balances){
        balances = new uint256[](2);
        for(uint256 i = 0; i < 2; i++){
            balances[i] = IStableSwap(_usdc).balances(i);
        }
    }

    function getUserLP_usdc(address _sun3swap, address _usdcswap, address usdclp, address usdcDepositer,address _user) public view 
        returns(uint256 userUsdcLpBalance,uint256 usdcLpTotalSupply, uint256 sun3LpTotalSupply, 
        uint256 userLpAllowance,uint256 userLpAllowanceUsdcSwap,
        uint256[] memory balances3pool,uint256[] memory balancesUsdc){
        
        userUsdcLpBalance = ITRC20(usdclp).balanceOf(_user);
        usdcLpTotalSupply = ITRC20(usdclp).totalSupply();
        address token = IStableSwap(_sun3swap).token();
        sun3LpTotalSupply = ITRC20(token).totalSupply();


        balancesUsdc = new uint256[](2);
        balances3pool = new uint256[](3);
        for(uint256 i = 0; i < 3; i++){
            balances3pool[i] = IStableSwap(_sun3swap).balances(i);
        }
        for(uint256 i = 0; i < 2; i++){
            balancesUsdc[i] = IStableSwap(_usdcswap).balances(i);
        }
        userLpAllowance = ITRC20(usdclp).allowance(_user,address(usdcDepositer));
        userLpAllowanceUsdcSwap = ITRC20(usdclp).allowance(_user,address(_usdcswap));
    }


    function getUserLP(address _user) public view returns(uint256 userLpBalance, uint256 lpTotalSupply,uint256 userLpAllowance,uint256[] memory balances){
        address token = getToken();
        userLpBalance = ITRC20(token).balanceOf(_user);
        lpTotalSupply = ITRC20(token).totalSupply();
        
        balances = new uint256[](2);
        for(uint256 i = 0; i < 2; i++){
            balances[i] = IStableSwap(stableSwap).balances(i);
        }
        userLpAllowance = ITRC20(token).allowance(_user,address(stableSwap));
    }

    // function fetchAPYofLpPool(address _lppooladdr)  public view returns( uint256 apy){
    //     TRC20LPPool trc20lpPool = TRC20LPPool(_lppooladdr);
    //     ITRCLP20 trc20lp = trc20lpPool.tokenAddr();
    //     // lp price(trx) = address(trc20lp).balance.mul(2) / trc20lp.totalSupply();
    //     // lp amount in trc20lpPool = trc20lpPool.totalSupply();
    //     uint256 lpTotal = trc20lpPool.totalSupply().mul(address(trc20lp).balance).mul(2).div(trc20lp.totalSupply());
    //     //ssp amountPerY
    //     uint256 amountPerY = trc20lpPool.rewardsPerSecond().mul(31_536_000);
    //     uint256 amountTrxPerY  = amountPerY * address(sspTokenLP).balance/sspTokenLP.tokenAddress().balanceOf(address(sspTokenLP));
    //     if(lpTotal > 0 ){
    //         apy = amountTrxPerY.mul(10**6).div(lpTotal);
    //     }   
    // }



    // function getSwapInfo() public view returns(uint256 _fee,uint256 _adminFee,uint256 _A){

    // }
    
   function getLpStaker(address _user,address _lp_staker) public view returns(uint256[] memory stakedBalance){
       uint256 length = ILpTokenStaker(_lp_staker).poolLength();
       stakedBalance = new uint256[](length);
       for(uint256 i = 0; i < length; i++){
         stakedBalance[i]  = ILpTokenStaker(_lp_staker).userInfo(i,_user).amount;
       }
   }

    function getLpStakerAll(address _user,address _lp_staker) public view returns(uint256[] memory claimableReward, uint256[] memory allocPoint){
       uint256 length = ILpTokenStaker(_lp_staker).poolLength();
       claimableReward = new uint256[](length);
       allocPoint = new uint256[](length);
       for(uint256 i = 0; i < length; i++){
         allocPoint[i]  = ILpTokenStaker(_lp_staker).poolInfo(i).allocPoint;
         claimableReward[i]  = ILpTokenStaker(_lp_staker).claimableReward(i,_user);
       }
   }

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



    function getHomeInfo(address sspToken,address _ssp_staker) public view returns(uint256 SspTotalSupply,uint256 lockedSupply){
        SspTotalSupply = ITRC20(sspToken).totalSupply();
        lockedSupply = ILpTokenStaker(_ssp_staker).lockedSupply();
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
        info[4] = ITRC20(_pool).balanceOf(_user);
        info[5] = ITRC20(_pool).totalSupply();
        
    }

    function _current(address  _pool, address _user, address _vesun) public view returns(uint256 current,uint256 future){
        uint256 working_balance = IGague(_pool).working_balances(_user);
        uint256 working_supply = IGague(_pool).working_supply();
        uint256 gaugeBalance = ITRC20(_pool).balanceOf(_user);
        uint256 gaugeTotalsupply = ITRC20(_pool).totalSupply();
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
