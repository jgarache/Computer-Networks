/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    components new TimerMilliC() as myTimerC;
    components new HashmapC(uint32_t, 10) as myHashNeighbors;
    components new HashmapC(int, 999) as myHashKnownPackets;
    components new HashmapC(int, 999) as myHashActiveNodes;
    components new HashmapC(int, 999) as myHashLastUpdate;
    components new ListC(int, 999) as myNeighborsCost;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;
    Node.periodicTimer -> myTimerC;
    Node.hashNeighbors -> myHashNeighbors;
    Node.hashKnownPackets -> myHashKnownPackets;
    Node.hashActiveNodes -> myHashActiveNodes;
    Node.hashLastUpdate -> myHashLastUpdate;
    Node.neighborsCost -> myNeighborsCost;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;
}
