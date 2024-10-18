pragma solidity 0.8.27;

import "../PokemonBaseSet.sol";

contract PokemonBaseSetTest is PokemonBaseSet {

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
    PokemonBaseSet(
        _nftURI,
        _claimFundAddress,
        _preSalesStartTime,
        _preSalesEndTime,
        _publicSalesStartTime,
        _rootHash,
        _subscriptionId,
        _vrfCoordinator,
        _keyHash)
    { }

    function rollDice() external {
        userBoosters[msg.sender].requestId = rollDice(msg.sender);
    }

    function getRollerByRequestId(uint256 key) external view returns(address) {
        return s_rollers[key];
    }

    function currentRandomNumberIndex() external view returns(uint8) {
        return currentRandomNumberIndex(msg.sender);
    }

    function currentRandomNumber() external view returns(uint256) {
        return currentRandomNumber(msg.sender);
    }

    function randomNumberByIndex(uint8 _index) external view returns(uint256) {
        return userBoosters[msg.sender].s_results[_index];
    }

    function requestId() external view returns(uint256) {
        return userBoosters[msg.sender].requestId;
    }

    function setNumberOfUnopenedBoosters(uint8 _number) external {
        userBoosters[msg.sender].numberOfUnopenedBoosters = _number;
    }

}