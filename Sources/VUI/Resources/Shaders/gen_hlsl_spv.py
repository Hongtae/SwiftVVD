import os
from pathlib import Path
import subprocess
import sys


def dxc_path(shader_path: Path) -> Path:
    executable = "dxc.exe" if os.name == "nt" else "dxc"
    workspace_candidate = shader_path.parents[4] / "VK_SDK" / "bin" / executable
    if workspace_candidate.is_file() and os.access(workspace_candidate, os.X_OK):
        return workspace_candidate
    sys.exit(f"DXC was not found at {workspace_candidate}.")


def shader_configuration(path: Path) -> tuple[str, str]:
    name = path.name
    configurations = {
        ".vert.hlsl": "vs_6_0",
        ".frag.hlsl": "ps_6_0",
        ".comp.hlsl": "cs_6_0",
    }
    for suffix, profile in configurations.items():
        if name.endswith(suffix):
            return name.removesuffix(suffix), profile
    raise ValueError(f"Unsupported HLSL shader filename: {name}")


shader_path = Path(__file__).resolve().parent
hlsl_path = shader_path / "HLSL"
spirv_path = shader_path / "SPIRV"
dxc = dxc_path(shader_path)

print("dxc:", dxc)
print("hlsl_path:", hlsl_path)
print("spirv_path:", spirv_path)

for input_path in sorted(hlsl_path.rglob("*.hlsl")):
    entry_point, profile = shader_configuration(input_path)
    relative_path = input_path.relative_to(hlsl_path).with_suffix(".spv")
    output_path = spirv_path / relative_path
    output_path.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(dxc),
        "-spirv",
        "-O3",
        "-fspv-target-env=vulkan1.3",
        "-T",
        profile,
        "-E",
        entry_point,
        "-Fo",
        str(output_path),
        str(input_path),
    ]
    print("input_file:", input_path)
    print("output_file:", output_path)
    subprocess.run(command, check=True)
