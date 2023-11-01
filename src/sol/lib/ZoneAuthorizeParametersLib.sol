// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    ItemType,
    Side,
    OrderType
} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    CriteriaResolver,
    OfferItem,
    Order,
    OrderComponents,
    OrderParameters,
    ZoneAuthorizeParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import { SeaportInterface } from "../SeaportInterface.sol";

import { GettersAndDerivers } from "seaport-core/src/lib/GettersAndDerivers.sol";

import { UnavailableReason } from "../SpaceEnums.sol";

import { AdvancedOrderLib } from "./AdvancedOrderLib.sol";

import { ConsiderationItemLib } from "./ConsiderationItemLib.sol";

import { OfferItemLib } from "./OfferItemLib.sol";

import { ReceivedItemLib } from "./ReceivedItemLib.sol";

import { OrderParametersLib } from "./OrderParametersLib.sol";

import { StructCopier } from "./StructCopier.sol";

import { AmountDeriverHelper } from "./fulfillment/AmountDeriverHelper.sol";

import { OrderDetails } from "../fulfillments/lib/Structs.sol";

import "forge-std/console.sol";

interface FailingContractOfferer {
    function failureReasonsForGenerateOrder(bytes32)
        external
        view
        returns (uint256);
    function failureReasonsForRatifyOrder(bytes32)
        external
        view
        returns (uint256);
}

library ZoneAuthorizeParametersLib {
    using AdvancedOrderLib for AdvancedOrder;
    using AdvancedOrderLib for AdvancedOrder[];
    using OfferItemLib for OfferItem;
    using OfferItemLib for OfferItem[];
    using ConsiderationItemLib for ConsiderationItem;
    using ConsiderationItemLib for ConsiderationItem[];
    using OrderParametersLib for OrderParameters;

    struct ZoneParametersStruct {
        AdvancedOrder[] advancedOrders;
        address fulfiller;
        uint256 maximumFulfilled;
        address seaport;
        CriteriaResolver[] criteriaResolvers;
    }

    struct ZoneDetails {
        AdvancedOrder[] advancedOrders;
        address fulfiller;
        uint256 maximumFulfilled;
        OrderDetails[] orderDetails;
        bytes32[] orderHashes;
    }

    function getZoneAuthorizeParameters(
        AdvancedOrder memory advancedOrder,
        address fulfiller,
        uint256 counter,
        address seaport
    ) internal view returns (ZoneAuthorizeParameters memory zoneParameters) {
        SeaportInterface seaportInterface = SeaportInterface(seaport);
        // Get orderParameters from advancedOrder
        OrderParameters memory orderParameters = advancedOrder.parameters;

        // Get orderHash
        bytes32 orderHash =
            advancedOrder.getTipNeutralizedOrderHash(seaportInterface, counter);

        // Store orderHash in orderHashes array to pass into zoneParameters
        bytes32[] memory orderHashes = new bytes32[](1);
        orderHashes[0] = orderHash;

        // Create ZoneAuthorizeParameters and add to zoneParameters array
        zoneParameters = ZoneAuthorizeParameters({
            orderHash: orderHash,
            fulfiller: fulfiller,
            offerer: orderParameters.offerer,
            offer: orderParameters.offer,
            consideration: orderParameters.consideration,
            extraData: advancedOrder.extraData,
            orderHashes: orderHashes,
            startTime: orderParameters.startTime,
            endTime: orderParameters.endTime,
            zoneHash: orderParameters.zoneHash
        });
    }

    function getZoneAuthorizeParameters(
        AdvancedOrder[] memory advancedOrders,
        address fulfiller,
        uint256 maximumFulfilled,
        address seaport,
        UnavailableReason[] memory unavailableReasons
    ) internal view returns (ZoneAuthorizeParameters[] memory) {
        return _getZoneAuthorizeParametersFromStruct(
            _getZoneAuthorizeParametersStruct(
                advancedOrders,
                fulfiller,
                maximumFulfilled,
                seaport,
                new CriteriaResolver[](0)
            ),
            unavailableReasons
        );
    }

    function _getZoneAuthorizeParametersStruct(
        AdvancedOrder[] memory advancedOrders,
        address fulfiller,
        uint256 maximumFulfilled,
        address seaport,
        CriteriaResolver[] memory criteriaResolvers
    ) internal pure returns (ZoneParametersStruct memory) {
        return ZoneParametersStruct(
            advancedOrders,
            fulfiller,
            maximumFulfilled,
            seaport,
            criteriaResolvers
        );
    }

    function _getZoneAuthorizeParametersFromStruct(
        ZoneParametersStruct memory zoneParametersStruct,
        UnavailableReason[] memory unavailableReasons
    ) internal view returns (ZoneAuthorizeParameters[] memory) {
        // TODO: use testHelpers pattern to use single amount deriver helper
        ZoneDetails memory details = _getZoneDetails(zoneParametersStruct);

        // Copy the offer and consideration over to the ZoneDetails struct for
        // parity for now.
        _applyOrderDetails(details, zoneParametersStruct, unavailableReasons);

        // Iterate over advanced orders to calculate orderHashes
        _applyOrderHashes(details, zoneParametersStruct.seaport);

        return _finalizeZoneAuthorizeParameters(details);
    }

    function _getZoneDetails(ZoneParametersStruct memory zoneParametersStruct)
        internal
        pure
        returns (ZoneDetails memory)
    {
        return ZoneDetails({
            advancedOrders: zoneParametersStruct.advancedOrders,
            fulfiller: zoneParametersStruct.fulfiller,
            maximumFulfilled: zoneParametersStruct.maximumFulfilled,
            orderDetails: new OrderDetails[]( zoneParametersStruct.advancedOrders.length),
            orderHashes: new bytes32[]( zoneParametersStruct.advancedOrders.length)
        });
    }

    function _applyOrderDetails(
        ZoneDetails memory details,
        ZoneParametersStruct memory zoneParametersStruct,
        UnavailableReason[] memory unavailableReasons
    ) internal view {
        bytes32[] memory orderHashes =
            details.advancedOrders.getOrderHashes(zoneParametersStruct.seaport);

        details.orderDetails = zoneParametersStruct
            .advancedOrders
            .getOrderDetails(
            zoneParametersStruct.criteriaResolvers,
            orderHashes,
            unavailableReasons
        );
    }

    function _applyOrderHashes(ZoneDetails memory details, address seaport)
        internal
        view
    {
        bytes32[] memory orderHashes =
            details.advancedOrders.getOrderHashes(seaport);

        console.log("orderHashes ============");
        console.log(orderHashes.length);
        for (uint256 i = 0; i < orderHashes.length; i++) {
            console.logBytes32(orderHashes[i]);
        }

        uint256 totalFulfilled = 0;
        // Iterate over advanced orders to calculate orderHashes
        for (uint256 i = 0; i < details.advancedOrders.length; i++) {
            bytes32 orderHash = orderHashes[i];

            if (
                totalFulfilled >= details.maximumFulfilled
                    || _isUnavailable(
                        details.advancedOrders[i].parameters,
                        orderHash,
                        SeaportInterface(seaport)
                    )
            ) {
                // Set orderHash to 0 if order index exceeds maximumFulfilled
                details.orderHashes[i] = bytes32(0);
            } else {
                // Add orderHash to orderHashes and increment totalFulfilled/
                details.orderHashes[i] = orderHash;
                ++totalFulfilled;
            }
        }
    }

    function _isUnavailable(
        OrderParameters memory order,
        bytes32 orderHash,
        SeaportInterface seaport
    ) internal view returns (bool) {
        (, bool isCancelled, uint256 totalFilled, uint256 totalSize) =
            seaport.getOrderStatus(orderHash);

        bool isRevertingContractOrder = false;
        if (order.orderType == OrderType.CONTRACT) {
            isRevertingContractOrder = (
                FailingContractOfferer(order.offerer)
                    .failureReasonsForGenerateOrder(orderHash) != 0
            )
                || (
                    FailingContractOfferer(order.offerer)
                        .failureReasonsForRatifyOrder(orderHash) != 0
                );
        }

        return (
            block.timestamp >= order.endTime
                || block.timestamp < order.startTime || isCancelled
                || isRevertingContractOrder
                || (totalFilled >= totalSize && totalSize > 0)
        );
    }

    function _finalizeZoneAuthorizeParameters(ZoneDetails memory zoneDetails)
        internal
        pure
        returns (ZoneAuthorizeParameters[] memory zoneParameters)
    {
        zoneParameters = new ZoneAuthorizeParameters[](
            zoneDetails.advancedOrders.length
        );

        // Iterate through advanced orders to create zoneParameters
        uint256 totalFulfilled = 0;

        // The order hashes array should be length i (3rd order, index 2, order
        // hashes array length 2) bc the order hashes array is only the prior
        // order hashes and not the prior plus the current.

        // TODO: confirm with 0 this is the intended behavior.

        for (uint256 i = 0; i < zoneDetails.advancedOrders.length; i++) {
            if (totalFulfilled >= zoneDetails.maximumFulfilled) {
                break;
            }

            bytes32[] memory orderHashes = new bytes32[](i);

            for (uint256 j = 0; j < i; j++) {
                orderHashes[j] = zoneDetails.orderHashes[j];
            }

            if (zoneDetails.orderHashes[i] != bytes32(0)) {
                // Create ZoneAuthorizeParameters and add to zoneParameters array
                zoneParameters[i] = _createZoneAuthorizeParameters(
                    zoneDetails.orderHashes[i],
                    zoneDetails.advancedOrders[i],
                    zoneDetails.fulfiller,
                    orderHashes
                );
                ++totalFulfilled;
            }
        }

        return zoneParameters;
    }

    function _createZoneAuthorizeParameters(
        bytes32 orderHash,
        AdvancedOrder memory advancedOrder,
        address fulfiller,
        bytes32[] memory orderHashes
    ) internal pure returns (ZoneAuthorizeParameters memory) {
        return ZoneAuthorizeParameters({
            orderHash: orderHash,
            fulfiller: fulfiller,
            offerer: advancedOrder.parameters.offerer,
            offer: advancedOrder.parameters.offer,
            consideration: advancedOrder.parameters.consideration,
            extraData: advancedOrder.extraData,
            orderHashes: orderHashes,
            startTime: advancedOrder.parameters.startTime,
            endTime: advancedOrder.parameters.endTime,
            zoneHash: advancedOrder.parameters.zoneHash
        });
    }
}
