# DKGL/DKGame for swift


Game Engine for swift programming language.

- Cross-platform game engine
- GPGPU Library with Vulkan / Metal / D3D12
- Audio & Physics for game development


---
### Install, Build & Run on Windows 10/11
1. Install Visual Studio 2019 Community or Professional **(NOT 2022)** [Download](https://visualstudio.microsoft.com/vs/older-downloads/) 
    * Be sure to install components: "Desktop development with C++", "Windows 10 SDK"
2. Install Vulkan SDK-Latest [Download](https://vulkan.lunarg.com/sdk/home)
    * Optional but strongly recommended!
    * Validation-Layer required for debugging
3. Install Swift 5.6 for Windows 10 (or Lastest stable) [Download](https://www.swift.org/download/)
4. Run "x64 Native Tools Command Prompt for VS 2019" from Visual Studio 2019 Start Menu Group
    * You can also run 'vs2019pro.bat' or 'vs2019com.bat' from your project folder instead. (useful for VSCode terminal)
5. (dev console) change directory to SwiftDKGL (ex: cd D:\repo\SwiftDKGL)
6. (dev console) swift build
7. (dev console) swift run
