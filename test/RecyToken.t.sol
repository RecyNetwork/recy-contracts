// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "../src/RecyToken.sol";
import "./helpers/TestHelpers.sol";
import {EndpointV2Mock} from "@layerzerolabs/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";
import {
    EndpointV2Mock as BridgingEndpointV2Mock
} from "@layerzerolabs/test-devtools-evm-hardhat/contracts/mocks/EndpointV2Mock.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import {SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract RecyTokenTest is Test, TestHelpers {
    RecyToken public token;
    EndpointV2Mock public endpoint;
    address public owner = address(0x1);
    address public user = address(0x2);
    uint256 public issuanceChain;

    function setUp() public {
        issuanceChain = block.chainid;
        endpoint = deployTestEndpoint(TEST_EID);
        token = new RecyToken("Test Token", "TEST", 1000000, address(endpoint), owner, issuanceChain);
    }

    function testTokenInitialization() public view {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1000000 * 10 ** 18);
        assertEq(token.owner(), owner);
        assertEq(token.balanceOf(owner), 1000000 * 10 ** 18);
        assertEq(token.totalIssued(), 1000000 * 10 ** 18);
    }

    function testMinting() public {
        mintAsOwner(token, user, 1000 * 10 ** 18, owner);

        assertBalanceChange(token, user, 1000 * 10 ** 18);
        assertTotalSupplyChange(token, 1001000 * 10 ** 18);
        assertEq(token.totalIssued(), 1001000 * 10 ** 18);
    }

    function testMintingOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 1000 * 10 ** 18);
    }

    function testBurning() public {
        burnAsOwner(token, 1000 * 10 ** 18, owner);

        assertBalanceChange(token, owner, 999000 * 10 ** 18);
        assertTotalSupplyChange(token, 999000 * 10 ** 18);
        assertEq(token.totalIssued(), 1000000 * 10 ** 18);
    }

    function testBurnFrom() public {
        // Owner approves user to burn tokens
        vm.prank(owner);
        token.approve(user, 1000 * 10 ** 18);

        // User burns tokens from owner's balance
        vm.prank(user);
        token.burnFrom(owner, 1000 * 10 ** 18);

        assertBalanceChange(token, owner, 999000 * 10 ** 18);
        assertTotalSupplyChange(token, 999000 * 10 ** 18);
        assertEq(token.totalIssued(), 1000000 * 10 ** 18);
    }

    function testTransfer() public {
        vm.prank(owner);
        token.transfer(user, 1000 * 10 ** 18);

        assertBalanceChange(token, owner, 999000 * 10 ** 18);
        assertBalanceChange(token, user, 1000 * 10 ** 18);
    }

    function testAllowanceAndTransferFrom() public {
        // Owner approves user to spend tokens
        vm.prank(owner);
        token.approve(user, 1000 * 10 ** 18);

        assertEq(token.allowance(owner, user), 1000 * 10 ** 18);

        // User transfers tokens on behalf of owner
        vm.prank(user);
        token.transferFrom(owner, user, 500 * 10 ** 18);

        assertBalanceChange(token, owner, 999500 * 10 ** 18);
        assertBalanceChange(token, user, 500 * 10 ** 18);
        assertEq(token.allowance(owner, user), 500 * 10 ** 18);
    }

    // ===== CONSTRUCTOR EDGE CASES =====

    function test_constructorWithZeroSupply() public {
        RecyToken zeroSupplyToken =
            new RecyToken("Zero Supply Token", "ZST", 0, address(endpoint), owner, issuanceChain);

        assertEq(zeroSupplyToken.totalSupply(), 0);
        assertEq(zeroSupplyToken.balanceOf(owner), 0);
        assertEq(zeroSupplyToken.totalIssued(), 0);
    }

    function test_constructorWithMaxSupply() public {
        // Test with max supply that won't overflow
        uint256 maxSupply = type(uint256).max / (10 ** 18);

        RecyToken maxSupplyToken =
            new RecyToken("Max Supply Token", "MST", maxSupply, address(endpoint), owner, issuanceChain);

        assertEq(maxSupplyToken.totalSupply(), maxSupply * 10 ** 18);
        assertEq(maxSupplyToken.totalIssued(), maxSupply * 10 ** 18);
    }

    function test_constructorWithZeroOwner() public {
        vm.expectRevert();
        new RecyToken("Zero Owner Token", "ZOT", 1000000, address(endpoint), address(0), issuanceChain);
    }

    function test_constructorRejectsZeroIssuanceChainId() public {
        vm.expectRevert(RecyToken.InvalidIssuanceChainId.selector);
        new RecyToken("Invalid Issuance Chain", "IIC", 0, address(endpoint), owner, 0);
    }

    function test_constructorRejectsInitialSupplyOnSatellite() public {
        uint256 satelliteChain = issuanceChain + 1;
        vm.chainId(satelliteChain);

        vm.expectRevert(
            abi.encodeWithSelector(RecyToken.IssuanceUnavailableOnThisChain.selector, satelliteChain, issuanceChain)
        );
        new RecyToken("Satellite Token", "SAT", 1, address(endpoint), owner, issuanceChain);
    }

    function test_satelliteOwnerCannotMint() public {
        uint256 satelliteChain = issuanceChain + 1;
        vm.chainId(satelliteChain);
        RecyToken satelliteToken = new RecyToken("Satellite Token", "SAT", 0, address(endpoint), owner, issuanceChain);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(RecyToken.IssuanceUnavailableOnThisChain.selector, satelliteChain, issuanceChain)
        );
        satelliteToken.mint(user, 1);

        assertEq(satelliteToken.totalIssued(), 0);
        assertEq(satelliteToken.totalSupply(), 0);
    }

    function test_constructorWithEmptyName() public {
        RecyToken emptyNameToken = new RecyToken("", "ENT", 1000000, address(endpoint), owner, issuanceChain);
        assertEq(emptyNameToken.name(), "");
        assertEq(emptyNameToken.symbol(), "ENT");
    }

    function test_constructorWithEmptySymbol() public {
        RecyToken emptySymbolToken =
            new RecyToken("Empty Symbol Token", "", 1000000, address(endpoint), owner, issuanceChain);

        assertEq(emptySymbolToken.name(), "Empty Symbol Token");
        assertEq(emptySymbolToken.symbol(), "");
    }

    // ===== MINTING EDGE CASES =====

    function test_mintZeroAmount() public {
        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(user);

        vm.prank(owner);
        token.mint(user, 0);

        assertEq(token.totalSupply(), initialSupply);
        assertEq(token.balanceOf(user), initialBalance);
        assertEq(token.totalIssued(), initialSupply);
    }

    function test_mintMaxAmount() public {
        uint256 maxMintAmount = type(uint256).max - token.totalSupply();

        vm.prank(owner);
        token.mint(user, maxMintAmount);

        assertEq(token.balanceOf(user), maxMintAmount);
        assertEq(token.totalSupply(), type(uint256).max);
        assertEq(token.totalIssued(), type(uint256).max);
    }

    function test_mintToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        token.mint(address(0), 1000);
    }

    function test_mintByNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 1000);
    }

    function test_mintToContractAddress() public {
        address contractAddress = address(this);
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.mint(contractAddress, mintAmount);

        assertEq(token.balanceOf(contractAddress), mintAmount);
    }

    function test_mintMultipleTimes() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.startPrank(owner);
        for (uint256 i = 0; i < 10; i++) {
            token.mint(user, mintAmount);
        }
        vm.stopPrank();

        assertEq(token.balanceOf(user), mintAmount * 10);
    }

    // ===== BURNING EDGE CASES =====

    function test_burnZeroAmount() public {
        uint256 initialBalance = token.balanceOf(owner);
        uint256 initialSupply = token.totalSupply();

        vm.prank(owner);
        token.burn(0);

        assertEq(token.balanceOf(owner), initialBalance);
        assertEq(token.totalSupply(), initialSupply);
    }

    function test_burnMoreThanBalance() public {
        uint256 userBalance = 1000 * 10 ** 18;

        vm.prank(owner);
        token.mint(user, userBalance);

        vm.prank(user);
        vm.expectRevert();
        token.burn(userBalance + 1);
    }

    function test_burnEntireBalance() public {
        uint256 userBalance = 1000 * 10 ** 18;

        vm.prank(owner);
        token.mint(user, userBalance);

        vm.prank(user);
        token.burn(userBalance);

        assertEq(token.balanceOf(user), 0);
    }

    function test_burnFromZeroBalance() public {
        vm.prank(user); // USER has 0 balance
        vm.expectRevert();
        token.burn(1);
    }

    // ===== BURN FROM EDGE CASES =====

    function test_burnFromWithZeroAllowance() public {
        uint256 userBalance = 1000 * 10 ** 18;
        address spender = address(0x3);

        vm.prank(owner);
        token.mint(user, userBalance);

        vm.prank(spender);
        vm.expectRevert();
        token.burnFrom(user, 100);
    }

    function test_burnFromWithInsufficientAllowance() public {
        uint256 userBalance = 1000 * 10 ** 18;
        uint256 allowanceAmount = 500 * 10 ** 18;
        address spender = address(0x3);

        vm.prank(owner);
        token.mint(user, userBalance);

        vm.prank(user);
        token.approve(spender, allowanceAmount);

        vm.prank(spender);
        vm.expectRevert();
        token.burnFrom(user, allowanceAmount + 1);
    }

    function test_burnFromWithExactAllowance() public {
        uint256 userBalance = 1000 * 10 ** 18;
        uint256 allowanceAmount = 500 * 10 ** 18;
        address spender = address(0x3);

        vm.prank(owner);
        token.mint(user, userBalance);

        vm.prank(user);
        token.approve(spender, allowanceAmount);

        vm.prank(spender);
        token.burnFrom(user, allowanceAmount);

        assertEq(token.balanceOf(user), userBalance - allowanceAmount);
        assertEq(token.allowance(user, spender), 0);
    }

    function test_burnFromWithMaxAllowance() public {
        uint256 userBalance = 1000 * 10 ** 18;
        address spender = address(0x3);

        vm.prank(owner);
        token.mint(user, userBalance);

        vm.prank(user);
        token.approve(spender, type(uint256).max);

        vm.prank(spender);
        token.burnFrom(user, userBalance);

        assertEq(token.balanceOf(user), 0);
        // Max allowance should remain max after burn
        assertEq(token.allowance(user, spender), type(uint256).max);
    }

    function test_burnFromZeroAmount() public {
        uint256 userBalance = 1000 * 10 ** 18;
        address spender = address(0x3);

        vm.prank(owner);
        token.mint(user, userBalance);

        vm.prank(user);
        token.approve(spender, 100);

        vm.prank(spender);
        token.burnFrom(user, 0);

        assertEq(token.balanceOf(user), userBalance);
        assertEq(token.allowance(user, spender), 100);
    }

    // ===== TRANSFER EDGE CASES =====

    function test_transferToSelf() public {
        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 initialBalance = token.balanceOf(owner);

        vm.prank(owner);
        token.transfer(owner, transferAmount);

        assertEq(token.balanceOf(owner), initialBalance);
    }

    function test_transferZeroAmount() public {
        uint256 initialOwnerBalance = token.balanceOf(owner);
        uint256 initialUserBalance = token.balanceOf(user);

        vm.prank(owner);
        token.transfer(user, 0);

        assertEq(token.balanceOf(owner), initialOwnerBalance);
        assertEq(token.balanceOf(user), initialUserBalance);
    }

    function test_transferToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        token.transfer(address(0), 1000);
    }

    function test_transferMoreThanBalance() public {
        uint256 ownerBalance = token.balanceOf(owner);

        vm.prank(owner);
        vm.expectRevert();
        token.transfer(user, ownerBalance + 1);
    }

    function test_transferEntireBalance() public {
        uint256 ownerBalance = token.balanceOf(owner);

        vm.prank(owner);
        token.transfer(user, ownerBalance);

        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(user), ownerBalance);
    }

    // ===== TRANSFER FROM EDGE CASES =====

    function test_transferFromToSelf() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.approve(user, transferAmount);

        uint256 initialBalance = token.balanceOf(owner);

        vm.prank(user);
        token.transferFrom(owner, owner, transferAmount);

        assertEq(token.balanceOf(owner), initialBalance);
        assertEq(token.allowance(owner, user), 0);
    }

    function test_transferFromWithZeroAllowance() public {
        vm.prank(user);
        vm.expectRevert();
        token.transferFrom(owner, user, 1000);
    }

    function test_transferFromToZeroAddress() public {
        vm.prank(owner);
        token.approve(user, 1000);

        vm.prank(user);
        vm.expectRevert();
        token.transferFrom(owner, address(0), 1000);
    }

    function test_transferFromZeroAmount() public {
        uint256 allowanceAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.approve(user, allowanceAmount);

        uint256 initialOwnerBalance = token.balanceOf(owner);
        uint256 initialUserBalance = token.balanceOf(user);

        vm.prank(user);
        token.transferFrom(owner, user, 0);

        assertEq(token.balanceOf(owner), initialOwnerBalance);
        assertEq(token.balanceOf(user), initialUserBalance);
        assertEq(token.allowance(owner, user), allowanceAmount);
    }

    // ===== APPROVAL EDGE CASES =====

    function test_approveZeroAmount() public {
        vm.prank(owner);
        token.approve(user, 0);

        assertEq(token.allowance(owner, user), 0);
    }

    function test_approveMaxAmount() public {
        vm.prank(owner);
        token.approve(user, type(uint256).max);

        assertEq(token.allowance(owner, user), type(uint256).max);
    }

    function test_approveSelf() public {
        vm.prank(owner);
        token.approve(owner, 1000);

        assertEq(token.allowance(owner, owner), 1000);
    }

    function test_approveZeroAddress() public {
        vm.prank(owner);
        // OpenZeppelin ERC20 now prevents approving to zero address
        vm.expectRevert();
        token.approve(address(0), 1000);
    }

    function test_multipleApprovals() public {
        vm.prank(owner);
        token.approve(user, 1000);
        assertEq(token.allowance(owner, user), 1000);

        vm.prank(owner);
        token.approve(user, 2000);
        assertEq(token.allowance(owner, user), 2000);

        vm.prank(owner);
        token.approve(user, 0);
        assertEq(token.allowance(owner, user), 0);
    }

    // ===== DECIMAL EDGE CASES =====

    function test_decimalsIs18() public view {
        assertEq(token.decimals(), 18);
    }

    // ===== OWNERSHIP TRANSFER EDGE CASES =====

    function test_transferOwnershipToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        token.transferOwnership(address(0));
    }

    function test_transferOwnershipToSelf() public {
        vm.prank(owner);
        token.transferOwnership(owner);

        assertEq(token.owner(), owner);
    }

    function test_transferOwnershipAndMint() public {
        vm.prank(owner);
        token.transferOwnership(user);

        assertEq(token.owner(), user);

        // Old owner should not be able to mint
        vm.prank(owner);
        vm.expectRevert();
        token.mint(address(0x4), 1000);

        // New owner should be able to mint
        vm.prank(user);
        token.mint(address(0x4), 1000);

        assertEq(token.balanceOf(address(0x4)), 1000);
    }

    function test_renounceOwnership() public {
        vm.prank(owner);
        token.renounceOwnership();

        assertEq(token.owner(), address(0));

        // No one should be able to mint after renouncing ownership
        vm.prank(owner);
        vm.expectRevert();
        token.mint(user, 1000);
    }

    // ===== GAS OPTIMIZATION TESTS =====

    function test_batchTransfers() public {
        address[] memory recipients = new address[](5);
        recipients[0] = user;
        recipients[1] = address(0x5);
        recipients[2] = address(0x6);
        recipients[3] = address(0x7);
        recipients[4] = address(0x8);

        uint256 amount = 1000 * 10 ** 18;

        vm.startPrank(owner);
        for (uint256 i = 0; i < recipients.length; i++) {
            token.transfer(recipients[i], amount);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(token.balanceOf(recipients[i]), amount);
        }
    }

    // ===== INTEGRATION WITH OTHER CONTRACTS =====

    function test_useAsPaymentInContract() public {
        // Create a simple contract that accepts token payments
        SimplePaymentContract paymentContract = new SimplePaymentContract(token);

        uint256 paymentAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.transfer(user, paymentAmount);

        vm.prank(user);
        token.approve(address(paymentContract), paymentAmount);

        vm.prank(user);
        paymentContract.makePayment(paymentAmount);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(paymentContract)), paymentAmount);
    }
}

contract RecyTokenOFTTest is Test {
    using OptionsBuilder for bytes;

    uint32 internal constant SOURCE_EID = 1;
    uint32 internal constant SATELLITE_EID = 2;
    uint256 internal constant ISSUANCE_CHAIN_ID = 31_337;
    uint256 internal constant SATELLITE_CHAIN_ID = 31_338;
    uint256 internal constant INITIAL_SUPPLY = 1_000_000;
    uint256 internal constant INITIAL_SUPPLY_WEI = INITIAL_SUPPLY * 1 ether;
    address internal constant RECIPIENT = address(0xBEEF);

    BridgingEndpointV2Mock internal sourceEndpoint;
    BridgingEndpointV2Mock internal satelliteEndpoint;
    RecyToken internal issuanceToken;
    RecyToken internal satelliteToken;

    function setUp() public {
        sourceEndpoint = new BridgingEndpointV2Mock(SOURCE_EID);
        satelliteEndpoint = new BridgingEndpointV2Mock(SATELLITE_EID);

        vm.chainId(ISSUANCE_CHAIN_ID);
        issuanceToken = new RecyToken(
            "RecyToken", "RECY", INITIAL_SUPPLY, address(sourceEndpoint), address(this), ISSUANCE_CHAIN_ID
        );

        vm.chainId(SATELLITE_CHAIN_ID);
        satelliteToken =
            new RecyToken("RecyToken", "RECY", 0, address(satelliteEndpoint), address(this), ISSUANCE_CHAIN_ID);

        sourceEndpoint.setDestLzEndpoint(address(satelliteToken), address(satelliteEndpoint));
        satelliteEndpoint.setDestLzEndpoint(address(issuanceToken), address(sourceEndpoint));
        issuanceToken.setPeer(SATELLITE_EID, _addressToBytes32(address(satelliteToken)));
        satelliteToken.setPeer(SOURCE_EID, _addressToBytes32(address(issuanceToken)));
        vm.deal(address(this), 1 ether);
    }

    function test_bridgeRoundTripRetainsDustAndDoesNotChangeIssuedCounters() public {
        uint256 requestedAmount = 10 ether + 123;
        uint256 bridgeableAmount = 10 ether;

        OFTReceipt memory receipt = _sendToSatellite(requestedAmount, bridgeableAmount);

        assertEq(receipt.amountSentLD, bridgeableAmount);
        assertEq(receipt.amountReceivedLD, bridgeableAmount);
        assertEq(requestedAmount - receipt.amountSentLD, 123);
        assertEq(issuanceToken.balanceOf(address(this)), INITIAL_SUPPLY_WEI - bridgeableAmount);
        assertEq(satelliteToken.balanceOf(RECIPIENT), bridgeableAmount);
        assertEq(issuanceToken.totalIssued(), INITIAL_SUPPLY_WEI);
        assertEq(satelliteToken.totalIssued(), 0);
        assertEq(issuanceToken.totalSupply() + satelliteToken.totalSupply(), INITIAL_SUPPLY_WEI);

        bytes memory returnOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        SendParam memory returnParam = SendParam({
            dstEid: SOURCE_EID,
            to: _addressToBytes32(address(this)),
            amountLD: bridgeableAmount,
            minAmountLD: bridgeableAmount,
            extraOptions: returnOptions,
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });
        MessagingFee memory returnFee = satelliteToken.quoteSend(returnParam, false);
        vm.deal(RECIPIENT, 1 ether);
        vm.prank(RECIPIENT);
        (, OFTReceipt memory returnReceipt) =
            satelliteToken.send{value: returnFee.nativeFee}(returnParam, returnFee, RECIPIENT);

        assertEq(returnReceipt.amountSentLD, bridgeableAmount);
        assertEq(satelliteToken.balanceOf(RECIPIENT), 0);
        assertEq(issuanceToken.balanceOf(address(this)), INITIAL_SUPPLY_WEI);
        assertEq(issuanceToken.totalSupply(), INITIAL_SUPPLY_WEI);
        assertEq(satelliteToken.totalSupply(), 0);
        assertEq(issuanceToken.totalIssued(), INITIAL_SUPPLY_WEI);
        assertEq(satelliteToken.totalIssued(), 0);
    }

    function test_inboundCreditAuthenticatesConfiguredPeerWithoutIssuingTokens() public {
        uint256 bridgeAmount = 2 ether;
        bytes32 sourcePeer = _addressToBytes32(address(issuanceToken));
        (bytes memory message,) = OFTMsgCodec.encode(
            _addressToBytes32(RECIPIENT), uint64(bridgeAmount / satelliteToken.decimalConversionRate()), bytes("")
        );
        Origin memory origin = Origin({srcEid: SOURCE_EID, sender: sourcePeer, nonce: 1});
        bytes32 guid = keccak256("peer-auth");

        satelliteToken.setPeer(SOURCE_EID, bytes32(uint256(0xBAD)));
        vm.prank(address(satelliteEndpoint));
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.OnlyPeer.selector, SOURCE_EID, sourcePeer));
        satelliteToken.lzReceive(origin, guid, message, address(0), bytes(""));

        assertEq(satelliteToken.balanceOf(RECIPIENT), 0);
        assertEq(satelliteToken.totalIssued(), 0);

        satelliteToken.setPeer(SOURCE_EID, sourcePeer);
        vm.prank(address(satelliteEndpoint));
        satelliteToken.lzReceive(origin, guid, message, address(0), bytes(""));

        assertEq(satelliteToken.balanceOf(RECIPIENT), bridgeAmount);
        assertEq(issuanceToken.totalIssued(), INITIAL_SUPPLY_WEI);
        assertEq(satelliteToken.totalIssued(), 0);
    }

    function _sendToSatellite(uint256 amountLD, uint256 minAmountLD) internal returns (OFTReceipt memory oftReceipt) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: SATELLITE_EID,
            to: _addressToBytes32(RECIPIENT),
            amountLD: amountLD,
            minAmountLD: minAmountLD,
            extraOptions: options,
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });
        MessagingFee memory fee = issuanceToken.quoteSend(sendParam, false);
        (, oftReceipt) = issuanceToken.send{value: fee.nativeFee}(sendParam, fee, address(this));
    }

    function _addressToBytes32(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}

// Helper contract for integration testing
contract SimplePaymentContract {
    RecyToken public token;

    constructor(RecyToken _token) {
        token = _token;
    }

    function makePayment(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
    }
}
