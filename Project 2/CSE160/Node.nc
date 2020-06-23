/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/linkState.h"
#include "includes/routingTable.h"

module Node{
    uses interface Boot;
    uses interface Timer<TMilli> as periodicTimer;
    uses interface Hashmap<uint32_t> as hashNeighbors;
    uses interface Hashmap<int> as hashKnownPackets;
    uses interface Hashmap<int> as hashActiveNodes;
    uses interface Hashmap<int> as hashLastUpdate;
    uses interface List<int> as neighborsCost;

    uses interface SplitControl as AMControl;
    uses interface Receive;

    uses interface SimpleSend as Sender;

    uses interface CommandHandler;
}

implementation{
    pack sendPackage;
    linkState nodeLS = {0};
    routingTable myRoutingTable;

    // Prototypes
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
    bool checkPackages(uint16_t src, uint16_t seq);
    // Project 1
    void addNeighborToHash(uint16_t node);
    void checkTimeStamps();
    // Project 2
    void initialProtocolTwo();
    bool checkLinkState(uint16_t src, uint16_t dest, uint16_t seq, int cost);
    void linkStateUpdate(uint16_t src, uint16_t dest, uint16_t seq, int cost);
    void updateRoutingTable();
    int minDistance();
    int getHop(int dest);

    event void Boot.booted(){
        call AMControl.start();
        call periodicTimer.startPeriodic(60000); //1s = 1000ms | 1 min = 60000ms | 5 min = 350000ms | 10 min = 3500000ms

        dbg(GENERAL_CHANNEL, "Booted\n");
    }

    event void AMControl.startDone(error_t err){
        if(err == SUCCESS){
            dbg(GENERAL_CHANNEL, "Radio On\n");
        }else{
            //Retry until successful
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err){}

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        if(len==sizeof(pack)){
            pack* myMsg=(pack*) payload;

            if(myMsg->dest != 0)
            {
                if(myMsg->protocol != 2){
                    //checks to see if package destination is the final destination
                    if((myMsg->dest == TOS_NODE_ID) && !(checkPackages(myMsg->src, myMsg->seq))) {
                        dbg(ROUTING_CHANNEL, "Package has reached destination\n");
                        dbg(ROUTING_CHANNEL, "Payload: %s\n", myMsg->payload);
                        if(myMsg->protocol == 0){
                            dbg(ROUTING_CHANNEL, "Ping Reply\n");
                            makePack(&sendPackage, TOS_NODE_ID, myMsg->src, 19, 1, (sendPackage.seq + 1), "GOT YOUR PACKAGE!", PACKET_MAX_PAYLOAD_SIZE);
                            call Sender.send(sendPackage, getHop(myMsg->src));
                            return msg;
                        }
                        return msg;
                    } else if (myMsg->TTL > 0 && !(checkPackages(myMsg->src, myMsg->seq)) && (myMsg->src != TOS_NODE_ID)){
                        //repackages package and sends to neighboring nodes
                        dbg(FLOODING_CHANNEL, "Flooding...\n");
                        makePack(&sendPackage, myMsg->src, myMsg->dest, (myMsg->TTL - 1), myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                        return msg;
                    } else {
                        dbg(FLOODING_CHANNEL, "TTL termination/Duplicate Package\n");
                        return msg;
                    }
                } else {
                    // Protocol #2 Implementation:
                    // Get cost from payload (1=Active 0=Disconnected)
                    int cost = atoi (myMsg->payload);

                    // checkLinkState returns TRUE only if update needs to be executed
                    if(checkLinkState(myMsg->src, myMsg->dest, myMsg->seq, cost)){
                        dbg(NEIGHBOR_CHANNEL, "Package is coming from node %d\n", myMsg->src);
                        linkStateUpdate(myMsg->src, myMsg->dest, myMsg->seq, cost);
                        if(myMsg->TTL > 0){
                           makePack(&sendPackage, myMsg->src, myMsg->dest, (myMsg->TTL - 1), 2, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                           call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                        }
                    }else{
                        // Do nothing since it is a repeated package
                    }
                }
            }
            // THE FOLLOWING IS FOR NEIGHBOR DISCOVERY
            if(myMsg->protocol != 2){
                addNeighborToHash(myMsg->src);
            }
            return msg;
        }

        dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }


    event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
        dbg(ROUTING_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, 19, 0, (sendPackage.seq + 1), payload, PACKET_MAX_PAYLOAD_SIZE);
        //call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        //call Sender.send(sendPackage, destination);
        call Sender.send(sendPackage, getHop(destination));
    }

    event void CommandHandler.printNeighbors(){
        int* pNeighbors = call hashNeighbors.getKeys();
        int nCounter = call hashNeighbors.size();
        int i;
        printf("Neighbors for %d: ", TOS_NODE_ID);

        for(i = 0; i < nCounter; i++){
            printf("%d", pNeighbors[i]);
        }

        printf("\n");
    }

    event void CommandHandler.printRouteTable(){
         int i;
        printf("SRC NODE: %d\n", TOS_NODE_ID);
        printf("V\tC\tH\n");
        for(i = 0; i < 999; i++){
            if(myRoutingTable[i].cost < 999){
                printf("%d\t%d\t%d\n", i, myRoutingTable[i].cost, myRoutingTable[i].hop);
            }
        }
    }

    event void CommandHandler.printLinkState(){
        int* pActiveNodes = call hashActiveNodes.getKeys();
        int nCounter = call hashActiveNodes.size();
        int neighbor;
        int mainNode;

        int i;
        int j;

        for(i = 0; i < nCounter; i++){
            mainNode = pActiveNodes[i];
            for(j = 0; j < nCounter; j++)
            {
                neighbor = pActiveNodes[j];
                if(nodeLS[mainNode].cost[neighbor] != 0){
                    printf("Node %d is connected to node %d\n", mainNode, neighbor);
                }
            }
        }

    }

    event void CommandHandler.printDistanceVector(){}

    event void CommandHandler.setTestServer(){}

    event void CommandHandler.setTestClient(){}

    event void CommandHandler.setAppServer(){}

    event void CommandHandler.setAppClient(){}

    event void periodicTimer.fired(){
        uint32_t currentTimeStamp = call periodicTimer.getNow();

        makePack(&sendPackage, TOS_NODE_ID, 0, 0, 0, (sendPackage.seq + 1), "ADD NEIGHBOR", PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);

        if(currentTimeStamp > 60000*3)
        {
            initialProtocolTwo();
        }

        checkTimeStamps();
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    bool checkPackages(uint16_t src, uint16_t seq){
        if(call hashKnownPackets.contains(src) == 1){
            int value = call hashKnownPackets.get(src);
            if(value < seq){
                call hashKnownPackets.remove(src);
                call hashKnownPackets.insert(src, seq);
                return FALSE; //Not a repeated package. Seq number updated
            } else {
                return TRUE; //Repeated package
            }
        } else {
            call hashKnownPackets.insert(src, seq);
            return FALSE; //Not a repeated package. Package inserted to hash for first time.
        }
    }

    void addNeighborToHash(uint16_t node){
        uint32_t currentTimeStamp = call periodicTimer.getNow();

        if(call hashNeighbors.contains(node) == 0){
            //call hashNeighbors.insert(node, node);
            //add if not already in hash w/ time stamp
            call hashNeighbors.insert(node, currentTimeStamp);
        } else {
            //updates time stamp
            call hashNeighbors.remove(node);
            call hashNeighbors.insert(node, currentTimeStamp);
        }

        // If a node comes back online:
        if(call hashActiveNodes.contains(node) == 0 && currentTimeStamp > 60000*5){
            dbg(NEIGHBOR_CHANNEL, "Node %d back online\n", node);

            // Insert node into Link State and Active Nodes
            linkStateUpdate(node, TOS_NODE_ID, (sendPackage.seq + 1), "1");

            // Let other nodes know a node has come online
            makePack(&sendPackage, TOS_NODE_ID, node, 19, 2, (sendPackage.seq + 1), "1", PACKET_MAX_PAYLOAD_SIZE);
            call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        }
    }

    void checkTimeStamps(){
        int * pNeighbors = call hashNeighbors.getKeys();
        int nCounter = call hashNeighbors.size();
        uint32_t currentTimeStamp = call periodicTimer.getNow();
        uint32_t neighborTimeStamp;
        int i;

        for(i = 0; i < nCounter; i++){

            neighborTimeStamp = call hashNeighbors.get(pNeighbors[i]);
            if((currentTimeStamp - neighborTimeStamp) > (60000*3)) {
                dbg(NEIGHBOR_CHANNEL, "Removed Neighbor %d\n", pNeighbors[i]);

                // Let other nodes know a node has disconnected
                makePack(&sendPackage, TOS_NODE_ID, pNeighbors[i], 19, 2, (sendPackage.seq + 1), "0", PACKET_MAX_PAYLOAD_SIZE);
                call Sender.send(sendPackage, AM_BROADCAST_ADDR);

                // Remove node from Link State and Active Nodes
                linkStateUpdate(TOS_NODE_ID, pNeighbors[i], (sendPackage.seq + 1), "0");

           } else {
                // Neighbor is still alive so do nothing
            }
        }
    }

    void initialProtocolTwo(){
        int * pNeighbors = call hashNeighbors.getKeys();
        int nCounter = call hashNeighbors.size();
        int i;

        for(i = 0; i < nCounter; i++){
           makePack(&sendPackage, TOS_NODE_ID, pNeighbors[i], 19, 2, (sendPackage.seq + 1), "1", PACKET_MAX_PAYLOAD_SIZE);
           call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        }
    }

    bool checkLinkState(uint16_t src, uint16_t dest, uint16_t seq, int cost){
        if(call hashLastUpdate.contains(src) == 1){
            // Old sequence number need to be less then the new seq number
            if(call hashLastUpdate.get(src) < seq){
                return TRUE;
            } else {
                return FALSE;
            }
        }

        return TRUE;
    }

    void linkStateUpdate(uint16_t src, uint16_t dest, uint16_t seq, int cost){
        // Update the Link State regardless (1=Connected , 0=Disconnected)
        nodeLS[src].cost[dest] = cost;

        // Do a refresh on the hash tables so there is no problems
        if(call hashLastUpdate.contains(src) == 1){
            call hashLastUpdate.remove(src);
        }

        if(call hashActiveNodes.contains(dest) == 1){
            call hashActiveNodes.remove(dest);
        }

        // Only add/update values into the hashtables if the node is determined to be online
        if(cost == 1){
            call hashActiveNodes.insert(dest, dest);
            call hashLastUpdate.insert(src, seq);
            dbg(NEIGHBOR_CHANNEL,"Node %d has been added to active nodes\n", dest);
            dbg(NEIGHBOR_CHANNEL,"Node %d has been added to Link State\n", dest);
            dbg(NEIGHBOR_CHANNEL,"Last update from Node %d was during sequence number %d\n", src, seq);
        } else {
            call hashLastUpdate.remove(dest); // Reset last update from disconnected node (seq number will be reset)
            dbg(NEIGHBOR_CHANNEL,"Node %d has been disconnected, sequence number reset initiated\n", dest);
            dbg(NEIGHBOR_CHANNEL,"Node %d has been removed from active nodes\n", dest);
            dbg(NEIGHBOR_CHANNEL,"Node %d has been removed from Link State\n", dest);
        }

        updateRoutingTable();
    }

    int minDistance(){
        int min = 999;
        int minIndex;
        int i;

        for(i = 0; i < 999; i++){
            if((myRoutingTable[i].processed == 0) && (myRoutingTable[i].cost <= min)){
                min = myRoutingTable[i].cost;
                minIndex = i;
            }
        }

        return minIndex;
    }

    void updateRoutingTable(){
        int nCount = call hashActiveNodes.size();
        int* pNeighbors = call hashActiveNodes.getKeys();
        // We have myRoutingTable that holds cost/hop aka solution
        int i;
        int u;
        int v;
        int k;

        for(k = 0; k < 999; k++){
            myRoutingTable[k].hop = 0;
            myRoutingTable[k].cost = 999;
            myRoutingTable[k].processed = 0;
        }

        // Set value of source node to be 0
        myRoutingTable[TOS_NODE_ID].cost = 0;

        // Calculating shortest path
        for(i = 0; i < 999-1; i++){
            u = minDistance();
            myRoutingTable[u].processed = 1;

            for(v = 0; v < 999; v++){
                if ((myRoutingTable[v].processed == 0) && nodeLS[u].cost[v] == 1 && myRoutingTable[u].cost != 999 && ((myRoutingTable[u].cost + nodeLS[u].cost[v]) < myRoutingTable[v].cost)){
                    myRoutingTable[v].cost = myRoutingTable[u].cost + nodeLS[u].cost[v];
                    if(myRoutingTable[u].hop == 0){
                        myRoutingTable[v].hop = v;
                    } else {
                        myRoutingTable[v].hop = myRoutingTable[u].hop;
                    }
                }
            }
        }
    }

    int getHop(int dest){
        return myRoutingTable[dest].hop;
    }
}

