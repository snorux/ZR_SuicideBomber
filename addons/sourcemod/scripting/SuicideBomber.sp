#define PLUGIN_NAME           "[MM] Suicide Bomber"
#define PLUGIN_AUTHOR         "Snowy"
#define PLUGIN_DESCRIPTION    "The mother zombies gets to be a suicide bomber"
#define PLUGIN_VERSION        "1.0.1-alpha"
#define PLUGIN_URL            ""

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <zombiereloaded>

#pragma semicolon 1
#pragma newdecls required

/*
* ConVars
*/
ConVar g_cSBenabled = null;
ConVar g_cSBdamageRadius = null;
ConVar g_cSBdamage = null;
ConVar g_cSBtimer = null;
ConVar g_cSBcooldown = null;
ConVar g_cSBreminder = null;
ConVar g_cSBringHex = null;


bool g_bSBenabled;
float g_fSBcooldown;
float g_fSBreminder;
int g_iSBdamageRadius;
int g_iSBdamage;
int g_iSBtimer;
char g_sSBringHex[10];

/*
* Main variables
*/
enum struct SuicideBomber
{
	bool isBomber;
	bool isBombActivated;
	int beepTimer;
}

SuicideBomber g_eSBclient[MAXPLAYERS+1];

/*
* Sprites & Sounds
*/
char g_sBeepSound[PLATFORM_MAX_PATH] = "weapons/c4/c4_beep3.wav";
char g_sInitiateSound[PLATFORM_MAX_PATH] = "weapons/c4/c4_initiate.wav";
char g_sExplosionSound[PLATFORM_MAX_PATH] = "weapons/hegrenade/explode5_distant.wav";
char g_sFinalSound[PLATFORM_MAX_PATH];

int g_iHaloSprite = -1;
int g_iLaserSprite = -1;
int g_iExplosionSprite = -1;

/*
* Timers
*/
Handle g_hReminderTimer = null;

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	g_cSBenabled = 				CreateConVar("sb_enabled", 			"0", 			"Enable/disable the plugin");
	g_cSBdamageRadius = 		CreateConVar("sb_damage_radius",	"850",			"The damage radius of the explosion (int)");
	g_cSBdamage =				CreateConVar("sb_damage",			"450",			"The damage of the explosion (int)");
	g_cSBtimer = 				CreateConVar("sb_timer",			"10.0",			"Time to explode after player triggers the explosion");
	g_cSBcooldown =				CreateConVar("sb_cooldown",			"60.0",			"Time in seconds for the bomb cooldown. (float)");
	g_cSBreminder =				CreateConVar("sb_reminder",			"120.0",		"Time in seconds to remind the player that they have the bomb. (float)");
	g_cSBringHex = 				CreateConVar("sb_ring_hex",			"eb6a59",		"Hex value for the color of the ring (do not include the #)");
	
	HookEvent("round_end", Event_RoundEnd);
	
	RegAdminCmd("sm_sbdebug", Command_Debug, ADMFLAG_ROOT);
	RegAdminCmd("sm_sbme", Command_SBMe, ADMFLAG_ROOT);
	
	AutoExecConfig(true, "suicide_bomber");
}

/*
* ConVar Hooks
*/
public void OnConfigsExecuted()
{
	GetValues();
	
	g_cSBenabled.AddChangeHook(OnConVarChanged);
	g_cSBdamageRadius.AddChangeHook(OnConVarChanged);
	g_cSBdamage.AddChangeHook(OnConVarChanged);
	g_cSBtimer.AddChangeHook(OnConVarChanged);
	g_cSBcooldown.AddChangeHook(OnConVarChanged);
	g_cSBreminder.AddChangeHook(OnConVarChanged);
	g_cSBringHex.AddChangeHook(OnConVarChanged);
}

void GetValues()
{
	g_bSBenabled = g_cSBenabled.BoolValue;
	g_iSBdamageRadius = g_cSBdamageRadius.IntValue;
	g_iSBdamage = g_cSBdamage.IntValue;
	g_iSBtimer = g_cSBtimer.IntValue;
	g_fSBcooldown = g_cSBcooldown.FloatValue;
	g_fSBreminder = g_cSBreminder.FloatValue;
	g_cSBringHex.GetString(g_sSBringHex, sizeof(g_sSBringHex));
}

public void OnConVarChanged (ConVar CVar, const char[] oldVal, const char[] newVal)
{
	GetValues();
}

/*
* Events
*/
public void OnMapStart()
{
	Handle hGameConfig = LoadGameConfigFile("funcommands.games");
	if (hGameConfig == null) {
		SetFailState("Unable to load game config funcommands.games!");
		return;
	}
	
	if (GameConfGetKeyValue(hGameConfig, "SoundFinal", g_sFinalSound, sizeof(g_sFinalSound)) && g_sFinalSound[0]) {
		PrecacheSound(g_sFinalSound, true);
	}
	
	char sBuffer[PLATFORM_MAX_PATH];
	if (GameConfGetKeyValue(hGameConfig, "SpriteHalo", sBuffer, sizeof(sBuffer)) && sBuffer[0]) {
		g_iHaloSprite = PrecacheModel(sBuffer);
	}
	
	g_iLaserSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iExplosionSprite = PrecacheModel("materials/particle/fire_explosion_1/fire_explosion_1.vmt");
	PrecacheSound(g_sBeepSound, true);
	PrecacheSound(g_sInitiateSound, true);
	PrecacheSound(g_sExplosionSound, true);
	
	delete hGameConfig;
}

public void OnClientPutInServer (int client)
{
	ResetPlayerData(client);
}

public void OnClientDisconnect (int client)
{
	ResetPlayerData(client);
}

public Action Event_RoundEnd (Event event, const char[] name, bool dontBroadcast)
{
	ResetPlayerData(.bResetAll = true);
	
	if(g_hReminderTimer != null)
		delete g_hReminderTimer;
}

/*
* Main
*/
public int ZR_OnClientInfected (int client, int attacker, bool motherInfect, bool respawn)
{
	if (motherInfect && g_bSBenabled) {
		g_eSBclient[client].isBomber = true;
		PrintToChat(client, " \x10[SuicideBomber] \x05You are a suicide bomber!");
		PrintToChat(client, " \x10[SuicideBomber] \x05Press \x07\"R\" \x05to activate the bomb!");
		PrintToChat(client, " \x10[SuicideBomber] \x05The bomb has a cooldown of %.1fs", g_fSBcooldown);
		
		if (g_hReminderTimer == null)
			g_hReminderTimer = CreateTimer(g_fSBreminder, Timer_Reminder, _, TIMER_REPEAT);
	}
}

/*
*Detect when the player presses R and activate the timer for the bomb.
*/
public Action OnPlayerRunCmd (int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsValidClient(client, true) && g_bSBenabled && g_eSBclient[client].isBomber) {
		if((buttons & IN_RELOAD) && !g_eSBclient[client].isBombActivated) {
			g_eSBclient[client].isBombActivated = true;
			PrintToChatAll(" \x10[SuicideBomber] \x07%N \x05has activated his bomb. Shoot or else...", client);
			
			/* Initialize sound and effects */
			float fPlayerEyes[3];
			GetClientEyePosition(client, fPlayerEyes);
			EmitAmbientSound(g_sInitiateSound, fPlayerEyes, client, SNDLEVEL_TRAIN, SND_CHANGEVOL);
			//PlaySound(g_sInitiateSound, .bPlayAll = true);
			CreateTimer(1.0, Timer_BombBeep, GetClientSerial(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			SetGlow(client, float(g_iSBtimer));
			g_eSBclient[client].beepTimer = g_iSBtimer;
		}
	}
}

/*
* Reference: - https://developer.valvesoftware.com/wiki/Env_explosion
*			 - https://raw.githubusercontent.com/Mapeadores/CSGO-Dumps/master/datamaps.txt
*/
void InitiateExplosion (int client)
{
	if (!IsValidClient(client, true))
		return;
		
	if (!g_bSBenabled || !g_eSBclient[client].isBomber)
		return;
		
	int iExplosionIndex = CreateEntityByName("env_explosion");
	
	if(iExplosionIndex != -1) {
		SetEntProp(iExplosionIndex, Prop_Data, "m_spawnflags", 16384);
		SetEntProp(iExplosionIndex, Prop_Data, "m_iMagnitude", g_iSBdamage);
		SetEntProp(iExplosionIndex, Prop_Data, "m_iRadiusOverride", g_iSBdamageRadius);
		SetEntPropEnt(iExplosionIndex, Prop_Send, "m_hOwnerEntity", client);
		
		float fPlayerOrigin[3], fPlayerEyes[3];
		GetClientAbsOrigin(client, fPlayerOrigin);
		GetClientEyePosition(client, fPlayerEyes);
		
		TeleportEntity(iExplosionIndex, fPlayerOrigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(iExplosionIndex);
		ActivateEntity(iExplosionIndex);
		
		/* All the necessary effects and function goes here, before we start the explosion */
		SetGlow(client, 0.0);
		SetupEffects(fPlayerOrigin);
		EmitAmbientSound(g_sExplosionSound, fPlayerEyes, client, SNDLEVEL_TRAIN, SND_CHANGEVOL);
		//PlaySound(g_sExplosionSound, .bPlayAll = true);
		CreateTimer(g_fSBcooldown, Timer_ResetUse, GetClientSerial(client));
		
		/* Boom */
		AcceptEntityInput(iExplosionIndex, "Explode");
		AcceptEntityInput(iExplosionIndex, "Kill");
		
		ForcePlayerSuicide(client);
	}
}

void SetGlow (int client, float fDuration)
{
	if (fDuration <= 0.0)
		SetEntPropFloat(client, Prop_Send, "m_flDetectedByEnemySensorTime", 0.0);
	else {
		float fTagDuration = GetGameTime() + fDuration;
		SetEntPropFloat(client, Prop_Send, "m_flDetectedByEnemySensorTime", fTagDuration);
	}
}

void SetupEffects(float fOrigin[3])
{
	/* Ring */
	int iBuffer = StringToInt(g_sSBringHex, 16);
	int iColor[4];
	iColor[0] = ((iBuffer >> 16) & 0xFF);
	iColor[1] = ((iBuffer >> 8)  & 0xFF);
	iColor[2] = ((iBuffer >> 0)  & 0xFF);
	iColor[3] = 255;
	
	TE_SetupBeamRingPoint(fOrigin, 10.0, 500.0, g_iLaserSprite, g_iHaloSprite, 0, 1, 1.0, 2.0, 0.0, iColor, 10, FBEAM_SOLID);
	TE_SendToAll();
	
	/* Explosion x2 */
	TE_SetupExplosion(fOrigin, g_iExplosionSprite, 300.0, 1, 0, 1000, 5000);
	TE_SendToAll();
	fOrigin[2] += 10;
	TE_SetupExplosion(fOrigin, g_iExplosionSprite, 300.0, 1, 0, 1000, 5000);
	TE_SendToAll();
}

/*
* Commands
*/
public Action Command_Debug (int client, int args)
{
	PrintToChat(client, " \x10[SuicideBomber] \x05Are you a bomber? - \x07%b", g_eSBclient[client].isBomber);
	PrintToChat(client, " \x10[SuicideBomber] \x05Is your bomb activated? - \x07%b", g_eSBclient[client].isBombActivated);
	PrintToChat(client, " \x10[SuicideBomber] \x05Your beep timer - \x07%i", g_eSBclient[client].beepTimer);
	
	return Plugin_Handled;
}

public Action Command_SBMe (int client, int args)
{
	if (!g_bSBenabled) {
		PrintToChat(client, " \x10[SuicideBomber] You can't use this command while the mode is disabled!");
		return Plugin_Handled;
	}
	
	if (args == 0) {
		if (!IsValidClient(client, true))
			return Plugin_Handled;
			
		if (!ZR_IsClientZombie(client)) {
			PrintToChat(client, " \x10[SuicideBomber] \x05You can't be a human suicide bomber!");
			return Plugin_Handled;
		}
		
		g_eSBclient[client].isBomber = true;
		PrintToChat(client, " \x10[SuicideBomber] \x05You are now a suicide bomber!");
		return Plugin_Handled;
	}

	if (args == 1)
	{
		char arg1[65];
		GetCmdArg(1, arg1, sizeof(arg1));
		int target = FindTarget(client, arg1, false, false);
		if (target == -1 || !IsValidClient(target, true) || !ZR_IsClientZombie(target))
		{
			return Plugin_Handled;
		}
		
		g_eSBclient[target].isBomber = true;
		PrintToChat(client, " \x10[SuicideBomber] \x07%N \x05is now a suicide bomber!", target);
		PrintToChat(target, " \x10[SuicideBomber] \x07%N \x05made you a suicide bomber!", client);
	}
	
	return Plugin_Handled;
}

/*
* Timers
*/
public Action Timer_Reminder (Handle timer)
{
	for(int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i) && g_eSBclient[i].isBomber) {
			PrintToChat(i, " \x10[SuicideBomber] \x05You are a suicide bomber!");
			PrintToChat(i, " \x10[SuicideBomber] \x05Press \x07\"R\" \x05to activate the bomb!");
			PrintToChat(i, " \x10[SuicideBomber] \x05The bomb has a cooldown of %.1fs", g_fSBcooldown);
		}
	}
}

public Action Timer_ResetUse (Handle timer, int data)
{
	int client = GetClientFromSerial(data);
	
	if (!client)
		return Plugin_Stop;
		
	if(!g_bSBenabled || !g_eSBclient[client].isBomber)
		return Plugin_Stop;
	
	if(g_eSBclient[client].isBombActivated) {
		g_eSBclient[client].isBombActivated = false;
		PrintToChat(client, " \x10[SuicideBomber] \x05Your bomb is now off cooldown!");
	}
	
	return Plugin_Continue;
}

public Action Timer_BombBeep (Handle timer, int data)
{
	int client = GetClientFromSerial(data);
	
	if (!client)
		return Plugin_Stop;
		
	if (!g_bSBenabled || !g_eSBclient[client].isBomber)
		return Plugin_Stop;
		
	float fPlayerEyes[3];
	GetClientEyePosition(client, fPlayerEyes);
	g_eSBclient[client].beepTimer--;
	
	if (g_eSBclient[client].beepTimer <= 0) {
		InitiateExplosion(client);
		return Plugin_Stop;
	}
	else if (g_eSBclient[client].beepTimer == 1) {
		EmitAmbientSound(g_sFinalSound, fPlayerEyes, client, SNDLEVEL_TRAIN, SND_CHANGEVOL);
		//PlaySound(g_sFinalSound, .bPlayAll = true);
	}
	else {
		EmitAmbientSound(g_sBeepSound, fPlayerEyes, client, SNDLEVEL_TRAIN, SND_CHANGEVOL);
		//PlaySound(g_sBeepSound, .bPlayAll = true);
		
	}
	
	PrintToChat(client, " \x10[SuicideBomber] \x05Your bomb will blow in \x07%i...", g_eSBclient[client].beepTimer);
	return Plugin_Continue;
}

/*
* Stock Functions
*/
bool IsValidClient (int client, bool bAlive = false)
{
	if (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && (bAlive == false || IsPlayerAlive(client)))
		return true;

	return false;
}

void ResetPlayerData (int client = 0, bool bResetAll = false)
{
	if(bResetAll) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsValidClient(i)) {
				g_eSBclient[i].isBomber = false;
				g_eSBclient[i].isBombActivated = false;
				g_eSBclient[i].beepTimer = 0;
			}
		}
	}
	else {
		g_eSBclient[client].isBomber = false;
		g_eSBclient[client].isBombActivated = false;
		g_eSBclient[client].beepTimer = 0;
	}
}

/* Yes, I know about EmitSoundToClient & EmitSoundToAll, but somehow it did not work out for me. idk why sad*/
stock void PlaySound (const char[] sPath, int client = 0, bool bPlayAll = false)
{
	if(bPlayAll) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsValidClient(i)) {
				ClientCommand(i, "play %s", sPath);
			}
		}
	}
	else {
		if(IsValidClient(client)) {
			ClientCommand(client, "play %s", sPath);
		}
	}
}