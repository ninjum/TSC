/***************************************************************************
 * data_dir.cpp  -  Finding the game data directory on Unix
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

#include "data_dir.hpp"

#if defined(__linux__)
#include <climits>
#include <unistd.h>
#endif

namespace {

    std::string strip_trailing_slashes(const std::string& path)
    {
        std::string result(path);

        while (result.size() > 1 && result[result.size() - 1] == '/')
            result.erase(result.size() - 1);

        return result;
    }

    /* Joins like boost::filesystem's operator/ does: an absolute right-hand
     * side replaces the left one rather than being appended to it. */
    std::string join_path(const std::string& base, const std::string& sub)
    {
        if (sub.empty())
            return base;
        if (sub[0] == '/')
            return sub;
        if (base.empty())
            return sub;

        return strip_trailing_slashes(base) + "/" + sub;
    }

    std::string parent_path(const std::string& path)
    {
        std::string stripped = strip_trailing_slashes(path);
        std::string::size_type pos = stripped.rfind('/');

        if (pos == std::string::npos)
            return "";
        if (pos == 0)
            return "/";

        return stripped.substr(0, pos);
    }

    /* "/usr", "/usr/share/tsc" -> "share/tsc". "" when `path` is not below
     * `base`, which is how a datadir configured outside the prefix (say
     * /opt/tsc-data) says that it cannot be relocated with the prefix. */
    std::string relative_to(const std::string& base, const std::string& path)
    {
        std::string stripped_base = strip_trailing_slashes(base);

        if (stripped_base.empty() || stripped_base == "/")
            return (!path.empty() && path[0] == '/') ? path.substr(1) : path;

        if (path.size() > stripped_base.size()
            && path.compare(0, stripped_base.size(), stripped_base) == 0
            && path[stripped_base.size()] == '/')
            return path.substr(stripped_base.size() + 1);

        return "";
    }

}

namespace TSC {

std::string Compiled_Game_Data_Dir(const std::string& install_prefix,
                                   const std::string& install_datadir)
{
    std::string datadir = install_datadir;

    // Relative means "below the install prefix", absolute means what it says.
    if (datadir.empty() || datadir[0] != '/')
        datadir = join_path(install_prefix, datadir);

    // TSC's own subdirectory of the shared data directory.
    return join_path(datadir, "tsc");
}

std::string Running_Executable_Path()
{
#if defined(__linux__)
    // /proc/self/exe is already the RESOLVED path, so a symlink in ~/bin
    // pointing at an unpacked tree still finds that tree's data.
    char buffer[PATH_MAX + 1];
    ssize_t length = readlink("/proc/self/exe", buffer, PATH_MAX);

    if (length > 0) {
        buffer[length] = '\0';
        return std::string(buffer);
    }
#endif

    // Not Linux, or /proc is not mounted. The compiled-in path then decides,
    // exactly as it did before.
    return std::string();
}

std::string Determine_Game_Data_Dir(const char* env_tsc_data_dir,
                                    const char* env_appdir,
                                    const std::string& exe_path,
                                    const std::string& install_prefix,
                                    const std::string& install_datadir,
                                    const DirExistsFn& dir_exists)
{
    const std::string compiled = Compiled_Game_Data_Dir(install_prefix, install_datadir);

    // 1. Told explicitly.
    if (env_tsc_data_dir && env_tsc_data_dir[0] != '\0')
        return strip_trailing_slashes(env_tsc_data_dir);

    // 2. Inside an AppImage, whose runtime exports the mount point.
    if (env_appdir && env_appdir[0] != '\0') {
        const std::string appdir = strip_trailing_slashes(env_appdir);
        const std::string candidate = (!compiled.empty() && compiled[0] == '/')
                                      ? appdir + compiled
                                      : join_path(appdir, compiled);

        if (dir_exists(candidate))
            return candidate;
    }

    // 3. Beside the running executable: <prefix>/bin/tsc -> <prefix>/share/tsc.
    if (!exe_path.empty()) {
        const std::string prefix = parent_path(parent_path(exe_path));

        if (!prefix.empty()) {
            const std::string suffix = relative_to(install_prefix, compiled);

            if (!suffix.empty()) {
                const std::string candidate = join_path(prefix, suffix);

                if (dir_exists(candidate))
                    return candidate;
            }

            // A datadir that is not below the prefix cannot be relocated with
            // it, but the layout every package uses still can be.
            const std::string fallback = join_path(prefix, "share/tsc");

            if (dir_exists(fallback))
                return fallback;
        }
    }

    // 4. Installed where it was compiled for.
    return compiled;
}

}
