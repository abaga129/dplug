module dplug.client.bus;

enum : int
{
    busDirectionInput = 0,
    busDirectionOutput,
    busDirectionAux
}
alias BusDirection = int;

struct BusInfo
{
    BusDirection direction;
    int numChannels;
    string label;
}