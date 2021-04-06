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

/*
*   Localized translation func
*/

local function lang( ... )
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
*   if you wish to use Mysqloo -- make sure you have the required libraries first:
*
*   Mysqloo             :   https://github.com/FredyH/MySQLOO/releases
*   Install Directory   :   \garrysmod\lua\bin
*
*   Libmysql (Windows)  :   https://github.com/syl0r/MySQLOO/raw/master/MySQL/lib/windows/libmysql.dll
*   Libmysql (Linux)    :   https://github.com/syl0r/MySQLOO/raw/master/MySQL/lib/linux/libmysqlclient.so.18
*   Install Director    :   \garrysmod\ (your root directory that also contains the srcds executable)
*
*   if you're using certain server hosts, check for a widget called 'Addons Manager', it should allow
*   you to download and install the required libraries from there. If not, submit a ticket with your
*   hosting provider and tell them you need mysqloo installed, they should be able to help.
*
*   to switch between database modes, locate the script's sh_config.lua file and edit the setting:
*   [ScriptName].settings.mode = 'sqlite || mysqloo'
*/

/*
*   localized lua functions
*/

local isfunction            = isfunction
local istable               = istable
local isnumber              = isnumber
local tonumber              = tonumber
local tostring              = tostring
local pairs                 = pairs
local pcall                 = pcall
local unpack                = unpack
local hook                  = hook
local game                  = game
local os                    = os
local table                 = table
local string                = string
local sql                   = sql
local sf                    = string.format

/*
*   insert query
*
*   queries that are ran will begin with the specified string query below.
*   this basically determines how sql will deal with duplicate keys.
*   choose the method based on what you want to accomplish as their is very little difference
*   optimization-wise, and execution time differences are microscopic.
*
*   :   INSERT
*       inserts new records into database, however, duplicated keys will toss an error and cause the
*       data to not be added/replaced. If using this method, you must append 'ON DUPLICATE KEY UPDATE'
*       to the end of your queries in order to handle duplicate keys.
*
*   :   INSERT IGNORE
*       ignore inserting record if the key already exists.
*       new records with a unique key will be added to the database.
*       does not raise errors/warnings on duplicated keys and will bypass inserting that record
*       if the duplicated key does indeed exist (chance to lose data if not careful).
*
*   :   REPLACE INTO
*       new records will be inserted just as they would using INSERT
*       existing records will be replaced instead of ignored.
*/

local _env                  = _G

/*
*   db > read config file
*/

mod.db                      = storage.get.db( mod )
                            if not mod.db then
                                base:log( 2, '[ %s ] » failed to load db cfg -- missing manifest ext declaration', mod.name )
                                return
                            end

/*
*   database localization
*/

local db                    = mod.database
db.cfg.mode                 = mod.db.general.mode
db.cfg.tables               = mod.db.tables
db.cfg.debug                = helper:val2bool( mod.db.adv.debug ) or false
db.cfg.adv                  = mod.db.adv
db.InsertQuery              = 'INSERT IGNORE'

/*
*   db :: initialize
*/

function db:initialize( )
    if not self.setup_tables then
        base:log( 2, '[ %s ] » failed to setup required db tables -- missing fn [ %s ]', mod.name, 'setup_tables' )
        return
    end

    self:setup_tables( )

    if not self.on_connected then return end
    self:on_connected( )
end
concommand.Add( pref( 'db.setup' ), function( ply, cmd, args, str )
    if not access:bIsRoot( ply ) then return end
    base:log( RLIB_LOG_DB, '[ %s ] » executed db setup', mod.name )
    db:initialize( ply, cmd, args, str )
end )

/*
*   check :: bIsMysql
*
*   determines if the current mode is mysqloo
*
*   @return : bool
*/

function db:bIsMysql( )
    return ( db.cfg.mode == 'mysqloo' and true ) or ( db.cfg.mode == 2 and true ) or false
end

/*
*   db :: bIsSqlite
*
*   determines if the current mode is sqlite
*
*   @return : bool
*/

function db:bIsSqlite( )
    return ( not db.cfg.mode and true ) or ( db.cfg.mode == 'sqlite' and true ) or ( db.cfg.mode == 1 and true ) or false
end

/*
*   db :: connect
*/

function db:connect( )

    local mysqloo_fail = false

    if self:bIsMysql( ) then
        require( 'mysqloo' )

        local mysqldb = mod.db.mysql

        if not mysqloo then
            base:log( 2, '[ %s ] » mysqloo is not installed. defaulting to sqlite instead!', mod.name )
            mysqloo_fail = true
        else
            local ver = tonumber( mysqloo.VERSION ) -- So I don't have to update it everytime a major release is done. Let's just see if it's anything below v9

            if ver < 9 then
                base:log( 3, '[ %s ] » warning » running outdated version of mysqloo: [v%s]. Download the latest library at [ https://github.com/FredyH/MySQLOO ] to avoid conflicts.', mod.name, ver )
            else
                base:log( 1, '[ %s ] » installed » mysqloo v%s.%s ', mod.name, mysqloo.VERSION, mysqloo.MINOR_VERSION )
            end

            if not istable( mysqldb ) then
                base:log( 2, '[ %s ] » could not fetch mysqloo db table! defaulting to sqlite!', mod.name )
                mysqloo_fail = true
            end
        end

        -- check to see if mysqloo failed to load, if so, default to sqlite
        if not mysqloo_fail then
            base:log( 4, '[ %s ] » connection » [ %s ] » [ %s ]', mod.name, 'OK', 'mysqloo' )
            self:establish_connection( mysqldb.host, mysqldb.user, mysqldb.pass, mysqldb.name, mysqldb.port )

            -- give a notification server-side if db.cfg.adv.keepalive enabled
            if helper:val2bool( db.cfg.adv.keepalive ) then
                base:log( RLIB_LOG_DB, '[ %s ] » keep-alive » [ %s ]', mod.name, 'OK' )
            end

        end
    else
        mysqloo_fail = true
    end

    if mysqloo_fail then
        base:log( RLIB_LOG_DB, '[ %s ] » storage method » [ %s ]', mod.name, 'sqlite' )
        self.m_bConnectedToDB = true
        self:initialize( )
    end

end

/*
*   db :: bConnected
*
*   check if we are connected to the sql db
*
*   @return : bool
*/

function db:bConnected( )
    return self.m_bConnectedToDB
end

/*
*   db :: connect
*
*   attempts to connect to the mysqloo db
*
*   @call   : db:establish_connection( db.host, db.user, db.pass, db.name, db.port )
*
*   @param  : str host
*   @param  : str user
*   @param  : str pass
*   @param  : str name
*   @param  : int port
*/

function db:establish_connection( host, user, pass, name, port )
    if ( helper.str:isempty( host ) or helper.str:isempty( user ) or helper.str:isempty( pass ) or helper.str:isempty( name ) ) then
        base:log( RLIB_LOG_DB, '[ %s ] » required parameters are missing and a db connection cannot be started. check mysqloo credentials', mod.name )
        return
    end

    host = tostring( host )
    user = tostring( user )
    pass = tostring( pass )
    name = tostring( name )
    port = tostring( port )

    local dbconn = mysqloo.connect( host, user, pass, name, port )
    dbconn:setAutoReconnect( true )
    dbconn:setMultiStatements( true )
    dbconn:setCachePreparedStatements( false )
    dbconn.onConnected = function( db )
        local id = tostring( db )
        base:log( RLIB_LOG_DB, '[ %s ] » db established » [ id %s ]', mod.name, string.gsub( id, 'Database ', '' ) )
        self.m_bConnectedToDB = true
        self:initialize( )
    end
    dbconn.onConnectionFailed = function( db, err )
        base:log( RLIB_LOG_DB, '[ %s ] » failed to connect using mysqloo » error [ %s ]', mod.name, err )
        self.m_bConnectedToDB = false
    end
    dbconn:connect( )
    _env[ pref( 'SQL' ) ] = dbconn
end

/*
*   method :: sqlite
*
*   @call   : query_sqlite( query, fn )
*
*   @param  : str query
*   @param  : func fn
*/

local function query_sqlite( query, fn )
    local q = sql.Query( query )

    if q == false then
        fn( query, false, sql.LastError( ) )
        base:log( RLIB_LOG_DB, '[ %s ] » sqlite error ( [ %s ] ) » %s', mod.name, query, sql.LastError( ) )
        return
    end

    fn( query, true, q or { } )
    if db.cfg.debug then
        base:log( RLIB_LOG_DB, '[ %s ] » query ran » ( [ %s ] )', mod.name, query )
    end
end

/*
*   method :: mysqloo
*
*   @call   : query_mysqloo( query, fn )
*
*   @param  : str query
*   @param  : func fn
*/

local function query_mysqloo( query, fn )
    local q = _env[ pref( 'SQL' ) ]:query( query )
    q.onSuccess = function( s, data )
        fn( query, true, data )
        if db.cfg.debug then
            base:log( RLIB_LOG_DB, '[ %s ] » query ran » [ %s ]', mod.name, query )
        end
    end
    q.onError = function( s, err, ret )
        local data = sf( '%s [ %s ]', err, ret )
        fn( query, false, data )
        base:log( RLIB_LOG_DB, data )
    end
    q:start( )
end

/*
*   runs queries on the db
*
*   @param  : str query
*   @param  : func fn
*/

function db:sqlQuery( query, fn )
    if ( helper:val2bool( db.cfg.adv.keepalive ) and not base:ping( ) ) then
        base:log( RLIB_LOG_DB, '[ %s ] » connection lost » [ %s ]', mod.name, 'RECONNECTING' )
    end

    fn = isfunction( fn ) and fn or function( q, ok, ret ) end

    if self:bIsSqlite( ) then
        query_sqlite( query, fn )
    elseif self:bIsMysql( ) then
        query_mysqloo( query, fn )
    end
end

/*
*   heartbeats
*
*   @call   :   db:query_heartbeat( 'SHOW TABLES LIKE "' .. settings.tables[ 'index' ] .. '"', function( q, ok, data )
*                   if not ok then return end
*               end )
*
*   @param  : str query
*   @param  : func fn
*/

function db:query_heartbeat( query, fn )
    if ( helper:val2bool( db.cfg.adv.keepalive ) and not base:ping( ) ) then
        base:log( RLIB_LOG_DB, '[ %s ] » connection lost » [ %s ]', mod.name, 'RECONNECTING' )
    end

    fn = isfunction( fn ) and fn or function( q, ok, ret ) end

    if self:bIsSqlite( ) then
        query_sqlite( query, fn )
    elseif self:bIsMysql( ) then
        local q = _env[ pref( 'SQL' ) ]:query( query )
        q:start( )
    end
end

/*
*   db :: escaping
*
*   @param  : str s
*   @return : str
*/

function db:query_escape( s )
    return ( self:bIsSqlite( ) and sql.SQLStr( s, true ) ) or _env[ pref( 'SQL' ) ]:escape( s )
end

/*
*   db :: query
*
*   preps a query and replaces {tags} with the proper values
*
*   @param  : str query
*   @param  : tbl args
*   @param  : func fn
*/

function db:query( query, args, fn )
    if not query then
        base:log( RLIB_LOG_DB, '[ %s ] » attempted to run empty query » missing query', mod.name )
        return
    end

    for k, v in pairs( args ) do
        v = isstring( v ) and self:query_escape( v ) or v
        query = query:Replace( '{' .. k .. '}', '"' .. v .. '"' )
        query = query:Replace( '[' .. k .. ']', v )
    end

    self:sqlQuery( query, fn )
end

/*
*   db :: get :: select
*
*   returns true if query has the requested single field and data
*   row must not be empty
*
*   @call   : db:qSelect( data, field )
*   @ex     : db:qSelect( data, 'house_id' )
*
*   @param  : tbl data
*   @param  : str id
*   @param  : bool bNoEmpty
*   @return : tbl or bool
*/

function db:qSelect( data, id, bNoEmpty )
    return istable( data[ 1 ] ) and data[ 1 ][ id ] and ( bNoEmpty and not helper.str:isempty( data[ 1 ][ id ] ) or not bNoEmpty ) and data[ 1 ] or false
end

/*
*   db :: get :: single
*
*   returns a single result from a specified column
*
*   @call   : db:qSingle( data, field )
*   @ex     : db:qSingle( data, 'house_id' )
*
*   @param  : tbl data
*   @param  : str id
*   @param  : bool bNoEmpty
*   @return : tbl or bool
*/

function db:qSingle( data, id, bNoEmpty )
    return istable( data[ 1 ] ) and data[ 1 ][ id ] and ( bNoEmpty and not helper.str:isempty( data[ 1 ][ id ] ) or not bNoEmpty ) and data[ 1 ][ id ] or false
end

/*
*   db :: get :: select :: num
*
*   returns data for a valid query and converts to a number
*
*   @call   : db:qSelect( data, field )
*   @ex     : db:qSelect( data, 'house_id' )
*
*   @param  : tbl data
*   @param  : str id
*   @return : int or bool
*/

function db:qSelectNum( data, id )
    return ( istable( data[ 1 ] ) and data[ 1 ][ id ] and tonumber( data[ 1 ][ id ] ) or 0 ) or false
end

/*
*   db :: get :: select row
*
*   returns all fields of query result row
*
*   @call   : db:qSelectRow( data )
*
*   @param  : tbl data
*   @return : tbl or bool
*/

function db:qSelectRow( data )
    return data and ( table.Count( data ) > 0 ) and data[ 1 ] or false
end

/*
*   db :: get :: count exists
*
*   returns bool if query count found and matches at least 1 result
*   used simply to confirm a result exists for a query
*
*   @call   : db:qCountOK( data )
*
*   @param  : tbl data
*   @param  : str id
*   @return : bool
*/

function db:qCountOK( data, id )
    id = isstring( id ) and id or 'count'
    return data[ 1 ] and data[ 1 ][ id ] and tonumber( data[ 1 ][ id ] ) > 0 and true or false
end

/*
*   db :: get :: count
*
*   returns the actual number of results matching a query using count(*)
*
*   @call   : db:qNumRows( data )
*
*   @param  : tbl data
*   @param  : str id
*   @return : int
*/

function db:qNumRows( data, id )
    id = isstring( id ) and id or 'count'
    return data[ 1 ] and data[ 1 ][ id ] and tonumber( data[ 1 ][ id ] ) or 0
end

/*
*   db :: data exists
*
*   used to check if a query contains matching data
*
*   @call   : db:bExists( ok, data )
*   @assoc  : db:createtable(  )
*           : db:droptables(  )
*
*   @param  : tbl data
*   @return : bool
*/

function db:bExists( ok, data )
    if not ok or ( data and table.Count( data ) > 0 ) then return true end
    return false
end

/*
 *   db :: valid str
*
*   simply ensures a string is cleaned up and not left blank
*
*   @call   : db:bDataOK( dbtable.row_id )
*
*   @param  : str str
*   @return : bool, str
*/

function db:validStr( str )
    if not isstring( str ) then return end
    if not helper.str:isempty( str ) then return str end
    return false
end

/*
*   db :: data valid
*
*   basic check for data
*   must contain 1 table row, and row must not be empty if its a table
*
*   @call   : db:bDataValid( data )
*   @ex     : db:bDataValid( data ) and data[ 1 ] or { }
*
*   @param  : tbl data
*   @return : bool
*/

function db:bDataValid( data )
    if data and data[ 1 ] then
        if ( istable( data ) and table.Count( data ) < 1 ) then return false end
        return data[ 1 ]
    end
    return false
end

/*
*   db :: get table
*
*   @alias  : gettable, tbl, table
*
*   @param  : str id
*   @return : str
*/

function db:gettable( id )
    if not db.cfg or not db.cfg.tables then return end
    local dbpref = db.cfg.tables[ 'prefix' ] or db.cfg.tables[ '_prefix' ] or false
    return ( dbpref and ( db.cfg.tables[ id ] and string.format( '%s_%s', dbpref, db.cfg.tables[ id ] ) ) ) or ( db.cfg.tables[ id ] )
end
db.tbl    = db.gettable
db.table  = db.gettable

/*
*   db :: mysql :: ping
*
*   checks for a valid connection to the mysqloo db
*   use with caution -- may cause lag if used improperly.
*
*   @return : bool
*/

function base:ping( )
    local result = false

    if db:bIsMysql( ) then
        result = _env[ pref( 'SQL' ) ]:ping( )
    end

    return result
end

/*
*   db :: mysql :: heartbeat
*
*   runs a simple heartbeat query to the db.
*   this is not associated to the alternative 'keeplive' method
*
*   only used for mysqloo -- sqlite doesnt need this
*/

function db:heartbeat( )
    if not db.cfg.adv.heartbeat then return end
    if self:bIsSqlite( ) then return end

    timex.expire( pref( 'db.heartbeat', pf ) )
    timex.create( pref( 'db.heartbeat', pf ), tonumber( db.cfg.adv.interval ) or 120, 0, function( )
        self:query_heartbeat( 'SHOW TABLES LIKE "' .. db.cfg.tables[ 'index' ] .. '"', function( q, ok, data )
            if not ok then return end
        end )
        if db.cfg.debug then
            base:log( RLIB_LOG_DB, '[ %s ] » heartbeat » [ %s ]', mod.name, os.date( '%H:%M:%S' ) )
        end
    end )
end

/*
*   db :: createtable
*
*   @param  : str name
*   @param  : str query
*/

function db:createtable( name, query )
    if not name or not query then return end

    if db.cfg.tables[ name ] then
        name = db.cfg.tables[ name ]
    end

    if self:bIsMysql( ) then

        /*
        *   mysqloo
        */

        self:sqlQuery( 'SHOW TABLES LIKE "' .. name .. '"', function( q, ok, data )

            if self:bExists( ok, data ) then
                if not self.post_connected then return end
                self:post_connected( )
                return
            end

            self:sqlQuery(
            [[
                CREATE TABLE `]] .. name .. [[` (]] .. query .. [[)
            ]],
            function( q2, ok2, data2 )
                if self.cfg.debug then
                    base:log( RLIB_LOG_DB, '[ %s ] » query [ %s ] » data [ %s ]', name, tostring( ok2 ), tostring( data2 ) )
                end
                if ( self.post_connected ) then
                    self:post_connected( )
                end
            end )

            self:log( RLIB_LOG_DB, '+ mysqloo table » [ %s ]', name )
        end )

    elseif self:bIsSqlite( ) then

        /*
        *   sqlite
        */

        if sql.TableExists( name ) then return end

        self:sqlQuery(
        [[
            CREATE TABLE `]] .. name .. [[` (]] .. query .. [[)
        ]])

        self:log( RLIB_LOG_DB, '+ sqlite table » [ %s ]', name )

        if db.cfg.debug then
            base:log( RLIB_LOG_DB, 'creating [ %s ] » [ %s ]' , name, tostring( sql.TableExists( name ) ) )
        end
    end
end
db.newtable = db.createtable

/*
*   db :: droptables
*
*   drops all module db tables or only specified tables by name
*
*   @param  : str name
*/

function db:droptables( name )

    if self:bIsMysql( ) then

        /*
        *   mysqloo
        */

        local srctbl = isstring( name ) and { name } or db.cfg.tables

        for k, v in pairs( srctbl ) do
            self:sqlQuery( 'SHOW TABLES LIKE "' .. v .. '"', function( q, ok, data )
                if not self:bExists( ok, data ) then return end

                self:sqlQuery(
                [[
                    DROP TABLE IF EXISTS`]] .. v .. [[`
                ]],
                function( q2, ok2, data2 )
                    if not ok2 then return end
                    base:log( RLIB_LOG_DB, '[ %s ] » dropped table [ %s ]', mod.name, v )
                end )

                self:log( RLIB_LOG_DB, '- mysqloo table » [ %s ]', name )
            end )
        end

    elseif self:bIsSqlite( ) then

        /*
        *   sqlite
        */

        if sql.TableExists( name ) then return end

        self:sqlQuery(
        [[
            CREATE TABLE `]] .. name .. [[` (]] .. query .. [[)
        ]])

        self:log( RLIB_LOG_DB, '+ sqlite table » [ %s ]', name )

        if db.cfg.debug then
            base:log( RLIB_LOG_DB, 'creating [ %s ] » [ %s ]' , name, tostring( sql.TableExists( name ) ) )
        end
    end
end
concommand.Add( pref( 'db.clear' ), function( ply, cmd, args, str )
    if not access:bIsRoot( ply ) then return end
    db:droptables( )
end )

/*
*   db wakeup
*/

gameevent.Listen( 'player_connect' )
local function db_wakeup( data )
    if data.networkid ~= 'BOT' then return end
    hook.Remove( 'player_connect', pref( 'db.wake' ) )
    game.ConsoleCommand( sf( 'kickid %d %s\n', data.userid, 'mysql wakeup -- bot disconnected.' ) )
end
hook.Add( 'player_connect', pref( 'db.wake' ), db_wakeup )

/*
*   db :: getstatus
*/

function db:getstatus( )
    local sinfo             = ( _env[ pref( 'SQL' ) ] and _env[ pref( 'SQL' ) ]:serverInfo( ) ) or 'unknown'
    local version           = ( _env[ pref( 'SQL' ) ] and _env[ pref( 'SQL' ) ]:serverVersion( ) ) or 'unknown'
    local host              = ( _env[ pref( 'SQL' ) ] and _env[ pref( 'SQL' ) ]:hostInfo( ) ) or 'unknown'
    local queue             = ( _env[ pref( 'SQL' ) ] and _env[ pref( 'SQL' ) ]:queueSize( ) ) or 0
    local status            = ( _env[ pref( 'SQL' ) ] and _env[ pref( 'SQL' ) ]:status( ) ) or 0
    local mode              = db.cfg.mode or 'unknown'
    local hb_stat           = helper.util:humanbool( db.cfg.adv.heartbeat, true )
    local hb_int            = db.cfg.adv.interval or 0
    local ka_stat           = helper.util:humanbool( db.cfg.adv.keepalive, true )

    if not db:bIsSqlite( ) then
        base:log( RLIB_LOG_DB, '[ %s ] » mysql [ %s ]',      mod.name, sinfo )
        base:log( RLIB_LOG_DB, '[ %s ] » version [ %s ]',    mod.name, version )
        base:log( RLIB_LOG_DB, '[ %s ] » host [ %s ]',       mod.name, host )
        base:log( RLIB_LOG_DB, '[ %s ] » queue size [ %s ]', mod.name, queue )
    end

    base:log( RLIB_LOG_DB, '[ %s ] » storage mode [ %s ]',  mod.name, mode )
    base:log( RLIB_LOG_DB, '[ %s ] » heartbeat [ %s ] » %s seconds',  mod.name, hb_stat, hb_int )
    base:log( RLIB_LOG_DB, '[ %s ] » keepalive [ %s ]',  mod.name, ka_stat )
end
concommand.Add( pref( 'db.status' ), function( ply, cmd, args, str )
    if not access:bIsRoot( ply ) then return end
    db:getstatus( ply, cmd, args, str )
end )

/*
*   db :: log
*
*   outputs sql execution processes to a modules' data folder
*
*   @usage  : db:log( 4, 'created sqlite table :: [ %s ]', 'tablename' )
*
*   @param  : int mtype
*   @param  : str msg
*   @param  : varg { ... }
*/

function db:log( mtype, msg, ... )
    local args = { ... }

    mtype   = isnumber( mtype ) and mtype or 1
    msg     = isstring( msg ) and msg or lang( 'msg_invalid' )

    local resp, msg = pcall( sf, msg, unpack( args ) )

    local c_type
    if isnumber( mtype ) then
        c_type = '[' .. helper.str:ucfirst( base._def.debug_titles[ mtype ] ) .. ']'
    elseif isstring( mtype ) then
        c_type = '[' .. mtype .. ']'
    end

    local affix     = os.date( '%m%d%y' )
    local filename  = sf( 'SQL_%s.txt', affix )

    local date      = '[' .. os.date( '%I:%M:%S' ) .. ']'
    local output    = sf( '%s %s %s', date, c_type, msg )

    local path_mod  = storage.mft:getpath( 'dir_modules' )
    local path_log  = sf( '%s/%s/logs', path_mod, mod.id )

    storage.file.append( path_log, filename, output )
end

/*
*   start
*
*   attempts to connect to the db after all the entities are initialized on the server, or when
*   toggled by concommand
*/

function db:Start( )
    db:connect( )
    db:heartbeat( )
end
hook.Add( 'InitPostEntity', pref( 'db.initialize' ), db.Start )
concommand.Add( pref( 'db.connect' ), function( ply, cmd, args, str )
    if not access:bIsRoot( ply ) then return end
    db:Start( ply, cmd, args, str )
end )

/*
*   hook :: think :: check db state
*
*   in the event that the db doesnt connect at server setup; monitor to make sure
*   a connection is active.
*/

local dbNextCheck = CurTime( ) + 30
local function think_check_state( )
    if dbNextCheck > CurTime( ) then return end
    if not db:bConnected( ) then
        base:log( RLIB_LOG_DB, '[ %s ] » not connected! reconnecting ...',  mod.name )
        db:Start( )
    end

    dbNextCheck = CurTime( ) + 30
end
hook.Add( 'Think', pref( 'db.think.checkstate' ), think_check_state )

/*
*   setup :: mysqloo
*
*   @param  : self this
*/

local function db_setup_mysqlo( this )
    this = this or db
    if not this then return end

    this:createtable( this:table( 'users' ),
    [[
        `uid` varchar(64) COLLATE utf8_unicode_ci NOT NULL,
        `is_blocked` tinyint(1) UNSIGNED NOT NULL DEFAULT '0',
        `connections` int(11) UNSIGNED NOT NULL DEFAULT '0',
        `host` varbinary(16) NOT NULL,
        `time_registered` DATETIME NOT NULL,
        `time_updated` DATETIME NOT NULL,
        UNIQUE KEY `uid_UNIQUE` (`uid`)
    ]])
end

/*
*   setup :: sqlite
*
*   @param  : self this
*/

local function db_setup_sqlite( this )
    this = this or db
    if not this then return end

    this:createtable( this:table( 'users' ),
    [[
        `uid` varchar(64) NOT NULL PRIMARY KEY,
        `is_blocked` int(1) NOT NULL DEFAULT '0',
        `history` text,
        `host` varbinary(16) DEFAULT '0',
        `time_updated` int(11) DEFAULT '0'
    ]])
end

/*
*   db :: setup_tables
*/

function db:setup_tables( )
    if self.cfg.mode == 'mysqloo' then
        db_setup_mysqlo( self )
    else
        db_setup_sqlite( self )

        self.InsertQuery = 'INSERT OR IGNORE'
        if ( self.post_connected ) then
            self:post_connected( )
        end
    end
end