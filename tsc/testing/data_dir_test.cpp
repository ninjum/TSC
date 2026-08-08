/***************************************************************************
 * data_dir_test.cpp  -  tests for finding the game data directory
 *
 * Copyright © 2012-2020 The TSC Contributors
 ***************************************************************************/
/*
   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 3 of the License, or
   (at your option) any later version.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/* What this pins is the bug the 2.2.0-beta2 AppImage shipped with: the game
 * looked for its data at the path compiled into it, /usr/share/tsc, which
 * inside an AppImage does not exist - the tree is mounted under
 * /tmp/.mount_TSCxxxxxx - so it aborted with
 *
 *   CEGUI::FileIOException ... /usr/share/tsc/gui/schemes/TSCLook256.scheme
 *   does not exist
 *
 * before drawing anything. The tests below drive Determine_Game_Data_Dir()
 * with a FAKE set of existing directories, so they need no installed game,
 * no boost and no display, and can run on any machine:
 *
 *   g++ -std=c++17 -I../src/core/filesystem -o data_dir_test \
 *       data_dir_test.cpp ../src/core/filesystem/data_dir.cpp && ./data_dir_test
 *
 * which is what run-tests.sh does.
 */

#include "data_dir.hpp"

#include <cstdlib>
#include <iostream>
#include <set>
#include <string>

using namespace TSC;

namespace {

int g_failures = 0;
int g_checks = 0;

void check_equal(const std::string& what, const std::string& got, const std::string& expected)
{
    g_checks++;

    if (got == expected) {
        std::cout << "ok   - " << what << std::endl;
    }
    else {
        std::cout << "FAIL - " << what << std::endl
                  << "       expected: " << expected << std::endl
                  << "       got:      " << got << std::endl;
        g_failures++;
    }
}

void check_true(const std::string& what, bool condition)
{
    g_checks++;

    if (condition) {
        std::cout << "ok   - " << what << std::endl;
    }
    else {
        std::cout << "FAIL - " << what << std::endl;
        g_failures++;
    }
}

/* A pretend filesystem: only the directories put in here exist. */
class FakeTree {
public:
    explicit FakeTree(const std::set<std::string>& dirs) : m_dirs(dirs) {}

    DirExistsFn exists_fn() const
    {
        std::set<std::string> dirs = m_dirs;
        return [dirs](const std::string& path) -> bool {
            return dirs.count(path) > 0;
        };
    }

private:
    std::set<std::string> m_dirs;
};

const char* const PREFIX  = "/usr";
const char* const DATADIR = "share";

/* The mount point an AppImage runs from, and where its copy of the tree is. */
const char* const MOUNT   = "/tmp/.mount_TSCabc123";
const char* const MOUNTED_DATA = "/tmp/.mount_TSCabc123/usr/share/tsc";
const char* const MOUNTED_EXE  = "/tmp/.mount_TSCabc123/usr/bin/tsc";

}

int main()
{
    // The compiled-in path itself is unchanged: a relative datadir hangs off
    // the prefix, an absolute one stands on its own.
    check_equal("relative datadir resolves against the prefix",
                Compiled_Game_Data_Dir("/usr", "share"), "/usr/share/tsc");
    check_equal("absolute datadir is taken as it is",
                Compiled_Game_Data_Dir("/usr", "/opt/data"), "/opt/data/tsc");
    check_equal("a prefix with a trailing slash does not double it",
                Compiled_Game_Data_Dir("/usr/local/", "share"), "/usr/local/share/tsc");

    // An installed package: everything points at the same place, and the
    // answer is the one TSC has always given.
    {
        FakeTree tree({"/usr/share/tsc"});
        check_equal("an installed TSC uses the compiled-in path",
                    Determine_Game_Data_Dir(NULL, NULL, "/usr/bin/tsc", PREFIX, DATADIR,
                                            tree.exists_fn()),
                    "/usr/share/tsc");
    }

    // Nothing exists anywhere: still the compiled-in path, so the error
    // message a broken install produces stays the one users have reported.
    {
        FakeTree tree({});
        check_equal("with nothing installed the compiled-in path is still the answer",
                    Determine_Game_Data_Dir(NULL, NULL, "/usr/bin/tsc", PREFIX, DATADIR,
                                            tree.exists_fn()),
                    "/usr/share/tsc");
    }

    // THE BUG. An AppImage: the mounted tree exists, /usr/share/tsc does not.
    {
        FakeTree tree({MOUNTED_DATA});
        check_equal("an AppImage finds the data under its mount point via $APPDIR",
                    Determine_Game_Data_Dir(NULL, MOUNT, MOUNTED_EXE, PREFIX, DATADIR,
                                            tree.exists_fn()),
                    MOUNTED_DATA);
        check_equal("and finds it from the executable's location with no $APPDIR set",
                    Determine_Game_Data_Dir(NULL, NULL, MOUNTED_EXE, PREFIX, DATADIR,
                                            tree.exists_fn()),
                    MOUNTED_DATA);
    }

    // A machine that ALSO has a system TSC installed must not have that other
    // version's data loaded into the AppImage - which is why the executable's
    // own location is consulted before the compiled-in path.
    {
        FakeTree tree({MOUNTED_DATA, "/usr/share/tsc"});
        check_equal("the AppImage prefers its own data over an installed TSC's",
                    Determine_Game_Data_Dir(NULL, MOUNT, MOUNTED_EXE, PREFIX, DATADIR,
                                            tree.exists_fn()),
                    MOUNTED_DATA);
        check_equal("the same without $APPDIR, from the executable alone",
                    Determine_Game_Data_Dir(NULL, NULL, MOUNTED_EXE, PREFIX, DATADIR,
                                            tree.exists_fn()),
                    MOUNTED_DATA);
    }

    // $TSC_DATA_DIR wins over everything, and is taken as given: if it is
    // wrong, the game must say THAT path is missing rather than quietly
    // loading another one.
    {
        FakeTree tree({MOUNTED_DATA, "/usr/share/tsc"});
        check_equal("$TSC_DATA_DIR overrides every other candidate",
                    Determine_Game_Data_Dir("/home/user/tsc-data", MOUNT, MOUNTED_EXE,
                                            PREFIX, DATADIR, tree.exists_fn()),
                    "/home/user/tsc-data");
        check_equal("a nonexistent $TSC_DATA_DIR is still used, so it is reported",
                    Determine_Game_Data_Dir("/nowhere", MOUNT, MOUNTED_EXE,
                                            PREFIX, DATADIR, tree.exists_fn()),
                    "/nowhere");
        check_equal("a trailing slash in $TSC_DATA_DIR is dropped",
                    Determine_Game_Data_Dir("/home/user/tsc-data/", NULL, "",
                                            PREFIX, DATADIR, tree.exists_fn()),
                    "/home/user/tsc-data");
        check_equal("an EMPTY $TSC_DATA_DIR is ignored, not used as a path",
                    Determine_Game_Data_Dir("", NULL, "/usr/bin/tsc", PREFIX, DATADIR,
                                            tree.exists_fn()),
                    "/usr/share/tsc");
    }

    // An $APPDIR that holds no data - a stale variable inherited from some
    // other AppImage - must not win over the real tree.
    {
        FakeTree tree({"/usr/share/tsc"});
        check_equal("an $APPDIR without the data is skipped",
                    Determine_Game_Data_Dir(NULL, "/tmp/.mount_other", "/usr/bin/tsc",
                                            PREFIX, DATADIR, tree.exists_fn()),
                    "/usr/share/tsc");
    }

    // A tree unpacked anywhere - `--appimage-extract`, a tarball, a build
    // directory - works from the executable's location alone.
    {
        FakeTree tree({"/home/user/squashfs-root/usr/share/tsc"});
        check_equal("an unpacked tree is found from where the binary sits",
                    Determine_Game_Data_Dir(NULL, NULL,
                                            "/home/user/squashfs-root/usr/bin/tsc",
                                            PREFIX, DATADIR, tree.exists_fn()),
                    "/home/user/squashfs-root/usr/share/tsc");
    }

    // A non-standard prefix relocates with the same rule.
    {
        FakeTree tree({"/opt/tsc/share/tsc"});
        check_equal("a build for /usr/local found under /opt relocates too",
                    Determine_Game_Data_Dir(NULL, NULL, "/opt/tsc/bin/tsc",
                                            "/usr/local", DATADIR, tree.exists_fn()),
                    "/opt/tsc/share/tsc");
    }

    // A datadir configured OUTSIDE the prefix cannot be relocated with the
    // prefix, but the ordinary share/tsc layout beside the binary still is.
    {
        FakeTree tree({"/opt/tsc/share/tsc"});
        check_equal("an out-of-prefix datadir still finds share/tsc beside the binary",
                    Determine_Game_Data_Dir(NULL, NULL, "/opt/tsc/bin/tsc",
                                            PREFIX, "/var/lib/tscdata", tree.exists_fn()),
                    "/opt/tsc/share/tsc");
    }
    {
        FakeTree tree({"/var/lib/tscdata/tsc"});
        check_equal("and falls back to the configured out-of-prefix datadir",
                    Determine_Game_Data_Dir(NULL, NULL, "/opt/tsc/bin/tsc",
                                            PREFIX, "/var/lib/tscdata", tree.exists_fn()),
                    "/var/lib/tscdata/tsc");
    }

    // The developer build (../build-tsc.sh) installs into a RELATIVE prefix,
    // so the compiled-in path is relative too and used to depend on the
    // working directory - which is why run-tsc.sh has to cd into the install
    // tree first. From the executable's location it is absolute and works
    // from anywhere.
    {
        FakeTree tree({"/home/user/TSC/tsc/tsc/share/tsc"});
        check_equal("a relative prefix stays relative when nothing else exists",
                    Determine_Game_Data_Dir(NULL, NULL, "", "../tsc", DATADIR,
                                            tree.exists_fn()),
                    "../tsc/share/tsc");
        check_equal("but the executable's location makes it absolute",
                    Determine_Game_Data_Dir(NULL, NULL,
                                            "/home/user/TSC/tsc/tsc/bin/tsc",
                                            "../tsc", DATADIR, tree.exists_fn()),
                    "/home/user/TSC/tsc/tsc/share/tsc");
    }

    // No executable path (no /proc, or a platform without it): the compiled-in
    // path, exactly as before this change.
    {
        FakeTree tree({"/usr/share/tsc"});
        check_equal("without an executable path the compiled-in path is used",
                    Determine_Game_Data_Dir(NULL, NULL, "", PREFIX, DATADIR,
                                            tree.exists_fn()),
                    "/usr/share/tsc");
    }

    // A binary sitting at the filesystem root has no prefix to go up to; it
    // must not walk off the top and produce something like "/share/tsc".
    {
        FakeTree tree({"/usr/share/tsc"});
        check_equal("a binary at / does not walk above the root",
                    Determine_Game_Data_Dir(NULL, NULL, "/tsc", PREFIX, DATADIR,
                                            tree.exists_fn()),
                    "/usr/share/tsc");
    }

    // And the real thing: this test binary can find itself.
    {
        std::string exe = Running_Executable_Path();
        check_true("the running executable's path is found and is absolute",
                   !exe.empty() && exe[0] == '/');
        check_true("and it ends in this test's own name",
                   exe.size() >= 13 && exe.compare(exe.size() - 13, 13, "data_dir_test") == 0);
    }

    std::cout << std::endl
              << (g_failures == 0 ? "PASS" : "FAIL")
              << " - " << g_checks << " checks, " << g_failures << " failed" << std::endl;

    return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
