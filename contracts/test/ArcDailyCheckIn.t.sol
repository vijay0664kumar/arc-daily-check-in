// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ArcDailyCheckIn} from "../ArcDailyCheckIn.sol";

contract ArcDailyCheckInTest is Test {
    ArcDailyCheckIn internal checkIn;

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");

    uint256 internal constant CHECK_IN_WINDOW    = 24 hours;
    uint256 internal constant STREAK_BREAK_WINDOW = 48 hours;
    uint256 internal constant MAX_RECENT         = 100;

    // Warp to a stable, non-zero starting point so "now > 0" assumptions hold.
    uint256 internal constant T0 = 1_700_000_000;

    function setUp() public {
        vm.warp(T0);
        checkIn = new ArcDailyCheckIn();
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /// Advance time and perform a check-in from `user`.
    function _warpAndCheckIn(address user, uint256 deltaSeconds) internal {
        vm.warp(block.timestamp + deltaSeconds);
        vm.prank(user);
        checkIn.checkIn();
    }

    // -----------------------------------------------------------------------
    // 1. Deployment & constants
    // -----------------------------------------------------------------------

    function test_Constants() public view {
        assertEq(checkIn.CHECK_IN_WINDOW(),    24 hours);
        assertEq(checkIn.STREAK_BREAK_WINDOW(), 48 hours);
        assertEq(checkIn.MAX_RECENT_CHECK_INS(), 100);
    }

    function test_InitialState_Alice() public view {
        assertEq(checkIn.totalCheckIns(alice), 0);
        assertEq(checkIn.streak(alice),        0);
        assertEq(checkIn.lastCheckIn(alice),   0);
        assertTrue(checkIn.canCheckIn(alice));
    }

    // -----------------------------------------------------------------------
    // 2. Happy path – first check-in
    // -----------------------------------------------------------------------

    function test_FirstCheckIn_TotalIncrementsToOne() public {
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.totalCheckIns(alice), 1);
    }

    function test_FirstCheckIn_StreakIsOne() public {
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.streak(alice), 1);
    }

    function test_FirstCheckIn_LastCheckInRecorded() public {
        uint256 before = block.timestamp;
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.lastCheckIn(alice), before);
    }

    function test_FirstCheckIn_EmitsCheckedIn() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(checkIn));
        emit ArcDailyCheckIn.CheckedIn(alice, block.timestamp, 1, 1);
        checkIn.checkIn();
    }

    // -----------------------------------------------------------------------
    // 3. Revert on second check-in within 24 h
    // -----------------------------------------------------------------------

    function test_SecondCheckIn_SameBlock_Reverts() public {
        vm.prank(alice);
        checkIn.checkIn();

        vm.prank(alice);
        vm.expectRevert(ArcDailyCheckIn.AlreadyCheckedInToday.selector);
        checkIn.checkIn();
    }

    function test_SecondCheckIn_23HoursLater_Reverts() public {
        vm.prank(alice);
        checkIn.checkIn();

        vm.warp(block.timestamp + 23 hours);
        vm.prank(alice);
        vm.expectRevert(ArcDailyCheckIn.AlreadyCheckedInToday.selector);
        checkIn.checkIn();
    }

    function test_SecondCheckIn_JustBefore24h_Reverts() public {
        vm.prank(alice);
        checkIn.checkIn();

        // One second before the 24 h window expires – still locked.
        vm.warp(block.timestamp + CHECK_IN_WINDOW - 1);
        vm.prank(alice);
        vm.expectRevert(ArcDailyCheckIn.AlreadyCheckedInToday.selector);
        checkIn.checkIn();
    }

    // -----------------------------------------------------------------------
    // 4. Second check-in exactly at / after 24 h – succeeds, streak continues
    // -----------------------------------------------------------------------

    function test_CheckIn_ExactlyAt24h_Succeeds() public {
        uint256 t1 = block.timestamp;
        vm.prank(alice);
        checkIn.checkIn();

        vm.warp(t1 + CHECK_IN_WINDOW);
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.totalCheckIns(alice), 2);
        assertEq(checkIn.streak(alice),        2);
    }

    function test_CheckIn_ExactlyAt24h_EmitsCorrectEvent() public {
        uint256 t1 = block.timestamp;
        vm.prank(alice);
        checkIn.checkIn();

        uint256 t2 = t1 + CHECK_IN_WINDOW;
        vm.warp(t2);
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(checkIn));
        emit ArcDailyCheckIn.CheckedIn(alice, t2, 2, 2);
        checkIn.checkIn();
    }

    // -----------------------------------------------------------------------
    // 5. Streak continues when second check-in is within the 48 h window
    // -----------------------------------------------------------------------

    function test_Streak_Continues_Within48h() public {
        vm.prank(alice);
        checkIn.checkIn();

        // 47 h later – still within the streak window (> 24 h, <= 48 h).
        vm.warp(block.timestamp + 47 hours);
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.streak(alice), 2);
    }

    function test_Streak_Continues_ExactlyAt48h() public {
        // The streak break condition is STRICTLY greater-than 48 h,
        // so checking in at exactly 48 h should still increment streak.
        vm.prank(alice);
        checkIn.checkIn();

        vm.warp(block.timestamp + STREAK_BREAK_WINDOW);
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.streak(alice), 2);
    }

    function test_Streak_MultiDay_Increments() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            checkIn.checkIn();
            if (i < 4) vm.warp(block.timestamp + 25 hours);
        }

        assertEq(checkIn.streak(alice),        5);
        assertEq(checkIn.totalCheckIns(alice), 5);
    }

    // -----------------------------------------------------------------------
    // 6. Streak resets after the 48 h window passes
    // -----------------------------------------------------------------------

    function test_Streak_Resets_After48h() public {
        // Build a streak of 3 first.
        vm.prank(alice);
        checkIn.checkIn();
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        checkIn.checkIn();
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.streak(alice), 3);

        // Now wait more than 48 h – streak should reset to 1.
        vm.warp(block.timestamp + STREAK_BREAK_WINDOW + 1);
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.streak(alice), 1);
        assertEq(checkIn.totalCheckIns(alice), 4); // total still increments
    }

    function test_Streak_Resets_ExactlyOneSecondAfter48h() public {
        vm.prank(alice);
        checkIn.checkIn();

        vm.warp(block.timestamp + STREAK_BREAK_WINDOW + 1);
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.streak(alice), 1);
    }

    // -----------------------------------------------------------------------
    // 7. canCheckIn view
    // -----------------------------------------------------------------------

    function test_CanCheckIn_TrueBeforeFirstCheckIn() public view {
        assertTrue(checkIn.canCheckIn(alice));
    }

    function test_CanCheckIn_FalseImmediatelyAfterCheckIn() public {
        vm.prank(alice);
        checkIn.checkIn();

        assertFalse(checkIn.canCheckIn(alice));
    }

    function test_CanCheckIn_FalseJustBefore24h() public {
        vm.prank(alice);
        checkIn.checkIn();

        vm.warp(block.timestamp + CHECK_IN_WINDOW - 1);
        assertFalse(checkIn.canCheckIn(alice));
    }

    function test_CanCheckIn_TrueExactlyAt24h() public {
        uint256 t = block.timestamp;
        vm.prank(alice);
        checkIn.checkIn();

        vm.warp(t + CHECK_IN_WINDOW);
        assertTrue(checkIn.canCheckIn(alice));
    }

    function test_CanCheckIn_TrueAfter24h() public {
        vm.prank(alice);
        checkIn.checkIn();

        vm.warp(block.timestamp + CHECK_IN_WINDOW + 1);
        assertTrue(checkIn.canCheckIn(alice));
    }

    function test_CanCheckIn_IndependentPerUser() public {
        vm.prank(alice);
        checkIn.checkIn();

        // Bob has never checked in – canCheckIn should still be true for him.
        assertTrue(checkIn.canCheckIn(bob));
        assertFalse(checkIn.canCheckIn(alice));
    }

    // -----------------------------------------------------------------------
    // 8. getUserStats
    // -----------------------------------------------------------------------

    function test_GetUserStats_InitialValues() public view {
        (uint256 total, uint256 str, uint256 last, bool can) = checkIn.getUserStats(alice);
        assertEq(total, 0);
        assertEq(str,   0);
        assertEq(last,  0);
        assertTrue(can);
    }

    function test_GetUserStats_AfterFirstCheckIn() public {
        uint256 t = block.timestamp;
        vm.prank(alice);
        checkIn.checkIn();

        (uint256 total, uint256 str, uint256 last, bool can) = checkIn.getUserStats(alice);
        assertEq(total, 1);
        assertEq(str,   1);
        assertEq(last,  t);
        assertFalse(can);
    }

    function test_GetUserStats_AfterStreakAndReset() public {
        // Day 1
        vm.prank(alice);
        checkIn.checkIn();
        // Day 2
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        checkIn.checkIn();
        // Break streak
        vm.warp(block.timestamp + STREAK_BREAK_WINDOW + 1);
        uint256 t3 = block.timestamp;
        vm.prank(alice);
        checkIn.checkIn();

        (uint256 total, uint256 str, uint256 last, bool can) = checkIn.getUserStats(alice);
        assertEq(total, 3);
        assertEq(str,   1);   // reset
        assertEq(last,  t3);
        assertFalse(can);     // just checked in
    }

    function test_GetUserStats_CanCheckInFlipsAfter24h() public {
        vm.prank(alice);
        checkIn.checkIn();

        (, , , bool can1) = checkIn.getUserStats(alice);
        assertFalse(can1);

        vm.warp(block.timestamp + CHECK_IN_WINDOW);
        (, , , bool can2) = checkIn.getUserStats(alice);
        assertTrue(can2);
    }

    // -----------------------------------------------------------------------
    // 9. getRecentCheckIns ring buffer
    // -----------------------------------------------------------------------

    function test_RecentCheckIns_EmptyInitially() public view {
        ArcDailyCheckIn.CheckInEntry[] memory entries = checkIn.getRecentCheckIns();
        assertEq(entries.length, 0);
    }

    function test_RecentCheckIns_SingleEntry_CorrectData() public {
        uint256 t = block.timestamp;
        vm.prank(alice);
        checkIn.checkIn();

        ArcDailyCheckIn.CheckInEntry[] memory entries = checkIn.getRecentCheckIns();
        assertEq(entries.length,      1);
        assertEq(entries[0].user,      alice);
        assertEq(entries[0].timestamp, t);
    }

    function test_RecentCheckIns_OrderedMostRecentFirst() public {
        vm.prank(alice);
        checkIn.checkIn();
        uint256 t1 = block.timestamp;

        vm.warp(block.timestamp + 25 hours);
        vm.prank(bob);
        checkIn.checkIn();
        uint256 t2 = block.timestamp;

        ArcDailyCheckIn.CheckInEntry[] memory entries = checkIn.getRecentCheckIns();
        assertEq(entries.length,       2);
        // Index 0 = most recent (bob).
        assertEq(entries[0].user,      bob);
        assertEq(entries[0].timestamp, t2);
        // Index 1 = previous (alice).
        assertEq(entries[1].user,      alice);
        assertEq(entries[1].timestamp, t1);
    }

    function test_RecentCheckIns_FillsTo100() public {
        // Each distinct address checks in once.
        for (uint256 i = 0; i < MAX_RECENT; i++) {
            address user = address(uint160(i + 1000));
            vm.prank(user);
            checkIn.checkIn();
        }

        ArcDailyCheckIn.CheckInEntry[] memory entries = checkIn.getRecentCheckIns();
        assertEq(entries.length, MAX_RECENT);
    }

    function test_RecentCheckIns_Wraps_At101() public {
        // Fill the ring buffer completely.
        for (uint256 i = 0; i < MAX_RECENT; i++) {
            address user = address(uint160(i + 1000));
            vm.prank(user);
            checkIn.checkIn();
        }

        // One more check-in – this is the 101st, wrapping the ring buffer.
        vm.warp(block.timestamp + 25 hours); // alice is fresh
        vm.prank(alice);
        checkIn.checkIn();
        uint256 aliceTs = block.timestamp;

        // Count is capped at MAX_RECENT.
        ArcDailyCheckIn.CheckInEntry[] memory entries = checkIn.getRecentCheckIns();
        assertEq(entries.length, MAX_RECENT);

        // Most recent entry (index 0) must be alice's 101st check-in.
        assertEq(entries[0].user,      alice);
        assertEq(entries[0].timestamp, aliceTs);
    }

    function test_RecentCheckIns_WrapPreservesOldEntries() public {
        // Fill 100 entries with known users.
        for (uint256 i = 0; i < MAX_RECENT; i++) {
            address user = address(uint160(i + 1000));
            vm.prank(user);
            checkIn.checkIn();
        }

        // The 100th entry was address(uint160(1099)), check it is at tail.
        ArcDailyCheckIn.CheckInEntry[] memory before = checkIn.getRecentCheckIns();
        assertEq(before[MAX_RECENT - 1].user, address(uint160(1000))); // oldest

        // Now push one more (alice, wraps index 0).
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        checkIn.checkIn();

        ArcDailyCheckIn.CheckInEntry[] memory afterWrap = checkIn.getRecentCheckIns();
        // Oldest slot (index MAX_RECENT-1) should now be address(1001), not address(1000).
        assertEq(afterWrap[MAX_RECENT - 1].user, address(uint160(1001)));
    }

    // -----------------------------------------------------------------------
    // 10. Multi-user isolation
    // -----------------------------------------------------------------------

    function test_MultiUser_StatsAreIndependent() public {
        vm.prank(alice);
        checkIn.checkIn();

        vm.warp(block.timestamp + 25 hours);
        vm.prank(bob);
        checkIn.checkIn();

        assertEq(checkIn.totalCheckIns(alice), 1);
        assertEq(checkIn.totalCheckIns(bob),   1);
        assertEq(checkIn.streak(alice),        1);
        assertEq(checkIn.streak(bob),          1);
        // Bob just checked in; alice is now past 24 h.
        assertFalse(checkIn.canCheckIn(bob));
        assertTrue(checkIn.canCheckIn(alice));
    }

    // -----------------------------------------------------------------------
    // 11. Fuzz – totalCheckIns never decreases
    // -----------------------------------------------------------------------

    /// @dev Fuzz the number of sequential check-ins (1–20) and verify
    ///      totalCheckIns increases monotonically and equals the loop counter.
    function testFuzz_TotalCheckIns_Monotonic(uint8 n) public {
        n = uint8(bound(uint256(n), 1, 20));
        for (uint256 i = 0; i < n; i++) {
            vm.prank(alice);
            checkIn.checkIn();
            assertEq(checkIn.totalCheckIns(alice), i + 1);
            vm.warp(block.timestamp + 25 hours);
        }
    }

    // -----------------------------------------------------------------------
    // 12. Fuzz – streak arithmetic with variable gaps
    // -----------------------------------------------------------------------

    /// @dev `gapHours` in [24, 48]: streak should always increment.
    function testFuzz_Streak_Increments_WhenGapWithinWindow(uint256 gapHours) public {
        // gap in [24 h, 48 h] – both boundaries allowed by the contract.
        gapHours = bound(gapHours, 24, 48);
        uint256 gapSeconds = gapHours * 1 hours;

        vm.prank(alice);
        checkIn.checkIn();

        vm.warp(block.timestamp + gapSeconds);
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.streak(alice), 2);
    }

    /// @dev `gapSeconds` strictly > 48 h: streak must reset to 1.
    function testFuzz_Streak_Resets_WhenGapExceeds48h(uint256 extraSeconds) public {
        // extra seconds beyond 48 h – range [1, 30 days].
        extraSeconds = bound(extraSeconds, 1, 30 days);

        vm.prank(alice);
        checkIn.checkIn();
        // Build streak to 3 first.
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        checkIn.checkIn();
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        checkIn.checkIn();
        assertEq(checkIn.streak(alice), 3);

        // Now wait past the break window.
        vm.warp(block.timestamp + STREAK_BREAK_WINDOW + extraSeconds);
        vm.prank(alice);
        checkIn.checkIn();

        assertEq(checkIn.streak(alice), 1);
    }

    // -----------------------------------------------------------------------
    // 13. Fuzz – canCheckIn correctness vs. lastCheckIn
    // -----------------------------------------------------------------------

    /// @dev After any number of elapsed seconds, canCheckIn must match
    ///      whether block.timestamp >= lastCheckIn + 24 h.
    function testFuzz_CanCheckIn_MatchesExpected(uint256 elapsedSeconds) public {
        // elapsed up to 72 hours
        elapsedSeconds = bound(elapsedSeconds, 0, 72 hours);

        uint256 t = block.timestamp;
        vm.prank(alice);
        checkIn.checkIn();

        vm.warp(t + elapsedSeconds);

        bool expected = block.timestamp >= checkIn.lastCheckIn(alice) + CHECK_IN_WINDOW;
        assertEq(checkIn.canCheckIn(alice), expected);
    }

    // -----------------------------------------------------------------------
    // 14. Fuzz – ring buffer count never exceeds MAX_RECENT
    // -----------------------------------------------------------------------

    /// @dev Perform n check-ins (up to 150) across distinct addresses;
    ///      getRecentCheckIns().length must never exceed MAX_RECENT_CHECK_INS.
    function testFuzz_RecentCheckIns_LengthCapped(uint256 n) public {
        n = bound(n, 1, 150);
        for (uint256 i = 0; i < n; i++) {
            address user = address(uint160(i + 5000));
            vm.prank(user);
            checkIn.checkIn();
        }

        ArcDailyCheckIn.CheckInEntry[] memory entries = checkIn.getRecentCheckIns();
        assertLe(entries.length, MAX_RECENT);
        assertEq(entries.length, n < MAX_RECENT ? n : MAX_RECENT);
    }
}
