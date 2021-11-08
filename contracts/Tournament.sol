pragma solidity ^0.8.4;
// SPDX-License-Identifier: UNLICENSED

import "./TournamentBase.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

interface IRoosterFight {
    function fight (uint _attacker, uint _defender,uint _randomNumber) external returns (uint, uint);
}

contract Tournament is TournamentBase, VRFConsumerBase {
    event FightStarted(bytes32 requestId, uint _attacker, uint _defense, uint _eventId, uint combatId);
    event FightFinished(bytes32 requestId, uint _attacker, uint _defense, uint _eventId, uint combatId);
    event FightWinner(bytes32 requestId, uint winner, address owner);

    struct MatchUp {
        uint token;
        bytes32 requestId;
        uint eventId;
        string name;
        uint attacker;
        uint defense;
        bool active;
        uint winner;
    }

    bytes32 internal keyHash;
    uint256 internal fee;    
    MatchUp[] internal combats;
    
    mapping (uint => mapping(uint => mapping(uint => bool))) public eventToPlayerVsPlayer;
    mapping (bytes32 => uint) public requestIdToRandomNumber;
    
    constructor(address _vrfCoodinator, address _linkToken, bytes32 _keyhash  ) VRFConsumerBase(
        _vrfCoodinator,
        _linkToken
    ) {
        contractOwner = payable(msg.sender);
        keyHash = _keyhash;
        fee = 0.1 * 10 ** 18; // 0.1 LINK (Varies by network)
    }

    function getMatchesForEvent(uint _eventId) public view returns (MatchUp[] memory) {
        uint combatsCount = events[_eventId].combatsCount;
        MatchUp[] memory eCombats = new MatchUp[](combatsCount);
        for (uint256 index = 0; index < combats.length; index++) {
            if (eventToPlayer[_eventId][index] != 0) {
                eCombats[index] = combats[index];
            }
        }
        return eCombats;
    }

    function prepareFight(uint _attackerPlayerId, uint _defensePlayerId, uint _eventId) public returns (bytes32, uint) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
        require(eventToPlayerVsPlayer[_eventId][_attackerPlayerId][_defensePlayerId] == false, "Fight already exists");
        bytes32 requestId = requestRandomness(keyHash, fee);
        uint combatId = combats.length;
        events[_eventId].combatsCount++;
        combats.push(MatchUp(combatId, requestId, _eventId, "", _attackerPlayerId, _defensePlayerId, true, 0));
        emit FightStarted(requestId, eventToPlayer[_eventId][_attackerPlayerId], eventToPlayer[_eventId][_defensePlayerId], _eventId, combatId); 
        eventToPlayerVsPlayer[_eventId][_attackerPlayerId][_defensePlayerId] = true;
        return (requestId, combatId);       
    }

    function fulfillRandomness(bytes32 _requestId, uint _randomNumber) internal override {
        requestIdToRandomNumber[_requestId] = _randomNumber;
    }

    function startFight(bytes32 _requestId, uint _combatId) public {
        MatchUp storage combat = combats[_combatId];
        require(combat.active == true, "Combat already finished");
        uint winner;
        uint loser;
        
        // Token Ids 
        (winner, loser) = IRoosterFight(roosterFightAdress).fight(eventToPlayer[combat.eventId][combat.attacker], eventToPlayer[combat.eventId][combat.defense], requestIdToRandomNumber[combat.requestId]);
        combat.active = false;
        combat.winner = winner;

        // Here I need players id
        uint winnerPlayerId = eventToPlayer[combat.eventId][combat.attacker] == winner ? combat.attacker : combat.defense;
        uint loserPlayerId = eventToPlayer[combat.eventId][combat.attacker] != winner ? combat.attacker : combat.defense;

        // Give the prizes to the winners
        players[winnerPlayerId].record.wins++;
        players[winnerPlayerId].points += 3;
        players[loserPlayerId].record.losses++;

        emit FightWinner(_requestId, winner, players[winnerPlayerId].owner);
        emit FightFinished(_requestId, combat.attacker, combat.defense, combat.eventId, combat.token);
    }
}