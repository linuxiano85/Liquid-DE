#define _DEFAULT_SOURCE
#include <security/pam_modules.h>
#include <stdlib.h>
#include <string.h>

/* Disposable CI module: exercise the real libpam conversation contract. */
PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags,
                                  int argc, const char **argv) {
    (void)flags;
    if (argc != 1) return PAM_SYSTEM_ERR;
    const void *item = NULL;
    if (pam_get_item(pamh, PAM_USER, &item) != PAM_SUCCESS || item == NULL
        || strcmp(item, "liquidci") != 0) return PAM_AUTH_ERR;
    if (!strcmp(argv[0], "maxtries")) return PAM_MAXTRIES;
    if (pam_get_item(pamh, PAM_CONV, &item) != PAM_SUCCESS || item == NULL)
        return PAM_SYSTEM_ERR;
    const struct pam_conv *conversation = item;
    struct pam_message messages[] = {
        {PAM_TEXT_INFO, "private PAM informational text"},
        {PAM_ERROR_MSG, "private PAM error text"},
        {PAM_PROMPT_ECHO_OFF, "Password:"},
        {PAM_PROMPT_ECHO_OFF, "OTP:"}
    };
    const struct pam_message *pointers[] = {
        &messages[0], &messages[1], &messages[2], &messages[3]
    };
    if (!strcmp(argv[0], "echo")) messages[2].msg_style = PAM_PROMPT_ECHO_ON;
    int count = !strcmp(argv[0], "multiple") ? 4 : 3;
    struct pam_response *answers = NULL;
    int status = conversation->conv(count, pointers, &answers, conversation->appdata_ptr);
    if (status != PAM_SUCCESS) return status;
    if (answers == NULL || answers[2].resp == NULL) status = PAM_CONV_ERR;
    else if (!strcmp(argv[0], "length"))
        status = strlen(answers[2].resp) == 4096 ? PAM_SUCCESS : PAM_AUTH_ERR;
    else status = !strcmp(answers[2].resp, "päss\n\t$`\\\"word") ? PAM_SUCCESS : PAM_AUTH_ERR;
    for (int i = 0; i < count; ++i) {
        if (answers[i].resp) {
            explicit_bzero(answers[i].resp, strlen(answers[i].resp));
            free(answers[i].resp);
        }
    }
    free(answers);
    if (!strcmp(argv[0], "sequential")) {
        answers = NULL;
        int next = conversation->conv(1, &pointers[3], &answers, conversation->appdata_ptr);
        if (answers) { free(answers[0].resp); free(answers); }
        return next;
    }
    return status;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags,
                             int argc, const char **argv) {
    (void)pamh; (void)flags; (void)argc; (void)argv;
    return PAM_SUCCESS;
}
