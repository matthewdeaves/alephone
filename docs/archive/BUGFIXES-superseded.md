# Bug fixes: superseded entries

Entries removed from BUGFIXES.md because a later fix replaced them. Grep the ticket number in BUGFIXES.md for the current state.

## alephone#11 -exported_symbols_list allow-list fixed Leopard, broke Tiger; reverted same day
Superseded by BUGFIXES.md "alephone#11 Leopard libstdc++ collision: -unexported_symbols_list deny-list ..." (surviving entry).
4ab82a53 (export only _main): real imac-g5 (Leopard) DYLD_PRINT_BINDINGS 188 cross-image libstdc++.6.dylib binds -> 0, GL init, no crash.
Same binary, mini-g4 (Tiger 10.4.11): 100% EXC_BAD_ACCESS at startup (_malloc_initialize <- calloc <- dwarf2_unwind_dyld_add_image_hook).
Without the flag it ran 2+ min (malloc warnings only): real regression; Tiger dyld 46.16 apparently needs a symbol the allow-list strips.
Reverted; scripts/ppc-exported-symbols.txt left in tree, unreferenced. Leopard back to the known locale/libstdc++ collision.
