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
*   functionality
*/

local pmeta 				= FindMetaTable( 'Player' )

/*
*	country code
*/

function pmeta:SetCountryCode( val )
    self:SetNWString( 'geo_countrycode', val or 'NA' )
end

function pmeta:GetCountryCode( )
    return self:GetNWString( 'geo_countrycode' ) or 'NA'
end

/*
*	country name
*/

function pmeta:SetCountryName( val )
    self:SetNWString( 'geo_countryname', val or 'local' )
end

function pmeta:GetCountryName( )
    return self:GetNWString( 'geo_countryname' ) or 'local'
end

/*
*	continent name
*/

function pmeta:SetContinentName( val )
    self:SetNWString( 'geo_continent', val or 'local' )
end

function pmeta:GetContinentName( )
    return self:GetNWString( 'geo_continent' ) or 'local'
end