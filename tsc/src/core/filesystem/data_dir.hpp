/***************************************************************************
 * data_dir.hpp  -  Finding the game data directory on Unix
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

#ifndef TSC_DATA_DIR_HPP
#define TSC_DATA_DIR_HPP

#include <functional>
#include <string>

namespace TSC {

    /* Where TSC's read-only game data lives is decided here, for Unix.
     *
     * It used to be only the path compiled in at build time
     * (INSTALL_PREFIX + INSTALL_DATADIR + "/tsc", usually /usr/share/tsc),
     * which is right for a package that really is installed there and wrong
     * for every build that is RELOCATED at runtime. An AppImage is exactly
     * that: the /usr tree inside it is mounted under /tmp/.mount_TSCxxxxxx,
     * so /usr/share/tsc does not exist and the game aborted while loading its
     * CEGUI scheme.
     *
     * The functions below are deliberately plain string handling with the
     * "does this directory exist" test passed IN, so the decision can be
     * tested without an installed game and without boost - see
     * testing/data_dir_test.cpp.
     */

    /* Tests whether a directory exists. Passed in so tests can supply a
     * fake tree instead of touching the real filesystem. */
    typedef std::function<bool(const std::string&)> DirExistsFn;

    /* "/usr" + "share" -> "/usr/share/tsc". An absolute INSTALL_DATADIR is
     * taken as-is, a relative one is resolved against the install prefix,
     * which is what the compiled-in path has always meant. */
    std::string Compiled_Game_Data_Dir(const std::string& install_prefix,
                                       const std::string& install_datadir);

    /* The path of the running executable, resolved, or "" if it cannot be
     * determined (which is not an error - the compiled-in path is then used). */
    std::string Running_Executable_Path();

    /* Decides the game data directory, trying in this order:
     *
     *   1. $TSC_DATA_DIR, so any relocated or unpacked build can simply say
     *      where its data is. Taken as given, without an existence check, so
     *      a wrong value shows up in the error message instead of being
     *      silently ignored.
     *   2. $APPDIR + the compiled-in path. The AppImage runtime exports
     *      APPDIR pointing at the mounted tree, so /usr/share/tsc becomes
     *      /tmp/.mount_TSCxxxxxx/usr/share/tsc.
     *   3. the running executable's own location: <exedir>/.. plus the
     *      compiled-in path's part below the prefix ("share/tsc"). This is
     *      what makes a moved install work with nothing set at all, and it
     *      covers an AppImage run with --appimage-extract-and-run too.
     *   4. the compiled-in path, which is the normal installed case and stays
     *      the answer when nothing else exists.
     *
     * The executable's location is tried BEFORE the compiled-in path on
     * purpose: a machine that has a system TSC installed in /usr/share/tsc
     * must not have that other version's data loaded into the AppImage. */
    std::string Determine_Game_Data_Dir(const char* env_tsc_data_dir,
                                        const char* env_appdir,
                                        const std::string& exe_path,
                                        const std::string& install_prefix,
                                        const std::string& install_datadir,
                                        const DirExistsFn& dir_exists);

}

#endif
