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

/*
*   module calls
*/

local mod, pf           	= base.modules:req( 'ipapi' )
local cfg               	= base.modules:cfg( mod )
local db                    = mod.database

/*
*   Localized cmd func
*/

local function call( t, ... )
    return base:call( t, ... )
end

/*
*   Localized translation func
*/

local function ln( ... )
    return base:translate( mod, ... )
end

/*
*	playerauth_vpn
*
*	checks player to see if they are on a vpn it will either check and check ALL players who connect
*	and use a vpn, or only ones that have been blocked from connecting to the server with a vpn
*   (depending on the settings)
*
*	@param  : ply pl
*/

local function vpn_pauth( pl )

    /*
    *	anyone with this permission will bypass vpn checks
    */

    --if access:allow( pl, 'ipconn_vpn_nocheck', mod ) or access:bIsDev( pl ) then return end

    /*
    *	start vpn check timer
    */

    timex.simple( 'ipconn_vpn_pauth', 3, function( )

        if not helper.ok.ply( pl ) then return end

        local env                   = storage.get.env( mod )
        local uri                   = tostring( env.api )

                                    if not uri then
                                        base:log( RLIB_LOG_ERR, 'VPN check err - no valid service provided. Check your module config' )
                                        return
                                    end

        /*
        *	player info
        */

        local uid		            = pl:sid( )
        local ip, port 		        = helper.str:split_addr( pl:IPAddress( ) )
        local now                   = os.date( '%Y-%m-%d %H:%M:%s' )

        ip                          = '139.99.159.20'

        /*
        *	create api url
        */

        if helper.ok.ip( ip ) then
            uri = string.format( uri, ip )
        end

        /*
        *	insert / update query
        */

        db:query(
            [[
                ]] .. db.InsertQuery .. [[ INTO ]] .. db:table( 'users' ) .. [[ ( uid, host, connections, time_registered, time_updated )
                VALUES ( {uid}, {host}, '1', {now}, {now} ) ON DUPLICATE KEY UPDATE host = {host}, connections = connections + 1, time_updated = {now}
            ]],
        { uid = uid, host = ip, now = now } )

        /*
        *	check user vpn
        */

        http.Fetch( uri, function( b, l, h, c )
            if c ~= 200 then return end
            if b:len( ) < 2 then return end

            local data	        = util.JSONToTable( b )
            local status	    = data[ 'result' ]

            /*
            *	@condition  : status = success
            */

            if data[ 'status' ] == 'success' then
                status          = tonumber( status ) or 0

                local bIsVpn    = helper:int2bool( status )
                local kline	    = cfg.kick_msg or 'Game does not allow use of VPNs'
                local bKick     = false

                /*
                *	@cond   : cfg.server_block  = true
                *             bIsVpn            = true
                */

                if ( cfg.server_block and bIsVpn ) then

                    -- helper.ply:kick( pl, kline, 'sys' )
                    bKick = true

                /*
                *	@cond   : cfg.server_block  = false
                *             bIsVpn            = true
                */

                elseif not cfg.server_block and bIsVpn then
                    db:query( 'SELECT is_blocked FROM ' .. db:gettable( 'users' ) .. ' WHERE uid = {uid}', { uid = uid }, function( q, ok, qry )
                        local ply_isvpnblock	= qry[ 1 ].is_blocked or ''
                        local chk_isblocked 	= helper.util:toggle( ply_isvpnblock )

                        if chk_isblocked then
                            --helper.ply:kick( pl, kline, 'sys' )
                            bKick = true
                        end
                    end )
                end
            else
                base:log( RLIB_LOG_ERR, 'VPN check err - status return failed' )
            end

            /*
            *	welcome messages
            */

            timex.create( pl:aid64( mod.id, 'onjoin', 'delay' ), 1, 1, function( )
                if cfg.welcome.enabled and isfunction( cfg.welcome.action ) then
                    cfg.welcome.action( pl, data[ 'Country' ] )
                end
            end )

            /*
            *	alogs > kick message
            */

            if bKick then
                hook.Run( 'alogs.send', 'Security', pl:Name( ) .. ' attempted to connect using a blocked vpn on ( ' .. pl:IPAddress( ) .. ' )' )
            end

        end,
        function( err )

        end )

    end )

end
rhook.new.gmod( 'PlayerAuthed', 'ipconn_vpn_pauth', vpn_pauth )
rcc.new.gmod( 'vpn', vpn_pauth )

/*
*	vpn :: api
*
*	checks player to see if they are on a vpn through the api url.
*
*	@param  : ply pl
*	@param  : ply requester
*/

function mod:vpn_check( pl, requester )

    if not access:allow_throwExcept( requester, 'ipconn_vpn_ply', mod ) then return end
    if not pl then return end

    local src           = pl
    if helper.ok.ply( pl ) then
        src             = pl:IPAddress( )
    elseif helper.ok.ip( pl ) then
        src             = pl
    end

    local env           = storage.get.env( mod )
    local uri           = tostring( env.api )

    if not uri then
        rlib:log( 2, 'VPN check err - no valid service provided. Check your module config' )
        return
    end

    local data	            = { }
    local bIsVpn	        = false
    local target_ip	        = src
    local ip, port          = helper.str:split_addr( target_ip )

    if helper.ok.ip( ip ) then
        uri = string.format( uri, ip )
    end

    http.Fetch( uri, function( b, l, h, c )
        if c == 200 and string.len( b ) > 0 then
            data			    = util.JSONToTable( b )
            local status	    = data[ 'result' ]
            status              = tonumber( status ) or 0
            bIsVpn 				= helper:int2bool( status )

            local resp	        = bIsVpn and ' running a vpn ' or ' not running a vpn '

            if istable( data ) and data[ 'result' ] then
                rlib.msg:target( requester, mod.name, 'VPN', 'Status: user', rlib.settings.cmsg.clrs.target_tri, pl:Name( ), rlib.settings.cmsg.clrs.target_sec, resp, rlib.settings.cmsg.clrs.tri, '( ' .. ip .. ' )' )
            end
        end
    end,
    function( err )
        rlib.msg:target( requester, mod.name, 'VPN', 'Error returning vpn status for player', rlib.settings.cmsg.clrs.target_tri, pl:Name( ) )
    end )

end
rhook.new.rlib( 'ipconn_vpn_check', 'ipconn_vpn_check', mod.vpn_check )

/*
*	concommand :: vpn :: check user
*
*	check user for vpn
*
*	@param	: ply ply
*	@param	: str cmd
*	@param	: tbl args
*
*	@usage	: ipconn.vpn.check < username >
*/

local function rcc_vpn_check( ply, cmd, args )

    if not access:bIsRoot( ply ) then return end

    local target = args and args[ 1 ]
    if not target then
        rlib.msg:target( ply, 'VPN', 'You must supply a valid partial', rlib.settings.cmsg.clrs.target_tri, 'player name', rlib.settings.cmsg.clrs.msg, 'to search for' )
        return
    end

    local c_results, result = helper.who:name_wc( target )
    if c_results > 1 then
        rlib.msg:route( ply, 'VPN', 'More than one result was found, type more of the name. Place in quotes to use first and last name. Example:', rlib.settings.cmsg.clrs.target_tri, '\"John Doe\"' )
        return
    elseif not c_results or c_results < 1 then
        rlib.msg:route( ply, 'VPN', 'No results found! Place in quotes to use first and last name. Example:', rlib.settings.cmsg.clrs.target_tri, '\"John Doe\"' )
        return
    else
        if not helper.ok.ply( result ) then
            rlib.msg:route( ply, 'VPN', 'not a valid player' )
        else
            local res = mod:vpn_check( result, ply )
        end
    end

end
rcc.new.rlib( 'ipconn_vpn_check', rcc_vpn_check )

/*
*	concommand :: vpn :: setuser
*
*	set a users vpn restrictions
*
*	@param	: ply ply
*	@param	: str cmd
*	@param	: tbl args
*
*	@usage  : ipconn.vpn.setblock < username > < enable|disable >
*/

local function rcc_vpn_setblock( ply, cmd, args )

    if not access:bIsRoot( ply ) then return end

    local target = args and args[ 1 ]
    if not target then
        rlib.msg:route( ply, 'VPN', 'You must supply a valid partial', rlib.settings.cmsg.clrs.target_tri, 'player name', rlib.settings.cmsg.clrs.msg, 'to search for' )
        return
    end

    local param = args and args[ 2 ]
    if not param then
        rlib.msg:route( ply, 'VPN', 'You must define the property to set' )
        return
    end

    local uid		    = ply:SteamID64( )
    local chk_vpnblock	= helper.util:toggle( param )
    local bIsBlocked	= chk_vpnblock and 1 or 0

    db:query(
    [[
        UPDATE ]] .. db:gettable( 'users' ) .. [[ SET is_blocked = {bIsBlocked}
        WHERE uid = {uid}
    ]], { uid = uid, bIsBlocked = bIsBlocked } )

    if db.settings.debug_enabled then
        local toggle = bIsBlocked and 'yes' or 'no'
        rlib:log( 6, '[DB] update player [ %s ] is_vpnblock => [ %s ]', ply:Name( ), tostring( toggle ) )
    end

end
rcc.new.rlib( 'ipconn_vpn_setblock', rcc_vpn_setblock )

/*
*	concommand :: vpn :: checkblock
*
*	determines if a player is allowed to connect using a vpn.
*
*	@param  : ply ply
*	@param  : str cmd
*	@param  : tbl args
*
*	@usage  : ipconn.vpn.checkblock < username >
*/

local function rcc_vpn_checkblock( ply, cmd, args )

    if not access:bIsRoot( ply ) then return end

    local target = args and args[ 1 ]
    if not target then
        rlib.msg:route( ply, 'VPN', 'You must supply a valid partial', rlib.settings.cmsg.clrs.target_tri, 'player name', rlib.settings.cmsg.clrs.msg, 'to search for' )
        return
    end

    local c_results, result = helper.who:name_wc( target )
    if c_results > 1 then
        rlib.msg:route( ply, 'VPN', 'More than one result was found, type more of the name. Place in quotes to use first and last name. Example:', rlib.settings.cmsg.clrs.target_tri, '\"John Doe\"' )
        return
    elseif not c_results or c_results < 1 then
        rlib.msg:route( ply, 'VPN', 'No results found! Place in quotes to use first and last name. Example:', rlib.settings.cmsg.clrs.target_tri, '\"John Doe\"' )
        return
    else
        if not helper.ok.ply( result[ 0 ] ) then
            rlib.msg:route( ply, 'VPN', 'No valid player found' )
            return
        else
            result                  = result[ 0 ]

            local uid		        = result:SteamID64( )
            local target_ip		    = result:IPAddress( )
            local ip, port 		    = helper.str:split_addr( target_ip )

            db:query( 'SELECT is_blocked FROM ' .. db:gettable( 'users' ) .. ' WHERE uid = {uid}', { uid = uid }, function( q, ok, data )
                if not ok then return end

                local user_db = data[ 1 ]
                if not db:bHasData( data ) or not db:bDataOK( user_db.is_blocked ) or helper.str:isempty( user_db.is_blocked ) then
                    rlib.msg:route( ply, 'VPN', 'Status: user', rlib.settings.cmsg.clrs.target_tri, result:Name( ), rlib.settings.cmsg.clrs.msg, 'is', rlib.settings.cmsg.clrs.target_tri, 'allowed', rlib.settings.cmsg.clrs.msg, 'to connect with vpns', rlib.settings.cmsg.clrs.target_sec, '( ' .. ip .. ' )' )
                    return
                end

                local is_vpnblock = data[ 1 ].is_blocked
                if is_vpnblock and is_vpnblock ~= nil then
                    if is_vpnblock == 0 then
                        rlib.msg:route( ply, 'VPN', 'Status: user', rlib.settings.cmsg.clrs.target_tri, result:Name( ), rlib.settings.cmsg.clrs.msg, 'is', rlib.settings.cmsg.clrs.target_tri, 'allowed', rlib.settings.cmsg.clrs.msg, 'to connect with vpns', rlib.settings.cmsg.clrs.target_sec, '( ' .. ip .. ' )' )
                    else
                        rlib.msg:route( ply, 'VPN', 'Status: user', rlib.settings.cmsg.clrs.target_tri, result:Name( ), rlib.settings.cmsg.clrs.msg, 'is', rlib.settings.cmsg.clrs.target_tri, 'blocked', rlib.settings.cmsg.clrs.msg, 'from connecting with vpns', rlib.settings.cmsg.clrs.target_sec, '( ' .. ip .. ' )' )
                    end
                end
            end )
        end
    end

end
rcc.new.rlib( 'ipconn_vpn_checkblock', rcc_vpn_checkblock )

local function test( pl )

    vpn_pauth( pl )
end
concommand.Add( 'aa', test )