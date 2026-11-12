/* Fuzz the distcc wire-protocol readers (rpc.c / srvrpc.c): the 12-byte
 * "TOKN" + hex-value framing, length-prefixed strings and the ARGC/ARGV
 * vector the daemon reads from any client on the network.  The input is
 * delivered through a pipe; its first byte selects which reader sequence runs. */
#include <config.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "distcc.h"
#include "rpc.h"
#include "trace.h"

const char *rs_program_name = "fuzz_protocol";

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void) argc;
    (void) argv;
    rs_trace_set_level(RS_LOG_EMERG);
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    int fds[2];
    enum dcc_protover ver;
    unsigned val;
    char token[5];
    char *s = NULL, **argv = NULL;
    int status;

    if (size < 1 || size > 4096)
        return 0;
    if (pipe(fds) != 0)
        return 0;
    if (write(fds[1], data + 1, size - 1) != (ssize_t) (size - 1)) {
        close(fds[0]);
        close(fds[1]);
        return 0;
    }
    close(fds[1]);

    switch (data[0] & 3) {
    case 0:
        if (dcc_r_request_header(fds[0], &ver) == 0
            && dcc_r_cwd(fds[0], &s) == 0
            && dcc_r_argv(fds[0], "ARGC", "ARGV", &argv) == 0) {
            if (argv)
                dcc_free_argv(argv);
            argv = NULL;
        }
        break;
    case 1:
        (void) dcc_r_sometoken_int(fds[0], token, &val);
        break;
    case 2:
        (void) dcc_r_token_string(fds[0], "DOTI", &s);
        break;
    default:
        if (dcc_r_result_header(fds[0], DCC_VER_1) == 0)
            (void) dcc_r_cc_status(fds[0], &status);
        break;
    }

    free(s);
    free(argv);
    close(fds[0]);
    return 0;
}
