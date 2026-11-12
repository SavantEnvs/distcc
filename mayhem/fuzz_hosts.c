/* Fuzz distcc's host list parser (the DISTCC_HOSTS / hosts-file syntax):
 * TCP, SSH, localhost, slot counts, option suffixes and --randomize. */
#include <config.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "distcc.h"
#include "hosts.h"
#include "trace.h"

const char *rs_program_name = "fuzz_hosts";

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void) argc;
    (void) argv;
    rs_trace_set_level(RS_LOG_EMERG);
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    char *spec;
    struct dcc_hostdef *list = NULL, *e, *next;
    int nhosts = 0;

    if (size > 4096)
        return 0;

    spec = malloc(size + 1);
    if (!spec)
        return 0;
    memcpy(spec, data, size);
    spec[size] = '\0';

    /* Even on a parse error the hosts built so far stay linked from list. */
    (void) dcc_parse_hosts(spec, "fuzz", &list, &nhosts, NULL);
    for (e = list; e; e = next) {
        next = e->next;
        dcc_free_hostdef(e);
    }

    free(spec);
    return 0;
}
