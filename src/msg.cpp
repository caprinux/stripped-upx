/* msg.cpp -- info and error messages

   This file is part of the UPX executable compressor.

   Copyright (C) 1996-2025 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 1996-2025 Laszlo Molnar
   All Rights Reserved.

   UPX and the UCL library are free software; you can redistribute them
   and/or modify them under the terms of the GNU General Public License as
   published by the Free Software Foundation; either version 2 of
   the License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; see the file COPYING.
   If not, write to the Free Software Foundation, Inc.,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

   Markus F.X.J. Oberhumer              Laszlo Molnar
   <markus@oberhumer.com>               <ezerotven+github@gmail.com>
 */

#include "util/system_headers.h"
#include <typeinfo> // typeid()
#include "conf.h"

/*************************************************************************
//
**************************************************************************/

static int pr_need_nl = 0;

void printSetNl(int need_nl) noexcept { pr_need_nl = need_nl; }

void printClearLine(FILE *f) noexcept {
    static char clear_line_msg[1 + 79 + 1 + 1];
    if (!clear_line_msg[0]) {
        char *msg = clear_line_msg;
        msg[0] = '\r';
        memset(msg + 1, ' ', 79);
        msg[80] = '\r';
        msg[81] = 0;
    }

    fflush(stdout);
    fflush(stderr);
    if (f == nullptr)
        f = stdout;
    con_fprintf(f, "%s", clear_line_msg); // NOLINT(clang-analyzer-unix.Stream)
    fflush(f);
    printSetNl(0);
}

static void pr_print(bool c, const char *msg) noexcept {
    if (c && !opt->to_stdout)
        con_fprintf(stderr, "%s", msg);
    else
        fprintf(stderr, "%s", msg);
}

static void pr_error(const char *iname, const char *msg, bool is_warning) noexcept {
    fflush(stdout);
    fflush(stderr);
    char buf[1024];
    buf[0] = 0;
    if (pr_need_nl == 2)
        printClearLine(stdout);
    else if (pr_need_nl) {
        buf[0] = '\n';
        buf[1] = 0;
        printSetNl(0);
    }

    // This hack is needed, otherwise error messages may get lost
    // when the cursor is not yet at the bottom of the screen.
    // At least I can use some colors then...
    bool c = acc_isatty(STDERR_FILENO) ? 1 : 0;

    int fg = con_fg(stderr, FG_BRTRED);
    upx_safe_snprintf(buf + strlen(buf), sizeof(buf) - strlen(buf), "%s: ", progname);
    pr_print(c, buf);
    //(void)con_fg(stderr,FG_RED);
    upx_safe_snprintf(buf, sizeof(buf), "%s: ", iname);
    pr_print(c, buf);
    //(void)con_fg(stderr,FG_BRTRED);
    pr_print(c, msg);
    pr_print(c, "\n");
    fflush(stdout);
    fflush(stderr);
    fg = con_fg(stderr, fg);

    UNUSED(is_warning);
    UNUSED(fg);
}

void printErr(const char *iname, const Throwable &e) noexcept {
    char buf[1024];
    size_t l;

    upx_safe_snprintf(buf, sizeof(buf), "%s", prettyExceptionName(typeid(e).name()));
    l = strlen(buf);
    if (l < sizeof(buf) && e.getMsg())
        upx_safe_snprintf(buf + l, sizeof(buf) - l, ": %s", e.getMsg());
    l = strlen(buf);
    if (l < sizeof(buf) && e.getErrno()) {
        upx_safe_snprintf(buf + l, sizeof(buf) - l, ": %s", strerror(e.getErrno()));
#if 1
        // some compilers (e.g. Borland C++) put a trailing '\n'
        // into the strerror() result
        l = strlen(buf);
        while (l-- > 0 && (buf[l] == '\n' || buf[l] == ' '))
            buf[l] = 0;
#endif
    }
    pr_error(iname, buf, e.isWarning());
}

void printErr(const char *iname, const char *format, ...) noexcept {
    va_list args;
    char buf[1024];

    va_start(args, format);
    upx_safe_vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);

    pr_error(iname, buf, false);
}

void printWarn(const char *iname, const char *format, ...) noexcept {
    va_list args;
    char buf[1024];

    va_start(args, format);
    upx_safe_vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);

    pr_error(iname, buf, true);
}

void printUnhandledException(const char *iname, const std::exception *e) noexcept {
    if (e != nullptr)
        printErr(iname, "unhandled exception: %s\n", prettyExceptionName(e->what()));
    else
        printErr(iname, "internal error: unhandled exception!\n");
    if (opt->cmd != CMD_COMPRESS) {
        printErr(iname, "  this file has possibly been modified/hacked; take care!\n");
    }
}

/*************************************************************************
// info
**************************************************************************/

static int info_header = 0;

static void info_print(const char *msg) {
    if (opt->info_mode <= 0)
        return;
    FILE *f = opt->to_stdout ? stderr : stdout;
    if (pr_need_nl) {
        printClearLine(f);
        con_fprintf(f, "%s\n", msg);
    } else if (pr_need_nl)
        con_fprintf(f, "\n%s\n", msg);
    else
        con_fprintf(f, "%s\n", msg);
    fflush(f);
    printSetNl(0);
}

void infoHeader() { info_header = 0; }

void infoHeader(const char *format, ...) {
    if (opt->info_mode <= 0)
        return;
    va_list args;
    char buf[1024];
    va_start(args, format);
    upx_safe_vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    info_print(buf);
    info_header = 1;
}

void info(const char *format, ...) {
    if (opt->info_mode <= 0)
        return;
    va_list args;
    char buf[1024];
    const int n = 4 * info_header;
    memset(buf, ' ', n);
    va_start(args, format);
    upx_safe_vsnprintf(buf + n, sizeof(buf) - n, format, args);
    va_end(args);
    info_print(buf);
}

void infoWarning(const char *format, ...) {
    if (opt->info_mode <= 0)
        return;
    va_list args;
    char buf[1024];
    va_start(args, format);
    upx_safe_vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    info("[WARNING] %s\n", buf);
}

void infoWriting(const char *what, upx_int64_t size) {
    if (opt->info_mode <= 0)
        return;
    info("Writing %s: %lld bytes", what, size);
}

/* vim:set ts=4 sw=4 et: */
