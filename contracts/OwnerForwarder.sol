///SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol"; /// required for swapExactETHForTokens
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol"; /// required for getPair
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol"; /// required for path & exclusion
import "./libraries/bits.sol";
import "./interfaces/IAffinity.sol";

/// @title ShillX OwnerForwarder
/// @notice all external / public methods names are verbose to prevent collisions with future token contracts
/// @dev A proxy contract that has ownership of the token and forwards deployer wallet calls to the token.
contract OwnerForwarder  {
    /// @notice easy bit manipulation library required for permission system
    using bits for uint;

    event PermissionsChanged(address indexed sender, address indexed account, uint permissionsBefore, uint permissionsAfter);

    /// @notice highest level permission usually reserved for the deployer wallet
    uint constant public OF_OWNER_PERMISSION = 1 << 255;

    /// @notice external permission allow access to swapping functions
    uint constant public OF_EXTERNAL_PERMISSION = OF_OWNER_PERMISSION >> 1;

    /// @notice an interface to the ERC20 contract replace this with custom interface if needed
    IAffinity _token;

    /// @notice an interface to the preferred Uniswap Router
    IUniswapV2Router02 _uniswapV2Router02;

    /// @notice the address to the Uniswap Pair for the given Router required for exclusion
    address  _uniswapV2PairAddress;

    /// @notice the Uniswap Router path
    address[] _path;
    
    /// @notice permission storage
    mapping(address => uint) public getOwnerForwarderPermissions;


    /// @notice enforces that the sender has  ANY of the required permission bit flags set
    modifier requires(uint permissions_) {
        require(getOwnerForwarderPermissions[msg.sender].any(permissions_), "OP: unauthorized");
        _;
    }

    /// @notice create a new OwnerForwarder
    constructor(address tokenAddress, address uniswapV2Router02Address)  {
        require(tokenAddress != address(0), "OP: tokenAddress is 0");
        getOwnerForwarderPermissions[msg.sender] = OF_OWNER_PERMISSION;
        _uniswapV2Router02 = IUniswapV2Router02(uniswapV2Router02Address);
        _path = new address[](2);
        _setOwnerForwarderTokenAddress(tokenAddress);
    }

    /// @notice forward receive calls
    fallback() external payable virtual {
        _forward();
    }

    /// @notice forward receive calls
    receive() external payable virtual {
        _forward();
    }

    /// @notice owner callable function to modify permissions for wallets or contracts
    function modifyOwnerForwarderPermission(address account, uint permissionsToBeAdded, uint permissionsToBeRemoved) external requires(OF_OWNER_PERMISSION) {
        uint permissionsBefore = getOwnerForwarderPermissions[account];
        uint permissionsAfter = getOwnerForwarderPermissions[account] = permissionsBefore.set(permissionsToBeAdded).clear(permissionsToBeRemoved);
        emit PermissionsChanged(msg.sender, account, permissionsBefore, permissionsAfter);
    }

    /// @notice owner callable function to change the Uniswap Router
    /// @param uniswapV2Router02Address the address of the new Uniswap Router
    /// @dev the token pair will be changed which is required for the taxless swap transaction below
    function setOwnerForwarderUniswapV2Router02(address uniswapV2Router02Address) public requires(OF_OWNER_PERMISSION) {
        _uniswapV2Router02 = IUniswapV2Router02(uniswapV2Router02Address); /// change the interface
        _setUniswapV2PairAddress(_uniswapV2Router02);
    }

    /// @notice set the token address this proxy forwards too
    function setOwnerForwarderTokenAddress(address tokenAddress) external virtual requires(OF_OWNER_PERMISSION) {
        _setOwnerForwarderTokenAddress(tokenAddress);
    }

    /// @notice required for IUniswapV2Router02 compatibility
    function WETH() external view returns (address) {
        return _uniswapV2Router02.WETH();
    }

    /// @notice encapsulated uniswap call
    /// @dev this was put in place for ShillX
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts) {
        return _uniswapV2Router02.getAmountsOut(amountIn, _path);
    }

    /// @notice encapsulated uniswap call
    /// @dev this was put in place for ShillX we don't use the path parameter as it's hardcoded for affinity
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable requires(OF_EXTERNAL_PERMISSION | OF_OWNER_PERMISSION) returns (uint[] memory){
        _token.setIsFeeAndTXLimitExempt(_uniswapV2PairAddress, true, true);
        uint[] memory amounts = _uniswapV2Router02.swapExactETHForTokens{value: msg.value}(amountOutMin, _path, to, deadline);
        _token.setIsFeeAndTXLimitExempt(_uniswapV2PairAddress, false, true);
        return amounts;
    }


    /// @notice get the token address
    function getOwnerForwarderTokenAddress() external view returns (address) {
        return address(_token);
    }

    /// @notice get the Uniswap Router address
    function getOwnerForwarderUniswapV2Router02Address() external view returns (address) {
        return address(_uniswapV2Router02);
    }

    /// @notice forward any call that doesn't exist in this contract to the token
    /// @dev this will require using either open zeppelin defender or programmatically calling functions.
    function _forward() internal requires(OF_OWNER_PERMISSION) {
        address tokenAddress = address(_token);
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := call(gas(), tokenAddress, 0, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            /// delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /// @notice set the token address this proxy forwards too
    function _setOwnerForwarderTokenAddress(address tokenAddress) internal {
        _token = IAffinity(tokenAddress);
        _setUniswapV2PairAddress(_uniswapV2Router02);
    }

    /// @notice set the uniswap address
    function _setUniswapV2PairAddress(IUniswapV2Router02 router) internal {
        (_path[0], _path[1]) = (router.WETH(), address(_token));
        _uniswapV2PairAddress = IUniswapV2Factory(router.factory()).getPair(_path[0], _path[1]);
    }


}