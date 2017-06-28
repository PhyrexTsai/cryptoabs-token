pragma solidity ^0.4.11;

import "./StandardToken.sol";
import "./Ownable.sol";

contract CryptoABS is StandardToken, Ownable {
  string public name = "CryptoABS";                     // 名稱
  string public symbol = "CABS";                        // token 代號
  uint256 public decimals = 0;                         
  address public contractAddress;                       // contract address

  uint256 public constant tokenExchangeRate = 100;      // 1 USD = token
  uint256 public minEthInvest;                          // 最低投資金額
  uint256 public ethExchangeRate;                       // 1 USD = wei

  uint256 public startBlock;                            // ICO 起始的 block number
  uint256 public endBlock;                              // ICO 結束的 block number
  uint256 public maxTokenSupply;                        // ICO 的 max token，透過 USD to ETH 換算出來
  
  uint256 public initalizedTime;                        // 起始時間，合約部署的時候會寫入
  uint256 public financingPeriod;                       // token 籌資期間
  uint256 public tokenLockoutPeriod;                    // token 閉鎖期，閉鎖期內不得 transfer
  uint256 public tokenMaturityPeriod;                   // token 到期日

  bool public paused;                                   // 暫停合約功能執行
  bool public initialized;                              // 合約啟動
  uint256 public finalizedBlock;                        // 合約終止的區塊編號
  uint256 public finalizedTime;                         // 合約終止的時間
  uint256 public finalizedCapital;                      // 合約到期的 ETH 金額

  struct Payee {
    bool isExists;                                      // payee 存在
    bool isPayable;                                     // payee 允許領錢
    uint256 interest;                                   // 待領利息金額
  }

  mapping (address => Payee) public payees; 
  address[] payeeArray;

  /**
   * @dev Throws if contract paused.
   */
  modifier notPaused() {
    require(paused == false);
    _;
  }

  /**
   * @dev Throws if not a payee. 
   */
  modifier isPayee() {
    require(payees[msg.sender].isPayable == true);
    _;
  }

  /**
   * @dev Throws if contract not initialized. 
   */
  modifier isInitialized() {
    require(initialized == true);
    _;
  }

  /**
   * @dev Throws if contract not open. 
   */
  modifier isContractOpen() {
    require(
      getBlockNumber() >= startBlock &&
      getBlockNumber() <= endBlock &&
      finalizedBlock == 0);
    _;
  }

  /**
   * @dev Throws if token in lockout period. 
   */
  modifier notLockout() {
    require(now > (initalizedTime + financingPeriod + tokenLockoutPeriod));
    _;
  }
  
  /**
   * @dev Throws if not over maturity date. 
   */
  modifier overMaturity() {
    require(now > (initalizedTime + financingPeriod + tokenMaturityPeriod));
    _;
  }

  /**
   * @dev Contract constructor.
   */
  function CryptoABS() {
    paused = false;
  }

  /**
   * @dev Initialize contract with inital parameters. 
   * @param _contractAddress contract deployed address
   * @param _startBlock start block number
   * @param _endBlock end block number
   * @param _initializedTime contract initalized time
   * @param _financingPeriod contract financing period
   * @param _tokenLockoutPeriod contract token lockout period
   * @param _tokenMaturityPeriod contract token maturity period
   * @param _minEthInvest minimum ether accept of invest
   * @param _maxTokenSupply maximum toke supply
   */
  function initialize(
      address _contractAddress,
      uint256 _startBlock,
      uint256 _endBlock,
      uint256 _initializedTime,
      uint256 _financingPeriod,
      uint256 _tokenLockoutPeriod,
      uint256 _tokenMaturityPeriod,
      uint256 _minEthInvest,
      uint256 _maxTokenSupply) onlyOwner {
    require(contractAddress == 0x0);
    require(totalSupply == 0);
    require(decimals == 0);
    require(_startBlock >= getBlockNumber());
    require(_startBlock < _endBlock);
    require(financingPeriod == 0);
    require(tokenLockoutPeriod == 0);
    require(tokenMaturityPeriod == 0);
    require(initalizedTime == 0);
    require(_maxTokenSupply >= totalSupply);
    contractAddress = _contractAddress;
    startBlock = _startBlock;
    endBlock = _endBlock;
    initalizedTime = _initializedTime;
    financingPeriod = _financingPeriod;
    tokenLockoutPeriod = _tokenLockoutPeriod;
    tokenMaturityPeriod = _tokenMaturityPeriod;
    minEthInvest = _minEthInvest;
    maxTokenSupply = _maxTokenSupply;
    initialized = true;
  }

  /**
   * @dev Finalize contract
   */
  function finalize() public isInitialized {
    require(getBlockNumber() >= startBlock);
    require(msg.sender == owner || getBlockNumber() > endBlock);

    finalizedBlock = getBlockNumber();
    finalizedTime = now;

    Finalized();
  }

  /**
   * @dev fallback function accept ether
   */
  function () payable notPaused {
    proxyPayment(msg.sender);
  }

  /**
   * @dev payment function, transfer eth to token
   * @param _payee The payee address
   */
  function proxyPayment(address _payee) public payable notPaused isInitialized isContractOpen returns (bool) {
    require(msg.value > 0);

    uint256 amount = msg.value / 1 ether;
    require(amount >= minEthInvest); // TODO: 改成變數

    uint256 tokens = amount.mul(tokenExchangeRate);
    require(totalSupply.add(tokens) <= maxTokenSupply);

    balances[_payee] = balances[_payee].add(tokens);

    if (payees[msg.sender].isExists != true) {
      payees[msg.sender].isExists = true;
      payees[msg.sender].isPayable = true;
      payeeArray.push(msg.sender);
    }

    require(owner.send(msg.value));
    return true;
  }

  /**
   * @dev transfer token
   * @param _to The address to transfer to.
   * @param _value The amount to be transferred.
   */
  function transfer(address _to, uint256 _value) onlyPayloadSize(2 * 32) notLockout notPaused isInitialized {
    require(_to != contractAddress);
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    if (payees[_to].isExists != true) {
      payees[_to].isExists = true;
      payees[_to].isPayable = true;
      payeeArray.push(_to);
    }
    Transfer(msg.sender, _to, _value);
  }

  /**
   * @dev Transfer tokens from one address to another
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint the amout of tokens to be transfered
   */
  function transferFrom(address _from, address _to, uint _value) onlyPayloadSize(3 * 32) {
    require(_to != contractAddress);
    require(_from != contractAddress);
    var _allowance = allowed[_from][msg.sender];

    // Check is not needed because sub(_allowance, _value) will already throw if this condition is not met
    // if (_value > _allowance) throw;
    require(_allowance >= _value);

    balances[_to] = balances[_to].add(_value);
    balances[_from] = balances[_from].sub(_value);
    allowed[_from][msg.sender] = _allowance.sub(_value);
    if (payees[_to].isExists != true) {
      payees[_to].isExists = true;
      payees[_to].isPayable = true;
      payeeArray.push(_to);
    }
    Transfer(_from, _to, _value);
  }

  /**
   * @dev add interest to each payees
   * @param _payee The payee address
   * @param _interest The interest amount to payee, unit `wei`
   */
  function depositInterest(address _payee, uint256 _interest) onlyOwner notPaused isInitialized {
    require(payees[_payee].isExists == true);
    payees[_payee].interest += _interest;
  }

  /**
   * @dev return interest by address, unit `wei`
   * @param _address The payee address
   */
  function interestOf(address _address) isInitialized returns (uint256 result)  {
    require(payees[_address].isExists == true);
    return payees[_address].interest;
  }

  /**
   * @dev withdraw interest by payee
   * @param _interest Withdraw interest amount
   */
  function withdrawInterest(uint256 _interest) payable isPayee notPaused isInitialized notLockout {
    require(msg.value == 0);
    uint256 interest = _interest * 1 wei;
    require(payees[msg.sender].isPayable == true && _interest <= payees[msg.sender].interest);
    require(msg.sender.send(interest));
    payees[msg.sender].interest -= interest;
  }

  /**
   * @dev withdraw capital by payee
   */
  function withdrawCapital() payable isPayee notPaused isInitialized overMaturity {
    require(msg.value == 0);
    require(balances[msg.sender] > 0 && totalSupply > 0);
    require(payees[msg.sender].isPayable == true);
    uint256 capital = (balances[msg.sender] / totalSupply) * finalizedCapital;
    require(msg.sender.send(capital));
  }

  /**
   * @dev pause contract
   */
  function pauseContract() onlyOwner {
    paused = true;
  }

  /**
   * @dev resume contract
   */
  function resumeContract() onlyOwner {
    paused = false;
  }

  /**
   * @dev set eth exchange rate
   * @param _ethExchangeRate change rate of ether
   */
  function setEthExchangeRate(uint256 _ethExchangeRate) onlyOwner {
    ethExchangeRate = _ethExchangeRate;
  }

  /**
   * @dev get eth exchange rate
   */
  function getEthExchangeRate() returns (uint256 result) {
    return ethExchangeRate;
  }

  /**
   * @dev disable single payee in emergency
   * @param _address Disable payee address
   */
  function disablePayee(address _address) onlyOwner {
    require(_address != owner);
    payees[_address].isPayable = false;
  }

  /**
   * @dev enable single payee
   * @param _address Enable payee address
   */
  function enablePayee(address _address) onlyOwner {
    payees[_address].isPayable = true;
  }

  /**
   * @dev get block number
   */
  function getBlockNumber() internal constant returns (uint256) {
    return block.number;
  }

  /**
   * @dev get payee count
   */
  function getPayeeCount() returns (uint256 result) {
    return payeeArray.length;
  }

  /**
   * @dev payee status
   */
  function isPayeePayable() constant returns (bool result) {
    return payees[msg.sender].isPayable;
  }

  /**
   * @dev put all capital in this contract
   */
  function capital() payable isInitialized onlyOwner {
    require(msg.value > 0);
    finalizedCapital = msg.value * 1 wei;
    Capital(msg.value);
  }

  /**
   * @dev put interest in this contract
   * @param times Number of interest
   */
  function interest(uint256 times) payable isInitialized onlyOwner {
    Interest(times, msg.value);
  }

  /**
   * @dev withdraw balance from contract if emergency
   */
  function withdraw() payable isInitialized onlyOwner {
    require(owner.send(this.balance));
  }

  event Capital(uint256 _capital);
  event Interest(uint256 times, uint256 _interest);
  event Finalized();
}
