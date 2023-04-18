// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract FranchiseStakingV2 is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IERC20 public token;
    IERC721 public councilNFTContract;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public lastClaim;
    uint256 public totalStaked;
    uint256 public totalPoolSize;
    uint256 public priorityPoolSize;
    uint256 public stakingPeriod; // The period during rewards will accrue against the staked balances of users
    uint256 public lockPeriod;
    uint256 public lockEndTime;
    uint256 public stakingPoolOpenTime;
    uint256 public stakingStartTime;
    uint256 public priorityAccessPeriod;
    uint256 public priorityAccessEndTime;
    uint256 public singleCouncilNFTStakingLimit;
    uint256 public minimumStakingLimitPerAddress;
    uint256 public maximumStakingLimitPerAddress;
    uint256 public prematureUnstakingFeePercentage;
    address public prematureUnstakingFeeCollector;
    // The quarterDuration variable and is set to 13 weeks which is more accurate representation of 3 months than using 3 * 30 days
    uint256 public quarterDuration;
    uint256 public currentQuarterNumber;
    mapping(uint256 => uint256) public rewardPercentagePerQuarter;

    // Primary events
    event Staked(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event RewardClaimed(address indexed staker, uint256 reward);
    event RewardWithdrawn(address indexed staker, uint256 reward);
    event RewardAdded(uint256 indexed quarter, uint256 rewardAmount);

    // Secondary events emitted from setter functions
    event StakingPeriodUpdated(uint256 newStakingPeriod);
    event LockPeriodUpdated(uint256 newLockPeriod);
    event PriorityAccessPeriodUpdated(uint256 newPriorityAccessPeriod);
    event SingleCouncilNFTStakingLimitUpdated(
        uint256 newSingleCouncilNFTStakingLimit
    );
    event MinimumStakingLimitPerAddressUpdated(
        uint256 newMinimumStakingLimitPerAddress
    );
    event MaximumStakingLimitPerAddressUpdated(
        uint256 newMaximumStakingLimitPerAddress
    );
    event PrematureUnstakingFeePercentageUpdated(
        uint256 newPrematureUnstakingFeePercentage
    );
    event PrematureUnstakingFeeCollectorUpdated(
        address newPrematureUnstakingFeeCollector
    );

    // Use initialize instead of Construnctor in upgradable contracts
    function initialize(
        address _token,
        address _councilNFTContract,
        uint256 _stakingPoolOpenTime,
        uint256 _stakingStartTime,
        uint256 _totalPoolSize,
        uint256 _priorityPoolSize,
        uint256 _singleCouncilNFTStakingLimit,
        uint256 _minimumStakingLimitPerAddress,
        uint256 _maximumStakingLimitPerAddress,
        uint256 _prematureUnstakingFeePercentage
    )
        public
        // address _prematureUnstakingFeeCollector
        initializer
    {
        // Initialize Parent init()
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        token = IERC20(_token);
        councilNFTContract = IERC721(_councilNFTContract);
        stakingPoolOpenTime = _stakingPoolOpenTime;
        stakingStartTime = _stakingStartTime;
        // The lockPeriod variable is set to 26 weeks which is more accurate representation of 6 months than using 6 * 30 days
        lockPeriod = 26 weeks;
        lockEndTime = stakingStartTime + lockPeriod;
        currentQuarterNumber = 0;
        stakingPeriod = 3 * 365 days; // 3 years
        priorityAccessPeriod = 24 hours;
        priorityAccessEndTime = stakingStartTime + priorityAccessPeriod;
        totalPoolSize = _totalPoolSize;
        priorityPoolSize = _priorityPoolSize;
        singleCouncilNFTStakingLimit = _singleCouncilNFTStakingLimit;
        minimumStakingLimitPerAddress = _minimumStakingLimitPerAddress;
        maximumStakingLimitPerAddress = _maximumStakingLimitPerAddress;
        prematureUnstakingFeePercentage = _prematureUnstakingFeePercentage;
        prematureUnstakingFeeCollector = _token;
        quarterDuration = 13 weeks;
    }

    function stake(uint256 amount) public whenNotPaused nonReentrant {
        require(block.timestamp >= stakingPoolOpenTime, "Staking not yet open");
        if (block.timestamp <= priorityAccessEndTime) {
            require(
                councilNFTContract.balanceOf(msg.sender) > 0,
                "Priority access for DRIFE Council members in effect"
            );
            require(
                amount + totalStaked < priorityPoolSize,
                "Priority pool has reached its limit"
            );
            require(
                balances[msg.sender] + amount <=
                    councilNFTContract.balanceOf(msg.sender) *
                        singleCouncilNFTStakingLimit,
                "Amount exceeding maximum staking amount per Council NFT"
            );
        }
        require(block.timestamp < stakingStartTime, "Staking pool has closed");
        require(amount + totalStaked <= totalPoolSize, "Pool filled up");
        require(
            balances[msg.sender] + amount >= minimumStakingLimitPerAddress,
            "Amount less than minimum staking amount per address"
        );
        require(
            balances[msg.sender] + amount <= maximumStakingLimitPerAddress,
            "Amount exceeing the maximum staking amount per address"
        );
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        balances[msg.sender] += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) public whenNotPaused nonReentrant {
        require(block.timestamp >= lockEndTime, "Lock period not over");
        require(balances[msg.sender] >= amount, "Insufficient balance");
        uint256 prematureUnstakingFee = 0;
        if (block.timestamp < stakingStartTime + stakingPeriod) {
            prematureUnstakingFee =
                (amount * prematureUnstakingFeePercentage) /
                100;
        }
        _claimReward(msg.sender);
        require(
            token.transfer(
                prematureUnstakingFeeCollector,
                prematureUnstakingFee
            ),
            "Fee transfer failed"
        );
        require(
            token.transfer(msg.sender, amount - prematureUnstakingFee),
            "Amount transfer failed"
        );
        balances[msg.sender] -= amount;
        totalStaked -= amount;
        emit Unstaked(msg.sender, amount);
    }

    function calculateReward(address staker) public view returns (uint256) {
        require(block.timestamp >= lockEndTime, "Lock period not over");
        require(balances[staker] > 0, "Zero balance");
        uint256 stakerBalance = balances[staker];
        uint256 startQuarterNumber = (getLastClaim(staker) - stakingStartTime) /
            quarterDuration +
            1;

        uint256 reward;

        if (startQuarterNumber == currentQuarterNumber) {
            reward =
                (block.timestamp - getLastClaim(staker)) *
                rewardPercentagePerQuarter[startQuarterNumber];
            return rewards[staker] + reward;
        }

        uint256 startQuarterReward = (((startQuarterNumber * quarterDuration) -
            getLastClaim(staker)) / quarterDuration) *
            stakerBalance *
            rewardPercentagePerQuarter[startQuarterNumber];
        uint256 currentQuarterReward = ((block.timestamp -
            ((currentQuarterNumber - 1) * quarterDuration)) / quarterDuration) *
            stakerBalance *
            rewardPercentagePerQuarter[currentQuarterNumber];

        reward += startQuarterReward + currentQuarterReward;

        for (
            uint256 i = startQuarterNumber + 1;
            i < currentQuarterNumber;
            i++
        ) {
            reward += stakerBalance * rewardPercentagePerQuarter[i];
        }
        return rewards[staker] + reward;
    }

    function claimReward() public whenNotPaused nonReentrant {
        _claimReward(msg.sender);
    }

    function _claimReward(address staker) private {
        uint256 reward = calculateReward(staker);
        require(reward > 0, "No reward to claim");
        lastClaim[staker] = block.timestamp;
        rewards[staker] += reward;
        emit RewardClaimed(staker, reward);
    }

    function withdrawReward() public whenNotPaused nonReentrant {
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No reward to withdraw");
        require(block.timestamp >= lockEndTime, "Lock period not over");
        rewards[msg.sender] = 0;
        require(token.transfer(msg.sender, reward), "Transfer failed");
        emit RewardWithdrawn(msg.sender, reward);
    }

    function getLastClaim(address staker) public view returns (uint256) {
        uint256 lastClaimTime = lastClaim[staker];
        if (lastClaimTime == 0) {
            return stakingStartTime;
        } else {
            return lastClaimTime;
        }
    }

    function addReward(uint256 rewardAmount) public onlyOwner {
        require(
            token.transferFrom(msg.sender, address(this), rewardAmount),
            "Transfer failed"
        );
        rewardPercentagePerQuarter[++currentQuarterNumber] =
            rewardAmount /
            totalStaked;
        emit RewardAdded(currentQuarterNumber, rewardAmount);
    }

    // Setters for lock period and priority access period, only callable by the contract owner
    function setLockPeriod(uint256 _lockPeriod) public onlyOwner {
        // TODO: Put validations to check that lock period is still not over
        lockPeriod = _lockPeriod;
        lockEndTime = stakingStartTime + lockPeriod;
        emit LockPeriodUpdated(_lockPeriod);
    }

    function setPriorityAccessPeriod(
        uint256 _priorityAccessPeriod
    ) public onlyOwner {
        // TODO: Put validations to check that priority access period is still not over
        priorityAccessPeriod = _priorityAccessPeriod;
        priorityAccessEndTime = stakingStartTime + priorityAccessPeriod;
        emit PriorityAccessPeriodUpdated(_priorityAccessPeriod);
    }

    // Auxillary Setters, only callable by the contract owner
    function setStakingPeriod(uint256 _stakingPeriod) public onlyOwner {
        stakingPeriod = _stakingPeriod;
        emit StakingPeriodUpdated(_stakingPeriod);
    }

    function setSingleCouncilNFTStakingLimit(
        uint256 _singleCouncilNFTStakingLimit
    ) public onlyOwner {
        singleCouncilNFTStakingLimit = _singleCouncilNFTStakingLimit;
        emit SingleCouncilNFTStakingLimitUpdated(_singleCouncilNFTStakingLimit);
    }

    function setMinimumStakingLimitPerAddress(
        uint256 _minimumStakingLimitPerAddress
    ) public onlyOwner {
        minimumStakingLimitPerAddress = _minimumStakingLimitPerAddress;
        emit MinimumStakingLimitPerAddressUpdated(
            _minimumStakingLimitPerAddress
        );
    }

    function setMaximumStakingLimitPerAddress(
        uint256 _maximumStakingLimitPerAddress
    ) public onlyOwner {
        maximumStakingLimitPerAddress = _maximumStakingLimitPerAddress;
        emit MaximumStakingLimitPerAddressUpdated(
            _maximumStakingLimitPerAddress
        );
    }

    function setPrematureUnstakingFeePercentage(
        uint256 _prematureUnstakingFeePercentage
    ) public onlyOwner {
        prematureUnstakingFeePercentage = _prematureUnstakingFeePercentage;
        emit PrematureUnstakingFeePercentageUpdated(
            _prematureUnstakingFeePercentage
        );
    }

    function setPrematureUnstakingFeeCollector(
        address _prematureUnstakingFeeCollector
    ) public onlyOwner {
        prematureUnstakingFeeCollector = _prematureUnstakingFeeCollector;
        emit PrematureUnstakingFeeCollectorUpdated(
            _prematureUnstakingFeeCollector
        );
    }

    // Pause and unpause functions, only callable by the contract owner
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function getTokenAddress() public view returns (address) {
        return address(token);
    }
}
