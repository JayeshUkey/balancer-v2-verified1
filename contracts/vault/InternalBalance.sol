// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../vendor/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./Fees.sol";

import "../math/FixedPoint.sol";

abstract contract InternalBalance is ReentrancyGuard, Fees {
    using SafeERC20 for IERC20;
    using FixedPoint for uint128;
    using FixedPoint for uint256;
    using SafeCast for uint256;

    // user -> token -> internal balance
    mapping(address => mapping(IERC20 => uint128)) internal _internalTokenBalance;

    event Deposited(address indexed depositor, address indexed user, IERC20 indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed recipient, IERC20 indexed token, uint256 amount);
    event Transferred(address indexed from, address indexed to, IERC20 indexed token, uint256 amount);

    function getInternalBalance(address user, IERC20 token) public view override returns (uint256) {
        return _internalTokenBalance[user][token];
    }

    function depositToInternalBalance(
        IERC20 token,
        uint256 amount,
        address user
    ) external override nonReentrant {
        token.safeTransferFrom(msg.sender, address(this), amount);

        _internalTokenBalance[user][token] = _internalTokenBalance[user][token].add128(amount.toUint128());
        emit Deposited(msg.sender, user, token, amount);
    }

    function withdrawFromInternalBalance(
        IERC20 token,
        uint256 amount,
        address recipient
    ) external override nonReentrant {
        require(_internalTokenBalance[msg.sender][token] >= amount, "Vault: withdraw amount exceeds balance");

        _internalTokenBalance[msg.sender][token] -= amount.toUint128();

        uint128 feeAmount = _calculateProtocolWithdrawFeeAmount(amount.toUint128());

        _collectedProtocolFees[token] = _collectedProtocolFees[token].add(feeAmount);
        token.safeTransfer(recipient, amount.sub(feeAmount));

        emit Withdrawn(msg.sender, recipient, token, amount);
    }

    function transferInternalBalance(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        address recipient
    ) external override nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            uint128 currentBalance = _internalTokenBalance[msg.sender][token];
            uint128 amount = amounts[i].toUint128();
            require(amount <= currentBalance, "ERR_NOT_ENOUGH_INTERNAL_BALANCE");

            _internalTokenBalance[msg.sender][token] = currentBalance - amount;
            _internalTokenBalance[recipient][token] = _internalTokenBalance[recipient][token].add128(amount);
            emit Transferred(msg.sender, recipient, token, amount);
        }
    }
}
