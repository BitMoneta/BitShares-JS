q = require 'q'

### For plug-in compatibility, migrage calling code to use methods that return a promise. 
###
class Storage
    
    constructor:(@namespace = "default")->
        if Storage.version_name and Storage.version_name.trim() isnt ""
            @namespace = Storage.version_name + '\t' + @namespace
        
        @local_storage = window?.localStorage ||
            # WARNING: node-localstorage may not be atomic
            # https://github.com/lmaccherone/node-localstorage/issues/6
            new (
                require('node-localstorage').LocalStorage
            ) './localstorage-bitsharesjs'

    get:(key)->
        defer = q.defer()
        #console.log '... Storage.getItem', @namespace+'\t'+key
        defer.resolve @local_storage.getItem @namespace+'\t'+key
        defer.promise
    
    set:(key, value)->
        defer = q.defer()
        #console.log '... Storage.setItem ', @namespace+'\t'+key
        @local_storage.setItem @namespace+'\t'+key, value
        defer.resolve()
        defer.promise
    
    ###* @deprecated ###
    getItem:(key)->
        #console.log '... Storage.getItem', @namespace+'\t'+key
        @local_storage.getItem @namespace+'\t'+key
    
    ###* @deprecated ###
    setItem:(key, value)->
        #console.log '... Storage.setItem ', @namespace+'\t'+key
        @local_storage.setItem @namespace+'\t'+key, value
        return
    
    removeItemOrThrow:(key)->
        return if key is undefined
        unless @getItem(key)
            throw Error "Could not remove #{@namespace+'\t'+key}" 
        @removeItem key
        return
    
    removeItem:(key)->
        #console.log '... removeItem ', @namespace+'\t'+key
        @local_storage.removeItem @namespace+'\t'+key
        return
    
    length:()->
        @local_storage.length
    
    key:(index)->
        key = (@local_storage.key index)
        prefix = @namespace+'\t'
        unless key?.indexOf(prefix) is 0
            return undefined
        #console.log '... key', key,'substring',key.substring prefix.length
        key.substring prefix.length
    
    #clear:()->
    #    @local_storage.clear()
    #    return
    
    isEmpty:->
        length = @local_storage.length
        for i in [0...length] by 1
            key = @local_storage.key i
            if key?.indexOf Storage.version_name is 0
                return no
        return yes
    
exports.Storage = Storage