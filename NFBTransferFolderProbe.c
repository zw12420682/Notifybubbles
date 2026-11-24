#ifndef __APPLE__
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>
#ifdef __APPLE__
#include <dlfcn.h>
#include <pthread.h>
#endif

static const char inputName[] = "中转读写测试.txt";
static const char input[] = "Minis 中转目录读写测试。看到这行就说明「文件」App 能看到 Minis 写入的文件。此文件可删除。\n";
static const char outputName[] = "NotifyBubbles 真机读写通过.txt";
static const char output[] = "NotifyBubbles 中转目录测试通过。\nSpringBoard 读取并校对了 Minis 的测试文件，随后在同一个目录写入并读回了本文件。此文件可删除。\n";

static int NFBReadExact(int fd, const char *expected, size_t size) {
    char buf[256];
    size_t at = 0;
    if (size >= sizeof(buf)) return -1;
    while (at <= size) {
        ssize_t n = read(fd, buf + at, size + 1 - at);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) return errno;
        if (!n) return at == size && !memcmp(buf, expected, size) ? 0 : -1;
        at += (size_t)n;
    }
    return -1;
}

static int NFBWriteExact(int fd, const char *msg, size_t len) {
    while (len) {
        ssize_t n = write(fd, msg, len);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) return errno;
        if (!n) return -1;
        msg += n;
        len -= (size_t)n;
    }
    return 0;
}

static int NFBFolderCheck(const char *path) {
    int dir = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int status = 0;
    const char *stage = "open directory";
    if (dir < 0) { status = errno; goto done; }
    stage = "read Minis marker";
    int in = openat(dir, inputName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (in < 0) { status = errno; goto done; }
    status = NFBReadExact(in, input, sizeof(input) - 1);
    close(in);
    if (status) goto done;
    stage = "create (existing files never overwritten)";
    int out = openat(dir, outputName, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644);
    if (out < 0) { status = errno; goto done; }
    // No success text is written until the first IO round trip has completed.
    static const char checking[] = "NotifyBubbles 正在验证真机读写…\n";
    stage = "write/read temporary contents";
    status = NFBWriteExact(out, checking, sizeof(checking) - 1);
    if (!status && lseek(out, 0, 0) < 0) status = errno;
    if (!status) status = NFBReadExact(out, checking, sizeof(checking) - 1);
    stage = status ? stage : "write/read confirmation";
    if (!status && lseek(out, 0, 0) < 0) status = errno;
    if (!status) status = NFBWriteExact(out, output, sizeof(output) - 1);
    if (!status && lseek(out, 0, 0) < 0) status = errno;
    if (!status) status = NFBReadExact(out, output, sizeof(output) - 1);
    if (close(out) && !status) status = errno;
 done:
    if (dir >= 0) close(dir);
    if (status) syslog(LOG_ERR, "[NFBTransferFolderProbe] %s: %d", stage, status);
    else syslog(LOG_NOTICE, "[NFBTransferFolderProbe] PASS: read original marker, create, write and read back");
    return status;
}

#if defined(__APPLE__)
static void *NFBRunFolderCheck(void *ignored) {
    (void)ignored;
    // Path configuration stays beside this dylib inside the current bootstrap.
    Dl_info info;
    char config[4096], path[4096];
    if (!dladdr((const void *)&inputName, &info) || !info.dli_fname) goto bad;
    const char *last = strrchr(info.dli_fname, '/');
    if (!last) goto bad;
    int len = snprintf(config, sizeof(config), "%.*s/NFBTransferFolderProbe.path", (int)(last - info.dli_fname), info.dli_fname);
    if (len < 0 || (size_t)len >= sizeof(config)) goto bad;
    FILE *f = fopen(config, "r");
    if (!f) goto bad;
    char *line = fgets(path, sizeof(path), f);
    fclose(f);
    if (!line || path[0] != '/' || !strchr(path, '\n')) goto bad;
    *strchr(path, '\n') = '\0';
    NFBFolderCheck(path);
    return 0;
 bad:
    syslog(LOG_ERR, "[NFBTransferFolderProbe] missing or invalid local path config");
    return 0;
}
__attribute__((constructor)) static void NFBStartFolderProbe(void) {
    const char *name = getprogname();
    if (!name || strcmp(name, "SpringBoard")) return;
    pthread_t task;
    int result = pthread_create(&task, 0, NFBRunFolderCheck, 0);
    if (!result) pthread_detach(task);
    else syslog(LOG_ERR, "[NFBTransferFolderProbe] pthread_create: %d", result);
}
#else
int main(int argc, char **argv) { return argc == 2 && NFBFolderCheck(argv[1]) == 0 ? 0 : 1; }
#endif
