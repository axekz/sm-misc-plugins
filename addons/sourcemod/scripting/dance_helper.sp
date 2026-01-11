/**
 *  random_emotes_helper.sp
 *
 *  Adds player-facing commands:
 *    - !randomdance [id]
 *    - !randomemotes [id]
 *
 *  Behavior:
 *    - If [id] is provided, use it directly.
 *    - Otherwise, pick a random ID from a configured pool/range.
 *
 *  This plugin triggers your existing admin commands as the server:
 *    - sm_setdance  <#userid|name> [Emote ID]
 *    - sm_setemote  <#userid|name> [Emote ID]
 *
 *  Configuration (ConVars):
 *    sm_randomdance_ids      CSV whitelist for dances (e.g. "1,2,3,10,78"). If non-empty, overrides range.
 *    sm_randomdance_min      Min dance ID (used when list empty). Default: 1
 *    sm_randomdance_max      Max dance ID (used when list empty). Default: 150
 *
 *    sm_randomemote_ids      CSV whitelist for emotes. If non-empty, overrides range.
 *    sm_randomemote_min      Min emote ID (used when list empty). Default: 1
 *    sm_randomemote_max      Max emote ID (used when list empty). Default: 300
 *
 *    sm_randomemote_cooldown Seconds between uses per player. Default: 3.0
 *
 *  Notes:
 *    - Adjust the *_max defaults to match your real ID ranges.
 *    - This plugin does not require admin flags; it issues commands via ServerCommand().
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Random Emotes Helper",
    author      = "ChatGPT (for Cinyan10)",
    description = "Player commands !randomdance / !randomemotes with optional ID argument",
    version     = "1.0.0",
    url         = ""
};

// ConVars
ConVar gCvarDanceList;
ConVar gCvarDanceMin;
ConVar gCvarDanceMax;

ConVar gCvarEmoteList;
ConVar gCvarEmoteMin;
ConVar gCvarEmoteMax;

ConVar gCvarCooldown;

// Cooldown store (by client) in game time seconds
float g_fNextUseTime[MAXPLAYERS + 1];

// Cached parsed lists
ArrayList gDanceList = null;
ArrayList gEmoteList = null;

public void OnPluginStart()
{
    // Create ConVars
    gCvarDanceList = CreateConVar("sm_randomdance_ids", "", "CSV list of dance IDs. If non-empty, overrides min/max range.");
    gCvarDanceMin  = CreateConVar("sm_randomdance_min", "1", "Minimum dance ID (used if list empty).", _, true, 1.0);
    gCvarDanceMax  = CreateConVar("sm_randomdance_max", "150", "Maximum dance ID (used if list empty).", _, true, 1.0);

    gCvarEmoteList = CreateConVar("sm_randomemote_ids", "", "CSV list of emote IDs. If non-empty, overrides min/max range.");
    gCvarEmoteMin  = CreateConVar("sm_randomemote_min", "1", "Minimum emote ID (used if list empty).", _, true, 1.0);
    gCvarEmoteMax  = CreateConVar("sm_randomemote_max", "300", "Maximum emote ID (used if list empty).", _, true, 1.0);

    gCvarCooldown  = CreateConVar("sm_randomemote_cooldown", "3.0", "Per-player cooldown in seconds.", _, true, 0.0);

    AutoExecConfig(true, "random_emotes_helper");

    // Init arrays
    gDanceList = new ArrayList();
    gEmoteList = new ArrayList();

    // Register commands (chat triggers like !randomdance map to these)
    RegConsoleCmd("sm_randomdance",  Cmd_RandomDance,  "Play a random or specified dance emote.");
    RegConsoleCmd("sm_randomemotes", Cmd_RandomEmotes, "Play a random or specified emote.");

    // Listen for changes to refresh caches
    HookConVarChange(gCvarDanceList, OnIDsChanged);
    HookConVarChange(gCvarEmoteList, OnIDsChanged);

    // Initial parse
    RefreshIDLists();
}

public void OnClientDisconnect(int client)
{
    if (0 < client <= MaxClients)
    {
        g_fNextUseTime[client] = 0.0;
    }
}

public void OnIDsChanged(ConVar cvar, const char[] oldValue, const char[] newValue)
{
    RefreshIDLists();
}

// ===== Command Handlers =====

public Action Cmd_RandomDance(int client, int args)
{
    if (!ValidateClient(client))
        return Plugin_Handled;

    if (!CheckCooldown(client))
        return Plugin_Handled;

    int id = -1;
    if (args >= 1)
    {
        char arg[32];
        GetCmdArg(1, arg, sizeof(arg));
        id = StringToIntSafe(arg, -1);

        if (id <= 0)
        {
            PrintToChat(client, "[SM] Invalid dance ID.");
            return Plugin_Handled;
        }
    }
    else
    {
        if (!PickRandomFromConfig(true, id))
        {
            PrintToChat(client, "[SM] No valid dance IDs configured.");
            return Plugin_Handled;
        }
    }

    // Execute admin command as server with player target
    if (!IssueSetDanceForClient(client, id))
    {
        PrintToChat(client, "[SM] Failed to trigger dance. Please contact an admin.");
        return Plugin_Handled;
    }

    ArmCooldown(client);
    PrintToChat(client, "[SM] Dance ID: %d", id);
    return Plugin_Handled;
}

public Action Cmd_RandomEmotes(int client, int args)
{
    if (!ValidateClient(client))
        return Plugin_Handled;

    if (!CheckCooldown(client))
        return Plugin_Handled;

    int id = -1;
    if (args >= 1)
    {
        char arg[32];
        GetCmdArg(1, arg, sizeof(arg));
        id = StringToIntSafe(arg, -1);

        if (id <= 0)
        {
            PrintToChat(client, "[SM] Invalid emote ID.");
            return Plugin_Handled;
        }
    }
    else
    {
        if (!PickRandomFromConfig(false, id))
        {
            PrintToChat(client, "[SM] No valid emote IDs configured.");
            return Plugin_Handled;
        }
    }

    if (!IssueSetEmoteForClient(client, id))
    {
        PrintToChat(client, "[SM] Failed to trigger emote. Please contact an admin.");
        return Plugin_Handled;
    }

    ArmCooldown(client);
    PrintToChat(client, "[SM] Emote ID: %d", id);
    return Plugin_Handled;
}

// ===== Helpers =====

bool ValidateClient(int client)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return false;
    }
    return true;
}

bool CheckCooldown(int client)
{
    float now = GetGameTime();
    float next = g_fNextUseTime[client];

    if (now < next)
    {
        float remain = next - now;
        PrintToChat(client, "[SM] Please wait %.1f seconds.", remain);
        return false;
    }
    return true;
}

void ArmCooldown(int client)
{
    float cd = gCvarCooldown.FloatValue;
    if (cd <= 0.0) return;

    g_fNextUseTime[client] = GetGameTime() + cd;
}

bool IssueSetDanceForClient(int client, int id)
{
    int userid = GetClientUserId(client);

    // Prefer sm_setdance (your plugin also registers sm_setdances)
    // Format: sm_setdance <#userid|name> [Emote ID]
    char cmd[128];
    Format(cmd, sizeof(cmd), "sm_setdance #%d %d", userid, id);
    ServerCommand("%s", cmd);
    return true;
}

bool IssueSetEmoteForClient(int client, int id)
{
    int userid = GetClientUserId(client);

    // Prefer sm_setemote (your plugin also registers sm_setemotes)
    // Format: sm_setemote <#userid|name> [Emote ID]
    char cmd[128];
    Format(cmd, sizeof(cmd), "sm_setemote #%d %d", userid, id);
    ServerCommand("%s", cmd);
    return true;
}

// Pick an ID based on CSV list if present, else from min..max
bool PickRandomFromConfig(bool dance, int &outId)
{
    ArrayList list = dance ? gDanceList : gEmoteList;

    if (list != null && list.Length > 0)
    {
        int idx = GetRandomInt(0, list.Length - 1);
        outId = list.Get(idx);
        return true;
    }

    // Fallback to range
    int minVal = dance ? gCvarDanceMin.IntValue : gCvarEmoteMin.IntValue;
    int maxVal = dance ? gCvarDanceMax.IntValue : gCvarEmoteMax.IntValue;

    if (maxVal < minVal)
    {
        int tmp = minVal; minVal = maxVal; maxVal = tmp;
    }

    if (minVal <= 0 || maxVal <= 0)
        return false;

    outId = GetRandomInt(minVal, maxVal);
    return true;
}

// Refresh cached lists from CSV ConVars
void RefreshIDLists()
{
    ParseCSVIntoList(gCvarDanceList, gDanceList);
    ParseCSVIntoList(gCvarEmoteList, gEmoteList);
}

// Parse a CSV of positive ints into an ArrayList
void ParseCSVIntoList(ConVar cvar, ArrayList list)
{
    if (list == null)
        return;

    list.Clear();

    char raw[2048];
    cvar.GetString(raw, sizeof(raw));

    TrimString(raw);
    if (raw[0] == '\0')
        return;

    char piece[32];
    int idx = 0;
    int len = strlen(raw);

    while (idx < len)
    {
        int start = idx;
        // find comma or end
        while (idx < len && raw[idx] != ',')
            idx++;

        int pieceLen = idx - start;
        if (pieceLen > 0 && pieceLen < sizeof(piece))
        {
            strcopy(piece, pieceLen + 1, raw[start]);
            TrimString(piece);

            int v = StringToIntSafe(piece, -1);
            if (v > 0)
            {
                list.Push(v);
            }
        }
        idx++; // skip comma
    }

    // Optional: make unique & sort ascending
    MakeUniqueAndSort(list);
}

int StringToIntSafe(const char[] s, int defval)
{
    if (s[0] == '\0')
        return defval;

    bool neg = (s[0] == '-');
    for (int i = neg ? 1 : 0; s[i] != '\0'; i++)
    {
        if (!IsCharNumeric(s[i]))
            return defval;
    }
    return StringToInt(s);
}

void MakeUniqueAndSort(ArrayList list)
{
    // Simple O(n^2) uniqueness for small lists, fine for CSVs
    for (int i = 0; i < list.Length; i++)
    {
        int vi = list.Get(i);
        for (int j = list.Length - 1; j > i; j--)
        {
            if (list.Get(j) == vi)
                list.Erase(j);
        }
    }

    // Bubble sort (lists are small); replace with ADT if you prefer
    bool swapped;
    do
    {
        swapped = false;
        for (int k = 0; k < list.Length - 1; k++)
        {
            int a = list.Get(k);
            int b = list.Get(k + 1);
            if (a > b)
            {
                list.Set(k, b);
                list.Set(k + 1, a);
                swapped = true;
            }
        }
    } while (swapped);
}
