// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";


/// @dev This interface is for calling these functions of NNN Token contract for transfering NNN Token.
interface Token {
    function transferFrom(address, address, uint) external returns (bool);
    function transfer(address, uint) external returns (bool);
}

/*
    @title NNN Token Staking Contract

    @notice This contract is for staking NNN tokens. There are 3 options;
    1- Stake for 1 year, you earn 5% of your staked amount as NVM Token
    2- Stake for 2 years, you earn 6% of your staked amount as NVM Token
    3- Stake for 5 years, you earn 8% of your staked amount as NVM Token

    @dev All calls to this contract should be made through the proxy, including admin actions. 
    Any call to transfer agains this contract fails because it is an upgradeable contract.
*/
contract StakeNNN is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    
    AggregatorV3Interface internal priceFeedXAU;

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer { 
        OwnableUpgradeable.__Ownable_init();
        priceFeedXAU = AggregatorV3Interface(0x81570059A0cb83888f1459Ec66Aad1Ac16730243); // price Feed XAU/BUSD on BSC Mainnet: 0x86896fEB19D8A607c3b11f2aF50A0f239Bd71CD0
    }


    event RewardsTransferred(address holder, uint amount);

    // @dev NNN Token contract address
    address public constant NNNtokenAddress = 0x5D5c5c1d14FaF8Ff704295b2F502dAA9D06799a0;

    // @dev NVM Token contract address
    address public constant NVMtokenAddress = 0xbC338EBAaEf242C5AEa767D9330CeA43AD4149E3;

    EnumerableSetUpgradeable.AddressSet private holders;
    uint public totalClaimedRewards = 0;

    mapping (address => uint) public depositedTokens;
    mapping (address => uint) public stakingTime;
    mapping (address => uint) public lastClaimedTime;
    mapping (address => uint) public totalEarnedTokens;

    /// @dev This function is for getting the latest XAU/BUSD price from a Chainlink data feed.
    function getLatestXAUPrice() 
        public 
        view 
        returns(int) 
    {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeedXAU.latestRoundData();
        return price;
    }

    /// @dev This function is for checking the staking time by calculating the timestamp difference
    function getPendings(address _holder) 
        public 
        view 
        returns(uint) 
    {
        if (!holders.contains(_holder)) return 0;
        if (depositedTokens[_holder] == 0) return 0;

        uint timeDiff = block.timestamp.sub(lastClaimedTime[_holder]);
        uint stakedAmount = depositedTokens[_holder];

        uint pendings;

        /// @dev This if condition is for 1 year staked tokens.
        if(timeDiff >= 31536000 && timeDiff < 63072000) {

            /// @dev Dividing by 1 and multiplying by 20 is equals to 5%. 5/100 = 1/20
            pendings = stakedAmount.div(20).mul(1);

        /// @dev This else if condition is for 2 years staked tokens.
        } else if(timeDiff >= 63072000 && timeDiff < 157680000) {

            /// @dev Dividing by 100 and multiplying by 6 is equals to 6%. 6/100
            pendings = stakedAmount.div(100).mul(6);

        /// @dev This else if condition is for 8 years staked tokens.
        } else if(timeDiff >= 157680000) {
            
            /// @dev Dividing by 100 and multiplying by 8 is equals to 8%. 8/100
            pendings = stakedAmount.div(100).mul(8);

        }

        
        return pendings;
    }

    /// @dev This function is for users to get rewards.
    function getRewards(address account) 
        private 
    {
        uint pendings = getPendings(account);
        if(pendings > 0) {
            require(Token(NVMtokenAddress).transfer(account, pendings), "Could not transfer tokens.");
            totalEarnedTokens[account] = totalEarnedTokens[account].add(pendings);
            totalClaimedRewards = totalClaimedRewards.add(pendings);
            emit RewardsTransferred(account, pendings);
        }
        lastClaimedTime[account] = block.timestamp;
    }

    function getNumberOfHolders() 
        public 
        view 
        returns (uint) 
    {
        return holders.length();
    }


    /*
        @notice This function is for depositing an amount to stake.
        @dev It calls the "transferTo" function of NNN Token contract to send the amount from user to the staking contract.
    */
    function deposit(uint amountToStake) 
        public 
    {
        require(amountToStake > 0, "Cannot deposit 0 tokens.");
        require(Token(NNNtokenAddress).transferFrom(msg.sender, address(this), amountToStake), "Insufficient token allowance.");

        depositedTokens[msg.sender] = depositedTokens[msg.sender].add(amountToStake);

        if (!holders.contains(msg.sender)) {
            holders.add(msg.sender);
            stakingTime[msg.sender] = block.timestamp;
        }

    }

    /*
        @notice This function is for withdrawing the amount that a user staked.
        @dev Users can only withdraw the amount that they've deposited. 
        It calls the "transfer" function of NNN Token contract to send the staked amount to a user.
    */
    function withdraw(uint amountToWithdraw) 
        public 
    {
        require(depositedTokens[msg.sender] != amountToWithdraw, "Invalid amount to withdraw");

        require(Token(NNNtokenAddress).transfer(msg.sender, amountToWithdraw), "Could not transfer tokens.");

        depositedTokens[msg.sender] = depositedTokens[msg.sender].sub(amountToWithdraw);
        
        if (holders.contains(msg.sender) && depositedTokens[msg.sender] == 0) {
            holders.remove(msg.sender);
        }
    }
    
    
}