// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';

contract AssetERC721 is ERC721, AccessControl, Pausable {
    using Counters for Counters.Counter;

    // The role that's allowed to pause in an emergency
    bytes32 public constant PAUSE_ROLE = keccak256('PAUSE_ROLE');

    // Allowed to modify fees
    bytes32 public constant SET_FEE_ROLE = keccak256('SET_FEE_ROLE');

    // Allowed to modify the treasury
    bytes32 public constant SET_TREASURY_ROLE = keccak256('SET_TREASURY_ROLE');

    // Allowed to create new products, listings, etc.
    bytes32 public constant SELLER_ROLE = keccak256('SELLER_ROLE');

    Counters.Counter private _tokenIdCounter;
    Counters.Counter private _listingIdCounter;
    Counters.Counter private _productIdCounter;
    Counters.Counter private _shippingIdCounter;

    // The address fees are sent to.
    address public treasury;

    // A mapping of productIds to Products
    mapping(uint256 => Product) public products;

    // A mapping of listingIds to Listings
    mapping(uint256 => Listing) public listings;

    // A mapping of shippingRateIds to ShippingRates
    mapping(uint256 => ShippingRate) public shippingRates;

    // A mapping of listingIds to accepted shippingRateIds
    mapping(uint256 => mapping(uint256 => bool)) public acceptedShippingRates;

    // A mapping of tokenIds to listingIds
    mapping(uint256 => uint256) public tokenIdsToListingIds;

    /// @dev the fee rate in parts per million
    uint256 public fee = 10000; // default is 1%

    /// @dev The denominator of parts per million
    uint256 constant ONE_MILLION = 1000000;

    event Purchase(uint256 indexed tokenId, address indexed buyer);
    event Redeem(
        uint256 indexed tokenId,
        address indexed user,
        uint256 amount,
        string uri
    );
    event CreateProduct(uint256 indexed productId);
    event CreateListing(uint256 indexed listingId);
    event CreateShippingRate(uint256 indexed shippingRateId);
    event SetProductOwner(uint256 indexed productId, address indexed newOwner);
    event SetProductURI(uint256 indexed productId, string newURI);
    event SetProductActive(uint256 indexed productId, bool newActive);
    event SetShippingRatePrice(
        uint256 indexed shippingRateId,
        uint256 newPrice
    );
    event SetListingURI(uint256 indexed listingId, string newURI);
    event SetListingPriceAndToken(
        uint256 indexed listingId,
        uint256 newPrice,
        IERC20 newToken
    );
    event SetListingSets(uint256 indexed listingId, uint256 newSets);
    event SetListingPurchasePeriod(
        uint256 indexed listingId,
        uint256 newPurchasePeriodBegins,
        uint256 newPurchasePeriodEnds
    );
    event SetListingRedemptionPeriod(
        uint256 indexed listingId,
        uint256 newRedemptionPeriodBegins,
        uint256 newRedemptionPeriodEnds
    );
    event SetListingShippingRate(
        uint256 indexed listingId,
        uint256 indexed shippingRateId,
        bool newAccepted
    );
    event SetShippingRateOwner(
        uint256 indexed shippingRateId,
        address indexed newOwner
    );
    event SetShippingRateURI(uint256 indexed shippingRateId, string newURI);
    event SetFee(uint256 newFee);
    event SetTreasury(address indexed oldTreasury, address indexed newTreasury);

    constructor() ERC721('RWTP', 'rwtp') {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SET_FEE_ROLE, msg.sender);
        _grantRole(SET_TREASURY_ROLE, msg.sender);
        _grantRole(SELLER_ROLE, msg.sender);
        _grantRole(PAUSE_ROLE, msg.sender);
        treasury = msg.sender;
    }

    // A "Product", like a jacket or a shirt.
    // Products have prices and can be listed for sale.
    struct Product {
        // URI to arbitrary listing metadata
        string uri;
        // Owner of this product.
        address owner;
        // If false, all purchases and redemptions will revert.
        bool active;
    }

    // A "Listing" that's associated with a product.
    struct Listing {
        // The product ID this is associated with
        uint256 productId;
        // URI to arbitrary listing metadata
        string uri;
        // The amount you'll get if you buy this listing
        uint256 supply;
        // The price of the entire package
        uint256 price;
        // The token to purchase it in
        IERC20 token;
        // The number of times someone can buy this listing
        uint256 sets;
        // The timestamp at which you can purchase this
        uint256 purchasePeriodBegins;
        // The timestamp at which you can no longer purchase this
        uint256 purchasePeriodEnds;
        // The timestamp at which you can start redeeming this
        uint256 redemptionPeriodBegins;
        // The timestamp at which you can no longer redeem this
        uint256 redemptionPeriodEnds;
    }

    struct ShippingRate {
        // URI to arbitrary shipping metadata
        string uri;
        // The additional fee for shipping
        uint256 price;
        // The owner of this shipping rate that's allowed to modify it
        address owner;
    }

    modifier onlyProductOwner(uint256 productId) {
        require(
            msg.sender == products[productId].owner,
            'Not the product owner'
        );
        _;
    }

    modifier onlyShippingRateOwner(uint256 shippingRateId) {
        require(
            msg.sender == shippingRates[shippingRateId].owner,
            'Not the shipping rate owner'
        );
        _;
    }

    modifier onlyListingOwner(uint256 listingId) {
        require(
            msg.sender == products[listings[listingId].productId].owner,
            'Not the product owner'
        );
        _;
    }

    modifier onlyIfTokenExists(uint256 tokenId) {
        require(tokenId != 0, 'Token does not exist');
        _;
    }

    modifier onlyIfItsYourToken(uint256 tokenId) {
        require(msg.sender == ownerOf(tokenId), 'Not the token owner');
        _;
    }

    function pause() public onlyRole(PAUSE_ROLE) {
        _pause();
    }

    function setTreasury(address newTreasury)
        public
        onlyRole(SET_TREASURY_ROLE)
    {
        require(newTreasury != address(0), 'Treasury cannot be 0');
        treasury = newTreasury;
        emit SetTreasury(treasury, newTreasury);
    }

    function setFee(uint256 newFee) public onlyRole(SET_FEE_ROLE) {
        require(newFee <= ONE_MILLION, 'Fee cannot be more than 100%');
        fee = newFee;
        emit SetFee(newFee);
    }

    function setProductURI(uint256 productId, string memory uri)
        public
        onlyProductOwner(productId)
        onlyRole(SELLER_ROLE)
    {
        products[productId].uri = uri;
        emit SetProductURI(productId, uri);
    }

    function setProductOwner(uint256 productId, address newOwner)
        public
        onlyProductOwner(productId)
        onlyRole(SELLER_ROLE)
    {
        products[productId].owner = newOwner;
        emit SetProductOwner(productId, newOwner);
    }

    function setProductActive(uint256 productId, bool active)
        public
        onlyProductOwner(productId)
        onlyRole(SELLER_ROLE)
    {
        products[productId].active = active;
        emit SetProductActive(productId, active);
    }

    function setListingURI(uint256 listingId, string memory uri)
        public
        onlyListingOwner(listingId)
        onlyRole(SELLER_ROLE)
    {
        listings[listingId].uri = uri;
        emit SetProductURI(listingId, uri);
    }

    function setListingPriceAndToken(
        uint256 listingId,
        uint256 newPrice,
        IERC20 newToken
    ) public onlyListingOwner(listingId) onlyRole(SELLER_ROLE) {
        listings[listingId].price = newPrice;
        listings[listingId].token = newToken;
        emit SetListingPriceAndToken(listingId, newPrice, newToken);
    }

    function setListingSets(uint256 listingId, uint256 newSets)
        public
        onlyListingOwner(listingId)
        onlyRole(SELLER_ROLE)
    {
        listings[listingId].sets = newSets;
        emit SetListingSets(listingId, newSets);
    }

    function setListingPurchasePeriod(
        uint256 listingId,
        uint256 newPurchasePeriodBegins,
        uint256 newPurchasePeriodEnds
    ) public onlyListingOwner(listingId) onlyRole(SELLER_ROLE) {
        listings[listingId].purchasePeriodBegins = newPurchasePeriodBegins;
        listings[listingId].purchasePeriodEnds = newPurchasePeriodEnds;
        emit SetListingPurchasePeriod(
            listingId,
            newPurchasePeriodBegins,
            newPurchasePeriodEnds
        );
    }

    function setListingRedemptionPeriod(
        uint256 listingId,
        uint256 newRedemptionPeriodBegins,
        uint256 newRedemptionPeriodEnds
    ) public onlyListingOwner(listingId) onlyRole(SELLER_ROLE) {
        listings[listingId].redemptionPeriodBegins = newRedemptionPeriodBegins;
        listings[listingId].redemptionPeriodEnds = newRedemptionPeriodEnds;
        emit SetListingRedemptionPeriod(
            listingId,
            newRedemptionPeriodBegins,
            newRedemptionPeriodEnds
        );
    }

    function setShippingRatePrice(uint256 shippingRateId, uint256 price)
        public
        onlyShippingRateOwner(shippingRateId)
        onlyRole(SELLER_ROLE)
    {
        shippingRates[shippingRateId].price = price;
        emit SetShippingRatePrice(shippingRateId, price);
    }

    function setShippingRateOwner(uint256 shippingRateId, address newOwner)
        public
        onlyShippingRateOwner(shippingRateId)
        onlyRole(SELLER_ROLE)
    {
        shippingRates[shippingRateId].owner = newOwner;
        emit SetShippingRateOwner(shippingRateId, newOwner);
    }

    function setShippingRateURI(uint256 shippingRateId, string memory uri)
        public
        onlyShippingRateOwner(shippingRateId)
        onlyRole(SELLER_ROLE)
    {
        shippingRates[shippingRateId].uri = uri;
        emit SetShippingRateURI(shippingRateId, uri);
    }

    function setListingShippingRate(
        uint256 listingId,
        uint256 shippingRateId,
        bool accepted
    ) public onlyListingOwner(listingId) onlyRole(SELLER_ROLE) {
        acceptedShippingRates[listingId][shippingRateId] = accepted;

        emit SetListingShippingRate(listingId, shippingRateId, accepted);
    }

    /// Creates a new product
    function createProduct(string memory uri)
        public
        onlyRole(SELLER_ROLE)
        returns (uint256)
    {
        Product memory product;
        product.uri = uri;
        product.owner = msg.sender;
        product.active = true;

        uint256 productId = _productIdCounter.current();
        _productIdCounter.increment();

        products[productId] = product;
        emit CreateProduct(productId);
        return productId;
    }

    function createShippingRate(uint256 price, string memory uri)
        public
        onlyRole(SELLER_ROLE)
        returns (uint256)
    {
        ShippingRate memory shippingRate;
        shippingRate.price = price;
        shippingRate.uri = uri;
        shippingRate.owner = msg.sender;

        uint256 shippingRateId = _shippingIdCounter.current();
        _shippingIdCounter.increment();

        shippingRates[shippingRateId] = shippingRate;
        emit CreateShippingRate(shippingRateId);

        return shippingRateId;
    }

    /// Creates a new listing for sale
    function createListing(
        uint256 productId,
        string memory uri,
        uint256 supply,
        uint256 price,
        IERC20 token,
        uint256 sets,
        uint256 purchasePeriodBegins,
        uint256 purchasePeriodEnds,
        uint256 redemptionPeriodBegins,
        uint256 redemptionPeriodEnds,
        uint256 defaultShippingRateId
    )
        public
        onlyProductOwner(productId)
        onlyRole(SELLER_ROLE)
        returns (uint256)
    {
        Listing memory listing;
        listing.productId = productId;
        listing.uri = uri;
        listing.supply = supply;
        listing.price = price;
        listing.token = token;
        listing.sets = sets;
        listing.purchasePeriodBegins = purchasePeriodBegins;
        listing.purchasePeriodEnds = purchasePeriodEnds;
        listing.redemptionPeriodBegins = redemptionPeriodBegins;
        listing.redemptionPeriodEnds = redemptionPeriodEnds;

        uint256 listingId = _listingIdCounter.current();
        _listingIdCounter.increment();
        listings[listingId] = listing;

        // Add the default shipping rate to the listing
        acceptedShippingRates[listingId][defaultShippingRateId] = true;

        emit CreateListing(listingId);
        return listingId;
    }

    function purchase(uint256 listingId)
        public
        whenNotPaused
        returns (uint256)
    {
        Listing storage listing = listings[listingId];
        Product memory product = products[listing.productId];

        require(listing.supply > 0, 'Uninitialized listing');
        require(product.owner != address(0), 'Uninitialized product');
        require(
            listing.purchasePeriodBegins <= block.timestamp &&
                block.timestamp <= listing.purchasePeriodEnds,
            'Not within purchase period'
        );
        require(listing.sets > 0, 'No more sets remaining');

        // Reduce sets by 1
        listing.sets--;

        // Mint token & connect it to the listingId
        uint256 tokenId = _mint(msg.sender);
        tokenIdsToListingIds[tokenId] = listingId;

        // Transfer payment
        uint256 toTreasury = (listing.price * fee) / ONE_MILLION;
        uint256 toProductOwner = listing.price - toTreasury;
        listing.token.transferFrom(msg.sender, treasury, toTreasury);
        listing.token.transferFrom(msg.sender, product.owner, toProductOwner);

        emit Purchase(tokenId, msg.sender);

        return tokenId;
    }

    function redeem(
        uint256 tokenId,
        uint256 amount,
        uint256 shippingRateId,
        string memory uri
    ) public whenNotPaused onlyIfItsYourToken(tokenId) {
        Listing storage listing = listings[tokenIdsToListingIds[tokenId]];
        Product memory product = products[listing.productId];

        require(
            acceptedShippingRates[tokenIdsToListingIds[tokenId]][
                shippingRateId
            ],
            'Shipping rate not accepted'
        );
        require(amount > 0, 'Amount must be greater than 0');
        require(
            listing.supply - amount >= 0,
            'Not enough supply in this token'
        );

        // If there's a shipping fee, transfer it.
        uint256 shippingFee = shippingRates[shippingRateId].price;
        if (shippingFee > 0) {
            // Shipping fees are also subject to contract fee
            uint256 toTreasury = (shippingFee * fee) / ONE_MILLION;
            uint256 toProductOwner = shippingFee - toTreasury;
            listing.token.transferFrom(msg.sender, treasury, toTreasury);
            listing.token.transferFrom(
                msg.sender,
                product.owner,
                toProductOwner
            );
        }

        listing.supply -= amount;
        if (listing.supply == 0) {
            _burn(tokenId);
        }

        emit Redeem(tokenId, msg.sender, amount, uri);
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function supplyOf(uint256 tokenId) public view returns (uint256) {
        if (!_exists(tokenId)) {
            return 0;
        }
        return listings[tokenIdsToListingIds[tokenId]].supply;
    }

    /// Mints a token, relatively safely.
    function _mint(address to) internal returns (uint256) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        return tokenId;
    }

    function _burn(uint256 tokenId) internal override(ERC721) {
        super._burn(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
