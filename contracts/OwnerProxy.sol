///SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol"; /// required for swapExactETHForTokens
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol"; /// required for getPair
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol"; /// required for path & exclusion
import "./libraries/bits.sol";
import "./interfaces/IAffinity.sol";

/// @title ShillX OwnerProxy
/// @notice all external / public methods names are verbose to prevent collisions with future token contracts
/// @dev A proxy contract that has ownership of the token and forwards deployer wallet calls to the token.
contract OwnerProxy  {
    /// @notice easy bit manipulation library required for permission system
    using bits for uint;

    event PermissionsChanged(address indexed sender, address indexed account, uint permissionsBefore, uint permissionsAfter);

    /// @notice highest level permission usually reserved for the deployer wallet
    uint constant public OP_OWNER_PERMISSION = 1 << 255;

    /// @notice external permission allow access to swapping functions
    uint constant public OP_EXTERNAL_PERMISSION = OP_OWNER_PERMISSION >> 1;

    /// @notice an interface to the ERC20 contract replace this with custom interface if needed
    IAffinity _token;

    /// @notice an interface to the preferred Uniswap Router
    IUniswapV2Router02 _uniswapV2Router02;

    /// @notice the address to the Uniswap Pair for the given Router required for exclusion
    address  _uniswapV2PairAddress;

    /// @notice the Uniswap Router path
    address[] _path;
    
    /// @notice permission storage
    mapping(address => uint) public getOwnerProxyPermissions;


    /// @notice enforces that the sender has  ANY of the required permission bit flags set
    modifier requires(uint permissions_) {
        require(getOwnerProxyPermissions[msg.sender].any(permissions_), "OP: unauthorized");
        _;
    }

    /// @notice create a new OwnerProxy
    constructor(address tokenAddress, address uniswapV2Router02Address)  {
        require(tokenAddress != address(0), "OP: tokenAddress is 0");
        getOwnerProxyPermissions[msg.sender] = OP_OWNER_PERMISSION;
        _uniswapV2Router02 = IUniswapV2Router02(uniswapV2Router02Address);
        _path = new address[](2);
        _setOwnerProxyTokenAddress(tokenAddress);
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
    function modifyOwnerProxyPermission(address account, uint permissionsToBeAdded, uint permissionsToBeRemoved) external requires(OP_OWNER_PERMISSION) {
        uint permissionsBefore = getOwnerProxyPermissions[account];
        uint permissionsAfter = getOwnerProxyPermissions[account] = permissionsBefore.set(permissionsToBeAdded).clear(permissionsToBeRemoved);
        emit PermissionsChanged(msg.sender, account, permissionsBefore, permissionsAfter);
    }

    /// @notice owner callable function to change the Uniswap Router
    /// @param uniswapV2Router02Address the address of the new Uniswap Router
    /// @dev the token pair will be changed which is required for the taxless swap transaction below
    function setOwnerProxyUniswapV2Router02(address uniswapV2Router02Address) public requires(OP_OWNER_PERMISSION) {
        _uniswapV2Router02 = IUniswapV2Router02(uniswapV2Router02Address); /// change the interface
        _setUniswapV2PairAddress(_uniswapV2Router02);
    }

    /// @notice set the token address this proxy forwards too
    function setOwnerProxyTokenAddress(address tokenAddress) external virtual requires(OP_OWNER_PERMISSION) {
        _setOwnerProxyTokenAddress(tokenAddress);
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
    /// @dev this was put in place for ShillX we don't enforce the path for affinity
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable requires(OP_EXTERNAL_PERMISSION | OP_OWNER_PERMISSION) returns (uint[] memory){
        _token.setIsFeeAndTXLimitExempt(_uniswapV2PairAddress, true, true);
        uint[] memory amounts = _uniswapV2Router02.swapExactETHForTokens{value: msg.value}(amountOutMin, _path, to, deadline);
        _token.setIsFeeAndTXLimitExempt(_uniswapV2PairAddress, false, true);
        return amounts;
    }


    /// @notice get the token address
    function getOwnerProxyTokenAddress() external view returns (address) {
        return address(_token);
    }

    /// @notice get the Uniswap Router address
    function getOwnerProxyUniswapV2Router02Address() external view returns (address) {
        return address(_uniswapV2Router02);
    }

    /// @notice forward any call that doesn't exist in this contract to the token
    /// @dev this will require using either open zeppelin defender or programmatically calling functions.
    function _forward() internal requires(OP_OWNER_PERMISSION) {
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
    function _setOwnerProxyTokenAddress(address tokenAddress) internal {
        _token = IAffinity(tokenAddress);
        _setUniswapV2PairAddress(_uniswapV2Router02);
    }

    /// @notice set the uniswap address
    function _setUniswapV2PairAddress(IUniswapV2Router02 router) internal {
        (_path[0], _path[1]) = (router.WETH(), address(_token));
        _uniswapV2PairAddress = IUniswapV2Factory(router.factory()).getPair(_path[0], _path[1]);
    }


}