/*
advancedc4timer.sp

Description:
	Advanced c4 countdown timer.  Based on the original sm c4 timer by sslice.

Versions:
	0.5
		* Initial Release
		
	0.6
		* Restructued most of the code
		* Added user configuration of sounds
		* Added optional announcement
		* Changed timer to go 30, 20, 10, 9.....1
		
	1.0
		* Minor code and naming standards changes
		* Added support for late loading
		
	1.1
		* Added an exit option to the settings menu
		* Changed command to sm_c4timer
		* Made the SoundNames array const
		* Added new hud text
		
	1.1.1
		* Fixed voice countdown bug
		
	1.2
		* Added translations
		* Added name to bomb exploded message
		* Added bomb defused hud message
		
	1.2.1
		* Updated translation files and script to match
		* Changed menu behavior
		
	1.3
		* Changed naming convention to be more in line with base sourcemod
		* Improved timer synchronization
		* Changed from panels to menus
		
	1.4
		* Removed duplicate menu exit
		* Added autoloading of config file
		* Added verbose, flexible bombtimer messages
		* Added the ability to have the voice or text messages start at 10 instead of 30
		
	1.4.1
		* Added individual sounds
		
	1.5.0 - Panduh
		* Replaced all instances of GetMaxClients() with MaxClients.
		* Modified / Optimized numerous blocks of code
		* Added support for extremely rare cases of Plant/Defuse with player no longer in-game.
		* Added two translations, "Terrorist" and "Counter-Terrorist", generics for the above issue.
		* Replaced KV data system with ClientPrefs to greatly improve performance.
		
	1.6.0 - Nerus
		* Fix for while playing sounds after the explosion
		* Removed warnings on a compilation
		* Some small improvements
		* Changed names of plugin config and translations files
		* Removed binary and config from source
*/
		
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>

#define PLUGIN_VERSION "1.6.0"
#define TOTAL_SOUNDS 12

#define ONLY_ALIVES true
#define ONLY_HUMMANS true

#define TWENTY 0
#define ONE 1
#define TWO 2
#define THREE 3
#define FOUR 4
#define FIVE 5
#define SIX 6
#define SEVEN 7
#define EIGHT 8
#define NINE 9
#define TEN 10
#define THIRTY 11

#define SOUND_AT_TEN 1
#define TEXT_AT_TEN 2
#define Preferences 4
#define Preferences_Hud 0
#define Preferences_Chat 1
#define Preferences_Center 2
#define Preferences_Sound 3

//* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *

bool STOP_PLAYING = false;

new Handle:g_hTimer_Countdown = INVALID_HANDLE;
new Handle:g_hEnable = INVALID_HANDLE;
new Handle:g_hCvarTimer = INVALID_HANDLE;
new Handle:g_hAnnounce = INVALID_HANDLE;
new Handle:g_hChatDefault = INVALID_HANDLE;
new Handle:g_hSoundDefault = INVALID_HANDLE;
new Handle:g_hHUDDefault = INVALID_HANDLE;
new Handle:g_hCenterDefault = INVALID_HANDLE;
new Handle:g_hAltStart = INVALID_HANDLE;
new Handle:g_cPrefSound = INVALID_HANDLE;
new Handle:g_cPrefChat = INVALID_HANDLE;
new Handle:g_cPrefCenter = INVALID_HANDLE;
new Handle:g_cPrefHud = INVALID_HANDLE;

new Float:g_fExplosionTime, Float:g_fCounter, Float:g_fCvarTimer;
new bool:g_bLateLoad, bool:g_bAnnounce, bool:g_bEnable;
new g_iAltSound;
new String:g_sSoundList[TOTAL_SOUNDS][PLATFORM_MAX_PATH], String:g_sC4Primer[32];
new String:g_sHUDDefault[2], String:g_sSoundDefault[2], String:g_sChatDefault[2], String:g_sCenterDefault[2];

new g_Prefs[MAXPLAYERS + 1][Preferences];
new bool:g_bLoaded[MAXPLAYERS + 1];
new String:g_sSteam[MAXPLAYERS + 1][24];

static const String:g_sSoundDisplay[TOTAL_SOUNDS][] = {"20", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "30"};

//* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *

public Plugin:myinfo = 
{
	name = "Advanced c4 Countdown Timer",
	author = "dalto, Panda",
	description = "Plugin that gives a countdown for the C4 explosion in Counter-Strike Source.",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	g_bLateLoad = late;
	
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("advancedc4timer.phrases");
	
	CreateConVar("sm_c4_timer_redux_version", PLUGIN_VERSION, "Advanced c4 Timer Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_hEnable = CreateConVar("sm_c4_timer_enable", "1", "Enables / Disables features of this plugin.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_bEnable = GetConVarBool(g_hEnable);
	HookConVarChange(g_hEnable, OnSettingsChange);
	
	g_hAnnounce = CreateConVar("sm_c4_timer_announce", "1", "If enabled, clients receive a message 30 seconds after joining concerning this plugin.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_bAnnounce = GetConVarBool(g_hEnable);
	HookConVarChange(g_hAnnounce, OnSettingsChange);
	
	g_hChatDefault = CreateConVar("sm_c4_timer_chat_default", "0", "Default client setting for chat preference.", FCVAR_NONE, true, 0.0, true, 1.0);
	GetConVarString(g_hChatDefault, g_sChatDefault, sizeof(g_sChatDefault));
	HookConVarChange(g_hChatDefault, OnSettingsChange);
	
	g_hCenterDefault = CreateConVar("sm_c4_timer_center_default", "0", "Default client setting for center preference.", FCVAR_NONE, true, 0.0, true, 1.0);
	GetConVarString(g_hCenterDefault, g_sCenterDefault, sizeof(g_sCenterDefault));
	HookConVarChange(g_hCenterDefault, OnSettingsChange);
	
	g_hHUDDefault = CreateConVar("sm_c4_timer_hud_default", "1", "Default client setting for HUD preference.", FCVAR_NONE, true, 0.0, true, 1.0);
	GetConVarString(g_hHUDDefault, g_sHUDDefault, sizeof(g_sHUDDefault));
	HookConVarChange(g_hHUDDefault, OnSettingsChange);
	
	g_hSoundDefault = CreateConVar("sm_c4_timer_sound_default", "1", "Default client setting for sound preference.", FCVAR_NONE, true, 0.0, true, 1.0);
	GetConVarString(g_hSoundDefault, g_sSoundDefault, sizeof(g_sSoundDefault));
	HookConVarChange(g_hSoundDefault, OnSettingsChange);
	
	g_hAltStart = CreateConVar("sm_c4_timer_start_at_ten", "0", "1 voice starts at 10, 2 text starts at 10, 3 both start at 10");
	g_iAltSound = GetConVarInt(g_hAltStart);
	HookConVarChange(g_hAltStart, OnSettingsChange);
	AutoExecConfig(true, "advancedc4timer");

	g_hCvarTimer = FindConVar("mp_c4timer");
	g_fCvarTimer = GetConVarFloat(g_hCvarTimer);
	HookConVarChange(g_hCvarTimer, OnSettingsChange);
	
	HookEvent("bomb_planted", EventBombPlanted, EventHookMode_Pre);
	HookEvent("player_death", EventPlayerDied, EventHookMode_PostNoCopy);
	HookEvent("round_start", EventRoundStart, EventHookMode_PostNoCopy);
	HookEvent("bomb_exploded", EventBombExploded, EventHookMode_PostNoCopy);
	HookEvent("bomb_defused", EventBombDefused, EventHookMode_Post);
	
	RegConsoleCmd("sm_c4timer", SettingsMenu);
	
	g_cPrefSound = RegClientCookie("AdvancedC4Timer_Sound", "Advanced C4 Timer: The client's sound preference.", CookieAccess_Protected);
	g_cPrefChat = RegClientCookie("AdvancedC4Timer_Chat", "Advanced C4 Timer: The client's chat message preference.", CookieAccess_Protected);
	g_cPrefCenter = RegClientCookie("AdvancedC4Timer_Center", "Advanced C4 Timer: The client's center message preference.", CookieAccess_Protected);
	g_cPrefHud = RegClientCookie("AdvancedC4Timer_Hud", "Advanced C4 Timer: The client's hud message preference.", CookieAccess_Protected);
	
	if(g_bEnable && g_bLateLoad)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				GetClientAuthId(i, AuthId_SteamID64, g_sSteam[i], sizeof(g_sSteam[]));
				if(!IsFakeClient(i) && !g_bLoaded[i] && AreClientCookiesCached(i))
					LoadClientData(i);
			}
		}

		g_bLateLoad = false;
	}
}

public OnSettingsChange(Handle:cvar, const String:oldvalue[], const String:newvalue[])
{
	if(cvar == g_hEnable)
		g_bEnable = bool:StringToInt(newvalue);
	else if(cvar == g_hAnnounce)
		g_bAnnounce = bool:StringToInt(newvalue);
	else if(cvar == g_hChatDefault)
		strcopy(g_sChatDefault, sizeof(g_sChatDefault), newvalue);
	else if(cvar == g_hCenterDefault)
		strcopy(g_sCenterDefault, sizeof(g_sCenterDefault), newvalue);
	else if(cvar == g_hHUDDefault)
		strcopy(g_sHUDDefault, sizeof(g_sHUDDefault), newvalue);
	else if(cvar == g_hSoundDefault)
		strcopy(g_sSoundDefault, sizeof(g_sSoundDefault), newvalue);
	else if(cvar == g_hAltStart)
		g_iAltSound = StringToInt(newvalue);
	else if(cvar == g_hCvarTimer)
		g_fCvarTimer = StringToFloat(newvalue);
}

public OnMapStart()
{
	if(g_bEnable)
	{
		Define_Sounds(true);
	}
}

public OnClientPostAdminCheck(client)
{
	if(g_bEnable)
	{
		GetClientAuthId(client, AuthId_SteamID64, g_sSteam[client], sizeof(g_sSteam[]));
		if(!g_bLoaded[client] && AreClientCookiesCached(client))
			LoadClientData(client);
	}
}

public OnClientCookiesCached(client)
{
	if(g_bEnable)
	{
		if(!g_bLoaded[client] && !IsFakeClient(client))
		{
			LoadClientData(client);
		}
	}
}

LoadClientData(client)
{
	new String:sCookie[4] = "";
	GetClientCookie(client, g_cPrefHud, sCookie, sizeof(sCookie));

	if(StrEqual(sCookie, "", false))
	{
		SetClientCookie(client, g_cPrefHud, g_sHUDDefault);
		SetClientCookie(client, g_cPrefChat, g_sChatDefault);
		SetClientCookie(client, g_cPrefCenter, g_sCenterDefault);
		SetClientCookie(client, g_cPrefSound, g_sSoundDefault);
		
		g_Prefs[client][Preferences_Hud] = StringToInt(g_sHUDDefault);
		g_Prefs[client][Preferences_Chat] = StringToInt(g_sChatDefault);
		g_Prefs[client][Preferences_Center] = StringToInt(g_sCenterDefault);
		g_Prefs[client][Preferences_Sound] = StringToInt(g_sSoundDefault);
	}
	else
	{
		g_Prefs[client][Preferences_Hud] = StringToInt(sCookie);
		
		GetClientCookie(client, g_cPrefChat, sCookie, sizeof(sCookie));
		g_Prefs[client][Preferences_Chat] = StringToInt(sCookie);
		
		GetClientCookie(client, g_cPrefCenter, sCookie, sizeof(sCookie));
		g_Prefs[client][Preferences_Center] = StringToInt(sCookie);
		
		GetClientCookie(client, g_cPrefSound, sCookie, sizeof(sCookie));
		g_Prefs[client][Preferences_Sound] = StringToInt(sCookie);
	}
	
	g_bLoaded[client] = true;

	if(g_bAnnounce)
		CreateTimer(30.0, Timer_Announce, GetClientUserId(client));
}

public EventRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(g_bEnable)
	{
		STOP_PLAYING = false;

		if(g_hTimer_Countdown != INVALID_HANDLE && CloseHandle(g_hTimer_Countdown))
			g_hTimer_Countdown = INVALID_HANDLE;
	}
}

public EventPlayerDied(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(g_bEnable)
	{
		if(GetPlayersCountFromTeam(CS_TEAM_CT, ONLY_ALIVES, !ONLY_HUMMANS) == 0)
		{
			STOP_PLAYING = true;
		}
	}
}

public Action:EventBombPlanted(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(g_bEnable)
	{
		g_fCounter = g_fCvarTimer - 1.0;
		g_fExplosionTime = GetEngineTime() + g_fCvarTimer;

		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		if(!client || !IsClientInGame(client))
			Format(g_sC4Primer, sizeof(g_sC4Primer), "%T", "Terrorist");
		else
			GetClientName(client, g_sC4Primer, sizeof(g_sC4Primer));
		
		g_hTimer_Countdown = CreateTimer(((g_fExplosionTime - g_fCounter) - GetEngineTime()), TimerCountdown, _, TIMER_REPEAT);
	}

	return Plugin_Continue;
}

public EventBombDefused(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(g_bEnable)
	{
		if(g_hTimer_Countdown != INVALID_HANDLE && CloseHandle(g_hTimer_Countdown))
			g_hTimer_Countdown = INVALID_HANDLE;

		decl String:sC4Defuser[32];
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		if(!client || !IsClientInGame(client))
			Format(sC4Defuser, sizeof(sC4Defuser), "%T", "Counter-Terrorist");
		else
			GetClientName(client, sC4Defuser, sizeof(sC4Defuser));

		for(new i = 1; i <= MaxClients; i++)
			if(IsClientInGame(i) && !IsFakeClient(i) && g_Prefs[i][Preferences_Hud])
				PrintHintText(i, "%T", "bomb defused", i, sC4Defuser);
	}
}

public EventBombExploded(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(g_bEnable)
	{
		if(g_hTimer_Countdown != INVALID_HANDLE && CloseHandle(g_hTimer_Countdown))
			g_hTimer_Countdown = INVALID_HANDLE;

		STOP_PLAYING = true;
			
		for(new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i) && g_Prefs[i][Preferences_Hud])
			{
				PrintHintText(i, "%T", "bomb exploded", i, g_sC4Primer);
			}
		}
	}
}

public Action:TimerCountdown(Handle:timer, any:data)
{
	BombMessage(RoundToFloor(g_fCounter));
	
	g_fCounter--;
	if(g_fCounter <= 0)
	{
		g_hTimer_Countdown = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

Define_Sounds(bool:bPrepare = false)
{
	decl String:sPath[PLATFORM_MAX_PATH];
	new Handle:hKeyValues = CreateKeyValues("c4SoundsList");
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/c4soundslist.cfg");

	if(!FileToKeyValues(hKeyValues, sPath) || !KvGotoFirstSubKey(hKeyValues))
		SetFailState("configs/c4soundslist.cfg not found or not correctly structured");
	else
	{
		for(new i = 0; i < TOTAL_SOUNDS; i++)
		{
			KvGetString(hKeyValues, g_sSoundDisplay[i], g_sSoundList[i], PLATFORM_MAX_PATH);
			if(bPrepare && !StrEqual(g_sSoundList[i], ""))
			{
				PrecacheSound(g_sSoundList[i], true);
				Format(sPath, PLATFORM_MAX_PATH, "sound/%s", g_sSoundList[i]);
				AddFileToDownloadsTable(sPath);
			}
		}
	}
	
	CloseHandle(hKeyValues);
}

public BombMessage(count)
{
	new soundKey;
	decl String:sBuffer[192];
	
	switch(count)
	{
		case 1, 2, 3, 4, 5, 6, 7, 8, 9, 10:
			soundKey = count;
		case 20:
			soundKey = TWENTY;
		case 30:
			soundKey = THIRTY;
		default:
			return;
	}

	if(!StrEqual(g_sSoundList[soundKey], ""))
	{
		for(new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i))
			{
				Format(sBuffer, sizeof(sBuffer), "countdown %i", count);
				Format(sBuffer, sizeof(sBuffer), "%T", sBuffer, i, count);

				if(!STOP_PLAYING && g_Prefs[i][Preferences_Sound] && !(g_iAltSound & SOUND_AT_TEN && (soundKey < 1 || soundKey > 10)))
				{
					EmitSoundToClient(i, g_sSoundList[soundKey]);
				}
				if(!(g_iAltSound & TEXT_AT_TEN && (soundKey < 1 || soundKey > 10)))
				{
					if(g_Prefs[i][Preferences_Chat])
					{
						PrintToChat(i, "Bomb: %s", sBuffer);
					}
					if(g_Prefs[i][Preferences_Center])
					{
						PrintCenterText(i, sBuffer);
					}
					if(g_Prefs[i][Preferences_Hud])
					{
						PrintHintText(i, sBuffer);
					}
				}
			}
		}
	}
}

public Action:Timer_Announce(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(client && IsClientInGame(client))
	{
		PrintToChat(client, "%t", "announce");
	}
}
 
public Action:SettingsMenu(client, args)
{
	decl String:sBuffer[128];
	new Handle:menu = CreateMenu(SettingsMenuHandler);
	Format(sBuffer, sizeof(sBuffer), "%T", "c4 menu", client);
	SetMenuTitle(menu, sBuffer);
	if(g_Prefs[client][Preferences_Sound] == 1)
		Format(sBuffer, sizeof(sBuffer), "%T", "disable sound", client);
	else
		Format(sBuffer, sizeof(sBuffer), "%T", "enable sound", client);
	AddMenuItem(menu, "menu item", sBuffer);

	if(g_Prefs[client][Preferences_Chat] == 1)
		Format(sBuffer, sizeof(sBuffer), "%T", "disable chat", client);
	else
		Format(sBuffer, sizeof(sBuffer), "%T", "enable chat", client);
	AddMenuItem(menu, "menu item", sBuffer);
	
	if(g_Prefs[client][Preferences_Center] == 1)
		Format(sBuffer, sizeof(sBuffer), "%T", "disable center", client);
	else
		Format(sBuffer, sizeof(sBuffer), "%T", "enable center", client);
	AddMenuItem(menu, "menu item", sBuffer);
	
	if(g_Prefs[client][Preferences_Hud] == 1)
		Format(sBuffer, sizeof(sBuffer), "%T", "disable hud", client);
	else
		Format(sBuffer, sizeof(sBuffer), "%T", "enable hud", client);
	AddMenuItem(menu, "menu item", sBuffer);

	DisplayMenu(menu, client, 30);
	return Plugin_Handled;
}

public SettingsMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			decl String:sBuffer[2];
			switch(param2)
			{
				case 0:
				{
					g_Prefs[param1][Preferences_Sound] = !g_Prefs[param1][Preferences_Sound];
					IntToString(g_Prefs[param1][Preferences_Sound], sBuffer, sizeof(sBuffer));
					SetClientCookie(param1, g_cPrefSound, sBuffer);
				}
				case 1:
				{
					g_Prefs[param1][Preferences_Chat] = !g_Prefs[param1][Preferences_Chat];
					IntToString(g_Prefs[param1][Preferences_Chat], sBuffer, sizeof(sBuffer));
					SetClientCookie(param1, g_cPrefChat, sBuffer);
				}
				case 2:
				{
					g_Prefs[param1][Preferences_Center] = !g_Prefs[param1][Preferences_Center];
					IntToString(g_Prefs[param1][Preferences_Center], sBuffer, sizeof(sBuffer));
					SetClientCookie(param1, g_cPrefCenter, sBuffer);
				}
				case 3:
				{
					g_Prefs[param1][Preferences_Hud] = !g_Prefs[param1][Preferences_Hud];
					IntToString(g_Prefs[param1][Preferences_Hud], sBuffer, sizeof(sBuffer));
					SetClientCookie(param1, g_cPrefHud, sBuffer);
				}
			}
			
			SettingsMenu(param1, 0);
		}
		case MenuAction_End:
			CloseHandle(menu);
	}
}

public int GetPlayersCountFromTeam(int team, bool only_alives, bool only_humans)
{
	if(!only_alives && !only_humans)
		return GetTeamClientCount(team);

	int count = 0;

	for(int client = 1; client < MaxClients+1; client++)
	{
		if(IsValidPlayer(client, only_humans))
		{
			if(GetClientTeam(client) != team || only_alives && !IsPlayerAlive(client))
				continue;

			count++;
		}
	}
	
	return count;
}

public void EmitDenaySoundToPlayer(int client)
{
	EmitSoundToClient(client, "buttons/button11.wav");
}

public bool IsValidPlayer(int client, bool only_human)
{
	if(only_human)
	{
		return (IsValidClient(client) && !IsClientSourceTV(client) && !IsFakeClient(client));
	}
	
	return (IsValidClient(client) && !IsClientSourceTV(client));
}

public bool IsValidClient(int client)
{
	return (IsClient(client) && IsClientConnected(client) && IsClientInGame(client));
}

public bool IsClient(int client)
{
	return (client > 0 && client < MaxClients + 1);
}
