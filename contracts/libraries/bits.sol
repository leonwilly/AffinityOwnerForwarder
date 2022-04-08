//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


/// @title simple bit manipulation library
library bits {


    /// @notice check if only a specific bit is set
    /// @param slot the bit  slot
    /// @param bits_ the bit to be checked
    /// @return return true if the bit is set
    function only(uint slot, uint bits_) internal pure returns (bool) {
        return slot == bits_;
    }


    /// @notice checks if any of the bits are set
    /// @param slot the bit  to slot
    /// @param bits_ the or list of bits_ to slot
    /// @return true of any of the bits_ are set otherwise false
    function any(uint slot, uint bits_) internal pure returns(bool) {
        return (slot & bits_) != 0;
    }


    /// @notice checks if all of the bits_ are set
    /// @param slot the bit 
    /// @param bits_ the list of bits_ required
    /// @return true if all of the bits_ are set in the sloted variable
    function all(uint slot, uint bits_) internal pure returns(bool) {
        return (slot & bits_) == bits_;
    }


    /// @notice set bits_ in this  slot
    /// @param slot the  slot to set
    /// @param bits_ the list of bits_ to be set
    /// @return a new uint with bits_ set
    /// @dev bits_ that are already set are not cleared
    function set(uint slot, uint bits_) internal pure returns(uint) {
        return slot | bits_;
    }

    /// @notice toggle bits
    /// @param slot the variable to be toggled
    /// @param bits_ the bits to toggle
    /// @return the slot with the toggled bits
    function toggle(uint slot, uint bits_) internal pure returns (uint) {
        return slot ^ bits_;
    }


    /// @notice check if the bits are 0 in the slot
    /// @param slot the variable with the cleared bits to be checked
    /// @param bits_ the bits that should be clear
    /// @return true if all the bits are cleared in the slot
    function isClear(uint slot, uint bits_) internal pure returns(bool) {
        return !all(slot, bits_);
    }


    /// @notice clear bits_ in the slot
    /// @param slot the variable to be cleared
    /// @param bits_ the list of bits_ to clear
    /// @return a new uint with bits_ cleared
    function clear(uint slot, uint bits_) internal pure returns(uint) {
        return slot & ~(bits_);
    }


    /// @notice clear & set bits_ in the  slot
    /// @param slot the variable to be reset
    /// @param bits_ the list of bits_ to clear
    /// @return a new uint with bits_ cleared and set
    function reset(uint slot, uint bits_) internal pure returns(uint) {
        slot = clear(slot, type(uint).max);
        return set(slot, bits_);
    }

}
