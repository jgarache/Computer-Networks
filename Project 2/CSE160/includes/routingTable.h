#ifndef ROUTINGTABLE_H
#define ROUTINGTABLE_H

typedef nx_struct routingTable{
    nx_uint16_t hop;
    nx_uint16_t cost;
    nx_uint16_t processed;
}routingTable[999];

#endif
