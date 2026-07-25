// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentRole — owner-managed set of operational "agents".
/// @notice ERC-3643 separates governance (owner) from day-to-day operations
///         (agents). The owner appoints agents; agents perform the routine
///         work — registering identities (Phase 5), minting/freezing (Phase 7).
///         Reused by the Identity Registry and the token.
abstract contract AgentRole is Ownable {
    mapping(address account => bool isAgent) private _agents;

    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);

    constructor() Ownable(msg.sender) {}

    modifier onlyAgent() {
        require(_agents[msg.sender], "AgentRole: caller is not an agent");
        _;
    }

    function addAgent(address agent) external onlyOwner {
        require(agent != address(0), "AgentRole: zero agent");
        require(!_agents[agent], "AgentRole: already an agent");
        _agents[agent] = true;
        emit AgentAdded(agent);
    }

    function removeAgent(address agent) external onlyOwner {
        require(_agents[agent], "AgentRole: not an agent");
        _agents[agent] = false;
        emit AgentRemoved(agent);
    }

    function isAgent(address agent) external view returns (bool) {
        return _agents[agent];
    }
}
