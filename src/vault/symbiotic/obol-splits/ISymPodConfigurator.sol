// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

interface ISymPodConfigurator {
    function isCheckPointPaused() external returns (bool);
    function isWithdrawalsPaused() external returns (bool);
}
