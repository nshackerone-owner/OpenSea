// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    ZoneAuthorizeParameters,
    ZoneValidateParameters,
    Schema
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { ZoneInterface } from "seaport-types/src/interfaces/ZoneInterface.sol";

contract TestZone is ERC165, ZoneInterface {
    function authorizeOrder(ZoneAuthorizeParameters calldata)
        public
        pure
        returns (bytes4)
    {
        return this.authorizeOrder.selector;
    }

    // Called by Consideration whenever any extraData is provided by the caller.
    function validateOrder(ZoneValidateParameters calldata)
        external
        pure
        returns (bytes4 validOrderMagicValue)
    {
        return ZoneInterface.validateOrder.selector;
    }

    /**
     * @dev Returns the metadata for this zone.
     */
    function getSeaportMetadata()
        external
        pure
        override
        returns (
            string memory name,
            Schema[] memory schemas // map to Seaport Improvement Proposal IDs
        )
    {
        schemas = new Schema[](1);
        schemas[0].id = 3003;
        schemas[0].metadata = new bytes(0);

        return ("TestZone", schemas);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC165, ZoneInterface)
        returns (bool)
    {
        return interfaceId == type(ZoneInterface).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
