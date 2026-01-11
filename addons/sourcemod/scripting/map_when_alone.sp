// filename: map_when_alone.sp
#include <sourcemod>
#include <sdktools>   // ForceChangeLevel
#include <halflife>   // IsMapValid, GetMapDisplayName, FindMap
#include <mapchooser> // ReadMapList, MAPLIST_FLAG_*

#pragma semicolon 1
#pragma newdecls required

ConVar gCvarEnabled;
ConVar gCvarMinHumans;   // default 1
ConVar gCvarDelay;       // seconds before switching
ConVar gCvarMaxMatches;  // cap for fuzzy results (default 12)

Handle g_hPendingTimer = null;
int    g_iRequester     = 0;
char   g_sPendingMap[PLATFORM_MAX_PATH];
bool   g_bPending       = false;

ArrayList g_MapList = null;
int g_MapFileSerial = -1;

public Plugin myinfo =
{
    name        = "Map When Alone",
    author      = "Cinyan10",
    description = "Allow !map only when there is 1 human on the server; always use this logic (even for admins).",
    version     = "1.3.1",
    url         = "https://forums.alliedmods.net/"
};

public void OnPluginStart()
{
    // Intercept sm_map for EVERYONE (admins included).
    AddCommandListener(MapCommandListener, "sm_map");

    gCvarEnabled   = CreateConVar("sm_mapalone_enabled", "1",
                        "Enable Map When Alone (1/0)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarMinHumans = CreateConVar("sm_mapalone_minhumans", "1",
                        "Max humans allowed to use !map (normally 1)", FCVAR_NOTIFY, true, 1.0, true, 2.0);
    gCvarDelay     = CreateConVar("sm_mapalone_delay", "3.0",
                        "Delay (seconds) before changing map", FCVAR_NOTIFY, true, 1.0, true, 30.0);
    gCvarMaxMatches = CreateConVar("sm_mapalone_maxfound", "12",
                        "Max number of fuzzy matches to show in menu (errors if above). 0 = unlimited.", 0, true, 0.0);

    // Prepare list for ReadMapList()
    int arraySize = ByteCountToCells(PLATFORM_MAX_PATH);
    g_MapList = new ArrayList(arraySize);
}

public void OnConfigsExecuted()
{
    if (ReadMapList(g_MapList,
                    g_MapFileSerial,
                    "nominations",
                    MAPLIST_FLAG_CLEARARRAY | MAPLIST_FLAG_MAPSFOLDER) == null)
    {
        if (g_MapFileSerial == -1)
        {
            SetFailState("Unable to create a valid map list.");
        }
    }
}

// === Core listener: always handle, even for admins ===
public Action MapCommandListener(int client, const char[] command, int argc)
{
    if (!gCvarEnabled.BoolValue)
        return Plugin_Continue; // allow basecommands if disabled

    // Always use our logic; do not fall through to base sm_map.
    return HandleMapRequest(client, argc);
}

Action HandleMapRequest(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Handled;

    int humans = CountHumans();
    if (humans > gCvarMinHumans.IntValue)
    {
        PrintToChat(client, "[Map] Too many players. This works only when you're alone.");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        PrintToChat(client, "[Map] Usage: !map <mapname>");
        return Plugin_Handled;
    }

    char raw[PLATFORM_MAX_PATH];
    GetCmdArgString(raw, sizeof(raw));
    TrimString(raw);

    // --- Only accept a unique, exact resolve from FindMap() ---
    char resolved[PLATFORM_MAX_PATH];
    FindMapResult fm = FindMap(raw, resolved, sizeof(resolved));
    if (fm == FindMap_Found && IsMapValid(resolved))
    {
        StartPending(client, resolved);
        return Plugin_Handled;
    }
    // If ambiguous (or not found), we’ll build our own match list/menu.
    // ---------------------------------------------------------------

    // Fuzzy match against our map list (like Nominations)
    ArrayList results = new ArrayList(); // indices into g_MapList
    int found = FindMatchingMaps(g_MapList, results, raw);

    if (found <= 0)
    {
        PrintToChat(client, "[Map] Unknown/invalid map: %s", raw);
        delete results;
        return Plugin_Handled;
    }

    if (found == 1)
    {
        char picked[PLATFORM_MAX_PATH];
        g_MapList.GetString(results.Get(0), picked, sizeof(picked));
        if (FindMap(picked, picked, sizeof(picked)) == FindMap_Found && IsMapValid(picked))
        {
            StartPending(client, picked);
        }
        else
        {
            PrintToChat(client, "[Map] Resolved map invalid: %s", picked);
        }
        delete results;
        return Plugin_Handled;
    }

    // 2..cap -> show choose menu (like nominations)
    Menu m = new Menu(Menu_SelectMatch, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);
    m.SetTitle("Select map");

    char mapResult[PLATFORM_MAX_PATH];
    for (int i = 0; i < results.Length; i++)
    {
        g_MapList.GetString(results.Get(i), mapResult, sizeof(mapResult));
        // Resolve the map name
        if (FindMap(mapResult, mapResult, sizeof(mapResult)) != FindMap_Found)
            continue;

        // Store resolved map name as both info and display (like nominations)
        m.AddItem(mapResult, mapResult);
    }

    delete results;
    m.ExitButton = true;
    m.Display(client, 30);
    return Plugin_Handled;
}

void StartPending(int client, const char[] mapname)
{
    // Replace any existing pending timer; do NOT cancel for new joins.
    if (g_bPending && g_hPendingTimer != null)
    {
        delete g_hPendingTimer;
        g_hPendingTimer = null;
    }

    strcopy(g_sPendingMap, sizeof(g_sPendingMap), mapname);
    g_iRequester = client;
    g_bPending   = true;

    float delay = gCvarDelay.FloatValue;
    PrintToChatAll("[Map] %N requested %s.", client, g_sPendingMap);
    PrintToChatAll("[Map] Changing in %.0f seconds...", delay);

    g_hPendingTimer = CreateTimer(delay, Timer_DoChange, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_DoChange(Handle timer)
{
    g_hPendingTimer = null;

    if (!IsMapValid(g_sPendingMap))
    {
        PrintToChatAll("[Map] Cancelled: map became invalid.");
        ClearPending();
        return Plugin_Stop;
    }

    int req = g_iRequester;
    PrintToChatAll("[Map] Changing map to %s (requested by %N).", g_sPendingMap, req);
    ForceChangeLevel(g_sPendingMap, "MapWhenAlone");

    ClearPending();
    return Plugin_Stop;
}

void ClearPending()
{
    g_bPending   = false;
    g_iRequester = 0;
    g_sPendingMap[0] = '\0';
}

// === Menu callback (like nominations) ===
public int Menu_SelectMatch(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char mapname[PLATFORM_MAX_PATH];
            // Get the map name and start pending change
            menu.GetItem(param2, mapname, sizeof(mapname));
            StartPending(param1, mapname);
        }
        case MenuAction_DrawItem:
        {
            // All items are enabled (no disabled maps like nominations)
            return ITEMDRAW_DEFAULT;
        }
        case MenuAction_DisplayItem:
        {
            char mapname[PLATFORM_MAX_PATH];
            menu.GetItem(param2, mapname, sizeof(mapname));
            
            // Show display name instead of internal map name
            char displayName[PLATFORM_MAX_PATH];
            GetMapDisplayName(mapname, displayName, sizeof(displayName));
            return RedrawMenuItem(displayName);
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

// === Helpers ===
int CountHumans()
{
    int humans = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            humans++;
    }
    return humans;
}

int FindMatchingMaps(ArrayList mapList, ArrayList results, const char[] input)
{
    int map_count = mapList.Length;
    if (!map_count)
        return -1;

    int matches = 0;
    char map[PLATFORM_MAX_PATH];

    int maxmatches = gCvarMaxMatches.IntValue;

    // Collect matches (like nominations)
    for (int i = 0; i < map_count; i++)
    {
        mapList.GetString(i, map, sizeof(map));
        if (StrContains(map, input, false) != -1) // case-insensitive
        {
            results.Push(i);
            matches++;

            // Respect max matches limit during collection (like nominations)
            if (maxmatches > 0 && matches >= maxmatches)
            {
                break;
            }
        }
    }
    return matches;
}
