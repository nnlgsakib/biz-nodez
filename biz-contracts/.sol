// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract ReentrancyGuard {
    bool private locked;
    
    modifier nonReentrant() {
        require(!locked, "ReentrancyGuard: reentrant call");
        locked = true;
        _;
        locked = false;
    }
}

contract MPTToken {
    string public name = "MIND PAIR TOKEN";
    string public symbol = "MPT";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) private balances;
    mapping(address => bool) private isMinter;

    constructor() {
        isMinter[msg.sender] = true; // Contract owner is a minter
    }

    modifier onlyMinter() {
        require(isMinter[msg.sender], "Not authorized to mint or burn");
        _;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function mint(address account, uint256 amount) external onlyMinter {
        require(account != address(0), "Cannot mint to zero address");
        totalSupply += amount;
        balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function burn(address account, uint256 amount) external onlyMinter {
        require(account != address(0), "Cannot burn from zero address");
        require(balances[account] >= amount, "Burn amount exceeds balance");
        totalSupply -= amount;
        balances[account] -= amount;
        emit Transfer(account, address(0), amount);
    }

    function setMinter(address account, bool status) external onlyMinter {
        isMinter[account] = status;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
}

contract FixedRateSwap is ReentrancyGuard {
    IERC20 public usdt;
    IERC20 public erc20;
    MPTToken public mpt;

    uint256 public mindToUsdtRate = 5;  // 1 MIND = 5 USDT
    uint256 public mindToErc20Rate = 3; // 1 MIND = 3 ERC20
    uint256 public usdtToErc20Rate = 3; // 1 USDT = 3 ERC20

    address public owner;
    uint256 public totalLiquidity;

    struct LiquidityProvider {
        uint256 mindAmount;
        uint256 usdtAmount;
        uint256 erc20Amount;
    }

    mapping(address => LiquidityProvider) public liquidityProviders;

    constructor(address _usdtAddress, address _erc20Address) {
        usdt = IERC20(_usdtAddress);
        erc20 = IERC20(_erc20Address);
        mpt = new MPTToken();
        mpt.setMinter(address(this), true);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyLiquidityProvider() {
        require(mpt.balanceOf(msg.sender) > 0, "Not a liquidity provider");
        _;
    }

    // Internal function to handle approvals and transfers in the same transaction
    function _approveAndTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        uint256 allowance = token.allowance(from, address(this));
        if (allowance < amount) {
            token.approve(address(this), type(uint256).max);
        }
        token.transferFrom(from, to, amount);
    }

    // Function to distribute fees to liquidity providers
    function _distributeFees(uint256 fee, address tokenAddress) internal {
        for (uint i = 0; i < totalLiquidity; i++) {
            // Distribute fee based on each liquidity provider's share
            uint256 share = (fee * mpt.balanceOf(msg.sender)) / totalLiquidity;
            IERC20(tokenAddress).transfer(msg.sender, share);
        }
    }

    // Swap MIND to USDT
    function swapEthToUsdt() external payable nonReentrant {
        uint256 usdtAmount = msg.value * mindToUsdtRate;
        uint256 fee = (usdtAmount * 3) / 1000;
        uint256 amountAfterFee = usdtAmount - fee;

        require(usdt.balanceOf(address(this)) >= amountAfterFee, "Not enough USDT in contract");
        usdt.transfer(msg.sender, amountAfterFee);
        _distributeFees(fee, address(usdt));
    }

    // Swap USDT to MIND
    function swapUsdtToMind(uint256 usdtAmount) external nonReentrant {
        uint256 mindAmount = usdtAmount / mindToUsdtRate;
        uint256 fee = (mindAmount * 3) / 1000;
        uint256 amountAfterFee = mindAmount - fee;

        require(address(this).balance >= amountAfterFee, "Not enough MIND in contract");
        _approveAndTransferFrom(usdt, msg.sender, address(this), usdtAmount);
        payable(msg.sender).transfer(amountAfterFee);
        _distributeFees(fee, address(0));
    }

    // Swap MIND to ERC20
    function swapMindToErc20() external payable nonReentrant {
        uint256 erc20Amount = msg.value * mindToErc20Rate;
        uint256 fee = (erc20Amount * 3) / 1000;
        uint256 amountAfterFee = erc20Amount - fee;

        require(erc20.balanceOf(address(this)) >= amountAfterFee, "Not enough ERC20 in contract");
        erc20.transfer(msg.sender, amountAfterFee);
        _distributeFees(fee, address(erc20));
    }

    // Swap ERC20 to MIND
    function swapErc20ToMind(uint256 erc20Amount) external nonReentrant {
        uint256 mindAmount = erc20Amount / mindToErc20Rate;
        uint256 fee = (mindAmount * 3) / 1000;
        uint256 amountAfterFee = mindAmount - fee;

        require(address(this).balance >= amountAfterFee, "Not enough MIND in contract");
        _approveAndTransferFrom(erc20, msg.sender, address(this), erc20Amount);
        payable(msg.sender).transfer(amountAfterFee);
        _distributeFees(fee, address(0));
    }

    // Swap USDT to ERC20
    function swapUsdtToErc20(uint256 usdtAmount) external nonReentrant {
        uint256 erc20Amount = usdtAmount * usdtToErc20Rate;
        uint256 fee = (erc20Amount * 3) / 1000;
        uint256 amountAfterFee = erc20Amount - fee;

        require(erc20.balanceOf(address(this)) >= amountAfterFee, "Not enough ERC20 in contract");
        _approveAndTransferFrom(usdt, msg.sender, address(this), usdtAmount);
        erc20.transfer(msg.sender, amountAfterFee);
        _distributeFees(fee, address(erc20));
    }

    // Swap ERC20 to USDT
    function swapErc20ToUsdt(uint256 erc20Amount) external nonReentrant {
        uint256 usdtAmount = erc20Amount / usdtToErc20Rate;
        uint256 fee = (usdtAmount * 3) / 1000;
        uint256 amountAfterFee = usdtAmount - fee;

        require(usdt.balanceOf(address(this)) >= amountAfterFee, "Not enough USDT in contract");
        _approveAndTransferFrom(erc20, msg.sender, address(this), erc20Amount);
        usdt.transfer(msg.sender, amountAfterFee);
        _distributeFees(fee, address(usdt));
    }

    // Calculator functions
    function calculateEthToUsdt(uint256 mindAmount) external view returns (uint256) {
        return mindAmount * mindToUsdtRate;
    }

    function calculateUsdtToMind(uint256 usdtAmount) external view returns (uint256) {
        return usdtAmount / mindToUsdtRate;
    }

    function calculateMindToErc20(uint256 mindAmount) external view returns (uint256) {
        return mindAmount * mindToErc20Rate;
    }

    function calculateErc20ToMind(uint256 erc20Amount) external view returns (uint256) {
        return erc20Amount / mindToErc20Rate;
    }

    function calculateUsdtToErc20(uint256 usdtAmount) external view returns (uint256) {
        return usdtAmount * usdtToErc20Rate;
    }

    function calculateErc20ToUsdt(uint256 erc20Amount) external view returns (uint256) {
        return erc20Amount / usdtToErc20Rate;
    }

    // Add liquidity functions
    function addLiquidityEth() external payable nonReentrant {
        liquidityProviders[msg.sender].mindAmount += msg.value;
        totalLiquidity += msg.value;
        mpt.mint(msg.sender, msg.value);
    }

    function addLiquidityUsdt(uint256 usdtAmount) external nonReentrant {
        _approveAndTransferFrom(usdt, msg.sender, address(this), usdtAmount);
        liquidityProviders[msg.sender].usdtAmount += usdtAmount;
        totalLiquidity += usdtAmount;
        mpt.mint(msg.sender, usdtAmount);
    }

    function addLiquidityErc20(uint256 erc20Amount) external nonReentrant {
        _approveAndTransferFrom(erc20, msg.sender, address(this), erc20Amount);
        liquidityProviders[msg.sender].erc20Amount += erc20Amount;
        totalLiquidity += erc20Amount;
        mpt.mint(msg.sender, erc20Amount);
    }

    // Remove liquidity functions
    function removeLiquidityEth(uint256 amount) external onlyLiquidityProvider nonReentrant {
        require(liquidityProviders[msg.sender].mindAmount >= amount, "Not enough MIND liquidity provided");
        liquidityProviders[msg.sender].mindAmount -= amount;
        totalLiquidity -= amount;
        mpt.burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    function removeLiquidityUsdt(uint256 amount) external onlyLiquidityProvider nonReentrant {
        require(liquidityProviders[msg.sender].usdtAmount >= amount, "Not enough USDT liquidity provided");
        liquidityProviders[msg.sender].usdtAmount -= amount;
        totalLiquidity -= amount;
        mpt.burn(msg.sender, amount);
        usdt.transfer(msg.sender, amount);
    }

    function removeLiquidityErc20(uint256 amount) external onlyLiquidityProvider nonReentrant {
        require(liquidityProviders[msg.sender].erc20Amount >= amount, "Not enough ERC20 liquidity provided");
        liquidityProviders[msg.sender].erc20Amount -= amount;
        totalLiquidity -= amount;
        mpt.burn(msg.sender, amount);
        erc20.transfer(msg.sender, amount);
    }

    // Allow contract to receive MIND
    receive() external payable {}

    // Function to withdraw MIND from the contract
    function withdrawEth(uint256 amount) external onlyOwner nonReentrant {
        require(address(this).balance >= amount, "Not enough MIND in contract");
        payable(msg.sender).transfer(amount);
    }

    // Function to withdraw USDT from the contract
    function withdrawUsdt(uint256 amount) external onlyOwner nonReentrant {
        require(usdt.balanceOf(address(this)) >= amount, "Not enough USDT in contract");
        usdt.transfer(msg.sender, amount);
    }

    // Function to withdraw ERC20 from the contract
    function withdrawErc20(uint256 amount) external onlyOwner nonReentrant {
        require(erc20.balanceOf(address(this)) >= amount, "Not enough ERC20 in contract");
        erc20.transfer(msg.sender, amount);
    }
}
