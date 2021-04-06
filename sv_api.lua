/*
*   @package      	: rcore
*   @module       	: ipapi
*   @author       	: Richard [http://steamcommunity.com/profiles/76561198135875727]
*   @copyright     	: (C) 2019
*
*   LICENSOR HEREBY GRANTS LICENSEE PERMISSION TO MODIFY AND/OR CREATE DERIVATIVE WORKS BASED AROUND THE
*   SOFTWARE HEREIN, ALSO, AGREES AND UNDERSTANDS THAT THE LICENSEE DOES NOT HAVE PERMISSION TO SHARE,
*   DISTRIBUTE, PUBLISH, AND/OR SELL THE ORIGINAL SOFTWARE OR ANY DERIVATIVE WORKS. LICENSEE MUST ONLY
*   INSTALL AND USE THE SOFTWARE HEREIN AND/OR ANY DERIVATIVE WORKS ON PLATFORMS THAT ARE OWNED/OPERATED
*   BY ONLY THE LICENSEE.
*
*   YOU MAY REVIEW THE COMPLETE LICENSE FILE PROVIDED AND MARKED AS LICENSE.TXT
*
*   BY MODIFYING THIS FILE -- YOU UNDERSTAND THAT THE ABOVE MENTIONED AUTHORS CANNOT BE HELD RESPONSIBLE
*   FOR ANY ISSUES THAT ARISE FROM MAKING ANY ADJUSTMENTS TO THIS SCRIPT. YOU UNDERSTAND THAT THE ABOVE
*   MENTIONED AUTHOR CAN ALSO NOT BE HELD RESPONSIBLE FOR ANY DAMAGES THAT MAY OCCUR TO YOUR SERVER AS A
*   RESULT OF THIS SCRIPT AND ANY OTHER SCRIPT NOT BEING COMPATIBLE WITH ONE ANOTHER.
*/

/*
*   standard tables and localization
*/

local base                  = rlib
local access                = base.a
local helper                = base.h
local storage				= base.s
local design			    = base.d
local ui				    = base.i

/*
*   module calls
*/

local mod, pf           	= base.modules:req( 'ipapi' )
local cfg               	= base.modules:cfg( mod )

/*
*   Localized translation func
*/

local function ln( ... )
    return base:translate( mod, ... )
end

/*
*	prefix ids
*/

local function pref( str, suffix )
    local state = not suffix and mod or isstring( suffix ) and suffix or false
    return base.get:pref( str, state )
end

/*
*   Localized cmd func
*
*   @source : lua\autorun\libs\_calls
*   @param  : str t
*   @param  : tbl { ... }
*/

local function call( t, ... )
    return rlib:call( t, ... )
end

/*
*   Localized translation func
*/

local function lang( ... )
    return rlib:translate( mod, ... )
end

local FAIL_COUNT 	= 3
local RETRY_TIME 	= 3
local GEO_URL 		= 'http://api.ipapi.com/%s?access_key=%s&format=1'

local res_cached	= { }

/*
*	ipapi :: get
*
*	@param  : str ip
*	@param  : func cb
*	@param  : func failure
*/

function mod.geoip.get( calling_ply, ip, cb, failure )
    timex.expire( 'ipconn_check_geo' )

    if res_cached[ ip ] then
        cb( res_cached[ ip ] )
    else
        local uri = string.format( GEO_URL, ip, cfg.api_key )
        http.Fetch( uri, function( b, l, h, c )
            if b[ 1 ] == '{' then
                local res           = util.JSONToTable( b )
                res_cached[ ip ]    = res

                if cb then
                    cb( res )
                else
                    return res
                end
            else
                rlib:log( 2, '[ %s ] :: %s failed to lookup %q with error %q', mod.name, 'ipapi', ip, b )
            end
        end, function( )
            if not calling_ply then return end
            calling_ply.ipconn_fails = ( calling_ply.ipconn_fails and ( calling_ply.ipconn_fails < 3 and calling_ply.ipconn_fails + 1 ) ) or 1

            local str_fails = tostring( calling_ply.ipconn_fails )
            rlib.msg:target( calling_ply, mod.name, 'Failed to fetch data requested [ Attempt #' .. str_fails )

            if calling_ply.ipconn_fails == FAIL_COUNT then
                timex.expire( 'ipconn_check_geo' )
                if failure then failure( ) end
            else
                timex.create( 'ipconn_check_geo', RETRY_TIME, 1, function( )
                    mod.geoip.get( calling_ply, ip, cb, failure )
                end )
            end
        end )
    end
end

/*
*	ipapi :: player authentication
*
*	@param  : ply target
*/

local function geoip_pauth( target )

    /*
    *	validate ply
    */

    if not helper.ok.ply( target ) then return end

    /*
    *	declarations
    */

    local target_ip		= target:IPAddress( )
    local ip, port 		= helper.str:split_addr( target_ip )

    /*
    *	halt :: ip not specified
    */

    if not ip then
        rlib:log( 2, '[%s] module specified invalid ip address', mod.name )
        return false
    end

    mod.geoip.get( nil, ip, function( data )

        if not helper.ok.ply( target ) then return end

        target:SetCountryCode( data.country_code or 'NA' )
        target:SetCountryName( data.country_name or 'local' )
        target:SetContinentName( data.continent_name or 'local' )

    end )

end
rhook.new.gmod( 'PlayerInitialSpawn', 'ipconn_geoip_pauth', geoip_pauth )

/*
*	geoip :: manual ip check
*
*	@param  : str ip
*	@param  : ply calling_ply
*/

local function geoip_checkip( calling_ply, ip )

    /*
    *	permissions
    */

    if not access:allow( calling_ply, 'ipconn_geoip_ip', mod ) then return end

    /*
    *	halt :: ip not specified
    */

    if not ip then
        rlib:log( 2, '[ %s ] module specified invalid ip address', mod.name )
        return false
    end

    /*
    *	halt :: protected users
    */

    for ply in helper.get.players( ) do
        local ply_cache_ip = ply:IPAddress( )
        local ply_ip, ply_port = helper.str:split_addr( ply_cache_ip )
        if ply_ip == ip then
            rlib.msg:target( calling_ply, mod.name, 'Geo-IP', 'Cannot perform this action on protected user', rlib.settings.cmsg.clrs.target_tri, ply:Nick( ) )
            return false
        end
    end

    /*
    *	get ip information
    */

    mod.geoip.get( ip, function( data )

        /*
        *	halt :: invalid data
        */

        if not data then
            rlib.msg:target( calling_ply, mod.name, 'Geo-IP', 'Error occured while fetching geoip data for', rlib.settings.cmsg.clrs.target_tri, tostring( ip ) )
            return false
        end

        local ip_address		= ip
        local continent_name 	= data.continent_name or 'na'
        local country_code 		= data.country_code or 'na'
        local country_name 		= data.country_name or 'na'
        local region_name       = data.region_name or 'na'
        local longitude 		= data.longitude or 'na'
        local latitude 			= data.latitude or 'na'

        local location          = string.format( '%s, %s, %s', continent_name, country_name, region_name )
        local longlat           = string.format( '%s, %s', longitude, latitude )

        rlib.msg:target( calling_ply, mod.name, 'Geo-IP', 'Target', rlib.settings.cmsg.clrs.target_tri, tostring( ip_address ), rlib.settings.cmsg.clrs.msg, '\n[ location ]', rlib.settings.cmsg.clrs.target_tri, tostring( location ), rlib.settings.cmsg.clrs.msg, '\n[ long/lat ]', rlib.settings.cmsg.clrs.target_tri, tostring( longlat ) )
    end,
    function( )
        print( 'issue' )
    end )
end
rhook.new.rlib( 'ipconn_api_checkip', 'ipconn_api_checkip', geoip_checkip )

/*
*	geoip :: check player
*
*	@param  : ply calling_ply
*	@param  : ply target_ply
*/

local function geoip_checkply( calling_ply, target_ply )

    /*
    *	validation
    */

    if not access:allow( calling_ply, 'ipconn_geoip_ply', mod ) then return end
    if not helper.ok.ply( target_ply ) then return end

    /*
    *	declarations
    */

    local target_ip		    = target_ply:IPAddress( )
    local ip, port 		    = helper.str:split_addr( target_ip )

    /*
    *	halt :: ip not specified
    */

    if not ip then
        base:log( 2, '[ %s ] module specified invalid ip address', mod.name )
        return false
    end

    /*
    *	get ip information
    */

    mod.geoip.get( calling_ply, ip, function( data )

        /*
        *	validate ply
        */

        if not helper.ok.ply( target_ply ) then return end

        /*
        *	halt :: invalid data
        */

        if not data then
            rlib.msg:target( calling_ply, mod.name, 'Geo-IP', 'Error occured while fetching geoip data for player', rlib.settings.cmsg.clrs.target_tri, target_ply:Nick( ) )
            return false
        end

        local ip_address		    = ip and not 'Error!' or 'localhost'
        local continent_name 	    = data.continent_name or 'na'
        local country_code 		    = data.country_code or 'na'
        local country_name 		    = data.country_name or 'na'
        local region_name           = data.region_name or 'na'
        local longitude 		    = data.longitude or 'na'
        local latitude 			    = data.latitude or 'na'

        local location              = string.format( '%s, %s, %s', continent_name, country_name, region_name )
        local longlat               = string.format( '%s, %s', longitude, latitude )

        rlib.msg:target( calling_ply, mod.name, 'Geo-IP', 'Target', rlib.settings.cmsg.clrs.target_tri, tostring( ip_address ), rlib.settings.cmsg.clrs.msg, '\n[ location ]', rlib.settings.cmsg.clrs.target_tri, tostring( location ), rlib.settings.cmsg.clrs.msg, '\n[ long/lat ]', rlib.settings.cmsg.clrs.target_tri, tostring( longlat ) )

    end,
    function( )
        print( 'issue' )
    end )

end
rhook.new.rlib( 'ipconn_api_checkply', 'ipconn_api_checkply', geoip_checkply )