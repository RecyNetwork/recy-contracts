// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RecyReport} from "../src/RecyReport.sol";
import {RecyReportAttributes} from "../src/RecyReportAttributes.sol";
import {RecyReportData} from "../src/RecyReportData.sol";
import {RecyReportSvg} from "../src/RecyReportSvg.sol";
import {RecyToken} from "../src/RecyToken.sol";
import {RecyConstants} from "../src/lib/RecyConstants.sol";
import {RecyErrors} from "../src/lib/RecyErrors.sol";
import {RecyReward} from "../src/lib/RecyReward.sol";
import {TestHelpers} from "./helpers/TestHelpers.sol";

/// @dev Exposes the pinned OFT bridge hooks without replacing their production behavior.
contract RecyTokenBridgeHarness is RecyToken {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address endpoint_,
        address owner_,
        uint256 issuanceChainId_
    ) RecyToken(name_, symbol_, initialSupply_, endpoint_, owner_, issuanceChainId_) {}

    function bridgeDebit(address from, uint256 amountLD, uint256 minAmountLD, uint32 dstEid)
        external
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        return _debit(from, amountLD, minAmountLD, dstEid);
    }

    function bridgeCredit(address to, uint256 amountLD, uint32 srcEid) external returns (uint256 amountReceivedLD) {
        return _credit(to, amountLD, srcEid);
    }
}

contract RecyReportRewardEpochTest is TestHelpers {
    uint256 internal constant ISSUANCE_CHAIN_ID = 31_337;
    uint256 internal constant SATELLITE_CHAIN_ID = 84_532;
    uint32 internal constant SATELLITE_EID = 40_245;

    uint256 internal constant INITIAL_SUPPLY_TOKENS = 12_775_429;
    uint256 internal constant BRIDGE_AMOUNT = 1 ether;
    uint128 internal constant WASTE_AMOUNT = 100_000_000;

    // Independently derived from the fifth-epoch divisor, 10_000_000_000:
    // 100_000_000 mg * 1e18 / 10_000_000_000 = 0.01 token.
    uint128 internal constant EXPECTED_FIFTH_EPOCH_REWARD = 0.01 ether;

    RecyTokenBridgeHarness internal issuanceToken;
    RecyTokenBridgeHarness internal satelliteToken;
    RecyReportData internal reportData;
    RecyReport internal report;

    function setUp() public {
        vm.chainId(ISSUANCE_CHAIN_ID);
        issuanceToken = new RecyTokenBridgeHarness(
            "Issuance RECY",
            "iRECY",
            INITIAL_SUPPLY_TOKENS,
            address(deployTestEndpoint(TEST_EID)),
            address(this),
            ISSUANCE_CHAIN_ID
        );

        vm.chainId(SATELLITE_CHAIN_ID);
        satelliteToken = new RecyTokenBridgeHarness(
            "Satellite RECY", "sRECY", 0, address(deployTestEndpoint(SATELLITE_EID)), address(this), ISSUANCE_CHAIN_ID
        );
        vm.chainId(ISSUANCE_CHAIN_ID);

        RecyReportAttributes attributes = new RecyReportAttributes();
        RecyReportSvg svg = new RecyReportSvg();
        reportData = new RecyReportData(address(attributes), address(svg));

        RecyReport implementation = new RecyReport();
        report = RecyReport(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        RecyReport.initialize,
                        (
                            "Issuance Reports",
                            "REPORT",
                            address(issuanceToken),
                            address(reportData),
                            PROTOCOL,
                            1 hours,
                            25,
                            25,
                            25,
                            25
                        )
                    )
                )
            )
        );

        issuanceToken.transfer(address(report), 10 ether);
        report.grantRole(RecyConstants.RECYCLER_ROLE, RECYCLER);
        report.grantRole(RecyConstants.AUDITOR_ROLE, RECYCLER);
        report.grantRole(RecyConstants.AUDITOR_ROLE, VALIDATOR);
    }

    function test_bridgeMovementBeforeFirstValidationDoesNotChangeFifthEpochReward() public {
        assertEq(issuanceToken.totalSupply(), RecyReward.FOURTH_EPOCH + BRIDGE_AMOUNT);
        assertEq(issuanceToken.totalIssued(), RecyReward.FOURTH_EPOCH + BRIDGE_AMOUNT);
        assertEq(issuanceToken.totalIssued(), RecyReward.FIFTH_EPOCH);

        uint256 bridgedOutReport = _completeReport();

        (uint256 sentOut, uint256 receivedOut) =
            issuanceToken.bridgeDebit(address(this), BRIDGE_AMOUNT, BRIDGE_AMOUNT, SATELLITE_EID);
        assertEq(sentOut, BRIDGE_AMOUNT);
        assertEq(receivedOut, BRIDGE_AMOUNT);
        assertEq(satelliteToken.bridgeCredit(address(this), receivedOut, TEST_EID), BRIDGE_AMOUNT);

        assertEq(issuanceToken.totalSupply(), RecyReward.FOURTH_EPOCH);
        assertEq(satelliteToken.totalSupply(), BRIDGE_AMOUNT);
        assertEq(issuanceToken.totalIssued(), RecyReward.FIFTH_EPOCH, "bridge debit changed cumulative issuance");
        assertEq(satelliteToken.totalIssued(), 0, "bridge credit counted as satellite issuance");

        vm.prank(RECYCLER);
        vm.expectRevert(RecyErrors.ValidatorCannotBeRecycler.selector);
        report.validateRecyReport(bridgedOutReport);

        vm.prank(VALIDATOR);
        report.validateRecyReport(bridgedOutReport);
        _assertReward(bridgedOutReport, EXPECTED_FIFTH_EPOCH_REWARD);

        (uint256 sentBack, uint256 receivedBack) =
            satelliteToken.bridgeDebit(address(this), BRIDGE_AMOUNT, BRIDGE_AMOUNT, TEST_EID);
        assertEq(sentBack, BRIDGE_AMOUNT);
        assertEq(receivedBack, BRIDGE_AMOUNT);
        assertEq(issuanceToken.bridgeCredit(address(this), receivedBack, SATELLITE_EID), BRIDGE_AMOUNT);

        assertEq(issuanceToken.totalSupply(), RecyReward.FIFTH_EPOCH);
        assertEq(satelliteToken.totalSupply(), 0);
        assertEq(issuanceToken.totalIssued(), RecyReward.FIFTH_EPOCH, "bridge return changed cumulative issuance");
        assertEq(satelliteToken.totalIssued(), 0);

        uint256 returnedReport = _completeReport();
        vm.prank(VALIDATOR);
        report.validateRecyReport(returnedReport);
        _assertReward(returnedReport, EXPECTED_FIFTH_EPOCH_REWARD);

        issuanceToken.burn(BRIDGE_AMOUNT);
        assertEq(issuanceToken.totalSupply(), RecyReward.FOURTH_EPOCH);
        assertEq(issuanceToken.totalIssued(), RecyReward.FIFTH_EPOCH, "burn changed cumulative issuance");

        uint256 burnedReport = _completeReport();
        vm.prank(VALIDATOR);
        report.validateRecyReport(burnedReport);
        _assertReward(burnedReport, EXPECTED_FIFTH_EPOCH_REWARD);

        assertEq(report.rewardTotal(), uint256(EXPECTED_FIFTH_EPOCH_REWARD) * 3);
        assertLe(report.rewardTotal() - report.rewardClaimed(), issuanceToken.balanceOf(address(report)));
    }

    function test_reportInitializationRevertsOnSatelliteChain() public {
        vm.chainId(SATELLITE_CHAIN_ID);
        RecyReport implementation = new RecyReport();
        bytes memory initData = abi.encodeCall(
            RecyReport.initialize,
            (
                "Satellite Reports",
                "SAT",
                address(satelliteToken),
                address(reportData),
                PROTOCOL,
                1 hours,
                25,
                25,
                25,
                25
            )
        );

        vm.expectRevert(RecyErrors.RewardsUnavailableOnThisChain.selector);
        new ERC1967Proxy(address(implementation), initData);
    }

    function _completeReport() internal returns (uint256 tokenId) {
        tokenId = report.nftNextId();
        vm.prank(USER);
        report.mintRecyReport();

        uint32[] memory materialIds = new uint32[](1);
        uint128[] memory materialAmounts = new uint128[](1);
        uint32[] memory recycleTypes = new uint32[](1);
        uint32[] memory recycleShapes = new uint32[](1);
        materialAmounts[0] = WASTE_AMOUNT;

        vm.prank(RECYCLER);
        report.setRecyReportResult(
            tokenId, uint64(block.timestamp), WASTE_AMOUNT, materialIds, materialAmounts, recycleTypes, recycleShapes, 0
        );
    }

    function _assertReward(uint256 tokenId, uint128 expectedReward) internal view {
        (uint128 rewardAmount,) = report.reward(tokenId);
        assertEq(rewardAmount, expectedReward);
    }
}
