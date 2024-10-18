pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "./SalesActivation.sol";

contract PokemonBaseSet is ERC721Enumerable, VRFConsumerBaseV2Plus {

    uint256 public s_subscriptionId;
    bytes32 public s_keyHash;
    uint32 public callbackGasLimit = 4000000;
    uint16 public requestConfirmations = 3;
    mapping(uint256 => address) internal s_rollers;

    uint256 public boosterPrice = 0.01 ether;
    uint256 public displayPrice = 0.3 ether;
    uint256 public maxBoosterSales = 3600000;
    uint8 public preSalesListMax = 2;
    uint8 public maxBoosterAtOnce = 35;
    uint8 public maxDisplayAtOnce = 6;
    address public claimFundAddress;
    string public nftURI;
    bytes32 public rootHash;
    mapping(address => bool) public preSalesList;
    mapping(address => uint256) public preSalesListClaimed;
    mapping(address => UserBoosters) internal userBoosters;
    uint8 public maxNumberOfUnopenedBoosters = 216;

    struct UserBoosters {
        uint8 numberOfUnopenedBoosters;
        uint256 requestId;
        bool roolInProgress;
        uint8 currentRandomNumberIndex;
        uint256[217] s_results;
    }

    // Presale
    uint256 public preSalesStartTime;
    uint256 public preSalesEndTime;
    uint256 public publicSalesStartTime;

    // Collection statistics
    uint8 public maxCardId = 102;
    uint8 public cardPerBooster = 11;
    uint8 public boosterPerDisplay = 36;
    mapping(uint256 => uint8) private cardIds;

    // Number of card per rarity
    uint8[] private holoCardIndex = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
    uint8[] private rareCardIndex = [16, 17, 18, 19, 20, 21, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78];
    uint8[] private uncommonCardIndex = [22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 95];
    uint8[] private commonCardIndex = [42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 90, 91, 92, 93, 94, 96];
    uint8[] private commonEnergyCardIndex = [97, 98, 99, 100, 101];

    event PreSaleBuyBooster(uint8 quantity, address indexed buyer);
    event BuyBooster(uint8 quantity, address indexed buyer);
    event BuyDisplay(uint8 quantity, address indexed buyer);
    event OpenBooster(address indexed buyer);
    event MintCard(uint8 cardIndex, address indexed buyer);
    event Withdraw(uint256 balance, address indexed owner);
    event DiceRolled(uint256 indexed requestId, address indexed roller);
    event DiceLanded(uint256 indexed requestId);

    error PreSalesNotStarted();
    error PublicSalesNotStarted();
    error StartTimeLaterThanEndTime();
    error NotWhiteListedAddress();
    error NotEnoughBoosterInStock();
    error ExceedsMaxBoostersPerUser();
    error ExceedsMaxTokens();
    error NotEnoughEthDeposited();
    error ExceedsTotalSupply();
    error CannotMint0Nft();
    error ExceedsMaxTokensAtOnce();

    constructor(
        string memory _nftURI,
        address _claimFundAddress,
        uint256 _preSalesStartTime,
        uint256 _preSalesEndTime,
        uint256 _publicSalesStartTime,
        bytes32 _rootHash,
        uint256 _subscriptionId,
        address _vrfCoordinator,
        bytes32 _keyHash
    )
    ERC721("PokemonBaseSet", "PKMN-BS")
    VRFConsumerBaseV2Plus(_vrfCoordinator)
    {
        preSalesStartTime = _preSalesStartTime;
        preSalesEndTime = _preSalesEndTime;
        publicSalesStartTime = _publicSalesStartTime;
        nftURI = _nftURI;
        claimFundAddress = _claimFundAddress;
        rootHash = _rootHash;
        s_subscriptionId = _subscriptionId;
        s_keyHash = _keyHash;
    }

    function verifyProof(
        bytes32[] calldata proof,
        bytes32 leaf
    ) private view returns (bool) {
        return MerkleProof.verify(proof, rootHash, leaf);
    }

    modifier isWhitelistedAddress(bytes32[] calldata proof) {
        require(verifyProof(proof, keccak256(abi.encodePacked(msg.sender))), NotWhiteListedAddress());
        _;
    }

    function preSaleBuyBooster(bytes32[] calldata proof, uint8 _number) external payable isPreSalesActive isWhitelistedAddress(proof) {
        require(preSalesListClaimed[msg.sender] + _number <= preSalesListMax, ExceedsMaxTokens());
        require(msg.value >= boosterPrice * _number, NotEnoughEthDeposited());
        require(_number > 0, CannotMint0Nft());

        preSalesListClaimed[msg.sender] += _number;
        userBoosters[msg.sender].numberOfUnopenedBoosters = numberOfUnopenedBoosters(msg.sender) + _number;

        userBoosters[msg.sender].requestId = rollDice(msg.sender);

        emit PreSaleBuyBooster(_number, msg.sender);
    }

    function buyBooster(uint8 _number) external payable isPublicSalesActive {
        require(_number > 0, CannotMint0Nft());
        require(_number <= maxBoosterAtOnce, ExceedsMaxTokensAtOnce());
        require(msg.value >= boosterPrice * _number, NotEnoughEthDeposited());
        require(totalSupply() + (_number) <= maxBoosterSales, ExceedsTotalSupply());
        require(numberOfUnopenedBoosters(msg.sender) + _number <= maxNumberOfUnopenedBoosters, ExceedsMaxBoostersPerUser());

        userBoosters[msg.sender].numberOfUnopenedBoosters = numberOfUnopenedBoosters(msg.sender) + _number;

        userBoosters[msg.sender].requestId = rollDice(msg.sender);

        emit BuyBooster(_number, msg.sender);
    }

    function buyDisplay(uint8 _number) external payable isPublicSalesActive {
        require(_number > 0, CannotMint0Nft());
        require(_number <= maxDisplayAtOnce, ExceedsMaxTokensAtOnce());
        require(msg.value >= displayPrice * _number, NotEnoughEthDeposited());
        require(totalSupply() + (_number * cardPerBooster) <= maxBoosterSales, ExceedsTotalSupply());
        require(numberOfUnopenedBoosters(msg.sender) + (_number * boosterPerDisplay) <= maxNumberOfUnopenedBoosters, ExceedsMaxBoostersPerUser());

        userBoosters[msg.sender].numberOfUnopenedBoosters = numberOfUnopenedBoosters(msg.sender) + (_number * boosterPerDisplay);

        userBoosters[msg.sender].requestId = rollDice(msg.sender);

        emit BuyDisplay(_number, msg.sender);
    }

    function openBooster() external {
        require(numberOfUnopenedBoosters(msg.sender) > 0, NotEnoughBoosterInStock());
        require(!roolInProgress(msg.sender), "Roll in progress");
        require(currentRandomNumberIndex(msg.sender) == numberOfUnopenedBoosters(msg.sender), "Roll in progress");
        
        userBoosters[msg.sender].numberOfUnopenedBoosters = numberOfUnopenedBoosters(msg.sender) -1;

        // 2 common energy cards
        for(uint8 i=0; i < 2;) {
            mintCard(getRandomCardIt(commonEnergyCardIndex, i));
            unchecked{ i++; }
        }

        // 5 common cards
        for(uint8 i=0; i < 5;) {
            mintCard(getRandomCardIt(commonCardIndex, i));
            unchecked{ i++; }
        }
        
        // 3 uncommon cards
        for(uint8 i=0; i < 3;) {
            mintCard(getRandomCardIt(uncommonCardIndex, i));
            unchecked{ i++; }
        }

        // 1/3 chance : 1 holo card, 2/3 chance : 1 rare card
        if((currentRandomNumber(msg.sender) % 3) == 0) {
            mintCard(getRandomCardIt(holoCardIndex, 0));
        } else {
            mintCard(getRandomCardIt(rareCardIndex, 0));
        }

        userBoosters[msg.sender].s_results[currentRandomNumberIndex(msg.sender)] = 0;
        userBoosters[msg.sender].currentRandomNumberIndex -= 1;

        emit OpenBooster(msg.sender);
    }

    function getRandomCardIt(uint8[] storage _cardIndexTable, uint8 _number) private view returns (uint8) {
        return _cardIndexTable[uint(keccak256(abi.encodePacked(currentRandomNumber(msg.sender), _number))) % _cardIndexTable.length];
    }

    function mintCard(uint8 _cardIndex) private {
        uint256 newTokenId = totalSupply() + 1;
        _safeMint(msg.sender, newTokenId);
        cardIds[newTokenId] = _cardIndex;
        emit MintCard(_cardIndex, msg.sender);
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(payable(claimFundAddress).send(balance));
        emit Withdraw(balance, claimFundAddress);
    }

    function rollDice(
        address roller
    ) internal returns (uint256 requestId) {
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: maxNumberOfUnopenedBoosters,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        s_rollers[requestId] = roller;
        userBoosters[msg.sender].roolInProgress = true;
        emit DiceRolled(requestId, roller);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        address roller = s_rollers[requestId];

        while(currentRandomNumberIndex(roller) < numberOfUnopenedBoosters(roller)) {
            userBoosters[roller].currentRandomNumberIndex++;
            userBoosters[roller].s_results[currentRandomNumberIndex(roller)] = randomWords[currentRandomNumberIndex(roller)];
        }

        userBoosters[roller].roolInProgress = false;

        emit DiceLanded(requestId);
    }

    function currentRandomNumberIndex(address addr) internal view returns(uint8) {
        return userBoosters[addr].currentRandomNumberIndex;
    }

    function currentRandomNumber(address addr) internal view returns(uint256) {
        require(currentRandomNumberIndex(addr) > 0, "Dice not rolled");
        return userBoosters[addr].s_results[currentRandomNumberIndex(addr)-1];
    }

    function numberOfUnopenedBoosters(address addr) internal view returns(uint8) {
        return userBoosters[addr].numberOfUnopenedBoosters;
    }

    function numberOfUnopenedBoosters() public view returns(uint8) {
        return numberOfUnopenedBoosters(msg.sender);
    }

    function roolInProgress(address addr) internal view returns(bool) {
        return userBoosters[addr].roolInProgress;
    }

    function roolInProgress() public view returns(bool) {
        return roolInProgress(msg.sender);
    }

    function setBoosterPrice(uint256 _boosterPrice) external onlyOwner {
        boosterPrice = _boosterPrice;
    }

    function setDisplayPrice(uint256 _displayPrice) external onlyOwner {
        displayPrice = _displayPrice;
    }

    function setMaxBoosterSales(uint256 _maxBoosterSales) external onlyOwner {
        maxBoosterSales = _maxBoosterSales;
    }

    function setPreSalesListMax(uint8 _preSalesListMax) external onlyOwner {
        preSalesListMax = _preSalesListMax;
    }

    function setClaimFundAddress(address _claimFundAddress) external onlyOwner {
        claimFundAddress = _claimFundAddress;
    }

    function setBaseURI(string calldata _nftURI) external onlyOwner {
        nftURI = _nftURI;
    }

    function setMaxBoosterAtOnce(uint8 _maxBoosterAtOnce) external onlyOwner {
        maxBoosterAtOnce = _maxBoosterAtOnce;
    }

    function setMaxDisplayAtOnce(uint8 _maxDisplayAtOnce) external onlyOwner {
        maxDisplayAtOnce = _maxDisplayAtOnce;
    }

    function _baseURI() internal view virtual override returns(string memory) {
        return nftURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireOwned(tokenId);
        require(cardIds[tokenId] >= 0);
        return bytes(nftURI).length > 0 ? string.concat(nftURI, Strings.toString(cardIds[tokenId])) : "";
    }

    modifier isPreSalesActive() {
        require(isPreSalesActivated(), PreSalesNotStarted());
        _;
    }

    modifier isPublicSalesActive() {
        require(isPublicSalesActivated(), PublicSalesNotStarted());
        _;
    }

    function isPreSalesActivated() public view returns(bool) {
        return preSalesStartTime > 0 && preSalesEndTime > 0 && block.timestamp >= preSalesStartTime  && block.timestamp <= preSalesEndTime;
    }

    function isPublicSalesActivated() public view returns(bool) {
        return publicSalesStartTime > 0 && block.timestamp >= publicSalesStartTime;
    }

    function setPublicSalesTime(uint256 _publicSalesStartTime) external onlyOwner {
        publicSalesStartTime = _publicSalesStartTime;
    }

    function setPresaleTime(uint256 _preSalesStartTime, uint256 _preSalesEndTime) external onlyOwner {
        require(preSalesStartTime < preSalesEndTime, StartTimeLaterThanEndTime());
        preSalesStartTime = _preSalesStartTime;
        preSalesEndTime = _preSalesEndTime;
    }

}