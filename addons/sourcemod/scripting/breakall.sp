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
