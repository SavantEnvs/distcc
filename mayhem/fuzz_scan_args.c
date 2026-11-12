/* Fuzz distcc's compiler command-line scanning: the client decides from the
 * arguments whether a compile can be distributed (dcc_scan_args), which
 * options are stripped before preprocessing (dcc_strip_local_args), how
 * -Wp, options are expanded, and how the .d file is derived (dcc_get_dotd_info).
 * Input: one compiler argument per line; argv[0] is always "cc". */
#include <config.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "distcc.h"
#include "dotd.h"
#include "trace.h"

const char *rs_program_name = "fuzz_scan_args";

#define MAX_ARGS 64

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void) argc;
    (void) argv;
    rs_trace_set_level(RS_LOG_EMERG);
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    char *text, *p;
    char *args[MAX_ARGS + 2];
    int n = 0;

    if (size > 4096)
        return 0;

    text = malloc(size + 1);
    if (!text)
        return 0;
    memcpy(text, data, size);
    text[size] = '\0';

    args[n++] = (char *) "cc";
    for (p = text; p && n <= MAX_ARGS;) {
        char *nl = strchr(p, '\n');
        if (nl)
            *nl = '\0';
        args[n++] = p;
        p = nl ? nl + 1 : NULL;
    }
    args[n] = NULL;

    /* Same order as dcc_build_somewhere(): expand -Wp, options, scan, and only for a
     * distributable compile strip the cpp-only options and work out the .d file. */
    {
        char **copy = NULL, **newargv = NULL;
        char *in = NULL, *out = NULL;

        if (dcc_copy_argv(args, &copy, 0) == 0) {
            if (dcc_expand_preprocessor_options(&copy) == 0) {
                int scan = dcc_scan_args(copy, &in, &out, &newargv);

                dcc_free_argv(copy);
                if (scan == 0) {
                    char **stripped = NULL, *dotd = NULL, *target = NULL;
                    int needs_dotd, sets_target;

                    if (dcc_strip_local_args(newargv, &stripped) == 0)
                        free(stripped);
                    if (dcc_get_dotd_info(newargv, &dotd, &needs_dotd, &sets_target, &target) == 0)
                        free(dotd);
                }
                if (newargv)
                    dcc_free_argv(newargv);
            } else {
                dcc_free_argv(copy);
            }
        }
    }

    free(text);
    return 0;
}
