// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "../src/RecyDistribution.sol";
import "../src/RecyToken.sol";
import "../src/RecyReport.sol";
import "./helpers/TestHelpers.sol";

contract MockRecyToken {
    mapping(address => uint256) public balanceOf;
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Only owner can mint");
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Only owner");
        owner = newOwner;
    }
}

contract MockRecyReport {
    uint256 public rewardTotal;
    uint256 public rewardClaimed;

    function setRewardTotal(uint256 _total) external {
        rewardTotal = _total;
    }

    function setRewardClaimed(uint256 _claimed) external {
        rewardClaimed = _claimed;
    }
}

contract RecyDistributionTest is Test, TestHelpers {
    RecyDistribution public distribution;
    MockRecyToken public token;
    MockRecyReport public mockReport1;
    MockRecyReport public mockReport2;
    MockRecyReport public mockReport3;

    address public owner = address(0x1);
    address public user = address(0x2);
    address public nonOwner = address(0x3);

    // Test amounts in wei (18 decimals)
    uint256 constant TOTAL_SUPPLY = 1000000 * 10 ** 18; // 1M tokens
    uint256 constant REWARD_AMOUNT = 1000 * 10 ** 18; // 1K tokens
    uint256 constant CLAIMED_AMOUNT = 500 * 10 ** 18; // 500 tokens

    event TokensMinted(address indexed reportContract, uint256 amount);
    event ReportContractAdded(address indexed reportContract);
    event ReportContractBlacklisted(address indexed reportContract);
    event ReportContractWhitelisted(address indexed reportContract);

    function setUp() public {
        // Deploy mock token with owner
        token = new MockRecyToken(owner);

        // Deploy distribution contract
        vm.prank(owner);
        distribution = new RecyDistribution(address(token));

        // Deploy mock report contracts
        mockReport1 = new MockRecyReport();
        mockReport2 = new MockRecyReport();
        mockReport3 = new MockRecyReport();

        // Transfer token ownership to distribution contract so it can mint
        vm.prank(owner);
        token.transferOwnership(address(distribution));

        // Give owner some initial tokens for transfer tests
        vm.prank(address(distribution));
        token.mint(owner, 10000 * 10 ** 18);
    }

    // ========== CONSTRUCTOR TESTS ==========

    function test_constructor() public view {
        assertEq(address(distribution.token()), address(token));
        assertEq(distribution.owner(), owner);
        assertEq(distribution.getReportContractCount(), 0);
    }

    function test_constructorWithZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Zero address not allowed");
        new RecyDistribution(address(0));
    }

    // ========== WHITELIST REPORT CONTRACT TESTS ==========

    function test_whitelistReportContract() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit ReportContractWhitelisted(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport1));

        assertEq(distribution.getReportContractCount(), 1);
        assertEq(distribution.reportContracts(0), address(mockReport1));
        assertFalse(distribution.blacklistedReports(address(mockReport1)));
    }

    function test_whitelistReportContractMultiple() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        vm.stopPrank();

        assertEq(distribution.getReportContractCount(), 2);
        assertEq(distribution.reportContracts(0), address(mockReport1));
        assertEq(distribution.reportContracts(1), address(mockReport2));
    }

    function test_whitelistReportContractAlreadyExists() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport1)); // Should not revert, just unblacklist
        vm.stopPrank();

        assertEq(distribution.getReportContractCount(), 1); // Still only 1
    }

    function test_whitelistReportContractAfterBlacklist() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));

        vm.expectEmit(true, false, false, false);
        emit ReportContractWhitelisted(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport1));
        vm.stopPrank();

        assertFalse(distribution.blacklistedReports(address(mockReport1)));
    }

    function test_whitelistReportContractOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.whitelistReportContract(address(mockReport1));
    }

    function test_whitelistReportContractZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Zero address not allowed");
        distribution.whitelistReportContract(address(0));
    }

    // ========== BLACKLIST REPORT CONTRACT TESTS ==========

    function test_blacklistReportContract() public {
        // First whitelist
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        vm.expectEmit(true, false, false, false);
        emit ReportContractBlacklisted(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));
        vm.stopPrank();

        assertTrue(distribution.blacklistedReports(address(mockReport1)));
        assertEq(distribution.getReportContractCount(), 1); // Still in array
    }

    function test_blacklistReportContractNotFound() public {
        vm.prank(owner);
        vm.expectRevert("Report contract not found");
        distribution.blacklistReportContract(address(mockReport1));
    }

    function test_blacklistReportContractAlreadyBlacklisted() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));

        vm.expectRevert("Report contract already blacklisted");
        distribution.blacklistReportContract(address(mockReport1));
        vm.stopPrank();
    }

    function test_blacklistReportContractOnlyOwner() public {
        vm.prank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.blacklistReportContract(address(mockReport1));
    }

    function test_blacklistReportContractZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Zero address not allowed");
        distribution.blacklistReportContract(address(0));
    }

    // ========== CALCULATE TOKENS TO MINT TESTS ==========

    function test_calculateTokensToMint() public {
        // Setup mock report
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(CLAIMED_AMOUNT);

        vm.prank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        uint256 expected = REWARD_AMOUNT - CLAIMED_AMOUNT; // Should have = 500 tokens
        uint256 actual = distribution.calculateTokensToMint(address(mockReport1));
        assertEq(actual, expected);
    }

    function test_calculateTokensToMintWithBalance() public {
        // Setup mock report
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(CLAIMED_AMOUNT);

        vm.prank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        // Give some tokens to the report contract
        uint256 existingBalance = 200 * 10 ** 18;
        vm.prank(owner);
        token.transfer(address(mockReport1), existingBalance);

        uint256 shouldHave = REWARD_AMOUNT - CLAIMED_AMOUNT; // 500 tokens
        uint256 expected = shouldHave - existingBalance; // 500 - 200 = 300 tokens
        uint256 actual = distribution.calculateTokensToMint(address(mockReport1));
        assertEq(actual, expected);
    }

    function test_calculateTokensToMintNoNeed() public {
        // Setup mock report where contract has enough tokens
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(CLAIMED_AMOUNT);

        vm.prank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        // Give more tokens than needed
        uint256 excessBalance = 600 * 10 ** 18;
        vm.prank(owner);
        token.transfer(address(mockReport1), excessBalance);

        uint256 actual = distribution.calculateTokensToMint(address(mockReport1));
        assertEq(actual, 0);
    }

    function test_calculateTokensToMintNotFound() public {
        vm.expectRevert("Report contract not found");
        distribution.calculateTokensToMint(address(mockReport1));
    }

    function test_calculateTokensToMintBlacklisted() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));
        vm.stopPrank();

        vm.expectRevert("Report contract is blacklisted");
        distribution.calculateTokensToMint(address(mockReport1));
    }

    // ========== MINT TOKENS TO REPORT TESTS ==========

    function test_mintTokensToReport() public {
        // Setup mock report
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(CLAIMED_AMOUNT);

        vm.prank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        uint256 expectedMint = REWARD_AMOUNT - CLAIMED_AMOUNT;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport1), expectedMint);
        distribution.mintTokensToReport(address(mockReport1));

        assertEq(token.balanceOf(address(mockReport1)), expectedMint);
        assertEq(distribution.totalMintedToReport(address(mockReport1)), expectedMint);
    }

    function test_mintTokensToReportNoNeed() public {
        // Setup mock report where no tokens are needed
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(REWARD_AMOUNT); // All claimed

        vm.prank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        vm.prank(owner);
        vm.expectRevert("No tokens need to be minted");
        distribution.mintTokensToReport(address(mockReport1));
    }

    function test_mintTokensToReportBlacklisted() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));

        vm.expectRevert("Report contract is blacklisted");
        distribution.mintTokensToReport(address(mockReport1));
        vm.stopPrank();
    }

    function test_mintTokensToReportOnlyOwner() public {
        mockReport1.setRewardTotal(REWARD_AMOUNT);
        mockReport1.setRewardClaimed(CLAIMED_AMOUNT);

        vm.prank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.mintTokensToReport(address(mockReport1));
    }

    // ========== MINT TOKENS TO ALL REPORTS TESTS ==========

    function test_mintTokensToAllReports() public {
        // Setup multiple mock reports
        mockReport1.setRewardTotal(1000 * 10 ** 18);
        mockReport1.setRewardClaimed(500 * 10 ** 18);

        mockReport2.setRewardTotal(2000 * 10 ** 18);
        mockReport2.setRewardClaimed(1000 * 10 ** 18);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));

        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport1), 500 * 10 ** 18);
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(address(mockReport2), 1000 * 10 ** 18);

        distribution.mintTokensToAllReports();
        vm.stopPrank();

        assertEq(token.balanceOf(address(mockReport1)), 500 * 10 ** 18);
        assertEq(token.balanceOf(address(mockReport2)), 1000 * 10 ** 18);
        assertEq(distribution.totalMintedToReport(address(mockReport1)), 500 * 10 ** 18);
        assertEq(distribution.totalMintedToReport(address(mockReport2)), 1000 * 10 ** 18);
    }

    function test_mintTokensToAllReportsSkipsBlacklisted() public {
        // Setup multiple mock reports
        mockReport1.setRewardTotal(1000 * 10 ** 18);
        mockReport1.setRewardClaimed(500 * 10 ** 18);

        mockReport2.setRewardTotal(2000 * 10 ** 18);
        mockReport2.setRewardClaimed(1000 * 10 ** 18);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        distribution.blacklistReportContract(address(mockReport2)); // Blacklist second one

        distribution.mintTokensToAllReports();
        vm.stopPrank();

        assertEq(token.balanceOf(address(mockReport1)), 500 * 10 ** 18); // Got tokens
        assertEq(token.balanceOf(address(mockReport2)), 0); // Skipped
    }

    function test_mintTokensToAllReportsNoNeed() public {
        // Setup reports that don't need tokens
        mockReport1.setRewardTotal(1000 * 10 ** 18);
        mockReport1.setRewardClaimed(1000 * 10 ** 18); // All claimed

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        vm.expectRevert("No tokens needed to be minted");
        distribution.mintTokensToAllReports();
        vm.stopPrank();
    }

    function test_mintTokensToAllReportsOnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        distribution.mintTokensToAllReports();
    }

    // ========== GETTER FUNCTION TESTS ==========

    function test_getAllReportContracts() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        distribution.blacklistReportContract(address(mockReport2));
        vm.stopPrank();

        address[] memory allContracts = distribution.getAllReportContracts();
        assertEq(allContracts.length, 2);
        assertEq(allContracts[0], address(mockReport1));
        assertEq(allContracts[1], address(mockReport2));
    }

    function test_getActiveReportContracts() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        distribution.whitelistReportContract(address(mockReport3));
        distribution.blacklistReportContract(address(mockReport2)); // Blacklist middle one
        vm.stopPrank();

        address[] memory activeContracts = distribution.getActiveReportContracts();
        assertEq(activeContracts.length, 2);
        assertEq(activeContracts[0], address(mockReport1));
        assertEq(activeContracts[1], address(mockReport3));
    }

    function test_getActiveReportContractsEmpty() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));
        vm.stopPrank();

        address[] memory activeContracts = distribution.getActiveReportContracts();
        assertEq(activeContracts.length, 0);
    }

    function test_getReportContractCount() public {
        assertEq(distribution.getReportContractCount(), 0);

        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        assertEq(distribution.getReportContractCount(), 1);

        distribution.whitelistReportContract(address(mockReport2));
        assertEq(distribution.getReportContractCount(), 2);

        distribution.blacklistReportContract(address(mockReport1));
        assertEq(distribution.getReportContractCount(), 2); // Still 2, blacklisting doesn't remove
        vm.stopPrank();
    }

    function test_getActiveReportContractCount() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.whitelistReportContract(address(mockReport2));
        assertEq(distribution.getActiveReportContractCount(), 2);

        distribution.blacklistReportContract(address(mockReport1));
        assertEq(distribution.getActiveReportContractCount(), 1);

        distribution.whitelistReportContract(address(mockReport1)); // Unblacklist
        assertEq(distribution.getActiveReportContractCount(), 2);
        vm.stopPrank();
    }

    // ========== EDGE CASE TESTS ==========

    function test_multipleMintingRounds() public {
        // Setup mock report
        mockReport1.setRewardTotal(1000 * 10 ** 18);
        mockReport1.setRewardClaimed(500 * 10 ** 18);

        vm.prank(owner);
        distribution.whitelistReportContract(address(mockReport1));

        // First mint
        vm.prank(owner);
        distribution.mintTokensToReport(address(mockReport1));
        assertEq(distribution.totalMintedToReport(address(mockReport1)), 500 * 10 ** 18);

        // Increase rewards and mint again
        mockReport1.setRewardTotal(1500 * 10 ** 18);

        vm.prank(owner);
        distribution.mintTokensToReport(address(mockReport1));
        assertEq(distribution.totalMintedToReport(address(mockReport1)), 1000 * 10 ** 18); // 500 + 500
    }

    function test_whitelistAfterRemoval() public {
        vm.startPrank(owner);
        distribution.whitelistReportContract(address(mockReport1));
        distribution.blacklistReportContract(address(mockReport1));

        // Whitelisting should unblacklist
        distribution.whitelistReportContract(address(mockReport1));
        assertFalse(distribution.blacklistedReports(address(mockReport1)));
        assertEq(distribution.getReportContractCount(), 1); // Still only 1 in array
        vm.stopPrank();
    }
}
