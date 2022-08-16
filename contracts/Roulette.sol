//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Roulette is Ownable, VRFConsumerBaseV2 {
    struct Bet {
        uint256 requestId;
        address player;
        address token;
        uint8 betType;
        uint8 number;
        uint128 betAmount;
    }

    struct Token {
        bool isSupported;
        uint128 minBet;
        uint128 maxBet;
    }

    VRFCoordinatorV2Interface COORDINATOR;

    /** BSC TESTNET */
    uint64 s_subscriptionId;
    address vrfCoordinator = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
    bytes32 keyHash =
        0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;
    uint32 callbackGasLimit = 1000000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;

    mapping(uint256 => address) private idToUser;
    mapping(uint256 => uint256) private idToIndex;

    uint128 public wallet1Fee = 150; //1.5%
    uint128 public wallet2Fee = 100; //1.0%
    address public wallet1 = address(0x123);
    address public wallet2 = address(0x456);

    uint8[] private payouts;
    uint8[] private numberRange;

    IERC721 nft;

    /*
    BetTypes are as follow:
      0: color
      1: column
      2: dozen
      3: eighteen
      4: modulus
      5: number
      
    Depending on the BetType, number will be:
      color: 0 for black, 1 for red
      column: 0 for left, 1 for middle, 2 for right
      dozen: 0 for first, 1 for second, 2 for third
      eighteen: 0 for low, 1 for high
      modulus: 0 for even, 1 for odd
      number: number
  */

    Bet[] public allBets;
    mapping(address => Bet[]) public userBets;
    mapping(address => Token) public tokens;

    event BetPlaced(
        address indexed user,
        uint256 betAmount,
        uint8 number,
        uint8 betType,
        address token
    );
    event WheelSpinned(
        address indexed user,
        bool win,
        uint256 randomNum,
        uint256 betAmount,
        uint256 winAmount,
        uint8 number,
        uint8 betType
    );

    constructor(uint64 subscriptionId, address _nft)
        VRFConsumerBaseV2(vrfCoordinator)
    {
        payouts = [2, 3, 3, 2, 2, 36];
        numberRange = [1, 2, 2, 1, 1, 36];
        s_subscriptionId = subscriptionId;
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        nft = IERC721(_nft);
    }

    function placeBet(
        address token,
        uint8 number,
        uint8 betType,
        uint128 betAmount
    ) external payable {
        /* 
       A bet is valid when:
       1 - the value of the bet is correct
       2 - betType is known (between 0 and 5)
       3 - the option betted is valid (don't bet on 37!)
       4 - the bank has sufficient funds to pay the bet
       5 - Token address provided is supported
    */
        Token memory tkn = tokens[token];
        IERC20 _token = IERC20(token);
        _token.transferFrom(msg.sender, address(this), betAmount);

        uint128 wallet1Amount = (betAmount * wallet1Fee) / 10000;
        uint128 wallet2Amount = (betAmount * wallet2Fee) / 10000;
        _token.transfer(wallet1, wallet1Amount);
        _token.transfer(wallet2, wallet2Amount);
        betAmount = betAmount - wallet1Amount - wallet2Amount;

        uint256 payoutForThisBet = payouts[betType] * betAmount;
        require(tkn.isSupported, "Token not supported");
        require(
            _token.balanceOf(address(this)) >= payoutForThisBet,
            "Not enough balance to pay profits"
        );
        require(
            betAmount >= tkn.minBet && betAmount <= tkn.maxBet,
            "Invalid bet amount"
        );
        require(betType >= 0 && betType <= 5, "Invalid bet type");
        require(
            number >= 0 && number <= numberRange[betType],
            "Invalid bet number"
        );
        require(nft.balanceOf(msg.sender) > 0, "Not an owner of NFT");

        uint256 s_requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        allBets.push(
            Bet({
                requestId: s_requestId,
                betType: betType,
                player: msg.sender,
                token: token,
                number: number,
                betAmount: betAmount
            })
        );

        userBets[msg.sender].push(
            Bet({
                requestId: s_requestId,
                betType: betType,
                player: msg.sender,
                token: token,
                number: number,
                betAmount: betAmount
            })
        );

        idToUser[s_requestId] = msg.sender;
        idToIndex[s_requestId] = userBets[msg.sender].length - 1;

        emit BetPlaced(msg.sender, betAmount, number, betType, token);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        uint256 number = randomWords[0] % 37;
        Bet memory bet = userBets[idToUser[requestId]][idToIndex[requestId]];
        bool won = false;
        if (number == 0) {
            won = (bet.betType == 5 && bet.number == 0); /* bet on 0 */
        } else {
            if (bet.betType == 5) {
                won = (bet.number == number); /* bet on number */
            } else if (bet.betType == 4) {
                if (bet.number == 0) won = (number % 2 == 0); /* bet on even */
                if (bet.number == 1) won = (number % 2 == 1); /* bet on odd */
            } else if (bet.betType == 3) {
                if (bet.number == 0) won = (number <= 18); /* bet on low 18s */
                if (bet.number == 1) won = (number >= 19); /* bet on high 18s */
            } else if (bet.betType == 2) {
                if (bet.number == 0) won = (number <= 12); /* bet on 1st dozen */
                if (bet.number == 1) won = (number > 12 && number <= 24); /* bet on 2nd dozen */
                if (bet.number == 2) won = (number > 24); /* bet on 3rd dozen */
            } else if (bet.betType == 1) {
                if (bet.number == 0) won = (number % 3 == 1); /* bet on left column */
                if (bet.number == 1) won = (number % 3 == 2); /* bet on middle column */
                if (bet.number == 2) won = (number % 3 == 0); /* bet on right column */
            } else if (bet.betType == 0) {
                if (bet.number == 0) {
                    /* bet on black */
                    if (number <= 10 || (number >= 20 && number <= 28)) {
                        won = (number % 2 == 0);
                    } else {
                        won = (number % 2 == 1);
                    }
                } else {
                    /* bet on red */
                    if (number <= 10 || (number >= 20 && number <= 28)) {
                        won = (number % 2 == 1);
                    } else {
                        won = (number % 2 == 0);
                    }
                }
            }
        }

        uint128 amount;
        if (won) {
            amount = bet.betAmount * payouts[bet.betType];
            uint128 wallet1Amount = (amount * wallet1Fee) / 10000;
            uint128 wallet2Amount = (amount * wallet2Fee) / 10000;
            amount = amount - wallet1Amount - wallet2Amount;

            IERC20(bet.token).transfer(wallet1, wallet1Amount);
            IERC20(bet.token).transfer(wallet2, wallet2Amount);
            IERC20(bet.token).transfer(bet.player, amount);
        }

        emit WheelSpinned(
            bet.player,
            won,
            number,
            bet.betAmount,
            amount,
            bet.number,
            bet.betType
        );
    }

    function setToken(
        address _token,
        bool _isSupported,
        uint128 _minBet,
        uint128 _maxBet
    ) external onlyOwner {
        tokens[_token].isSupported = _isSupported;
        tokens[_token].minBet = _minBet;
        tokens[_token].maxBet = _maxBet;
    }

    function setFees(
        uint16 _wallet1Fee,
        uint16 _wallet2Fee,
        address _wallet1,
        address _wallet2
    ) external onlyOwner {
        wallet1Fee = _wallet1Fee;
        wallet2Fee = _wallet2Fee;
        wallet1 = _wallet1;
        wallet2 = _wallet2;
    }

    function getAllBetsOfUser(
        address user,
        uint256 from,
        uint256 to
    ) external view returns (Bet[] memory bets) {
        bets = new Bet[](to - from + 1);
        for (uint256 i = from; i <= to; i++) {
            bets[i] = userBets[user][i];
        }
    }

    function getAllBets(uint256 from, uint256 to)
        external
        view
        returns (Bet[] memory bets)
    {
        bets = new Bet[](to - from + 1);
        for (uint256 i = from; i <= to; i++) {
            bets[i] = allBets[i];
        }
    }
}
