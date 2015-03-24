config = require './config'
LE = require('../common/exceptions').LocalizedException
q = require 'q'
{Storage} = require '../common/storage'
BigInteger = require 'bigi'

###* 
    Chain interface is generally the interface that is useful for both chain 
    database and pending chain state PLUS general helper functions that don't 
    depend on the current chain state.
###
class ChainInterface
    
    constructor:(@blockchain_api, chain_id)->
        throw new Error 'required chain_id' unless chain_id
        @storage = new Storage chain_id
    
    ChainInterface.is_valid_account_orThrow=(account_name)->
        unless ChainInterface.is_valid_account_name account_name
            LE.throw 'jslib_wallet.invalid_account_name',[account_name]
        return
            
    ChainInterface.is_valid_account_name=(account_name)->
        return false unless account_name
        return false if account_name.length < config.BTS_BLOCKCHAIN_MIN_NAME_SIZE
        return false if account_name.length > config.BTS_BLOCKCHAIN_MAX_NAME_SIZE
        return false unless /^[a-z]/i.test(account_name) # starts with alpha
        return false unless /[a-z0-9]$/i.test(account_name)
        return false if /[A-Z]$/.test(account_name)
        
        subname = account_name
        supername = ""
        dot = account_name.indexOf '.'
        if dot isnt -1
            subname = account_name.substring 0, dot
            supername = account_name.substring dot+1
        return false unless /[a-z0-9]$/i.test(subname) or /[A-Z]$/.test(subname)
        return false unless /[a-z0-9-\.]$/i.test subname
        return true if supername is ""
        ChainInterface.is_valid_acccount_name supername
    
    #ChainInterface.isSafeInteger_orThrow:(precision)->
    #    unless Number.isSafeInteger new Number number_string
    #        throw new Error "Number #{number_string} is too large"
    
    REAL128_PRECISION = BigInteger("10").pow 18
    
    ChainInterface.string_to_Ratio128=(number_string)->
        throw new Error "Missing parameter: number_string" unless number_string
        number_string = ""+number_string if typeof number_string is "number"
        console.log '... number_string', number_string
        number_string = number_string.trim()
        number_parts = number_string.match /^([0-9]*)\.?([0-9]*)$/
        unless number_parts
            throw new Error "Invalid number: #{number_string}"
        
        int_part = number_parts[1]
        decimal_part = number_parts[2]
        
        ratio = if int_part isnt undefined
            lhs = BigInteger(int_part)
            if lhs.bitCount() > 128 # 128 bit limit here has nothing to do with precision below
                throw new Error "Integer digits require #{lhs.bitCount()} bits which exceeds 128 bits"
            lhs.multiply REAL128_PRECISION
        else
            BigInteger.ZERO
        
        if decimal_part isnt undefined
            throw new Error "More than 18 decimal digits" if decimal_part.length > 18
            frac_magnitude = BigInteger("10").pow decimal_part.length
            ratio = ratio.add BigInteger(decimal_part).multiply (
                REAL128_PRECISION.divide frac_magnitude
            )
        ratio
    
    ###* @return asset ###
    ChainInterface.to_ugly_asset=(amount_to_transfer, asset)->
        #amount = ChainInterface.toNumber_orThrow amount_to_transfer # TODO
        amount = amount_to_transfer
        amount *= asset.precision
        #example: 100.500019 becomes 10050001
        amount = parseInt amount.toString().split('.')[0]
        amount:amount
        asset_id:asset.id
    
    ChainInterface.to_ugly_price=(
        price_string, base_asset, quote_asset
        needs_satoshi_conversion # do_precision_dance
    )->
        throw new Error 'price is required' unless price_string
        throw new Error 'base_asset is required' unless base_asset
        throw new Error 'quote_asset is required' unless quote_asset
        ratio = ChainInterface.string_to_Ratio128 price_string
        if needs_satoshi_conversion
            ratio = ratio.multiply BigInteger ""+quote_asset.precision
            ratio = ratio.divide BigInteger ""+base_asset.precision
        ratio:ratio
        base:base_asset.id
        quote:quote_asset.id
    
    ChainInterface.get_active_key=(hist)->
        hist = hist.sort (a,b)-> 
            if a[0] < b[0] then -1 
            else if a[0] > b[0] then 1 
            else 0
        hist[hist.length - 1][1]
    
    valid_unique_account:(account_name)->
        defer = q.defer()
        try
            ChainInterface.is_valid_account_orThrow account_name
            @blockchain_api.get_account(account_name).then (resp)->
                if resp
                    error = new LE 'jslib_blockchain.account_already_exists', [account_name]
                    defer.reject error
                else
                    defer.resolve()
            , (error)->
                defer.resolve error
            #.done() null ptr in browser
        catch error
            defer.reject error.stack
        defer.promise
    
    ###* Use cache or query ###
    get_asset:(name_or_id, refresh_cache = false)->
        cache_key = 'chain-asset-'+name_or_id
        unless refresh_cache
            asset_string = @storage.getItem cache_key
            if asset_string
                defer = q.defer()
                defer.resolve JSON.parse asset_string
                return defer.promise
        
        @blockchain_api.get_asset(name_or_id).then (asset)=>
            unless asset
                return null
            unless asset.precision
                #ref: wallet::transfer_asset_to_address
                asset.precision = 1
                console.log 'INFO using default precision 1',asset
            asset_string = JSON.stringify asset,null,0
            @storage.setItem cache_key, asset_string
            asset
    
    # refresh_assets:-> blockchain_list_assets probably once a day or if the user requests a refresh ...
    ###* Default fee is in the base asset ID ###
    convert_base_asset_amount:(desired_asset_name_or_id = 0, amount)->
        throw new Error "amount is required" unless amount
        throw new Error "amount should be an integer" if amount.amount
        defer = q.defer()
        if desired_asset_name_or_id is 0
            defer.resolve
                asset_id: 0
                amount: amount
            return defer.promise
        
        target_asset = @get_asset desired_asset_name_or_id
        base_asset = @get_asset 0
        q.all([target_asset, base_asset]).spread (target_asset, base_asset)=>
            if target_asset.id is 0
                asset_id: 0
                amount: amount
            else
                @blockchain_api.market_status(target_asset.symbol, base_asset.symbol).then (market)->
                    feed_price = market.current_feed_price
                    unless market.current_feed_price
                        asset_id: 0
                        amount: amount
                    else
                        fee = (amount / base_asset.precision) * feed_price
                        asset_id: target_asset.id
                        amount: Math.ceil fee * target_asset.precision

exports.ChainInterface = ChainInterface
