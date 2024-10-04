# swift-openal-soft
OpenAL Soft Swift Package

* Swift programming language
  * https://swift.org
* OpenAL Soft
  * https://github.com/kcat/openal-soft

## Usage
Add this repository URL as a dependency of your Package.swift.
```
import PackageDescription

let package = Package(
    name: "MyProject",
    dependencies: [
        .package(
            url: "https://github.com/Hongtae/swift-openal-soft.git",
            branch: "master"),
    ],
    ...
```

in your swift file
```
import OpenAL

let device = alcOpenDevice(deviceName)
...
alcCloseDevice(device)
```

### Take a look at the files in the following repository.
https://github.com/Hongtae/SwiftVVD/tree/main/Sources/DKGame/Audio
