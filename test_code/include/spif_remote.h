//************************************************//
//*                                              *//
//* functions to interact with spif              *//
//* from SpiNNaker                               *//
//*                                              *//
//* lap - 08/06/2021                             *//
//*                                              *//
//************************************************//

#ifndef __SPIF_REMOTE_H__
#define __SPIF_REMOTE_H__

#include "spif.h"


//--------------------------------------------------------------------
// spif (remote) and spiNNlink (local) configuration routing keys and masks
//--------------------------------------------------------------------
#define PER_KEY            0xfffe0000    // peripheral packets
#define PER_MSK            0xffff0000    // peripheral packets
#define LCFG_KEY           0xfffffe00    // spiNNlink configuration
#define LCFG_MSK           0xffffff00    // spiNNlink configuration
#define RCFG_KEY           0xffffff00    // spif configuration
#define RCFG_MSK           0xffffff00    // spif configuration
#define RPLY_KEY           0xfffffd00    // diagnostic counter packets
#define RPLY_MSK           0xffffff00    // diagnostic counter packets
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// spiNNlink (local) configuration registers
//NOTE: in most cases payload carries the value
//--------------------------------------------------------------------
#define LCFG_PKEY          2
#define LCFG_PMSK          3
#define LCFG_LCKEY         12
#define LCFG_LCMSK         13
#define LCFG_RCKEY         14
#define LCFG_RCMSK         15
#define LCFG_STOP          16
#define LCFG_START         17
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// helpful macros
//--------------------------------------------------------------------
// spif is always connected to the SOUTH link of chip (0, 0)
#define ROUTE_TO_SPIF         (1 << 5)
#define ROUTE_TO_CORE(core)   (1 << (core + 6))
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// initialise spif and spiNNlink resources
//--------------------------------------------------------------------
uint spif_init ()
{
  // initialise spif configuration MC routing table entries
  // -----------------------------------------------------------------
  uint entry = rtr_alloc (3);
  if (entry == 0) {
    return (FAILURE);
  }

  // setup local configuration route
  rtr_mc_set (entry,
               LCFG_KEY,
               LCFG_MSK,
               ROUTE_TO_SPIF
             );

  // setup remote configuration route
  rtr_mc_set (entry + 1,
               RCFG_KEY,
               RCFG_MSK,
               ROUTE_TO_SPIF
             );

  // identify this core for reply messages
  uint core = spin1_get_core_id ();

  // setup remote reply configuration route
  rtr_mc_set (entry + 2,
               RPLY_KEY,
               RPLY_MSK,
               ROUTE_TO_CORE(core)
             );

  return (SUCCESS);
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// set value of key used to identify input peripheral packets
//--------------------------------------------------------------------
void spif_set_peripheral_key (uint key)
{
  while (!spin1_send_mc_packet (
          LCFG_KEY | LCFG_PKEY,
          key,
          WITH_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// set value of mask used to identify input peripheral packets
//--------------------------------------------------------------------
void spif_set_peripheral_mask (uint mask)
{
  while (!spin1_send_mc_packet (
          LCFG_KEY | LCFG_PMSK,
          mask,
          WITH_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// set value of input router key
//--------------------------------------------------------------------
void spif_set_routing_key (uint entry, uint key)
{
  while (!spin1_send_mc_packet (
          RCFG_KEY | (SPIF_ROUTER_KEY + entry),
          key,
          WITH_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// set value of input router mask
//--------------------------------------------------------------------
void spif_set_routing_mask (uint entry, uint mask)
{
  while (!spin1_send_mc_packet (
          RCFG_KEY | (SPIF_ROUTER_MASK + entry),
          mask,
          WITH_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// set value of input router route
//--------------------------------------------------------------------
void spif_set_routing_route (uint entry, uint route)
{
  while (!spin1_send_mc_packet (
          RCFG_KEY | (SPIF_ROUTER_ROUTE + entry),
          route,
          WITH_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// set value of cycle count before input packet is dropped on spif
//--------------------------------------------------------------------
void spif_set_input_drop_wait (uint wait)
{
  while (!spin1_send_mc_packet (
          RCFG_KEY | SPIF_IN_DROP_WAIT,
          wait,
          WITH_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// set value of mapper key
//--------------------------------------------------------------------
void spif_set_mapper_key (uint map, uint key)
{
  while (!spin1_send_mc_packet (
          RCFG_KEY | (SPIF_MAPPER_KEY + map),
          key,
          WITH_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// set value of mapper field mask
//--------------------------------------------------------------------
void spif_set_mapper_field_mask (uint map, uint field, uint mask)
{
  while (!spin1_send_mc_packet (
          RCFG_KEY | (SPIF_MAPPER_MASK + (SPIF_MPREGS_NUM * map) + field),
          mask,
          WITH_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// set value of mapper field shift
//
//NOTE; negative shift indicates left shift
//--------------------------------------------------------------------
void spif_set_mapper_field_shift (uint map, uint field, uint shift)
{
  while (!spin1_send_mc_packet (
          RCFG_KEY | (SPIF_MAPPER_SHIFT + (SPIF_MPREGS_NUM * map) + field),
          shift,
          WITH_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// allow peripheral input packets in
//--------------------------------------------------------------------
void spif_start_input (void)
{
  while (!spin1_send_mc_packet (
          LCFG_KEY | LCFG_START,
          0,
          NO_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// stop peripheral input packets (not configuration packets)
//
//NOTE: packets are stopped on spiNNlink not spif
//--------------------------------------------------------------------
void spif_stop_input (void)
{
  while (!spin1_send_mc_packet (
          LCFG_KEY | LCFG_STOP,
          0,
          NO_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// read a spif diagnostic counter
//--------------------------------------------------------------------
void spif_read_counter (uint counter)
{
  // send counter read request
  while (!spin1_send_mc_packet (
          RCFG_KEY | counter,
          0,
          NO_PAYLOAD)
        );
}
//--------------------------------------------------------------------


//--------------------------------------------------------------------
// reset all spif diagnostic counters
//
//NOTE: assumes that all counters occupy contiguous registers
//--------------------------------------------------------------------
void spif_reset_counters ()
{
  // clear spif diagnostic packet counters
  for (uint i = 0; i < SPIF_DCREGS_NUM; i++) {
     while (!spin1_send_mc_packet (
             RCFG_KEY | SPIF_COUNT_OUT + i,
             0,
             WITH_PAYLOAD)
           );
  }
}
//--------------------------------------------------------------------


#endif /* __SPIF_REMOTE_H__ */
