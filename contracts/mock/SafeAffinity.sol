//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AffinityDistributor.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol"; /// required for getPair


/** 
 * Contract: SafeAffinity 
 * 
 *  This Contract Awards SafeVault and SafeEarn to holders
 *  weighted by how much SafeAffinity you hold
 * 
 *  Transfer Fee:  8%
 *  Buy Fee:       8%
 *  Sell Fee:     20%
 * 
 *  Fees Go Toward:
 *  43.75% SafeVault Distribution
 *  43.75% SafeEarn Distribution
 *  8.75% Burn
 *  3.75% Marketing
 */
contract SafeAffinity is IERC20, Context, Ownable {

    using SafeMath for uint256;
    using SafeMath for uint8;
    using Address for address;

    // token data
    string constant _name = "SafeAffinity";
    string constant _symbol = "AFFINITY";
    uint8 constant _decimals = 9;
    // 1 Trillion Max Supply
    uint256 _totalSupply = 1 * 10**12 * (10 ** _decimals);
    uint256 public _maxTxAmount = _totalSupply.div(200); // 0.5% or 5 Billion
    // balances
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;
    // exemptions
    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => bool) isDividendExempt;
    // fees
    uint256 public burnFee = 175;
    uint256 public reflectionFee = 1750;
    uint256 public marketingFee = 75;
    // total fees
    uint256 totalFeeSells = 2000;
    uint256 totalFeeBuys = 800;
    uint256 feeDenominator = 10000;
    // Marketing Funds Receiver
    address public marketingFeeReceiver = 0x66cF1ef841908873C34e6bbF1586F4000b9fBB5D;
    // minimum bnb needed for distribution
    uint256 public minimumToDistribute = 5 * 10**18;
    // Pancakeswap V2 Router
    IUniswapV2Router02 router;
    address public pair;
    bool public allowTransferToMarketing = true;
    // gas for distributor
    AffinityDistributor public distributor;
    uint256 distributorGas = 500000;
    // in charge of swapping
    bool public swapEnabled = true;
    uint256 public swapThreshold = _totalSupply.div(300); // 0.03% = 300 Million
    // true if our threshold decreases with circulating supply
    bool public canChangeSwapThreshold = false;
    uint256 public swapThresholdPercentOfCirculatingSupply = 300;
    bool inSwap;
    bool isDistributing;
    // false to stop the burn
    bool burnEnabled = true;
    modifier swapping() { inSwap = true; _; inSwap = false; }
    modifier distributing() { isDistributing = true; _; isDistributing = false; }
    // Uniswap Router V2
    address private _dexRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // initialize some stuff
    constructor (
        address marketingFeeReceiverAddress,
        address routerAddress
    ) {
        // Pancakeswap V2 Router
        _dexRouter = routerAddress;
        marketingFeeReceiver = marketingFeeReceiverAddress;
        router = IUniswapV2Router02(_dexRouter);
        // Liquidity Pool Address for BNB -> Vault
        pair = IUniswapV2Factory(router.factory()).createPair(router.WETH(), address(this));
        _allowances[address(this)][address(router)] = _totalSupply;
        // our dividend Distributor
        distributor = new AffinityDistributor(_dexRouter);
        // exempt deployer and contract from fees
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        // exempt important addresses from TX limit
        isTxLimitExempt[msg.sender] = true;
        isTxLimitExempt[marketingFeeReceiver] = true;
        isTxLimitExempt[address(distributor)] = true;
        isTxLimitExempt[address(this)] = true;
        // exempt this important addresses  from receiving Rewards
        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        // approve router of total supply
        approve(_dexRouter, _totalSupply);
        approve(address(pair), _totalSupply);
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function internalApprove() private {
        _allowances[address(this)][address(router)] = _totalSupply;
        _allowances[address(this)][address(pair)] = _totalSupply;
    }

    /** Approve Total Supply */
    function approveMax(address spender) external returns (bool) {
        return approve(spender, _totalSupply);
    }

    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != _totalSupply){
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, "Insufficient Allowance");
        }

        return _transferFrom(sender, recipient, amount);
    }

    /** Internal Transfer */
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        // make standard checks
        require(recipient != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        // check if we have reached the transaction limit
        require(amount <= _maxTxAmount || isTxLimitExempt[sender], "TX Limit Exceeded");
        // whether transfer succeeded
        bool success;
        // amount of tokens received by recipient
        uint256 amountReceived;
        // if we're in swap perform a basic transfer
        if(inSwap || isDistributing){
            (amountReceived, success) = handleTransferBody(sender, recipient, amount);
            emit Transfer(sender, recipient, amountReceived);
            return success;
        }

        // limit gas consumption by splitting up operations
        if(shouldSwapBack()) {
            swapBack();
            (amountReceived, success) = handleTransferBody(sender, recipient, amount);
        } else if (shouldReflectAndDistribute()) {
            reflectAndDistribute();
            (amountReceived, success) = handleTransferBody(sender, recipient, amount);
        } else {
            (amountReceived, success) = handleTransferBody(sender, recipient, amount);
            try distributor.process(distributorGas) {} catch {}
        }

        emit Transfer(sender, recipient, amountReceived);
        return success;
    }

    /** Takes Associated Fees and sets holders' new Share for the Safemoon Distributor */
    function handleTransferBody(address sender, address recipient, uint256 amount) internal returns (uint256, bool) {
        // subtract balance from sender
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        // amount receiver should receive
        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(recipient, amount) : amount;
        // add amount to recipient
        _balances[recipient] = _balances[recipient].add(amountReceived);
        // set shares for distributors
        if(!isDividendExempt[sender]){
            distributor.setShare(sender, _balances[sender]);
        }
        if(!isDividendExempt[recipient]){
            distributor.setShare(recipient, _balances[recipient]);
        }
        // return the amount received by receiver
        return (amountReceived, true);
    }

    /** False if sender is Fee Exempt, True if not */
    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    /** Takes Proper Fee (8% buys / transfers, 20% on sells) and stores in contract */
    function takeFee(address receiver, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = amount.mul(getTotalFee(receiver == pair)).div(feeDenominator);
        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        return amount.sub(feeAmount);
    }

    /** True if we should swap from Vault => BNB */
    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapEnabled
        && _balances[address(this)] >= swapThreshold;
    }

    /**
     *  Swaps SafeAffinity for BNB if threshold is reached and the swap is enabled
     *  Burns 20% of SafeAffinity in Contract
     *  Swaps The Rest For BNB
     */
    function swapBack() private swapping {
        // path from token -> BNB
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        // tokens allocated to burning
        uint256 burnAmount = swapThreshold.mul(burnFee).div(totalFeeSells);
        // burn tokens
        burnTokens(burnAmount);
        // how many are left to swap with
        uint256 swapAmount = swapThreshold.sub(burnAmount);
        // swap tokens for BNB
        try router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            swapAmount,
            0,
            path,
            address(this),
            block.timestamp
        ) {} catch{return;}

        // Tell The Blockchain
        emit SwappedBack(swapAmount, burnAmount);
    }

    function shouldReflectAndDistribute() private view returns(bool) {
        return msg.sender != pair
        && !isDistributing
        && swapEnabled
        && address(this).balance >= minimumToDistribute;
    }

    function reflectAndDistribute() private distributing {

        bool success; bool successful;
        uint256 amountBNBMarketing; uint256 amountBNBReflection;
        // allocate bnb
        if (allowTransferToMarketing) {
            amountBNBMarketing = address(this).balance.mul(marketingFee).div(totalFeeSells);
            amountBNBReflection = address(this).balance.sub(amountBNBMarketing);
            // fund distributors
            (success,) = payable(address(distributor)).call{value: amountBNBReflection, gas: 26000}("");
            distributor.deposit();
            // transfer to marketing
            if (allowTransferToMarketing) {
                (successful,) = payable(marketingFeeReceiver).call{value: amountBNBMarketing, gas: 26000}("");
            }
        } else {
            amountBNBReflection = address(this).balance;
            // fund distributors
            (success,) = payable(address(distributor)).call{value: amountBNBReflection, gas: 26000}("");
            distributor.deposit();
        }
        emit FundDistributors(amountBNBReflection, amountBNBMarketing);
    }

    /** Removes Tokens From Circulation */
    function burnTokens(uint256 tokenAmount) private returns (bool) {
        if (!burnEnabled) {
            return false;
        }
        // update balance of contract
        _balances[address(this)] = _balances[address(this)].sub(tokenAmount, 'cannot burn this amount');
        // update Total Supply
        _totalSupply = _totalSupply.sub(tokenAmount, 'total supply cannot be negative');
        // approve Router for total supply
        internalApprove();
        // change Swap Threshold if we should
        if (canChangeSwapThreshold) {
            swapThreshold = _totalSupply.div(swapThresholdPercentOfCirculatingSupply);
        }
        // emit Transfer to Blockchain
        emit Transfer(address(this), address(0), tokenAmount);
        return true;
    }

    /** Claim Your Vault Rewards Early */
    function claimVaultDividend() external returns (bool) {
        distributor.claimVAULTDividend(msg.sender);
        return true;
    }

    /** Claim Your Earn Rewards Manually */
    function claimEarnDividend() external returns (bool) {
        distributor.claimEarnDividend(msg.sender);
        return true;
    }

    /** Manually Depsoits To The Earn or Vault Contract */
    function manuallyDeposit() external returns (bool){
        distributor.deposit();
        return true;
    }

    /** Is Holder Exempt From Fees */
    function getIsFeeExempt(address holder) public view returns (bool) {
        return isFeeExempt[holder];
    }

    /** Is Holder Exempt From Earn Dividends */
    function getIsDividendExempt(address holder) public view returns (bool) {
        return isDividendExempt[holder];
    }

    /** Is Holder Exempt From Transaction Limit */
    function getIsTxLimitExempt(address holder) public view returns (bool) {
        return isTxLimitExempt[holder];
    }

    /** Get Fees for Buying or Selling */
    function getTotalFee(bool selling) public view returns (uint256) {
        if(selling){ return totalFeeSells; }
        return totalFeeBuys;
    }

    /** Sets Various Fees */
    function setFees(uint256 _burnFee, uint256 _reflectionFee, uint256 _marketingFee, uint256 _buyFee) external onlyOwner {
        burnFee = _burnFee;
        reflectionFee = _reflectionFee;
        marketingFee = _marketingFee;
        totalFeeSells = _burnFee.add(_reflectionFee).add(_marketingFee);
        totalFeeBuys = _buyFee;
        require(_buyFee <= 1000);
        require(totalFeeSells < feeDenominator/2);
    }

    /** Set Exemption For Holder */
    function setIsFeeAndTXLimitExempt(address holder, bool feeExempt, bool txLimitExempt) external onlyOwner {
        require(holder != address(0));
        isFeeExempt[holder] = feeExempt;
        isTxLimitExempt[holder] = txLimitExempt;
    }

    /** Set Holder To Be Exempt From Earn Dividends */
    function setIsDividendExempt(address holder, bool exempt) external onlyOwner {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;
        if(exempt) {
            distributor.setShare(holder, 0);
        } else {
            distributor.setShare(holder, _balances[holder]);
        }
    }

    /** Set Settings related to Swaps */
    function setSwapBackSettings(bool _swapEnabled, uint256 _swapThreshold, bool _canChangeSwapThreshold, uint256 _percentOfCirculatingSupply, bool _burnEnabled, uint256 _minimumBNBToDistribute) external onlyOwner {
        swapEnabled = _swapEnabled;
        swapThreshold = _swapThreshold;
        canChangeSwapThreshold = _canChangeSwapThreshold;
        swapThresholdPercentOfCirculatingSupply = _percentOfCirculatingSupply;
        burnEnabled = _burnEnabled;
        minimumToDistribute = _minimumBNBToDistribute;
    }

    /** Set Criteria For SafeAffinity Distributor */
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution, uint256 _bnbToTokenThreshold) external onlyOwner {
        distributor.setDistributionCriteria(_minPeriod, _minDistribution, _bnbToTokenThreshold);
    }

    /** Should We Transfer To Marketing */
    function setAllowTransferToMarketing(bool _canSendToMarketing, address _marketingFeeReceiver) external onlyOwner {
        allowTransferToMarketing = _canSendToMarketing;
        marketingFeeReceiver = _marketingFeeReceiver;
    }

    /** Updates The Pancakeswap Router */
    function setDexRouter(address nRouter) external onlyOwner{
        require(nRouter != _dexRouter);
        _dexRouter = nRouter;
        router = IUniswapV2Router02(nRouter);
        address _uniswapV2Pair = IUniswapV2Factory(router.factory())
        .createPair(address(this), router.WETH());
        pair = _uniswapV2Pair;
        _allowances[address(this)][address(router)] = _totalSupply;
        distributor.updatePancakeRouterAddress(nRouter);
    }

    /** Set Address For SafeAffinity Distributor */
    function setDistributor(address payable newDistributor) external onlyOwner {
        require(newDistributor != address(distributor), 'Distributor already has this address');
        distributor = AffinityDistributor(newDistributor);
        emit SwappedDistributor(newDistributor);
    }

    /** Swaps SafeAffinity and SafeVault Addresses in case of migration */
    function setTokenAddresses(address nSafeEarn, address nSafeVault) external onlyOwner {
        distributor.setSafeEarnAddress(nSafeEarn);
        distributor.setSafeVaultAddress(nSafeVault);
        emit SwappedTokenAddresses(nSafeEarn, nSafeVault);
    }

    /** Deletes the entire bag from sender */
    function deleteBag(uint256 nTokens) external returns(bool){
        // make sure you are burning enough tokens
        require(nTokens > 0);
        // if the balance is greater than zero
        require(_balances[msg.sender] >= nTokens, 'user does not own enough tokens');
        // remove tokens from sender
        _balances[msg.sender] = _balances[msg.sender].sub(nTokens, 'cannot have negative tokens');
        // remove tokens from total supply
        _totalSupply = _totalSupply.sub(nTokens, 'total supply cannot be negative');
        // approve Router for the new total supply
        internalApprove();
        // set share in distributor
        distributor.setShare(msg.sender, _balances[msg.sender]);
        // tell blockchain
        emit Transfer(msg.sender, address(0), nTokens);
        return true;
    }

    // Events
    event SwappedDistributor(address newDistributor);
    event SwappedBack(uint256 tokensSwapped, uint256 amountBurned);
    event SwappedTokenAddresses(address newSafeEarn, address newSafeVault);
    event FundDistributors(uint256 reflectionAmount, uint256 marketingAmount);
}