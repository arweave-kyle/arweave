# Arweave HTTP Interface Documentation




### GET network information

Get the current network information.

**Request**

`GET /info`

**Headers**

*None*

**Parameters**

*None*

**Response**

`GET /info`

```json
{
  "network": "arweave.N.1",
  "version": 3,
  "release": 16,
  "height": 78309,
  "current": "o8ahQ55Omd7Fdi4UgGP82bD2-TZ66JYY33NzGyvpLL3_V3wCmsq8NJmnkJl1p_ew",
  "blocks": 97375,
  "peers": 64,
  "queue_length": 0,
  "node_state_latency": 18
}
```


### GET peer list  

Get the list of known peers for the node. Nodes can only respond with peers they currently know about so this will not be an exhaustive list of nodes in the network.

**Request**

`GET /peers`

**Headers**

*None*

**Parameters**

*None*

**Response**

`GET /peers`
```
HTTP/1.1 200 OK
```
```json
[
  "127.0.0.1:1984",
  "127.0.0.1.:1984"
]
```


### GET transaction by ID

Get a JSON transaction record by its ID.

**Request**

`GET /tx/{transaction_id}`

**Headers**

*None*

**Parameters**

Name | Required | Value
------------ | ------------- | -------------
`transaction_id` | Yes | The transaction ID


**Response**

An example JSON object for a data transaction

`GET /tx/BNttzDav3jHVnNiV7nYbQv-GY0HQ-4XXsdkE5K9ylHQ`

```
HTTP/1.1 200 OK
```

```json
{
  "id": "BNttzDav3jHVnNiV7nYbQv-GY0HQ-4XXsdkE5K9ylHQ",
  "last_tx": "jUcuEDZQy2fC6T3fHnGfYsw0D0Zl4NfuaXfwBOLiQtA",
  "owner": "posmE...psEok",
  "tags": [],
  "target": "",
  "quantity": "0",
  "data": "PGh0b...RtbD4",
  "reward": "124145681682",
  "signature": "HZRG_...jRGB-M"
}
```
An example JSON object for a transfer between wallets

`GET /tx/UEVFNJVXSu7GodYbZoldRHGi_tjzNtNcYjeSkxKCpiE`

```
HTTP/1.1 200 OK
```
```json
{
  "id": "UEVFNJVXSu7GodYbZoldRHGi_tjzNtNcYjeSkxKCpiE",
  "last_tx": "knQ5gf4Z_3i-NQ6_jFT2a9zShUOHh4lDZoAUzsWMxMQ",
  "owner": "1nPKv...LjJMc",
  "tags": [],
  "target": "WxLW1MWiSWcuwxmvzokahENCbWurzvwcsukFTGrqwdw",
  "quantity": "46598403314697200",
  "data": "",
  "reward": "321179212",
  "signature": "OYIJU...j9Mxc"
}
```

An example JSON object for a transfer between wallets with a piece of data attached

`GET /tx/3pXpj43Tk8QzDAoERjHE3ED7oEKLKephjnVakvkiHF8`
```
HTTP/1.1 200 OK
```

```json
{
  "id": "3pXpj43Tk8QzDAoERjHE3ED7oEKLKephjnVakvkiHF8",
  "last_tx": "NpeIbi93igKhE5lKUMhH5dFmyEsNGC0fb2Qysggd-kM",
  "owner": "posmE...psEok",
  "tags": [],
  "target": "pEbU_SLfRzEseum0_hMB1Ie-hqvpeHWypRhZiPoioDI",
  "quantity": "10000000000",
  "data": "VGVzdA",
  "reward": "321579659",
  "signature": "fjL0N...f2UMk"
}
```

A pending transaction

`GET /tx/3pXpj43Tk8QzDAoERjHE3ED7oEKLKephjnVakvkiHF8`
```
HTTP/1.1 202 Accepted
```

```json
pending
```


### GET transaction field

Get a single field from a transaction.

**Request**

`GET /tx/{transaction_id}/{field}`

**Headers**

*None*

**Parameters**

Name | Required | Value
------------ | ------------- | -------------
`transaction_id` | Yes | The transaction ID
`field` | Yes | The field to return, acceptable values: `id,last_tx,owner,tags,target,quantity,data,reward,signature`


**Response**

`GET /tx/BNttzDav3jHVnNiV7nYbQv-GY0HQ-4XXsdkE5K9ylHQ/last_tx`

```http
HTTP/1.1 200 OK
```

```
jUcuEDZQy2fC6T3fHnGfYsw0D0Zl4NfuaXfwBOLiQtA
```

### GET transaction data

Retrieve the data segment of the transaction body in its original format. If the transaction was an archived webpage then the result will be browser rendererable HTML, if the original data was a binary (image, pdf, etc) then the response will be in that format.


**Request**

`/tx/{transaction_id}/data.{extension}`

**Headers**

*None*
  
**Parameters**

Name | Required | Value
------------ | ------------- | -------------
`transaction_id` | Yes | The transaction ID
`extension` | Yes | For HTML/webpages use `data.html` to serve browser renderable HTML with `Content-Type: text/html` header. If a binary transaction is posted with a `Content-Type` tag, then that `Content-Type` value will be used to set the `Content-Type` header on the response.


**Response**

`tx/BNttzDav3jHVnNiV7nYbQv-GY0HQ-4XXsdkE5K9ylHQ/data.html`

```http
HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
Content-Length: 1033478
Content-Type: text/html
```

```html
<html lang="en-GB" class="b-pw-1280 no-touch orb-js id-svg bbcdotcom ads-enabled bbcdotcom-init bbcdotcom-responsive bbcdotcom-async bbcdotcom-ads-enabled orb-more-loaded  bbcdotcom-group-5" id="responsive-news">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=1">
...
```



### GET transaction price

Returns an estimated cost for a transaction of the given size, the returned amount is in winston (the smallest division of AR, 1 AR = 1000000000000 winston).

- For data transactions `/price/{number_of_bytes}` should be used.
- For transfers to other wallets `/price/{number_of_bytes}/{target_address}` should be used.
- For transfers to other wallets with data attached `/price/{number_of_bytes}/{target_address}` should be used.

The first transfer to a new wallet will incur an additional fee of 0.25 AR, this is to disincentivise the creation and usage of superfluous wallets.


**Request**

`/price/{number_of_bytes}/{target_address}`

**Headers**

*None*
  
**Parameters**

Name | Required | Value
------------ | ------------- | -------------
`number_of_bytes` | Yes | The number of bytes to be used in the `data` field in a transaction.
`target_address` | No | The target wallet address, if required.


**Response**

A string containing the estimated cost of the transaction in Winston.

```
1896296296
```



### GET last transaction from wallet address

Get the ID of the last transaction made from the given wallet address. You'll need this endpoint to build a new transaction.


**Request**

`GET /wallet/{wallet_address}/last_tx`

**Headers**

*None*
  
**Parameters**

Name | Required | Value
------------ | ------------- | -------------
`wallet_address` | Yes | The wallet address


**Response**

`GET wallet/WxLW1MWiSWcuwxmvzokahENCbWurzvwcsukFTGrqwdw/last_tx`

```json
-YW9sdrCIDyrdNAKqDjQjChYFQrEbRqwl-2feATE770
```


### GET wallet balance from address

Get the balance for the given wallet address.
The returned amount is in winston (the smallest division of AR, 1 AR = 1000000000000 winston).

**Request**

`GET /wallet/{wallet_address}/balance`

**Headers**

*None*
  
**Parameters**

Name | Required | Value
------------ | ------------- | -------------
`wallet_address` | Yes | The wallet address


**Response**

`GET wallet/WxLW1MWiSWcuwxmvzokahENCbWurzvwcsukFTGrqwdw/balance`

```json
22505687150866594
```


### GET block by ID

Get a block by its ID (indep_hash).

**Request**

`GET /block/hash/{block_id}`

**Headers**

Name | Required | Value
------------ | ------------- | -------------
`X-Block-Format` | No | Acceptable values: `1`,`2`. The V1 block format contained the full `hash_list` and `wallet_list` as arrays of hashes. The V2 format has `hash_list` removed entirely and `wallet_list` is simply a hash of the wallet_list for the given block. These lists can now be found on the X and Y endpoints.

**For backwards compaiability the default format is V1, but we *strongly* recommend setting this header and using the V2 format as this will be the default in future releases.**

**Parameters**

Name | Required | Value
------------ | ------------- | -------------
`block_id` | Yes | Block ID (indep_hash)

**Response**

```json
{
    "nonce": "AQAAAQABAAEBAQAAAAAAAQEAAQABAAABAAABAQEBAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "previous_block": "fVOpb6C3yjC3-XaBS0865fS_wH3IbIX08ZeZHB7HoHh12X8GD-X8jMJFzU0r9BoE",
    "timestamp": 1541689343,
    "last_retarget": 1541688945,
    "diff": 34,
    "height": 78415,
    "hash": "AAAAAAc1al2KXr-MdSn2WG_Aqal613yxKlH2uCLpV5CF5H3RzI7uDwjn50E64lpm",
    "indep_hash": "hN-K2p7XmH3J6JdKONct3lHX-81NPcv0_0u02k1Ha16kVo2na6Czx1rsQiXt9vcg",
    "txs": [],
    "wallet_list": "ESzKam5rmvmlI1K-L7U5BKO50MtNt52INExzZBAvWA0",
    "reward_addr": "bfgWCyS7pYS4fXUDYblFxBLRugDiGMSR0_kP2vMz6oE",
    "tags": [],
    "reward_pool": 4925,
    "weave_size": 160604943,
    "block_size": 0
}
```

### GET current block

Retrieve a JSON array representing the contents of the current block, the network head.

**Request**

`GET /block/current`

**Headers**

Name | Required | Value
------------ | ------------- | -------------
`X-Block-Format` | No | Acceptable values: `1`,`2`. The V1 block format contained the full `hash_list` and `wallet_list` as arrays of hashes. The V2 format has `hash_list` removed entirely and `wallet_list` is simply a hash of the wallet_list for the given block. These lists can now be found on the X and Y endpoints.

**For backwards compaiability the default format is V1, but we *strongly* recommend setting this header and using the V2 format as this will be the default in future releases.**

**Parameters**

Name | Required | Value
------------ | ------------- | -------------
`block_id` | Yes | Block ID (indep_hash)

**Response**

```json
{
    "nonce": "AQAAAQABAAEBAQAAAAAAAQEAAQABAAABAAABAQEBAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "previous_block": "fVOpb6C3yjC3-XaBS0865fS_wH3IbIX08ZeZHB7HoHh12X8GD-X8jMJFzU0r9BoE",
    "timestamp": 1541689343,
    "last_retarget": 1541688945,
    "diff": 34,
    "height": 78415,
    "hash": "AAAAAAc1al2KXr-MdSn2WG_Aqal613yxKlH2uCLpV5CF5H3RzI7uDwjn50E64lpm",
    "indep_hash": "hN-K2p7XmH3J6JdKONct3lHX-81NPcv0_0u02k1Ha16kVo2na6Czx1rsQiXt9vcg",
    "txs": [],
    "wallet_list": "ESzKam5rmvmlI1K-L7U5BKO50MtNt52INExzZBAvWA0",
    "reward_addr": "bfgWCyS7pYS4fXUDYblFxBLRugDiGMSR0_kP2vMz6oE",
    "tags": [],
    "reward_pool": 4925,
    "weave_size": 160604943,
    "block_size": 0
}
```


### POST transaction to network

Submit a new transaction to the network.

**Request**

`POST /tx`

**Headers**

*None*

**Parameters**

*None*

**Body**

Name | Required | Value
------------ | ------------- | -------------
`id` | Yes | The transaction ID, this is a SHA-256 hash of the transaction signature which is then base64 URL encoded.
`last_tx` | Yes | The last transaction id from the sending wallet, see X
`owner` | Yes | The full RSA modulus value from the sending wallet base64 URL encoded. The modulus is the `n` value from the JWK file.
`target` | Yes | The recipient address (if sending AR to another wallet). Use an empty string (`""`) for data transactions.
`quantity` | Yes | The amount in winston to transfer to the `target` wallet. Use an empty string (`""`) for data transactions.
`data` | Yes | The data to be uploaded, base64 URL encoded.
`reward` | Yes | The transaction fee which can be calulated using X
`signature` | Yes | The transaction signature, base64 URL encoded.


> **Note** `quantity` and `reward` values are always winston strings. This is to allow for interoperability between environments that do not accommodate arbitrary-precision arithmetic. JavaScript for instance stores all numbers as double precision floating point values and as such cannot natively express the integer number of winston. Providing these values as strings allows them to be directly loaded into most 'bignum' libraries.

**Request**

`POST /tx`

```json
{
  "id": "BNttzDav3jHVnNiV7nYbQv-GY0HQ-4XXsdkE5K9ylHQ",
  "last_tx": "jUcuEDZQy2fC6T3fHnGfYsw0D0Zl4NfuaXfwBOLiQtA",
  "owner": "posmE...psEok",
  "tags": [],
  "target": "",
  "quantity": "0",
  "data": "PGh0b...RtbD4",
  "reward": "124145681682",
  "signature": "HZRG_...jRGB-M"
}
```

**Response**

Accepted
```http
HTTP/1.1 200 OK
```

Invalid transaction
```http
HTTP/1.1 400 Bad Request
```

# Help

If you have questions or comments on the Arweave HTTP interface you can get in touch by
finding us on [Twitter](https://twitter.com/ArweaveTeam), [Reddit](https://www.reddit.com/r/arweave), [Discord](https://discord.gg/2ZpV8nM) or by emailing us at team@arweave.org.

# License
The Arweave project is released under GNU General Public License v2.0.
See [LICENSE](LICENSE.md) for full license conditions.
