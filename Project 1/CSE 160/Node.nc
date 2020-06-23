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

module Node{
   uses interface Boot;
   uses interface Timer<TMilli> as periodicTimer; 

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;
}

implementation{
   pack sendPackage;
   uint16_t recievedSeq[100];
   uint16_t recievedSrc[100];
   int neighbors[10];
   int neighborCount = 0;
   int recievedCounter = 0;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   bool checkPackages(uint16_t src, uint16_t seq);
   void addNeighbor(uint16_t node);

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
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         
         if(myMsg->dest != 0)
         {
		 dbg(FLOODING_CHANNEL, "Package Sent From: %d\n", myMsg->src);
		 dbg(FLOODING_CHANNEL, "Package Sequence Number: %d\n", myMsg->seq);
		 dbg(FLOODING_CHANNEL, "Package TTL: %d\n", myMsg->TTL);
		//checks to see if package destination is the final destination
		 if(myMsg->dest == TOS_NODE_ID) {
	 	        dbg(FLOODING_CHANNEL, "Package has reached destination\n");
		 	return msg;
	 	}
		 else if (myMsg->TTL > 0 && !(checkPackages(myMsg->src, myMsg->seq)) && (myMsg->src != TOS_NODE_ID)){
		 	//repackages package and sends to neighboring nodes
	 		dbg(FLOODING_CHANNEL, "Flooding...\n");
		 	makePack(&sendPackage, myMsg->src, myMsg->dest, (myMsg->TTL - 1), 0, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
		 	call Sender.send(sendPackage, AM_BROADCAST_ADDR);
		 	return msg;
		 }
		 else
		 {
		 	dbg(FLOODING_CHANNEL, "TTL termination/Duplicate Package\n");
		 	return msg;
		 }
         }
         	// THE FOLLOWING IS FOR NEIGHBOR DISCOVERY
         	dbg(NEIGHBOR_CHANNEL, "Neighbor is: %d\n", myMsg->src);
         	addNeighbor(myMsg->src);
         	dbg(NEIGHBOR_CHANNEL, "Number of Neighbors: %d\n", neighborCount);
         	return msg;
      }

      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 19, 0, (sendPackage.seq + 1), payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
      //call Sender.send(sendPackage, destination);
   }

   event void CommandHandler.printNeighbors(){
   	int i;
   	printf("Neighbors for %d: ", TOS_NODE_ID);
   	for(i = 0; i < 10; i++)
   	{
   		if(neighbors[i] > 0)
   		{
   			printf("%d ", neighbors[i]);
		}
   	}
   	
   	printf("\n");
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}
   
   event void periodicTimer.fired(){
   	neighborCount = 0;
   
	makePack(&sendPackage, TOS_NODE_ID, 0, 0, 0, 0, "TIMER", PACKET_MAX_PAYLOAD_SIZE);
      	call Sender.send(sendPackage, AM_BROADCAST_ADDR);
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
   	int i;
   	for(i = 0; i < 100; i++)
   	{
   		if(src ==  recievedSrc[i] && seq == recievedSeq[i])
   		{
   			return TRUE; //Found
   		}
   	}
   	
   	recievedSrc[recievedCounter] = src;
   	recievedSeq[recievedCounter] = seq;
   	
   	if(recievedCounter != 99)
   		recievedCounter = recievedCounter + 1; //Increment Counter
	else
		recievedCounter = 0; //Reset counter
		
   	return FALSE; //Not Found
   }
   
   void addNeighbor(uint16_t node)
   {
   	int i, found;
   	for(i = 0, found = 0; i < 10; i++)
   	{
   		if(node == neighbors[i])
   		{
   			found = found + 1;
   		}
   	}
   	
   	if(found == 0)
   	{
   		neighbors[neighborCount] = node;
		neighborCount = neighborCount + 1;
   	}
   }
   
}
