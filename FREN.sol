pragma solidity ^0.8.0;

contract InterestCalculator {
    function calculateInterest(uint256 initialBurnedTokens, uint256 timeElapsed, uint256 interestRate) public pure returns (uint256) {
        uint256 numberOfDaysElapsed = timeElapsed / 86400;
        uint256 dailyBonusRate = 1; // 0.01% daily bonus rate
        uint256 cappedDailyBonusRate = 99; // 0.99% capped daily bonus rate
        uint256 scaleFactor = 1e18;

        uint256 interestEarned = 0;
        for (uint256 i = 0; i < numberOfDaysElapsed; i++) {
            uint256 dailyBonus = i < 99 ? i * dailyBonusRate : cappedDailyBonusRate;
            uint256 dailyInterestRate = (interestRate + dailyBonus) * scaleFactor / 10000;
            uint256 dailyInterest = initialBurnedTokens * dailyInterestRate / scaleFactor;
            interestEarned += dailyInterest;
            initialBurnedTokens += dailyInterest;
        }

        uint256 remainingSecondsInDay = timeElapsed % 86400;
        uint256 remainingBonus = numberOfDaysElapsed < 99 ? numberOfDaysElapsed * dailyBonusRate : cappedDailyBonusRate;
        uint256 remainingInterestRate = (interestRate + remainingBonus) * scaleFactor / 10000;
        uint256 remainingInterest = getRemainingInterest(initialBurnedTokens,remainingInterestRate,remainingSecondsInDay,scaleFactor);
        interestEarned += remainingInterest;

        return interestEarned;
    }

    function getRemainingInterest(uint256 initialBurnedTokens, uint256 remainingInterestRate, uint256 remainingSecondsInDay, uint256 scaleFactor) internal pure returns (uint256) {
            return initialBurnedTokens * remainingInterestRate * remainingSecondsInDay / scaleFactor / 86400;
    }
}


pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ERC20r.sol";

contract FREN is ERC20r, ReentrancyGuard, InterestCalculator {

    //Declartion of variables
    uint256 public initialSupply;
    
    //Variables relating to burn and interest rates
    uint256 public constant minBurnRate = 1;
    uint256 public constant maxBurnRate = 2000;
    uint256 public constant baseBurnRate = 100;
    uint256 public dailyInterestRate = 10;


    //Variables relating to farming
    uint256 public makeFrenPrice = 1000000 * 10 ** decimals();
    uint256 public minFrenTime = 604800; //Defaulted to 1 week in seconds

    //Percentage of burned tokens that are re-distributed
    uint256 public distributionPercentage = 690;

    uint256 public sigilRewardPercentage = 100;
    address public sigilRewardContract;
    //Total number of reflected tokens
    uint256 public _totalReflected;
    //Total FREN being used for farming currently
    uint256 public totalFarmingFren;

    //Mappings to handle FrenPairs and solo-queuers 
    mapping(address => uint256) public queueTime;
    mapping(address => uint256) public stakeAmount;
    mapping(address => uint256) public userToFrenPairIndex;
    mapping(address => bool) public isFrended;
    
    //Daily interest rate earned by FrenPairs in basis points
    uint256 public constant interestRatePerDay = 10;
    //Burn toggle and owner variables
    bool public isBurnPaused = true;
    address public owner;
    //Variable to track last user in the queue
    address public lastFrenInQueue;
    

    //Events regarding FrenPairs
    event NewFrenPair(address indexed fren1, address indexed fren2);
    event EndedFrenPair(address indexed fren);
    event NewFrenInQueue(address indexed fren, uint256 amount);

    //Initial supply = 69billion
    constructor() ERC20r("FREN", "FREN") {
        initialSupply = 69000000000 * 10 ** decimals();
        owner = msg.sender;
        _mint(msg.sender, initialSupply);
    }

    //Struct holding FrenPair data, stakes refer to the user's initial stake only
    struct FrenPair {
        address fren1;
        address fren2;
        uint256 fren1Stake;
        uint256 fren2Stake;
        uint256 startTimestamp;
    }

    //Array for quick access
    FrenPair[] public frenPairs;
    
    //Overridden transfer function to handle burn and reflection calculations
    function _transfer(address sender, address recipient, uint256 amount) internal override {

        uint256 burnAmount = 0;
        if (!isBurnPaused) {
            uint256 burnRate = _calculateBurnRate();
            burnAmount = amount * burnRate / 10000;

            uint256 distributionAmount = burnAmount * distributionPercentage / 10000;
            uint256 sigilRewards = burnAmount * sigilRewardPercentage / 10000;
            _mint(sigilRewardContract, sigilRewards);
            _totalReflected += distributionAmount;
        }
        uint256 amountAfterBurn = amount - burnAmount;

        super._transfer(sender, recipient, amountAfterBurn);
        _burn(sender, burnAmount);
    }

    //Overridden balanceOf function to automatically increase/decrease holder balances based on reflections
    function balanceOf(address account) public view virtual override returns (uint256) {
        uint256 reflectedRewards = (_totalReflected * _balances[account]) / (_totalReflected + totalSupply());
        return _balances[account] + reflectedRewards;
    }

        /**
        * @dev Allows a user to become a Fren by staking FREN tokens.
        *      Adds the user to the Fren queue if no other users are in the queue.
        *      Pairs the user with the most recent user in the queue and creates a Fren pair.
        *      Burns the staked tokens and adds them to the total Fren farming pool.
        * @param amount The amount of FREN tokens to stake.
        */
    function makeFren(uint256 amount) public nonReentrant {
        require(amount >= makeFrenPrice, "Below minimum stake!");
        require(balanceOf(msg.sender) >= amount, "You need more FREN to begin FREN farming!");
        require(lastFrenInQueue != msg.sender, "You can't be paired with yourself, fren!");
        require(!isFrended[msg.sender], "You have a fren to watch out for already!");
        _burn(msg.sender, amount);

        if (lastFrenInQueue == address(0)) {
            lastFrenInQueue = msg.sender;
            queueTime[msg.sender] = block.timestamp;
            stakeAmount[msg.sender] = amount;
            totalFarmingFren += amount;
            emit NewFrenInQueue(msg.sender, amount);
        } else {
            stakeAmount[msg.sender] = amount;
            address pairedUser = lastFrenInQueue;
            uint256 timeAverage = (queueTime[pairedUser] + block.timestamp) / 2;
            isFrended[pairedUser] = true;
            isFrended[msg.sender] = true;
            queueTime[pairedUser] = 0;
            lastFrenInQueue = address(0);
            frenPairs.push(FrenPair(msg.sender, pairedUser, stakeAmount[msg.sender], stakeAmount[pairedUser], timeAverage));
            totalFarmingFren += stakeAmount[msg.sender];
            uint256 newFrenPairIndex;
            if (frenPairs.length > 0) {
                newFrenPairIndex = frenPairs.length - 1;
            } else {
                newFrenPairIndex = frenPairs.length;
            }
            userToFrenPairIndex[msg.sender] = newFrenPairIndex;
            userToFrenPairIndex[pairedUser] = newFrenPairIndex;
            emit NewFrenPair(msg.sender, pairedUser);
        }
    }

    /**
    * @dev Allows two Fren pair members to stop being Frens and claim their stakes and rewards.
    *      Calculates the rewards earned by each Fren based on their staked amount and the duration of the Fren pair.
    *      Distributes a portion of each Fren's stake to other users as a farming reward.
    *      Mints tokens to each Fren for their stake plus rewards earned, minus farming rewards distributed.
    */
    function stopBeingFren() public nonReentrant {
        uint256 frenPairIndex = userToFrenPairIndex[msg.sender];
        FrenPair storage frenPair = frenPairs[frenPairIndex];

        require(frenPair.fren1 == msg.sender || frenPair.fren2 == msg.sender, "Sender is not part of any Fren pair");

        uint256 timeElapsed = block.timestamp - frenPair.startTimestamp;

        require(timeElapsed >= minFrenTime, "You must be Frens for a minimum amount of time first!");

        uint256 tokensToMintFren1 = earnedFren(frenPair.fren1);
        uint256 tokensToMintFren2 = earnedFren(frenPair.fren2);

        uint256 fren1Stake = frenPair.fren1Stake;
        uint256 fren2Stake = frenPair.fren2Stake;
        frenPair.fren1Stake = 0;
        frenPair.fren2Stake = 0;

        uint256 distributionPercentage1 = frenPair.fren1 == msg.sender ? 500 : 190; // 5% for unstaking FREN, 1.9% for the other
        uint256 distributionPercentage2 = frenPair.fren2 == msg.sender ? 500 : 190; // 5% for unstaking FREN, 1.9% for the other

        uint256 distributionAmount1 = (tokensToMintFren1 - fren1Stake) * distributionPercentage1 / 10000;
        uint256 distributionAmount2 = (tokensToMintFren2 - fren2Stake) * distributionPercentage2 / 10000;
        uint256 sigilRewards = (distributionAmount1 * sigilRewardPercentage / 10000) + (distributionAmount2 * sigilRewardPercentage / 10000);
        

        _totalReflected += distributionAmount1;
        _totalReflected += distributionAmount2;

        // Mint the tokens for the fren1 and fren2 users
        _mint(frenPair.fren1, tokensToMintFren1 - distributionAmount1);
        _mint(frenPair.fren2, tokensToMintFren2 - distributionAmount2);
        _mint(sigilRewardContract, sigilRewards);
        isFrended[frenPair.fren1] = false;
        isFrended[frenPair.fren2] = false;

        totalFarmingFren -= stakeAmount[frenPair.fren1] + stakeAmount[frenPair.fren2];

        // Remove the Fren pair and update the mapping
        delete userToFrenPairIndex[frenPair.fren1];
        delete userToFrenPairIndex[frenPair.fren2];
        if (frenPairIndex != frenPairs.length - 1) {
            // Move the last Fren pair to the removed pair's position
            frenPairs[frenPairIndex] = frenPairs[frenPairs.length - 1];
            userToFrenPairIndex[frenPairs[frenPairIndex].fren1] = frenPairIndex;
            userToFrenPairIndex[frenPairs[frenPairIndex].fren2] = frenPairIndex;
        }
        frenPairs.pop();
        emit EndedFrenPair(msg.sender);
    }

    /**
    * @dev Allows a user to leave the queue and claim their stake and interest.
    *      Calculates the interest earned based on the time elapsed and daily interest rate.
    *      Distributes a portion of the staked tokens to other users as a farming reward.
    *      Mints tokens to the user for their stake plus interest earned.
    */
    function leaveQueue() public {
        require(lastFrenInQueue == msg.sender);
        require(queueTime[msg.sender] != 0);
            uint256 timeElapsed = block.timestamp - queueTime[msg.sender];
        require(timeElapsed >= (minFrenTime / 7), "You must be alone in the queue for longer before leaving.");
            lastFrenInQueue = address(0);
            queueTime[msg.sender] = 0;
            uint256 initialBurnedTokens = stakeAmount[msg.sender];
            stakeAmount[msg.sender] = 0;
            uint256 interestEarned = calculateInterest(initialBurnedTokens, timeElapsed, dailyInterestRate)/3;
            uint256 tokensToMintFren = initialBurnedTokens + interestEarned;
            uint256 distributionAmount = (initialBurnedTokens/10) * distributionPercentage / 10000;
            _totalReflected += distributionAmount;
            _mint(msg.sender, tokensToMintFren);
            totalFarmingFren -= stakeAmount[msg.sender];
    }


    /**
    * @dev Calculates the amount of FREN tokens earned by a user in their Fren pair based on their staked amount and the duration of the Fren pair.
    *      Calculates the earned tokens by calling the calculateInterest function.
    *      Returns the total amount of tokens to be minted for the user (initial stake amount plus earned tokens).
    * @param user The address of the user to calculate the earned FREN for.
    * @return The total amount of FREN tokens to be minted for the user.
    */
    function earnedFren(address user) public view returns (uint256) {
            uint256 frenPairIndex = userToFrenPairIndex[user];
            FrenPair storage frenPair = frenPairs[frenPairIndex];

                uint256 userFrenNumber = frenPair.fren1 == user ? 1 : 2;
                uint256 timeElapsed = block.timestamp - frenPair.startTimestamp;

                    uint256 userStakeAmount;
                        if (userFrenNumber == 1) {
                            userStakeAmount = frenPair.fren1Stake;
                        } else {
                            userStakeAmount = frenPair.fren2Stake;
                        }
                    uint256 initialBurnedTokens = userStakeAmount;

                    uint256 earnedTokens = calculateInterest(initialBurnedTokens, timeElapsed, dailyInterestRate);

                    uint256 tokensToMintFren = earnedTokens + initialBurnedTokens;

                    return tokensToMintFren;
    }


    /**
    * @dev Calculates the current burn rate based on the current supply of tokens.
    *      The burn rate increases or decreases by 1 basis point for every 0.1% change in supply.
    *      The burn rate is capped between the minBurnRate and maxBurnRate values.
    * @return The current burn rate as a percentage (basis points).
    */
    function _calculateBurnRate() public view returns (uint256) {
        uint256 currentSupply = totalSupply();
        uint256 currentBurnRate = baseBurnRate;

        // Calculate the percentage change in supply relative to the initial supply
        uint256 supplyChangePercentage;
        if (currentSupply > initialSupply) {
            supplyChangePercentage = (currentSupply - initialSupply) * 10000 / initialSupply;
        } else {
            supplyChangePercentage = (initialSupply - currentSupply) * 10000 / initialSupply;
        }

        // Calculate the change in burn rate
        uint256 burnRateChange = supplyChangePercentage / 25;

        // Apply the change in burn rate
        if (currentSupply > initialSupply) {
            currentBurnRate += burnRateChange;
            if (currentBurnRate > maxBurnRate) {
                currentBurnRate = maxBurnRate;
            }
        } else {
            if (currentBurnRate > burnRateChange) {
                currentBurnRate -= burnRateChange;
            } else {
                currentBurnRate = minBurnRate;
            }
        }

        return currentBurnRate;
    }


    function setBurnPaused(bool _isBurnPaused) public onlyOwner {
        isBurnPaused = _isBurnPaused;
    }

    function updateMinFrenTime(uint256 _newTime) public onlyOwner {
        minFrenTime = _newTime;
    }

    function updateSigilRewardContract(address _contractAddress) external onlyOwner {
        sigilRewardContract = _contractAddress;
    }

    function renounceOwnership() public onlyOwner {
        owner = address(0);
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Wrong permissions.");
        _;
    }
}
