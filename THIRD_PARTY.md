# Third-party components and references

The project's own source is distributed under [MIT](LICENSE). This document identifies dependencies and references, not every transitive component in the installed KOReader distribution.

## Runtime dependencies

[KOReader](https://github.com/koreader/koreader) is the separately installed host, licensed under [GNU AGPL version 3](https://github.com/koreader/koreader/blob/master/COPYING). The plugin uses its UI, settings, networking helpers, translation utilities, filesystem access, JSON module and `ffi/sha2`, as well as LuaJIT's `bit`, LuaSocket and LuaSec supplied by the host.

Those components are not vendored or bundled here. Versions and license notices belong to the user's KOReader distribution. This project's MIT license does not replace their licenses.

## Implementation references

Development consulted [FanFicFare's site adapters](https://github.com/JimmXinu/FanFicFare), [OTW Archive's templates](https://github.com/otwcode/otwarchive), KOReader APIs, and the [LuaSocket](https://github.com/lunarmodules/luasocket) and [LuaSec](https://github.com/lunarmodules/luasec) implementations. These projects are references, not bundled components. This plugin does not claim full FanFicFare compatibility.

Website text, images, fonts and styles are fetched at runtime, not distributed with the project. Their rights are not granted by this project's license. Website support does not imply affiliation.

## Packaging

The packager uses the Python standard library. No third-party build packages are required. Local test tooling is excluded from the published sources and release archives.
