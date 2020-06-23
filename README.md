# Computer-Networks

Both projects were done in NesC, a derivative of C.

Table of Contents:

Project 1 - Flooding and Neighbor Discovery:

Delivered a package while implementing flooding and neighbor discovery in a network. In flooding, the objective was to enable a package to be delivered to a certain location even when the location was unknown by passing a copy of the package to neighbors and
having them pass it to their neighbors in hope that it would eventually get to the destination. For neighbor discovery, the objective was to create a method on figuring out neighboring nodes using the given package header file.


Project 2 - Link State Routing:

Expanded upong Project 1 and included link state, routing tables, and the ability to forward packets throughout the network. Creating and sending the link state was implemented first because the routing table and forwarding utilize the link state during computation. A structure called Link State was created that contains an array called cost that would store the cost between each node.  The number of cost in our implementation correlated to the number of hops required to reach the destination node.  To start creating the Link State, each node determines its neighbors through neighbor discovery. A timer starts the neighbor discovery process as well as the Link State creation. Neighbors are stored inside a hash table with their key values representing the TOS_NODE_ID and the input being the time stamp in which it was added to the table. The time stamp are recorded to determine if a node is still active within the network and update as time progresses. Link State packets are then propagated throughout the network so that each node will have a copy of every known node and their connections in the network. An instance of Link State called NodeLS would be the structure that contains the connections between the nodes. NodeLS stores the node and its cost to traverse toward it. The Link States are restructured during two occurrences: when a node is dropped from the network or added. To check for these, every five minutes, a check is done to determine if any new nodes have been added to the network and therefore informs the node to neighbor discover and reconstruct their Link States.
