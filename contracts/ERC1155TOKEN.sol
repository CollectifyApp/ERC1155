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
    }

    mapping(uint256 => MintInfo) public mintInfoList;

    modifier validId(uint256 _id) {
        require(avaliable_ids[_id], "Id is not minted");
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

    function createNewid(uint256 id, bytes32 _merkleRoot, uint256 _maxSupply, uint256 _mintPrice, uint256 _maxPerAddress, TimeZone memory _timezone, MintTime memory _publicMintTime, MintTime memory _privateMintTime) public onlyOwner {
        require(!avaliable_ids[id], "Not avaliable");
        avaliable_ids[id] = true;
        mintInfoList[id].merkleRoot = _merkleRoot;
        mintInfoList[id].maxSupply = _maxSupply;
        mintInfoList[id].mintPrice = _mintPrice;
        mintInfoList[id].maxCountPerAddress = _maxPerAddress;
        mintInfoList[id].timezone = _timezone;
        mintInfoList[id].publicMintTime = _publicMintTime;
        mintInfoList[id].privateMintTime = _privateMintTime;
    }

    function privateMint(uint256 id, uint256 quantity, uint256 whiteQuantity, bytes32[] calldata merkleProof) external payable validId(id) {
        require(block.timestamp >= mintInfoList[id].privateMintTime.startAt && block.timestamp <= mintInfoList[id].privateMintTime.endAt, "10000 time is not allowed");
        uint256 supply = totalSupply(id);
        require(supply + quantity <= mintInfoList[id].maxSupply, "10001 supply exceeded");
        require(mintInfoList[id].mintPrice * quantity <= msg.value, "10002 price insufficient");
        address claimAddress = _msgSender();
        require(!mintInfoList[id].privateClaimList[claimAddress], "error:10003 already claimed");
        require(quantity <= whiteQuantity, "10004 quantity is not allowed");
        require(
            MerkleProof.verify(merkleProof, mintInfoList[id].merkleRoot, keccak256(abi.encodePacked(claimAddress, whiteQuantity))),
            "error:10004 not in the whitelist"
        );
        _mint( claimAddress, id, quantity, "");
        mintInfoList[id].privateClaimList[claimAddress] = true;
        mintInfoList[id]._privateMintCount = mintInfoList[id]._privateMintCount + quantity;
    }

    function publicMint(uint256 id, uint256 quantity) external payable validId(id)  {
        require(block.timestamp >= mintInfoList[id].publicMintTime.startAt && block.timestamp <= mintInfoList[id].publicMintTime.endAt, "10000 time is not allowed");
        uint256 supply = totalSupply(id);
        require(supply + quantity <= mintInfoList[id].maxSupply, "10001 supply exceeded");
        require(mintInfoList[id].mintPrice * quantity <= msg.value, "10002 price insufficient");
        address claimAddress = _msgSender();
        require(!mintInfoList[id].publicClaimList[claimAddress], "error:10003 already claimed");
        require(quantity <= mintInfoList[id].maxCountPerAddress, "10004 max per address exceeded");
        _mint( claimAddress, id, quantity, "" );
        mintInfoList[id].publicClaimList[claimAddress] = true;
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

    function withdraw(uint amt) external onlyOwner {
        (bool sent, ) = payable(_msgSender()).call{value: amt}("");
        require(sent, "GG: Failed to withdraw Ether");
    }
}
