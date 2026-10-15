//  The whole C surface of the Rust oracle. Four calls: wake it, talk to it,
//  hand memory back, put it to sleep. Everything else travels as opaque bytes.

#ifndef VERDANT_ORACLE_H
#define VERDANT_ORACLE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Oracle Oracle;

/// Boots an oracle from a sealed profile blob. Pass NULL/0 for a fresh start.
/// `tongue` picks a compiled language: 0 English, 1 Russian.
Oracle *vr_awaken(const uint8_t *blob, size_t span, uint8_t tongue);

/// Sends one numbered request and returns a freshly allocated binary frame.
/// The caller owns the result and must release it with vr_reclaim.
uint8_t *vr_relay(Oracle *handle,
                  uint32_t op,
                  const uint8_t *body,
                  size_t span,
                  size_t *out_span);

/// Releases a frame handed out by vr_relay.
void vr_reclaim(uint8_t *head, size_t span);

/// Tears the oracle down.
void vr_slumber(Oracle *handle);

#ifdef __cplusplus
}
#endif

#endif /* VERDANT_ORACLE_H */
