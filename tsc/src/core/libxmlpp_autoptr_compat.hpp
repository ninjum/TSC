/* libxmlpp_autoptr_compat.hpp - std::auto_ptr shim for libxml++ 2.6 on libc++.
 *
 * This header is FORCE-INCLUDED (compiler -include flag) on macOS only, before
 * any other header, by tsc/CMakeLists.txt.
 *
 * Why it exists: TSC builds with -std=c++17 (required by SFML 3). C++17 removed
 * std::auto_ptr, and macOS's libc++ does not provide it under C++17 - from
 * libc++ 18 not even behind the opt-in _LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR
 * macro. But libxml++ 2.6 - the only libxml++ Homebrew ships (2.42.x; there is no
 * 3.0/5.0 formula) - still declares `std::auto_ptr<Impl> pimpl_;` in half a dozen
 * of its public headers (parsers/saxparser.h, parsers/textreader.h,
 * relaxngschema.h, xsdschema.h, validators/relaxngvalidator.h,
 * validators/xsdvalidator.h). So every translation unit that includes a libxml++
 * header failed to compile with:
 *
 *     error: no template named 'auto_ptr' in namespace 'std'
 *
 * The fix: provide a minimal std::auto_ptr when the standard library does not.
 * It is guarded to libc++ (_LIBCPP_VERSION), so on Linux's libstdc++ - which
 * keeps std::auto_ptr in every mode, which is why only the macOS build broke -
 * this header does nothing and the real std::auto_ptr is used. Under libc++ +
 * C++17 (without the restore macro, which we deliberately do not set) there is no
 * std::auto_ptr, so defining one here does not redefine an existing type.
 *
 * ABI: libxml++'s compiled dylib manages these pimpl members itself; the members
 * are a single owning pointer, and this replacement is likewise a single owning
 * pointer (layout-compatible), which is all libxml++ uses auto_ptr for. Adding a
 * name to namespace std is technically undefined, but it is the established
 * workaround for building libxml++ 2.6 against a C++17 standard library, and it
 * is confined to the one platform and library that need it.
 */
#ifndef TSC_LIBXMLPP_AUTOPTR_COMPAT_HPP
#define TSC_LIBXMLPP_AUTOPTR_COMPAT_HPP

#if defined(_LIBCPP_VERSION) && !defined(TSC_HAVE_STD_AUTO_PTR)
#define TSC_HAVE_STD_AUTO_PTR

#include <cstddef>

namespace std {

template <class T>
class auto_ptr {
    T* m_ptr;

public:
    typedef T element_type;

    explicit auto_ptr(T* p = 0) noexcept : m_ptr(p) {}
    auto_ptr(auto_ptr& a) noexcept : m_ptr(a.release()) {}
    template <class U>
    auto_ptr(auto_ptr<U>& a) noexcept : m_ptr(a.release()) {}

    auto_ptr& operator=(auto_ptr& a) noexcept {
        reset(a.release());
        return *this;
    }
    template <class U>
    auto_ptr& operator=(auto_ptr<U>& a) noexcept {
        reset(a.release());
        return *this;
    }

    ~auto_ptr() { delete m_ptr; }

    T& operator*() const noexcept { return *m_ptr; }
    T* operator->() const noexcept { return m_ptr; }
    T* get() const noexcept { return m_ptr; }

    T* release() noexcept {
        T* tmp = m_ptr;
        m_ptr = 0;
        return tmp;
    }
    void reset(T* p = 0) noexcept {
        if (m_ptr != p) {
            delete m_ptr;
            m_ptr = p;
        }
    }
};

} // namespace std

#endif // _LIBCPP_VERSION && !TSC_HAVE_STD_AUTO_PTR

#endif // TSC_LIBXMLPP_AUTOPTR_COMPAT_HPP
