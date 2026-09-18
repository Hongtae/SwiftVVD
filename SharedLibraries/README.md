# Shared libraries

These Swift packages build VVD, VUI, and VGame as separate dynamic libraries.
Each package declares one dynamic library product. VUI and VGame depend on the
VVD product from the sibling package.

```text
SharedLibraries/
├── VVD/
│   ├── Package.swift
│   └── Sources -> ../../Sources/VVD
├── VUI/
│   ├── Package.swift
│   └── Sources/
│       ├── VUI -> ../../../Sources/VUI
│       └── VUIMacros -> ../../../Sources/VUIMacros
└── VGame/
    ├── Package.swift
    └── Sources -> ../../Sources/VGame
```

The source links refer to the repository's canonical sources. Build these
packages from a complete repository checkout so that the source links and local
`SupportPackages` dependencies are available. On Windows, the checkout must
preserve symbolic links as links, rather than materializing them as text files.

## Build

Run from the SwiftVVD repository root with Swift 6.4 or later:

```sh
swift build --package-path SharedLibraries/VVD -c release --product VVD
swift build --package-path SharedLibraries/VUI -c release --product VUI
swift build --package-path SharedLibraries/VGame -c release --product VGame
```

Each package uses its own `.build` directory. Building VUI or VGame also builds
the sibling VVD dependency in that package's build directory; a prior standalone
VVD build is not required.

VUI retains its resource declarations and the VUIMacros compiler plugin target.
The macro plugin is a host build tool, separate from the VUI runtime library.

## Maintenance

The repository root package and these packages have independent manifests.
When source dependencies, platform settings, resources, or compiler and linker
settings change, update the corresponding manifests together. The shared
library products here explicitly use `.dynamic`.

The VVD, VUI, and VGame targets use the same compiler package name, `swiftvvd`,
to retain access to the repository's `package` declarations across these build
packages. Each target disables SwiftPM's automatic package name with
`packageAccess: false` and supplies `-package-name swiftvvd` explicitly. Keep
this setting consistent across the three runtime targets.

This directory defines the shared library builds. Preparing prebuilt releases
also requires platform validation and staging of libraries, module files,
resources, and any compiler plugins required by consumers. These manifests
alone do not establish binary compatibility across Swift toolchains.
