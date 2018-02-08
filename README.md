### What is this plugin ###

This is a completion plugin for C/C++/ObjC/ObjC++ preprocessor's `#include`
directive.

### Which files are matched ###

`""` completion lists header files which are defined by `hpp` or `h` extension.

`<>` completion lists files that have `hpp` or `h` extension or don't have any.

### Sources of completion ###

Sources for `""` completion are a combination of path relative to the directory
of current file and a project root (can be specified on configuration).

Sources for `<>` completion are:
 - `'path'` option (on *nix it's set to `'/usr/include'` by default, but on
   Windows you should set it to the right directories manually)
 - `g:clang_user_options` (`'-I'` keys)
 - `b:clang_user_options` (`'-I'` keys)

### Additional notes ###

If you think it's faster to use `find` than builtin VimL functions, there is an
option for that.

This plugin can be used along with clang_complete plugin. And maybe with some
other completion plugins that weren't tested (inccomplete should work as long as
it's loaded after some other completion plugin).

### License ###

Same terms as Vim itself (see `:help license`).
