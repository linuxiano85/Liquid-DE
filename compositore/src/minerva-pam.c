#define _DEFAULT_SOURCE
#include <ctype.h>
#include <errno.h>
#include <pwd.h>
#include <security/pam_appl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

/* Run as the locked-in user, never setuid. exec gives PAM a fresh process
 * without the GUI's inherited mutexes. A single password arrives via stdin
 * up to EOF; no credential, PAM message or account name is printed. */
struct response {
    char secret[4097];
    bool supplied;
    bool unsupported;
};

static void erase(void *data, size_t size) {
    volatile unsigned char *p = data;
    while (size--) *p++ = 0;
}

static int converse(int count, const struct pam_message **messages,
                    struct pam_response **output, void *context) {
    struct response *input = context;
    if (count <= 0 || count > PAM_MAX_NUM_MSG || messages == NULL || output == NULL)
        return PAM_CONV_ERR;
    struct pam_response *answers = calloc((size_t)count, sizeof(*answers));
    if (answers == NULL) return PAM_BUF_ERR;
    for (int i = 0; i < count; ++i) {
        if (messages[i] == NULL) goto fail;
        switch (messages[i]->msg_style) {
        case PAM_PROMPT_ECHO_OFF:
            /* Do not silently reuse the login password for OTP/PIN prompts. */
            if (input->supplied) { input->unsupported = true; goto fail; }
            answers[i].resp = strdup(input->secret);
            if (answers[i].resp == NULL) goto fail;
            input->supplied = true;
            erase(input->secret, sizeof(input->secret));
            break;
        case PAM_TEXT_INFO:
        case PAM_ERROR_MSG:
            break;
        default:
            input->unsupported = true;
            goto fail;
        }
    }
    *output = answers;
    return PAM_SUCCESS;
fail:
    for (int i = 0; i < count; ++i) {
        if (answers[i].resp != NULL) {
            erase(answers[i].resp, strlen(answers[i].resp));
            free(answers[i].resp);
        }
    }
    free(answers);
    return PAM_CONV_ERR;
}

static bool valid_service(const char *service) {
    size_t length = strlen(service);
    if (length == 0 || length > 128 || service[0] == '.') return false;
    for (size_t i = 0; i < length; ++i) {
        unsigned char c = (unsigned char)service[i];
        if (!isalnum(c) && c != '-' && c != '_' && c != '.') return false;
    }
    char path[160];
    if (snprintf(path, sizeof(path), "/etc/pam.d/%s", service) >= (int)sizeof(path))
        return false;
    struct stat info;
    /* Missing services must not silently fall back to /etc/pam.d/other. */
    return stat(path, &info) == 0 && S_ISREG(info.st_mode)
        && info.st_uid == 0 && !(info.st_mode & (S_IWGRP | S_IWOTH));
}

int main(int argc, char **argv) {
    struct response input = {0};
    int exit_code = 3;
    const char *result = "error";
    pam_handle_t *handle = NULL;
    struct rlimit no_core = {0, 0};
    if (setrlimit(RLIMIT_CORE, &no_core) != 0) goto done;
    if (getuid() != geteuid() || getgid() != getegid()) goto done;
    pid_t parent = getppid();
    if (parent == 1 || prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || getppid() != parent)
        goto done;
    alarm(65);
    if (argc != 2 || !valid_service(argv[1])) goto done;
    struct passwd *user = getpwuid(getuid());
    if (user == NULL) goto done;
    size_t used = 0;
    for (;;) {
        ssize_t n = read(STDIN_FILENO, input.secret + used, sizeof(input.secret) - used);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) goto done;
        if (n == 0) break;
        used += (size_t)n;
        if (used == sizeof(input.secret)) goto done;
    }
    if (used == 0 || memchr(input.secret, '\0', used) != NULL) goto done;
    input.secret[used] = '\0';
    struct pam_conv conversation = {.conv = converse, .appdata_ptr = &input};
    int status = pam_start(argv[1], user->pw_name, &conversation, &handle);
    if (status == PAM_SUCCESS) status = pam_authenticate(handle, 0);
    if (handle != NULL && pam_end(handle, status) != PAM_SUCCESS) status = PAM_SYSTEM_ERR;
    if (input.unsupported) { result = "unsupported"; exit_code = 4; }
    else if (status == PAM_SUCCESS) { result = "ok"; exit_code = 0; }
    else if (status == PAM_AUTH_ERR) { result = "denied"; exit_code = 1; }
    else if (status == PAM_MAXTRIES) { result = "maxtries"; exit_code = 2; }
done:
    erase(&input, sizeof(input));
    puts(result);
    return exit_code;
}
