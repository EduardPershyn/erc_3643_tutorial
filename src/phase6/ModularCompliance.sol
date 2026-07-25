// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICompliance} from "./interfaces/ICompliance.sol";
import {IModule} from "./interfaces/IModule.sol";

/// @title ModularCompliance — aggregates pluggable rule modules.
/// @notice This is the piece that makes ERC-3643 more than an ERC-20. The token
///         asks `canTransfer`; this contract returns true only if EVERY module
///         agrees. After a transfer executes, the token calls the matching hook
///         so stateful modules (e.g. holder counter) stay accurate.
contract ModularCompliance is ICompliance, Ownable {
    address private _tokenBound;
    IModule[] private _modules;
    mapping(address module => bool bound) private _isModuleBound;

    constructor() Ownable(msg.sender) {}

    modifier onlyToken() {
        require(msg.sender == _tokenBound, "Compliance: caller is not the bound token");
        _;
    }

    // --- wiring ---------------------------------------------------------

    function bindToken(address token) external override onlyOwner {
        require(token != address(0), "Compliance: zero token");
        _tokenBound = token;
        emit TokenBound(token);
    }

    function getTokenBound() external view override returns (address) {
        return _tokenBound;
    }

    function addModule(IModule module) external override onlyOwner {
        require(address(module) != address(0), "Compliance: zero module");
        require(!_isModuleBound[address(module)], "Compliance: module already added");
        _modules.push(module);
        _isModuleBound[address(module)] = true;
        emit ModuleAdded(address(module));
    }

    function removeModule(IModule module) external override onlyOwner {
        require(_isModuleBound[address(module)], "Compliance: module not added");
        _isModuleBound[address(module)] = false;
        uint256 len = _modules.length;
        for (uint256 i = 0; i < len; i++) {
            if (_modules[i] == module) {
                _modules[i] = _modules[len - 1];
                _modules.pop();
                break;
            }
        }
        emit ModuleRemoved(address(module));
    }

    function getModules() external view override returns (IModule[] memory) {
        return _modules;
    }

    // --- the gate -------------------------------------------------------

    function canTransfer(address from, address to, uint256 amount)
        external
        view
        override
        returns (bool)
    {
        uint256 len = _modules.length;
        for (uint256 i = 0; i < len; i++) {
            if (!_modules[i].moduleCheck(from, to, amount)) return false;
        }
        return true;
    }

    // --- post-action hooks (only the bound token) ----------------------

    function transferred(address from, address to, uint256 amount) external override onlyToken {
        uint256 len = _modules.length;
        for (uint256 i = 0; i < len; i++) {
            _modules[i].moduleTransferAction(from, to, amount);
        }
    }

    function created(address to, uint256 amount) external override onlyToken {
        uint256 len = _modules.length;
        for (uint256 i = 0; i < len; i++) {
            _modules[i].moduleMintAction(to, amount);
        }
    }

    function destroyed(address from, uint256 amount) external override onlyToken {
        uint256 len = _modules.length;
        for (uint256 i = 0; i < len; i++) {
            _modules[i].moduleBurnAction(from, amount);
        }
    }
}
