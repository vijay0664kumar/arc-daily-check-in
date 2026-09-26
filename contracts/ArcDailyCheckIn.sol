// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ArcDailyCheckIn {
    error AlreadyCheckedInToday();

    uint256 public constant CHECK_IN_WINDOW = 24 hours;
    uint256 public constant STREAK_BREAK_WINDOW = 48 hours;
    uint256 public constant MAX_RECENT_CHECK_INS = 100;

    struct CheckInEntry {
        address user;
        uint256 timestamp;
    }

    mapping(address => uint256) public totalCheckIns;
    mapping(address => uint256) public streak;
    mapping(address => uint256) public lastCheckIn;

    CheckInEntry[MAX_RECENT_CHECK_INS] private _recentCheckIns;
    uint256 private _recentCheckInsCount;
    uint256 private _recentCheckInsNextIndex;

    event CheckedIn(address indexed user, uint256 timestamp, uint256 totalCheckIns, uint256 streak);

    function checkIn() external {
        uint256 previousCheckIn = lastCheckIn[msg.sender];

        if (previousCheckIn != 0 && block.timestamp < previousCheckIn + CHECK_IN_WINDOW) {
            revert AlreadyCheckedInToday();
        }

        uint256 newStreak;
        if (previousCheckIn == 0) {
            newStreak = 1;
        } else if (block.timestamp > previousCheckIn + STREAK_BREAK_WINDOW) {
            newStreak = 1;
        } else {
            newStreak = streak[msg.sender] + 1;
        }

        streak[msg.sender] = newStreak;
        lastCheckIn[msg.sender] = block.timestamp;

        uint256 newTotalCheckIns = totalCheckIns[msg.sender] + 1;
        totalCheckIns[msg.sender] = newTotalCheckIns;

        _recentCheckIns[_recentCheckInsNextIndex] = CheckInEntry({user: msg.sender, timestamp: block.timestamp});
        _recentCheckInsNextIndex = (_recentCheckInsNextIndex + 1) % MAX_RECENT_CHECK_INS;

        if (_recentCheckInsCount < MAX_RECENT_CHECK_INS) {
            _recentCheckInsCount++;
        }

        emit CheckedIn(msg.sender, block.timestamp, newTotalCheckIns, newStreak);
    }

    function canCheckIn(address user) public view returns (bool) {
        uint256 previousCheckIn = lastCheckIn[user];
        return previousCheckIn == 0 || block.timestamp >= previousCheckIn + CHECK_IN_WINDOW;
    }

    function getRecentCheckIns() external view returns (CheckInEntry[] memory entries) {
        uint256 count = _recentCheckInsCount;
        entries = new CheckInEntry[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 index = (_recentCheckInsNextIndex + MAX_RECENT_CHECK_INS - 1 - i) % MAX_RECENT_CHECK_INS;
            entries[i] = _recentCheckIns[index];
        }
    }

    function getUserStats(address user)
        external
        view
        returns (uint256 userTotalCheckIns, uint256 userStreak, uint256 userLastCheckIn, bool canCheckInNow)
    {
        userTotalCheckIns = totalCheckIns[user];
        userStreak = streak[user];
        userLastCheckIn = lastCheckIn[user];
        canCheckInNow = canCheckIn(user);
    }
}
