#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "Break All",
    author      = "Cinyan10",
    description = "Breaks all breakable entities on the map",
    version     = "1.0",
    url         = "https://axekz.com/"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_breakall", Cmd_BreakAll, "Breaks all breakable entities");
}

public Action Cmd_BreakAll(int client, int args)
{
    // Allow if user is admin (generic flag), or if they are the only real player on the server
    bool isAdmin = (client > 0 && CheckCommandAccess(client, "sm_breakall", ADMFLAG_GENERIC, true));
    int numPlayers = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            numPlayers++;
        }
    }
    if (!isAdmin && numPlayers > 1)
    {
        if (client > 0)
            PrintToChat(client, "[BreakAll] You must be an admin or the only player to use this command.");
        return Plugin_Handled;
    }

    int count = 0;
    char classname[64];

    for (int entity = MaxClients + 1; entity <= GetMaxEntities(); entity++)
    {
        if (!IsValidEntity(entity) || !IsValidEdict(entity))
            continue;

        GetEdictClassname(entity, classname, sizeof(classname));

        if (StrEqual(classname, "func_breakable", false) || StrEqual(classname, "func_breakable_surf", false))
        {
            AcceptEntityInput(entity, "Break");
            count++;
        }
    }

    PrintToChatAll("[BreakAll] Broke %d entities.", count);
    LogMessage("[BreakAll] Broke %d breakables.", count);
    return Plugin_Handled;
}
