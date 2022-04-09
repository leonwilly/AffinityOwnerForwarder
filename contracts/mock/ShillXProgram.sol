pragma solidity ^0.8.0;
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol"; /// required for swapExactETHForTokens
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // required for calling af ERC20 functions
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ShillXProgram {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 _router;
    IERC20 _token;
    address[] _path;

    constructor(address token, address router) {
        _token = IERC20(token);
        _router = IUniswapV2Router02(router);
        _path = new address[](2);
    (_path[0], _path[1]) = (_router.WETH(), token);
    }

    /// @notice mock swap call to test OwnerProxy
    function swap() external payable returns (bool) {
        uint[] memory amountsOut = _router.getAmountsOut(msg.value, _path);
        _router.swapExactETHForTokens{value: msg.value}(0, _path, address(this), block.timestamp + 3);
        if (amountsOut[1] == _token.balanceOf(address(this))) {
            _token.safeTransfer(msg.sender, _token.balanceOf(address(this)));
            return true;
        }
        return false;
    }

}
