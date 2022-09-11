# Swift-VV&D

Game Engine for swift programming language.

- Cross-platform game engine
- GPGPU Library with Vulkan / Metal / D3D12
- Audio & Physics for game development

**Still in development, not recommended for product.**


---
### Install, Build & Run on Windows 10/11
1. Install Visual Studio 2022 Community or Professional  
    * [Download Visual Studio 2022](https://visualstudio.microsoft.com/vs/) 
    * Be sure to install components: "Desktop development with C++", "Windows 10 SDK"
2. Install Vulkan SDK-Latest (Not required for macOS and iOS) 
    * [Download Vulkan SDK](https://vulkan.lunarg.com/sdk/home)
    * Optional but strongly recommended!
    * Validation-Layer required for debugging
3. Install Swift 5.6 for Windows 10 (or Lastest stable) 
    * [Download Swift](https://www.swift.org/download/)
4. Run "x64 Native Tools Command Prompt for VS 2022" from Visual Studio 2022 Start Menu Group
    * You can also run 'vs2022pro.bat' or 'vs2022com.bat' from your project folder instead. (useful for VSCode terminal)
5. *(command prompt)* Change directory to SwiftVVD (ex: cd D:\repo\SwiftVVD)
6. *(command prompt)* ```swift build```
7. *(command prompt)* ```swift run TestApp1```


### Troubleshooting
If you get an "Invalid manifest..." error when compiling, follow these steps:
1. Run "x64 Native Tools Command Prompt for VS 2022" with administrator privileges. (**Run as administrator**)
2. Change directory to SwiftVVD
3. Execute ```fixup_vs2022.bat``` from the command prompt. This will resolve the missing symbols.
