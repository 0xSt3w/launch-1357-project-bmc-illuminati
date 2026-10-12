// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev TEST ONLY: etched at the fixed BMC address. Never a deployable replacement for BMC.
contract MockBMC is ERC20 {
    uint256 public feeBps;
    uint256 public surchargeBps;
    uint256 public reflectionBps;
    uint8 public mockDecimals;
    uint8 public returnMode;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackSucceeded;
    bytes4 public callbackError;
    bool private inCallback;

    constructor() ERC20("Test-only BMC behavior", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    function setFee(uint256 bps) external {
        require(bps <= 10_000);
        feeBps = bps;
    }


    /// @notice Simulates ERC20Burnable.burnFrom for integration tests.
    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    }

    function setFee(uint256 bps) external {
        require(bps <= 10_000);
        feeBps = bps;
    }

    function setSurcharge(uint256 bps) external {
        surchargeBps = bps;
    }

    function setReflection(uint256 bps) external {
        reflectionBps = bps;
    }

    function setDecimals(uint8 value) external {
        mockDecimals = value;
    }

    function setReturnMode(uint8 mode) external {
        returnMode = mode;
    }

    function decimals() public view override returns (uint8) {
        return mockDecimals;
    }

    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
        callbackSucceeded = false;
        callbackError = bytes4(0);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        return _returnValue();
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        return _returnValue();
    }

    function _returnValue() private view returns (bool) {
        if (returnMode == 2) {
            assembly { return(0, 0) }
        }
        return returnMode != 1;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }
        uint256 fee = value * feeBps / 10_000;
        if (fee != 0) super._update(from, address(0), fee);
        super._update(from, to, value - fee);
        if (surchargeBps != 0) super._update(from, address(0), value * surchargeBps / 10_000);
        if (reflectionBps != 0) super._update(address(0), to, value * reflectionBps / 10_000);
        if (callbackTarget != address(0) && !inCallback) {
            inCallback = true;
            bytes memory result;
            (callbackSucceeded, result) = callbackTarget.call(callbackData);
            if (result.length >= 4) callbackError = bytes4(result);
            inCallback = false;
        }
    }
}
