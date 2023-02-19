pragma solidity ^0.8.0;

import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

contract SuperPool {
    ISuperfluid private superfluid;
    ISuperToken private superToken;
    IConstantFlowAgreementV1 private cfa;
    uint256 public totalDeposits;
    mapping(address => uint256) public balances;
    mapping(address => address) public streams;
    uint256 private constant INTEREST_RATE = 1 ether; // 1 token per second
    
    constructor(address _superfluid, address _superToken, address _cfa) {
        superfluid = ISuperfluid(_superfluid);
        superToken = ISuperToken(_superToken);
        cfa = IConstantFlowAgreementV1(_cfa);
    }
    
    function deposit(uint256 _amount) external {
        superToken.approve(address(superfluid), _amount);
        superfluid.deposit(address(superToken), address(this), _amount, "");
        balances[msg.sender] += _amount;
        totalDeposits += _amount;
        _startStream(msg.sender);
    }
    
    function withdraw(uint256 _amount) external {
        require(_amount <= balances[msg.sender], "Insufficient balance");
        _stopStream(msg.sender);
       _payInterest(msg.sender);
        superfluid.withdraw(address(superToken), address(this), _amount, "");
        balances[msg.sender] -= _amount;
        totalDeposits -= _amount;
    }
    
    function getBalance() external view returns (uint256) {
        return superToken.balanceOf(address(this));
    }
    
    function _startStream(address _user) private {
        // Create a new flow for the user
        uint256 depositRate = 1 ether; // 1 token per second
        (,int96 outFlowRate,,) = cfa.getFlow(superToken, _user, address(this));
        if (outFlowRate == 0) {
            cfa.createFlow(superToken, _user, depositRate, new bytes(0));
            streams[_user] = address(this);
        }
    }
    
    function _stopStream(address _user) private {
        // Stop the user's flow and update the streams mapping
        (,int96 outFlowRate,,) = cfa.getFlow(superToken, _user, address(this));
        if (outFlowRate != 0) {
            cfa.deleteFlow(superToken, _user, address(this), new bytes(0));
            streams[_user] = address(0);
        }
    }
    
	function _payInterest(address _user) private {
        // Calculate the interest earned by the user and send it to them
        (,int96 outFlowRate,,) = cfa.getFlow(superToken, _user, address(this));
        if (outFlowRate != 0) {
            uint256 timeElapsed = block.timestamp - superfluid.getAccountStreamInfo(_user, address(this)).timestamp;
            uint256 interestEarned = INTEREST_RATE * timeElapsed;
            superfluid.flow({
                superToken: address(superToken),
                sender: address(this),
                receiver: _user,
                flowRate: int96(interestEarned),
                userData: ""
            });
        }
    }
	
    function createStream(uint256 _flowRate) external {
        // Create a new money stream for the user
        (,int96 outFlowRate,,) = cfa.getFlow(superToken, msg.sender, address(this));
        if (outFlowRate == 0) {
            cfa.createFlow(superToken, msg.sender, _flowRate, new bytes(0));
            streams[msg.sender] = address(this);
        }
    }
    
    function deleteStream() external {
        // Stop the user's money stream and update the streams mapping
        (,int96 outFlowRate,,) = cfa.getFlow(superToken, msg.sender, address(this));
        if (outFlowRate != 0) {
            cfa.deleteFlow(superToken, msg.sender, address(this), new bytes(0));
            streams[msg.sender] = address(0);
        }
    }
}
