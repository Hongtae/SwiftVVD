:: This file must be run with administrator privileges.
:: This file must be run in the VS-2022 developer command prompt environment.
:: Run as administrator 'x64 Native Tools Command Prompt for VS 2022'

copy /Y %SDKROOT%\usr\share\ucrt.modulemap "%UniversalCRTSdkDir%Include\%UCRTVersion%\ucrt\module.modulemap"
copy /Y %SDKROOT%\usr\share\visualc.modulemap "%VCToolsInstallDir%include\module.modulemap"
copy /Y %SDKROOT%\usr\share\visualc.apinotes "%VCToolsInstallDir%include\visualc.apinotes"
copy /Y %SDKROOT%\usr\share\winsdk.modulemap "%UniversalCRTSdkDir%Include\%UCRTVersion%\um\module.modulemap"
