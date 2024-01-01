// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IArena} from "./IArena.sol";
import {IHost} from "./IHost.sol";
import {IFund} from "./IFund.sol";

contract Arena is IArena, ERC721, ReentrancyGuard {
    uint8 public constant maxRank = 3;
    uint256 public registrationDeadline;
    uint256 public challengeDeadline;
    uint256 public mintDeadline;
    IHost public host;
    IERC20 public rewardToken;
    uint256 public rewardAmount;
    mapping(address => bool) public participants;
    mapping(address => uint256) public initProfit;
    mapping(uint8 => address) public ranks;
    mapping(address => uint8) public inRanks;

    constructor() ERC721("Trader Arena", "TA") {
        host = IHost(msg.sender);
    }

    function initialize(uint256 _registrationDeadline, uint256 _challengeDeadline, uint256 _mintDeadline, address _rewardToken, uint256 _rewardAmount) external {
        if(msg.sender != address(host)) {
            revert InvalidHost();
        }

        registrationDeadline = _registrationDeadline;
        challengeDeadline = _challengeDeadline;
        mintDeadline = _mintDeadline;
        rewardToken = IERC20(_rewardToken);
        rewardAmount = _rewardAmount;

        rewardToken.transferFrom(msg.sender, address(this), _rewardAmount);
    }

    function register() external nonReentrant returns(bool) {
        // check registration for the arena has not closed
        if (block.number > registrationDeadline) {
            revert ExceededDeadline();
        }

        if(!host.hasFund(msg.sender)) {
            revert InvalidFund();
        }

        (uint256 profit, uint256 loss) = IFund(msg.sender).performance();
        if(profit < loss) {
            revert InvalidFund();
        }

        initProfit[msg.sender] = profit;
        participants[msg.sender] = true;
        return true;
    }

    function challenge(uint8 _rank) nonReentrant external {
        if(_rank > maxRank || _rank == 0) {
            revert InvalidRank();
        }

        if(block.number <= registrationDeadline || block.number > challengeDeadline) {
            revert ExceededDeadline();
        }

        if(!participants[msg.sender]) {
            revert InvalidFund();
        }

        // avoid high rank trader challenge low rank trader
        uint8 challengerRank = inRanks[msg.sender];
        if(challengerRank != 0 && challengerRank < _rank) {
            revert InvalidChallenge();
        }

        // avoid challenger in loss raise a challenge
        (uint256 challengerProfit,) = IFund(msg.sender).performance();
        uint256 challengerInitProfit = initProfit[msg.sender];
        if(challengerProfit < challengerInitProfit) {
            revert InvalidChallenge();
        }
        
        address defender = ranks[_rank];
        uint256 defenderProfit = 0;
        if(defender != address(0)) {
            // avoid negative value
            (uint256 newDefenderProfit,) = IFund(defender).performance();
            uint256 defenderInitProfit = initProfit[defender];
            if(newDefenderProfit > defenderInitProfit) {
                defenderProfit = newDefenderProfit - defenderInitProfit;
            }
        }

        // challenger does not win
        if(challengerProfit <= defenderProfit) {
            revert InvalidChallenge();
        }

        // remove defender from rank
        if(defender != address(0)) {
            inRanks[defender] = 0;
        }

        if(challengerRank != 0) {
            // remove challenger's previous rank
            ranks[challengerRank] = address(0);
        }
        // add challenger in rank
        inRanks[msg.sender] = _rank;

        // update challenger new rank
        ranks[_rank] = msg.sender;
    }

    function mint(uint8 _rank) nonReentrant external {
        if(_rank > maxRank || _rank == 0) {
            revert InvalidRank();
        }

        if(block.number <= challengeDeadline || block.number > mintDeadline ) {
            revert ExceededDeadline();
        }
        
        if(ranks[_rank] != msg.sender) {
            revert InvalidWinner();
        }

        if(inRanks[msg.sender] != _rank) {
            revert AlreadyMinted();
        }

        // calculate reward amount
        uint256 winnerReward = rewardAmount;
        if(_rank == 1) {
            winnerReward = winnerReward * 5 / 10;
        } else if(_rank == 2) {
            winnerReward = winnerReward * 3 / 10;
        } else {
            winnerReward = winnerReward * 2 / 10;
        }

        // remove winner from rank
        inRanks[msg.sender] = 0;

        // mint the rank winner NFT
        _mint(msg.sender, _rank);

        // reward the trader
        address trader = IFund(msg.sender).trader();
        rewardToken.transfer(trader, winnerReward);
    }

    function clear(address _token) external {
        if(msg.sender != address(host)) {
            revert InvalidHost();
        }

        if(block.number <= mintDeadline ) {
            revert ExceededDeadline();
        }

        IERC20(_token).transfer(address(host), IERC20(_token).balanceOf(address(this)));
    }
}