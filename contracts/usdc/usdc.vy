# (c) Curve.Fi, 2020

from vyper.interfaces import ERC20

interface CurveToken:
    def totalSupply() -> uint256: view
    def mint(_to: address, _value: uint256): nonpayable
    def burnFrom(_to: address, _value: uint256): nonpayable

interface Curve:
    def coins(i: uint256) -> address: view
    def get_virtual_price() -> uint256: view
    def calc_token_amount(amounts: uint256[BASE_N_COINS], deposit: bool) -> uint256: view
    #def calc_withdraw_one_coin(_token_amount: uint256, i: int128) -> uint256: view
    def fee() -> uint256: view
    #def get_dy(i: int128, j: int128, dx: uint256) -> uint256: view
    def get_dy_underlying(i: int128, j: int128, dx: uint256) -> uint256: view
    #def exchange(i: int128, j: int128, dx: uint256, min_dy: uint256): nonpayable
    def add_liquidity(amounts: uint256[BASE_N_COINS], min_mint_amount: uint256): nonpayable
    #def remove_liquidity_one_coin(_token_amount: uint256, i: int128, min_amount: uint256): nonpayable

interface FeeConverter:
    def convertFees(): nonpayable


# Events
event TokenExchange:
    buyer: indexed(address)
    sold_id: int128
    tokens_sold: uint256
    bought_id: int128
    tokens_bought: uint256

event TokenExchangeUnderlying:
    buyer: indexed(address)
    sold_id: int128
    tokens_sold: uint256
    bought_id: int128
    tokens_bought: uint256

event AddLiquidity:
    provider: indexed(address)
    token_amounts: uint256[N_COINS]
    fees: uint256[N_COINS]
    invariant: uint256
    token_supply: uint256

event RemoveLiquidity:
    provider: indexed(address)
    token_amounts: uint256[N_COINS]
    fees: uint256[N_COINS]
    token_supply: uint256

event RemoveLiquidityOne:
    provider: indexed(address)
    token_amount: uint256
    coin_amount: uint256
    token_supply: uint256

event RemoveLiquidityImbalance:
    provider: indexed(address)
    token_amounts: uint256[N_COINS]
    fees: uint256[N_COINS]
    invariant: uint256
    token_supply: uint256

event CommitNewAdmin:
    deadline: indexed(uint256)
    admin: indexed(address)

event NewAdmin:
    admin: indexed(address)

event CommitNewFee:
    deadline: indexed(uint256)
    fee: uint256
    admin_fee: uint256

event NewFee:
    fee: uint256
    admin_fee: uint256

event RampA:
    old_A: uint256
    new_A: uint256
    initial_time: uint256
    future_time: uint256

event StopRampA:
    A: uint256
    t: uint256


N_COINS: constant(int128) = 2
MAX_COIN: constant(int128) = N_COINS - 1

FEE_DENOMINATOR: constant(uint256) = 10 ** 10
PRECISION: constant(uint256) = 10 ** 18  # The precision to convert to
PRECISION_MUL: constant(uint256[N_COINS]) =  [1000000000000,1]
RATES: constant(uint256[N_COINS]) = [1000000000000000000000000000000,1000000000000000000]
BASE_N_COINS: constant(int128) = 3

# An asset which may have a transfer fee (USDT)
FEE_INDEX: constant(int128) = 3

MAX_ADMIN_FEE: constant(uint256) = 10 * 10 ** 9
MAX_FEE: constant(uint256) = 5 * 10 ** 9
MAX_A: constant(uint256) = 10 ** 6
MAX_A_CHANGE: constant(uint256) = 10

ADMIN_ACTIONS_DELAY: constant(uint256) = 3 * 86400
MIN_RAMP_TIME: constant(uint256) = 86400

coins: public(address[N_COINS])
balances: public(uint256[N_COINS])
fee: public(uint256)  # fee * 1e10
admin_fee: public(uint256)  # admin_fee * 1e10

owner: public(address)
fee_converter: public(address)
lp_token: public(address)

# Token corresponding to the pool is always the last one
BASE_CACHE_EXPIRES: constant(int128) = 10 * 60  # 10 min
base_pool: public(address)
base_virtual_price: public(uint256)
base_cache_updated: public(uint256)
base_coins: public(address[BASE_N_COINS])
base_lp: public(address)

A_PRECISION: constant(uint256) = 100
initial_A: public(uint256)
future_A: public(uint256)
initial_A_time: public(uint256)
future_A_time: public(uint256)

admin_actions_deadline: public(uint256)
transfer_ownership_deadline: public(uint256)
future_fee: public(uint256)
future_admin_fee: public(uint256)
future_owner: public(address)

is_killed: bool
kill_deadline: uint256
KILL_DEADLINE_DT: constant(uint256) = 2 * 30 * 86400
initialed: public(bool)


@external
def initial(
    _owner: address,
    _coinsA: address,
    _coinsB: address,
    _pool_token: address,
    _base_pool: address,
    _base_lp: address,
    _A: uint256,
    _fee: uint256,
    _admin_fee: uint256,
    _fee_converter: address,
):
    """
    @notice Contract constructor
    @param _owner Contract owner address
    @param _coins Addresses of ERC20 conracts of coins
    @param _pool_token Address of the token representing LP share
    @param _base_pool Address of the base pool (which will have a virtual price)
    @param _A Amplification coefficient multiplied by n * (n - 1)
    @param _fee Fee to charge for exchanges
    @param _admin_fee Admin fee
    """

    assert self.initialed == False

    self.initialed = True
    self.coins[0] = _coinsA
    self.coins[1] = _coinsB
    self.initial_A = _A * A_PRECISION
    self.future_A = _A * A_PRECISION
    self.fee = _fee
    self.admin_fee = _admin_fee
    self.owner = _owner
    self.kill_deadline = block.timestamp + KILL_DEADLINE_DT
    self.lp_token = _pool_token
    self.fee_converter = _fee_converter

    self.base_pool = _base_pool
    self.base_lp = _base_lp
    self.base_virtual_price = Curve(_base_pool).get_virtual_price()
    self.base_cache_updated = block.timestamp

    _resp: Bytes[32] = raw_call(
        _base_lp,
        concat(
            method_id("approve(address,uint256)"),
            convert(_base_pool, bytes32),
            convert(MAX_UINT256, bytes32),
        ),
        max_outsize=32,
    )

    for i in range(BASE_N_COINS):
        base_coin: address = Curve(_base_pool).coins(i)
        self.base_coins[i] = base_coin

        # approve underlying coins for infinite transfers
        response: Bytes[32] = raw_call(
            base_coin,
            concat(
                method_id("approve(address,uint256)"),
                convert(_base_pool, bytes32),
                convert(MAX_UINT256, bytes32),
            ),
            max_outsize=32,
        )
        if len(response) > 0:
            assert convert(response, bool)


@view
@internal
def call_get_dy(i: int128, j: int128, dx: uint256) -> uint256:
    result: Bytes[32] = raw_call(
        self.base_pool,
        concat(
            method_id('get_dy(uint128,uint128,uint256)'),
            convert(i, bytes32),
            convert(j, bytes32),
            convert(dx, bytes32),
        ),
        max_outsize=32,
        is_static_call=True
    )
    return convert(extract32(result, 0), uint256)


@view
@internal
def call_get_dy_underlying(i: int128, j: int128, dx: uint256) -> uint256:
    result: Bytes[32] = raw_call(
        self.base_pool,
        concat(
            method_id('get_dy_underlying(uint128,uint128,uint256)'),
            convert(i, bytes32),
            convert(j, bytes32),
            convert(dx, bytes32),
        ),
        max_outsize=32,
        is_static_call=True
    )
    return convert(extract32(result, 0), uint256)



@view
@internal
def call_calc_withdraw_one_coin(_token_amount: uint256, i: int128) -> uint256:
    result: Bytes[32] = raw_call(
        self.base_pool,
        concat(
            method_id('calc_withdraw_one_coin(uint256,uint128)'),
            convert(_token_amount, bytes32),
            convert(i, bytes32)
        ),
        max_outsize=32,
        is_static_call=True
    )
    return convert(extract32(result, 0), uint256)


@view
@external
def test_call_calc_withdraw_one_coin(_token_amount: uint256, i: int128) -> uint256:
    return self.call_calc_withdraw_one_coin(_token_amount,i)


@internal
def call_exchange(i: int128, j: int128, _dx: uint256, _min_dy: uint256) :
    result: Bytes[32] = raw_call(
        self.base_pool,
        concat(
            method_id('exchange(uint128,uint128,uint256,uint256)'),
            convert(i, bytes32),
            convert(j, bytes32),
            convert(_dx, bytes32),
            convert(_min_dy, bytes32)
        ),
        max_outsize=32,
        is_static_call=False
    )



@internal
def call_remove_liquidity_one_coin(_token_amount: uint256, i: int128, min_amount: uint256) :
    result: Bytes[32] = raw_call(
        self.base_pool,
        concat(
            method_id('remove_liquidity_one_coin(uint256,uint128,uint256)'),
            convert(_token_amount, bytes32),
            convert(i, bytes32),
            convert(min_amount, bytes32)
        ),
        max_outsize=32,
        is_static_call=False
    )

@view
@internal
def _A() -> uint256:
    """
    Handle ramping A up or down
    """
    t1: uint256 = self.future_A_time
    A1: uint256 = self.future_A

    if block.timestamp < t1:
        A0: uint256 = self.initial_A
        t0: uint256 = self.initial_A_time
        # Expressions in uint256 cannot have negative numbers, thus "if"
        if A1 > A0:
            return A0 + (A1 - A0) * (block.timestamp - t0) / (t1 - t0)
        else:
            return A0 - (A0 - A1) * (block.timestamp - t0) / (t1 - t0)

    else:  # when t1 == 0 or block.timestamp >= t1
        return A1


@view
@external
def A() -> uint256:
    return self._A() / A_PRECISION


@view
@external
def A_precise() -> uint256:
    return self._A()


@view
@internal
def _xp(_vp_rate: uint256) -> uint256[N_COINS]:
    result: uint256[N_COINS] = RATES
    result[MAX_COIN] = _vp_rate  # virtual price for the metacurrency
    for i in range(N_COINS):
        result[i] = result[i] * self.balances[i] / PRECISION
    return result


@pure
@internal
def _xp_mem(_vp_rate: uint256, _balances: uint256[N_COINS]) -> uint256[N_COINS]:
    result: uint256[N_COINS] = RATES
    result[MAX_COIN] = _vp_rate  # virtual price for the metacurrency
    for i in range(N_COINS):
        result[i] = result[i] * _balances[i] / PRECISION
    return result


@internal
def _vp_rate() -> uint256:
    if block.timestamp > self.base_cache_updated + BASE_CACHE_EXPIRES:
        vprice: uint256 = Curve(self.base_pool).get_virtual_price()
        self.base_virtual_price = vprice
        self.base_cache_updated = block.timestamp
        return vprice
    else:
        return self.base_virtual_price


@internal
@view
def _vp_rate_ro() -> uint256:
    if block.timestamp > self.base_cache_updated + BASE_CACHE_EXPIRES:
        return Curve(self.base_pool).get_virtual_price()
    else:
        return self.base_virtual_price


@pure
@internal
def _get_D(_xp: uint256[N_COINS], _amp: uint256) -> uint256:
    S: uint256 = 0
    Dprev: uint256 = 0

    for _x in _xp:
        S += _x
    if S == 0:
        return 0

    D: uint256 = S
    Ann: uint256 = _amp * N_COINS
    for _i in range(255):
        D_P: uint256 = D
        for _x in _xp:
            D_P = D_P * D / (_x * N_COINS)  # If division by 0, this will be borked: only withdrawal will work. And that is good
        Dprev = D
        D = (Ann * S / A_PRECISION + D_P * N_COINS) * D / ((Ann - A_PRECISION) * D / A_PRECISION + (N_COINS + 1) * D_P)
        # Equality with the precision of 1
        if D > Dprev:
            if D - Dprev <= 1:
                return D
        else:
            if Dprev - D <= 1:
                return D
    # convergence typically occurs in 4 rounds or less, this should be unreachable!
    # if it does happen the pool is borked and LPs can withdraw via `remove_liquidity`
    raise


@view
@internal
def _get_D_mem(_vp_rate: uint256, _balances: uint256[N_COINS], _amp: uint256) -> uint256:
    return self._get_D(self._xp_mem(_vp_rate, _balances), _amp)


@view
@external
def get_virtual_price() -> uint256:
    """
    @notice The current virtual price of the pool LP token
    @dev Useful for calculating profits
    @return LP token virtual price normalized to 1e18
    """
    amp: uint256 = self._A()
    vp_rate: uint256 = self._vp_rate_ro()
    xp: uint256[N_COINS] = self._xp(vp_rate)
    D: uint256 = self._get_D(xp, amp)
    # D is in the units similar to DAI (e.g. converted to precision 1e18)
    # When balanced, D = n * x_u - total virtual value of the portfolio
    token_supply: uint256 = CurveToken(self.lp_token).totalSupply()
    return D * PRECISION / token_supply


@view
@external
def calc_token_amount(_amounts: uint256[N_COINS], _is_deposit: bool) -> uint256:
    """
    @notice Calculate addition or reduction in token supply from a deposit or withdrawal
    @dev This calculation accounts for slippage, but not fees.
         Needed to prevent front-running, not for precise calculations!
    @param _amounts Amount of each coin being deposited
    @param _is_deposit set True for deposits, False for withdrawals
    @return Expected amount of LP tokens received
    """
    amp: uint256 = self._A()
    vp_rate: uint256 = self._vp_rate_ro()
    balances: uint256[N_COINS] = self.balances
    D0: uint256 = self._get_D_mem(vp_rate, balances, amp)
    for i in range(N_COINS):
        if _is_deposit:
            balances[i] += _amounts[i]
        else:
            balances[i] -= _amounts[i]
    D1: uint256 = self._get_D_mem(vp_rate, balances, amp)
    token_amount: uint256 = CurveToken(self.lp_token).totalSupply()
    diff: uint256 = 0
    if _is_deposit:
        diff = D1 - D0
    else:
        diff = D0 - D1
    return diff * token_amount / D0


@external
@nonreentrant('lock')
def add_liquidity(_amounts: uint256[N_COINS], _min_mint_amount: uint256) -> uint256:
    """
    @notice Deposit coins into the pool
    @param _amounts List of amounts of coins to deposit
    @param _min_mint_amount Minimum amount of LP tokens to mint from the deposit
    @return Amount of LP tokens received by depositing
    """
    assert not self.is_killed  # dev: is killed

    amp: uint256 = self._A()
    vp_rate: uint256 = self._vp_rate()
    old_balances: uint256[N_COINS] = self.balances

    # Initial invariant
    D0: uint256 = self._get_D_mem(vp_rate, old_balances, amp)

    lp_token: address = self.lp_token
    token_supply: uint256 = CurveToken(lp_token).totalSupply()
    new_balances: uint256[N_COINS] = old_balances

    for i in range(N_COINS):
        if token_supply == 0:
            assert _amounts[i] > 0  # dev: initial deposit requires all coins
        # balances store amounts of c-tokens
        new_balances[i] = old_balances[i] + _amounts[i]

    # Invariant after change
    D1: uint256 = self._get_D_mem(vp_rate, new_balances, amp)
    assert D1 > D0

    # We need to recalculate the invariant accounting for fees
    # to calculate fair user's share
    fees: uint256[N_COINS] = empty(uint256[N_COINS])
    D2: uint256 = D1
    mint_amount: uint256 = 0
    if token_supply > 0:
        fee: uint256 = self.fee * N_COINS / (4 * (N_COINS - 1))
        admin_fee: uint256 = self.admin_fee
        # Only account for fees if we are not the first to deposit
        for i in range(N_COINS):
            ideal_balance: uint256 = D1 * old_balances[i] / D0
            difference: uint256 = 0
            if ideal_balance > new_balances[i]:
                difference = ideal_balance - new_balances[i]
            else:
                difference = new_balances[i] - ideal_balance
            fees[i] = fee * difference / FEE_DENOMINATOR
            self.balances[i] = new_balances[i] - (fees[i] * admin_fee / FEE_DENOMINATOR)
            new_balances[i] -= fees[i]
        D2 = self._get_D_mem(vp_rate, new_balances, amp)
        mint_amount = token_supply * (D2 - D0) / D0
    else:
        self.balances = new_balances
        mint_amount = D1  # Take the dust if there was any

    assert mint_amount >= _min_mint_amount, "Slippage screwed you"

    # Take coins from the sender
    for i in range(N_COINS):
        if _amounts[i] > 0:
            # "safeTransferFrom" which works for ERC20s which return bool or not
            response: Bytes[32] = raw_call(
                self.coins[i],
                concat(
                    method_id("transferFrom(address,address,uint256)"),
                    convert(msg.sender, bytes32),
                    convert(self, bytes32),
                    convert(_amounts[i], bytes32),
                ),
                max_outsize=32,
            )
            if len(response) > 0:
                assert convert(response, bool)  # dev: failed transfer
            # end "safeTransferFrom"

    # Mint pool tokens
    CurveToken(lp_token).mint(msg.sender, mint_amount)

    log AddLiquidity(msg.sender, _amounts, fees, D1, token_supply + mint_amount)

    return mint_amount


@view
@internal
def _get_y(i: int128, j: int128, x: uint256, _xp: uint256[N_COINS]) -> uint256:
    """
    Calculate x[j] if one makes x[i] = x

    Done by solving quadratic equation iteratively.
    x_1**2 + x_1 * (sum' - (A*n**n - 1) * D / (A * n**n)) = D ** (n + 1) / (n ** (2 * n) * prod' * A)
    x_1**2 + b*x_1 = c

    x_1 = (x_1**2 + c) / (2*x_1 + b)
    """
    # x in the input is converted to the same price/precision

    assert i != j       # dev: same coin
    assert j >= 0       # dev: j below zero
    assert j < N_COINS  # dev: j above N_COINS

    # should be unreachable, but good for safety
    assert i >= 0
    assert i < N_COINS

    A: uint256 = self._A()
    D: uint256 = self._get_D(_xp, A)
    Ann: uint256 = A * N_COINS
    c: uint256 = D
    S: uint256 = 0
    _x: uint256 = 0
    y_prev: uint256 = 0

    for _i in range(N_COINS):
        if _i == i:
            _x = x
        elif _i != j:
            _x = _xp[_i]
        else:
            continue
        S += _x
        c = c * D / (_x * N_COINS)
    c = c * D * A_PRECISION / (Ann * N_COINS)
    b: uint256 = S + D * A_PRECISION / Ann  # - D
    y: uint256 = D
    for _i in range(255):
        y_prev = y
        y = (y*y + c) / (2 * y + b - D)
        # Equality with the precision of 1
        if y > y_prev:
            if y - y_prev <= 1:
                return y
        else:
            if y_prev - y <= 1:
                return y
    raise


@view
@external
def get_dy(i: int128, j: int128, _dx: uint256) -> uint256:
    rates: uint256[N_COINS] = RATES
    rates[MAX_COIN] = self._vp_rate_ro()
    xp: uint256[N_COINS] = self._xp(rates[MAX_COIN])

    x: uint256 = xp[i] + (_dx * rates[i] / PRECISION)
    y: uint256 = self._get_y(i, j, x, xp)
    dy: uint256 = xp[j] - y - 1
    fee: uint256 = self.fee * dy / FEE_DENOMINATOR
    return (dy - fee) * PRECISION / rates[j]


@view
@external
def get_dy_underlying(i: int128, j: int128, _dx: uint256) -> uint256:
    # dx and dy in underlying units
    vp_rate: uint256 = self._vp_rate_ro()
    xp: uint256[N_COINS] = self._xp(vp_rate)
    precisions: uint256[N_COINS] = PRECISION_MUL
    base_pool: address = self.base_pool

    # Use base_i or base_j if they are >= 0
    base_i: int128 = i - MAX_COIN
    base_j: int128 = j - MAX_COIN
    meta_i: int128 = MAX_COIN
    meta_j: int128 = MAX_COIN
    if base_i < 0:
        meta_i = i
    if base_j < 0:
        meta_j = j

    x: uint256 = 0
    if base_i < 0:
        x = xp[i] + _dx * precisions[i]
    else:
        if base_j < 0:
            # i is from BasePool
            # At first, get the amount of pool tokens
            base_inputs: uint256[BASE_N_COINS] = empty(uint256[BASE_N_COINS])
            base_inputs[base_i] = _dx
            # Token amount transformed to underlying "dollars"
            x = Curve(base_pool).calc_token_amount(base_inputs, True) * vp_rate / PRECISION
            # Accounting for deposit/withdraw fees approximately
            x -= x * Curve(base_pool).fee() / (2 * FEE_DENOMINATOR)
            # Adding number of pool tokens
            x += xp[MAX_COIN]
        else:
            # If both are from the base pool
            return self.call_get_dy(base_i, base_j, _dx)

    # This pool is involved only when in-pool assets are used
    y: uint256 = self._get_y(meta_i, meta_j, x, xp)
    dy: uint256 = xp[meta_j] - y - 1
    dy = (dy - self.fee * dy / FEE_DENOMINATOR)

    # If output is going via the metapool
    if base_j < 0:
        dy /= precisions[meta_j]
    else:
        # j is from BasePool
        # The fee is already accounted for
        dy = self.call_calc_withdraw_one_coin(dy * PRECISION / vp_rate, base_j)

    return dy


@external
@nonreentrant('lock')
def exchange(i: int128, j: int128, _dx: uint256, _min_dy: uint256) -> uint256:
    """
    @notice Perform an exchange between two coins
    @dev Index values can be found via the `coins` public getter method
    @param i Index value for the coin to send
    @param j Index valie of the coin to recieve
    @param _dx Amount of `i` being exchanged
    @param _min_dy Minimum amount of `j` to receive
    @return Actual amount of `j` received
    """
    assert not self.is_killed  # dev: is killed
    rates: uint256[N_COINS] = RATES
    rates[MAX_COIN] = self._vp_rate()

    old_balances: uint256[N_COINS] = self.balances
    xp: uint256[N_COINS] = self._xp_mem(rates[MAX_COIN], old_balances)

    x: uint256 = xp[i] + _dx * rates[i] / PRECISION
    y: uint256 = self._get_y(i, j, x, xp)

    dy: uint256 = xp[j] - y - 1  # -1 just in case there were some rounding errors
    dy_fee: uint256 = dy * self.fee / FEE_DENOMINATOR

    # Convert all to real units
    dy = (dy - dy_fee) * PRECISION / rates[j]
    assert dy >= _min_dy, "Too few coins in result"

    dy_admin_fee: uint256 = dy_fee * self.admin_fee / FEE_DENOMINATOR
    dy_admin_fee = dy_admin_fee * PRECISION / rates[j]

    # Change balances exactly in same way as we change actual ERC20 coin amounts
    self.balances[i] = old_balances[i] + _dx
    # When rounding errors happen, we undercharge admin fee in favor of LP
    self.balances[j] = old_balances[j] - dy - dy_admin_fee

    response: Bytes[32] = raw_call(
        self.coins[i],
        concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(msg.sender, bytes32),
            convert(self, bytes32),
            convert(_dx, bytes32),
        ),
        max_outsize=32,
    )
    if len(response) > 0:
        assert convert(response, bool)

    response = raw_call(
        self.coins[j],
        concat(
            method_id("transfer(address,uint256)"),
            convert(msg.sender, bytes32),
            convert(dy, bytes32),
        ),
        max_outsize=32,
    )
    if len(response) > 0:
        assert convert(response, bool)

    log TokenExchange(msg.sender, i, _dx, j, dy)

    return dy


@external
@nonreentrant('lock')
def exchange_underlying(i: int128, j: int128, _dx: uint256, _min_dy: uint256) -> uint256:
    """
    @notice Perform an exchange between two underlying coins
    @dev Index values can be found via the `underlying_coins` public getter method
    @param i Index value for the underlying coin to send
    @param j Index valie of the underlying coin to recieve
    @param _dx Amount of `i` being exchanged
    @param _min_dy Minimum amount of `j` to receive
    @return Actual amount of `j` received
    """
    assert not self.is_killed  # dev: is killed
    rates: uint256[N_COINS] = RATES
    rates[MAX_COIN] = self._vp_rate()
    base_pool: address = self.base_pool

    # Use base_i or base_j if they are >= 0
    base_i: int128 = i - MAX_COIN
    base_j: int128 = j - MAX_COIN
    meta_i: int128 = MAX_COIN
    meta_j: int128 = MAX_COIN
    if base_i < 0:
        meta_i = i
    if base_j < 0:
        meta_j = j
    dy: uint256 = 0

    # Addresses for input and output coins
    input_coin: address = ZERO_ADDRESS
    output_coin: address = ZERO_ADDRESS
    if base_i < 0:
        input_coin = self.coins[i]
    else:
        input_coin = self.base_coins[base_i]
    if base_j < 0:
        output_coin = self.coins[j]
    else:
        output_coin = self.base_coins[base_j]

    # Handle potential Tether fees
    dx_w_fee: uint256 = _dx
    if i == FEE_INDEX:
        dx_w_fee = ERC20(input_coin).balanceOf(self)

    response: Bytes[32] = raw_call(
        input_coin,
        concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(msg.sender, bytes32),
            convert(self, bytes32),
            convert(_dx, bytes32),
        ),
        max_outsize=32,
    )
    if len(response) > 0:
        assert convert(response, bool)

    # Handle potential Tether fees
    if i == FEE_INDEX:
        dx_w_fee = ERC20(input_coin).balanceOf(self) - dx_w_fee

    if base_i < 0 or base_j < 0:
        old_balances: uint256[N_COINS] = self.balances
        xp: uint256[N_COINS] = self._xp_mem(rates[MAX_COIN], old_balances)

        x: uint256 = 0
        if base_i < 0:
            x = xp[i] + dx_w_fee * rates[i] / PRECISION
        else:
            # i is from BasePool
            # At first, get the amount of pool tokens
            base_inputs: uint256[BASE_N_COINS] = empty(uint256[BASE_N_COINS])
            base_inputs[base_i] = dx_w_fee
            coin_i: address = self.coins[MAX_COIN]
            # Deposit and measure delta
            x = ERC20(coin_i).balanceOf(self)
            Curve(base_pool).add_liquidity(base_inputs, 0)
            # Need to convert pool token to "virtual" units using rates
            # dx is also different now
            dx_w_fee = ERC20(coin_i).balanceOf(self) - x
            x = dx_w_fee * rates[MAX_COIN] / PRECISION
            # Adding number of pool tokens
            x += xp[MAX_COIN]

        y: uint256 = self._get_y(meta_i, meta_j, x, xp)

        # Either a real coin or token
        dy = xp[meta_j] - y - 1  # -1 just in case there were some rounding errors
        dy_fee: uint256 = dy * self.fee / FEE_DENOMINATOR

        # Convert all to real units
        # Works for both pool coins and real coins
        dy = (dy - dy_fee) * PRECISION / rates[meta_j]

        dy_admin_fee: uint256 = dy_fee * self.admin_fee / FEE_DENOMINATOR
        dy_admin_fee = dy_admin_fee * PRECISION / rates[meta_j]

        # Change balances exactly in same way as we change actual ERC20 coin amounts
        self.balances[meta_i] = old_balances[meta_i] + dx_w_fee
        # When rounding errors happen, we undercharge admin fee in favor of LP
        self.balances[meta_j] = old_balances[meta_j] - dy - dy_admin_fee

        # Withdraw from the base pool if needed
        if base_j >= 0:
            out_amount: uint256 = ERC20(output_coin).balanceOf(self)
            self.call_remove_liquidity_one_coin(dy, base_j, 0)
            dy = ERC20(output_coin).balanceOf(self) - out_amount

        assert dy >= _min_dy, "Too few coins in result"

    else:
        # If both are from the base pool
        dy = ERC20(output_coin).balanceOf(self)
        self.call_exchange(base_i, base_j, dx_w_fee, _min_dy)
        dy = ERC20(output_coin).balanceOf(self) - dy

    # "safeTransfer" which works for ERC20s which return bool or not
    response = raw_call(
        output_coin,
        concat(
            method_id("transfer(address,uint256)"),
            convert(msg.sender, bytes32),
            convert(dy, bytes32),
        ),
        max_outsize=32,
    )
    # dev: failed transfer
    if j != 3:
        if len(response) > 0:
            assert convert(response, bool)  # dev: failed transfer
    # end "safeTransfer"

    log TokenExchangeUnderlying(msg.sender, i, _dx, j, dy)

    return dy


@external
@nonreentrant('lock')
def remove_liquidity(_amount: uint256, _min_amounts: uint256[N_COINS]) -> uint256[N_COINS]:
    """
    @notice Withdraw coins from the pool
    @dev Withdrawal amounts are based on current deposit ratios
    @param _amount Quantity of LP tokens to burn in the withdrawal
    @param _min_amounts Minimum amounts of underlying coins to receive
    @return List of amounts of coins that were withdrawn
    """
    lp_token: address = self.lp_token
    total_supply: uint256 = CurveToken(lp_token).totalSupply()
    amounts: uint256[N_COINS] = empty(uint256[N_COINS])

    for i in range(N_COINS):
        old_balance: uint256 = self.balances[i]
        value: uint256 = old_balance * _amount / total_supply
        assert value >= _min_amounts[i], "Withdrawal resulted in fewer coins than expected"
        self.balances[i] = old_balance - value
        amounts[i] = value
        ERC20(self.coins[i]).transfer(msg.sender, value)

    CurveToken(lp_token).burnFrom(msg.sender, _amount)  # dev: insufficient funds

    log RemoveLiquidity(msg.sender, amounts, empty(uint256[N_COINS]), total_supply - _amount)

    return amounts


@external
@nonreentrant('lock')
def remove_liquidity_imbalance(_amounts: uint256[N_COINS], _max_burn_amount: uint256) -> uint256:
    """
    @notice Withdraw coins from the pool in an imbalanced amount
    @param _amounts List of amounts of underlying coins to withdraw
    @param _max_burn_amount Maximum amount of LP token to burn in the withdrawal
    @return Actual amount of the LP token burned in the withdrawal
    """
    assert not self.is_killed  # dev: is killed

    amp: uint256 = self._A()
    vp_rate: uint256 = self._vp_rate()
    old_balances: uint256[N_COINS] = self.balances
    new_balances: uint256[N_COINS] = old_balances
    D0: uint256 = self._get_D_mem(vp_rate, old_balances, amp)
    for i in range(N_COINS):
        new_balances[i] -= _amounts[i]
    D1: uint256 = self._get_D_mem(vp_rate, new_balances, amp)

    fee: uint256 = self.fee * N_COINS / (4 * (N_COINS - 1))
    admin_fee: uint256 = self.admin_fee
    fees: uint256[N_COINS] = empty(uint256[N_COINS])
    for i in range(N_COINS):
        ideal_balance: uint256 = D1 * old_balances[i] / D0
        difference: uint256 = 0
        if ideal_balance > new_balances[i]:
            difference = ideal_balance - new_balances[i]
        else:
            difference = new_balances[i] - ideal_balance
        fees[i] = fee * difference / FEE_DENOMINATOR
        self.balances[i] = new_balances[i] - (fees[i] * admin_fee / FEE_DENOMINATOR)
        new_balances[i] -= fees[i]
    D2: uint256 = self._get_D_mem(vp_rate, new_balances, amp)

    lp_token: address = self.lp_token
    token_supply: uint256 = CurveToken(lp_token).totalSupply()
    token_amount: uint256 = (D0 - D2) * token_supply / D0
    assert token_amount != 0  # dev: zero tokens burned
    token_amount += 1  # In case of rounding errors - make it unfavorable for the "attacker"
    assert token_amount <= _max_burn_amount, "Slippage screwed you"

    CurveToken(lp_token).burnFrom(msg.sender, token_amount)  # dev: insufficient funds
    for i in range(N_COINS):
        if _amounts[i] != 0:
            ERC20(self.coins[i]).transfer(msg.sender, _amounts[i])

    log RemoveLiquidityImbalance(msg.sender, _amounts, fees, D1, token_supply - token_amount)

    return token_amount


@pure
@internal
def _get_y_D(A: uint256, i: int128, _xp: uint256[N_COINS], D: uint256) -> uint256:
    """
    Calculate x[i] if one reduces D from being calculated for xp to D

    Done by solving quadratic equation iteratively.
    x_1**2 + x_1 * (sum' - (A*n**n - 1) * D / (A * n**n)) = D ** (n + 1) / (n ** (2 * n) * prod' * A)
    x_1**2 + b*x_1 = c

    x_1 = (x_1**2 + c) / (2*x_1 + b)
    """
    # x in the input is converted to the same price/precision

    assert i >= 0  # dev: i below zero
    assert i < N_COINS  # dev: i above N_COINS

    Ann: uint256 = A * N_COINS
    c: uint256 = D
    S: uint256 = 0
    _x: uint256 = 0
    y_prev: uint256 = 0

    for _i in range(N_COINS):
        if _i != i:
            _x = _xp[_i]
        else:
            continue
        S += _x
        c = c * D / (_x * N_COINS)
    c = c * D * A_PRECISION / (Ann * N_COINS)
    b: uint256 = S + D * A_PRECISION / Ann
    y: uint256 = D

    for _i in range(255):
        y_prev = y
        y = (y*y + c) / (2 * y + b - D)
        # Equality with the precision of 1
        if y > y_prev:
            if y - y_prev <= 1:
                return y
        else:
            if y_prev - y <= 1:
                return y
    raise


@view
@internal
def _calc_withdraw_one_coin(_token_amount: uint256, i: int128, _vp_rate: uint256) -> (uint256, uint256, uint256):
    # First, need to calculate
    # * Get current D
    # * Solve Eqn against y_i for D - _token_amount
    amp: uint256 = self._A()
    xp: uint256[N_COINS] = self._xp(_vp_rate)
    D0: uint256 = self._get_D(xp, amp)

    total_supply: uint256 = CurveToken(self.lp_token).totalSupply()
    D1: uint256 = D0 - _token_amount * D0 / total_supply
    new_y: uint256 = self._get_y_D(amp, i, xp, D1)

    fee: uint256 = self.fee * N_COINS / (4 * (N_COINS - 1))
    rates: uint256[N_COINS] = RATES
    rates[MAX_COIN] = _vp_rate

    xp_reduced: uint256[N_COINS] = xp
    dy_0: uint256 = (xp[i] - new_y) * PRECISION / rates[i]  # w/o fees

    for j in range(N_COINS):
        dx_expected: uint256 = 0
        if j == i:
            dx_expected = xp[j] * D1 / D0 - new_y
        else:
            dx_expected = xp[j] - xp[j] * D1 / D0
        xp_reduced[j] -= fee * dx_expected / FEE_DENOMINATOR

    dy: uint256 = xp_reduced[i] - self._get_y_D(amp, i, xp_reduced, D1)
    dy = (dy - 1) * PRECISION / rates[i]  # Withdraw less to account for rounding errors

    return dy, dy_0 - dy, total_supply


@view
@external
def calc_withdraw_one_coin(_token_amount: uint256, i: int128) -> uint256:
    """
    @notice Calculate the amount received when withdrawing a single coin
    @param _token_amount Amount of LP tokens to burn in the withdrawal
    @param i Index value of the coin to withdraw
    @return Amount of coin received
    """
    vp_rate: uint256 = self._vp_rate_ro()
    return self._calc_withdraw_one_coin(_token_amount, i, vp_rate)[0]


@external
@nonreentrant('lock')
def remove_liquidity_one_coin(_token_amount: uint256, i: int128, _min_amount: uint256) -> uint256:
    """
    @notice Withdraw a single coin from the pool
    @param _token_amount Amount of LP tokens to burn in the withdrawal
    @param i Index value of the coin to withdraw
    @param _min_amount Minimum amount of coin to receive
    @return Amount of coin received
    """
    assert not self.is_killed  # dev: is killed

    vp_rate: uint256 = self._vp_rate()
    dy: uint256 = 0
    dy_fee: uint256 = 0
    total_supply: uint256 = 0
    dy, dy_fee, total_supply = self._calc_withdraw_one_coin(_token_amount, i, vp_rate)
    assert dy >= _min_amount, "Not enough coins removed"

    self.balances[i] -= (dy + dy_fee * self.admin_fee / FEE_DENOMINATOR)
    CurveToken(self.lp_token).burnFrom(msg.sender, _token_amount)  # dev: insufficient funds

    ERC20(self.coins[i]).transfer(msg.sender, dy)

    log RemoveLiquidityOne(msg.sender, _token_amount, dy, total_supply - _token_amount)

    return dy


### Admin functions ###
@external
def ramp_A(_future_A: uint256, _future_time: uint256):
    assert msg.sender == self.owner  # dev: only owner
    assert block.timestamp >= self.initial_A_time + MIN_RAMP_TIME
    assert _future_time >= block.timestamp + MIN_RAMP_TIME  # dev: insufficient time

    initial_A: uint256 = self._A()
    future_A_p: uint256 = _future_A * A_PRECISION

    assert _future_A > 0 and _future_A < MAX_A
    if future_A_p < initial_A:
        assert future_A_p * MAX_A_CHANGE >= initial_A
    else:
        assert future_A_p <= initial_A * MAX_A_CHANGE

    self.initial_A = initial_A
    self.future_A = future_A_p
    self.initial_A_time = block.timestamp
    self.future_A_time = _future_time

    log RampA(initial_A, future_A_p, block.timestamp, _future_time)


@external
def stop_ramp_A():
    assert msg.sender == self.owner  # dev: only owner

    current_A: uint256 = self._A()
    self.initial_A = current_A
    self.future_A = current_A
    self.initial_A_time = block.timestamp
    self.future_A_time = block.timestamp
    # now (block.timestamp < t1) is always False, so we return saved A

    log StopRampA(current_A, block.timestamp)


@external
def commit_new_fee(_new_fee: uint256, _new_admin_fee: uint256):
    assert msg.sender == self.owner  # dev: only owner
    assert self.admin_actions_deadline == 0  # dev: active action
    assert _new_fee <= MAX_FEE  # dev: fee exceeds maximum
    assert _new_admin_fee <= MAX_ADMIN_FEE  # dev: admin fee exceeds maximum

    deadline: uint256 = block.timestamp + ADMIN_ACTIONS_DELAY
    self.admin_actions_deadline = deadline
    self.future_fee = _new_fee
    self.future_admin_fee = _new_admin_fee

    log CommitNewFee(deadline, _new_fee, _new_admin_fee)


@external
def apply_new_fee():
    assert msg.sender == self.owner  # dev: only owner
    assert block.timestamp >= self.admin_actions_deadline  # dev: insufficient time
    assert self.admin_actions_deadline != 0  # dev: no active action

    self.admin_actions_deadline = 0
    fee: uint256 = self.future_fee
    admin_fee: uint256 = self.future_admin_fee
    self.fee = fee
    self.admin_fee = admin_fee

    log NewFee(fee, admin_fee)


@external
def revert_new_parameters():
    assert msg.sender == self.owner  # dev: only owner

    self.admin_actions_deadline = 0


@external
def commit_transfer_ownership(_owner: address):
    assert msg.sender == self.owner  # dev: only owner
    assert self.transfer_ownership_deadline == 0  # dev: active transfer

    deadline: uint256 = block.timestamp + ADMIN_ACTIONS_DELAY
    self.transfer_ownership_deadline = deadline
    self.future_owner = _owner

    log CommitNewAdmin(deadline, _owner)


@external
def apply_transfer_ownership():
    assert msg.sender == self.owner  # dev: only owner
    assert block.timestamp >= self.transfer_ownership_deadline  # dev: insufficient time
    assert self.transfer_ownership_deadline != 0  # dev: no active transfer

    self.transfer_ownership_deadline = 0
    owner: address = self.future_owner
    self.owner = owner

    log NewAdmin(owner)


@external
def revert_transfer_ownership():
    assert msg.sender == self.owner  # dev: only owner

    self.transfer_ownership_deadline = 0

@external
def commit_fee_converter(_fee_converter: address):
    assert msg.sender == self.owner  # dev: only owner
    self.fee_converter = _fee_converter



@view
@external
def admin_balances(i: uint256) -> uint256:
    return ERC20(self.coins[i]).balanceOf(self) - self.balances[i]


@external
def withdraw_admin_fees():
    fee_converter: address = self.fee_converter
    for i in range(N_COINS):
        c: address = self.coins[i]
        value: uint256 = ERC20(c).balanceOf(self) - self.balances[i]
        # "safeTransfer" which works for ERC20s which return bool or not
        _response: Bytes[32] = raw_call(
            c,
            concat(
                method_id("transfer(address,uint256)"),
                convert(fee_converter, bytes32),
                convert(value, bytes32),
            ),
            max_outsize=32,
        )  # dev: failed transfer
        if len(_response) > 0:
            assert convert(_response, bool)  # dev: failed transfer
    FeeConverter(fee_converter).convertFees()


@external
def kill_me():
    assert msg.sender == self.owner  # dev: only owner
    assert self.kill_deadline > block.timestamp  # dev: deadline has passed
    self.is_killed = True


@external
def unkill_me():
    assert msg.sender == self.owner  # dev: only owner
    self.is_killed = False