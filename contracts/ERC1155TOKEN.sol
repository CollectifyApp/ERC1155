// SPDX-License-Identifier: MIT
// Collectify Launchapad Contracts v1.0.0
// Creator: Hging

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ERC1155TOKEN is ERC2981, ERC1155, ERC1155Supply, Ownable {
    string public name;
    string public symbol;
    string public baseURI = "";
    mapping(uint256 => string) private _tokenURIs;

    mapping (uint256 => bool) public avaliable_ids;

    struct MintTime {
        uint64 startAt;
        uint64 endAt;
    }

    struct TimeZone {
        int8 offset;
        string text;
    }

    struct MintState {
        bool privateMinted;
        bool publicMinted;
    }

    struct MintInfo {
        bytes32 merkleRoot;
        uint256 maxSupply;
        uint256 mintPrice;
        uint256 maxCountPerAddress;
        uint256 _privateMintCount;
        MintTime privateMintTime;
        MintTime publicMintTime;
        TimeZone timezone;
        mapping(address => bool) privateClaimList;
        mapping(address => bool) publicClaimList;
        address tokenContract;
    }

    address[] private _operatorFilterAddresses;

    mapping(uint256 => MintInfo) public mintInfoList;

    modifier validId(uint256 _id) {
        require(avaliable_ids[_id], "Id is not minted");
        _;
    }

    modifier onlyAllowedOperatorApproval(address operator) {
        for (uint256 i = 0; i < _operatorFilterAddresses.length; i++) {
            require(
                operator != _operatorFilterAddresses[i],
                "ERC721: operator not allowed"
            );
        }
        _;
    }

    modifier onlyAllowedOperator(address from) {
        for (uint256 i = 0; i < _operatorFilterAddresses.length; i++) {
            require(
                from != _operatorFilterAddresses[i],
                "ERC721: operator not allowed"
            );
        }
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        uint96 royaltyFraction
    ) ERC1155(_uri) {
        name = _name;
        symbol = _symbol;
        baseURI = _uri;
        _setDefaultRoyalty(_msgSender(), royaltyFraction);
    }

    function changeOperatorFilterAddresses(address[] memory _addresses) public onlyOwner {
        _operatorFilterAddresses = _addresses;
    }

    function operatorFilterAddresses() public view returns (address[] memory) {
        return _operatorFilterAddresses;
    }

    function uri(uint256 id) public view virtual override(ERC1155) validId(id) returns (string memory) {
        string memory tokenURI = _tokenURIs[id];
        return bytes(tokenURI).length > 0 ? tokenURI : string(abi.encodePacked(baseURI, Strings.toString(id)));

    }

    function isMinted(uint256 id, address owner) public view returns (MintState memory)  {
        return(
            MintState(
                mintInfoList[id].privateClaimList[owner],
                mintInfoList[id].publicClaimList[owner]
            )
        );
    }

    function changeBaseURI(string memory _uri) public onlyOwner {
        baseURI = _uri;
    }

    function setURI(uint256 id, string memory _uri) public onlyOwner validId(id) {
        _tokenURIs[id] = _uri;
    }

    function changeMerkleRoot(uint256 id, bytes32 _merkleRoot) public onlyOwner validId(id) {
        mintInfoList[id].merkleRoot = _merkleRoot;
    }

    function changeMintPrice(uint256 id, uint256 _mintPrice) public onlyOwner validId(id) {
        mintInfoList[id].mintPrice = _mintPrice;
    }

    function changemaxPerAddress(uint256 id, uint256 _maxPerAddress) public onlyOwner validId(id) {
        mintInfoList[id].maxCountPerAddress = _maxPerAddress;
    }

    function changeRoyalty(uint256 id, uint96 _royaltyFraction) public onlyOwner validId(id) {
        _setTokenRoyalty(id, _msgSender(), _royaltyFraction);
    }

    function changeMintTime(uint256 id, MintTime memory _publicMintTime, MintTime memory _privateMintTime) public onlyOwner validId(id) {
        mintInfoList[id].privateMintTime = _privateMintTime;
        mintInfoList[id].publicMintTime = _publicMintTime;
    }

    function createNewid(uint256 id, bytes32 _merkleRoot, uint256 _maxSupply, uint256 _mintPrice, uint256 _maxPerAddress, TimeZone memory _timezone, MintTime memory _publicMintTime, MintTime memory _privateMintTime,  address _tokenContract) public onlyOwner {
        require(!avaliable_ids[id], "Not avaliable");
        avaliable_ids[id] = true;
        mintInfoList[id].merkleRoot = _merkleRoot;
        mintInfoList[id].maxSupply = _maxSupply;
        mintInfoList[id].mintPrice = _mintPrice;
        mintInfoList[id].maxCountPerAddress = _maxPerAddress;
        mintInfoList[id].timezone = _timezone;
        mintInfoList[id].publicMintTime = _publicMintTime;
        mintInfoList[id].privateMintTime = _privateMintTime;
        mintInfoList[id].tokenContract = _tokenContract;
    }

    function privateMint(uint256 id, uint256 quantity, uint256 whiteQuantity, bytes32[] calldata merkleProof) external payable validId(id) {
        uint256 _id = id;
        require(block.timestamp >= mintInfoList[id].privateMintTime.startAt && block.timestamp <= mintInfoList[id].privateMintTime.endAt, "10000 time is not allowed");
        uint256 supply = totalSupply(id);
        require(supply + quantity <= mintInfoList[id].maxSupply, "10001 supply exceeded");
        // require(mintInfoList[id].mintPrice * quantity <= msg.value, "10002 price insufficient");
        address claimAddress = _msgSender();
        require(!mintInfoList[id].privateClaimList[claimAddress], "error:10003 already claimed");
        require(quantity <= whiteQuantity, "10004 quantity is not allowed");
        require(
            MerkleProof.verify(merkleProof, mintInfoList[id].merkleRoot, keccak256(abi.encodePacked(claimAddress, whiteQuantity))),
            "error:10004 not in the whitelist"
        );
        if (mintInfoList[id].tokenContract == address(0)) {
            require(mintInfoList[id].mintPrice * quantity <= msg.value, "error: 10002 price insufficient");
        } else {
            (bool success, bytes memory data) = mintInfoList[id].tokenContract.call(abi.encodeWithSelector(0x23b872dd, claimAddress, address(this), mintInfoList[_id].mintPrice * quantity));
            require(
                success && (data.length == 0 || abi.decode(data, (bool))),
                "error: 10002 price insufficient"
            );
        }
        mintInfoList[id].privateClaimList[claimAddress] = true;
        mintInfoList[id]._privateMintCount = mintInfoList[id]._privateMintCount + quantity;
        _mint( claimAddress, id, quantity, "");
    }

    function publicMint(uint256 id, uint256 quantity) external payable validId(id)  {
        require(block.timestamp >= mintInfoList[id].publicMintTime.startAt && block.timestamp <= mintInfoList[id].publicMintTime.endAt, "10000 time is not allowed");
        uint256 supply = totalSupply(id);
        require(supply + quantity <= mintInfoList[id].maxSupply, "10001 supply exceeded");
        address claimAddress = _msgSender();
        require(!mintInfoList[id].publicClaimList[claimAddress], "error:10003 already claimed");
        require(quantity <= mintInfoList[id].maxCountPerAddress, "10004 max per address exceeded");
        if (mintInfoList[id].tokenContract == address(0)) {
            require(mintInfoList[id].mintPrice * quantity <= msg.value, "error: 10002 price insufficient");
        } else {
            (bool success, bytes memory data) = mintInfoList[id].tokenContract.call(abi.encodeWithSelector(0x23b872dd, claimAddress, address(this), mintInfoList[id].mintPrice * quantity));
            require(
                success && (data.length == 0 || abi.decode(data, (bool))),
                "error: 10002 price insufficient"
            );
        }
        mintInfoList[id].publicClaimList[claimAddress] = true;
        _mint( claimAddress, id, quantity, "" );
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, ERC2981)
        returns (bool)
    {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(ERC2981).interfaceId;
    }

    // This allows the contract owner to withdraw the funds from the contract.

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155Supply, ERC1155) {
        ERC1155Supply._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function setApprovalForAll(address operator, bool approved) public override(ERC1155) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, uint256 amount, bytes memory data)
        public
        override(ERC1155)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, amount, data);
    }

    function safeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) 
        public
        override(ERC1155)
        onlyAllowedOperator(from)
    {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }


    // This allows the contract owner to withdraw the funds from the contract.
    function withdraw(uint256 id, uint amt) external onlyOwner validId(id) {
        if (mintInfoList[id].tokenContract == address(0)) {
            (bool sent, ) = payable(_msgSender()).call{value: amt}("");
            require(sent, "GG: Failed to withdraw Ether");
        } else {
            (bool success, bytes memory data) = mintInfoList[id].tokenContract.call(abi.encodeWithSelector(0xa9059cbb, _msgSender(), amt));
            require(
                success && (data.length == 0 || abi.decode(data, (bool))),
                "GG: Failed to withdraw Ether"
            );
        }

    }
}
