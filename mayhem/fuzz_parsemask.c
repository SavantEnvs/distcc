/* Fuzz distccd's --allow ACL syntax: "A.B.C.D", "A.B.C.D/BITS" and
 * "A.B.C.D/MASK", then match an address against the parsed rule.
 * Input: 4 raw bytes (the client IPv4 address) followed by the rule text. */
#include <config.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>

#include "distcc.h"
#include "access.h"
#include "trace.h"

const char *rs_program_name = "fuzz_parsemask";

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void) argc;
    (void) argv;
    rs_trace_set_level(RS_LOG_EMERG);
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    struct sockaddr_in client;
    dcc_address_t value, mask;
    char *spec;

    if (size < 4 || size > 1024)
        return 0;

    spec = malloc(size - 4 + 1);
    if (!spec)
        return 0;
    memcpy(spec, data + 4, size - 4);
    spec[size - 4] = '\0';

    memset(&client, 0, sizeof client);
    client.sin_family = AF_INET;
    memcpy(&client.sin_addr, data, 4);

    if (dcc_parse_mask(spec, &value, &mask) == 0)
        (void) dcc_check_address((struct sockaddr *) &client, &value, &mask);

    free(spec);
    return 0;
}
