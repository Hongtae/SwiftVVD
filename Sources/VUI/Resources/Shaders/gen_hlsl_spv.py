from pathlib import Path
import shutil
import subprocess
import sys


def shader_tool_path(name: str) -> Path:
    path_candidate = shutil.which(name)
    if path_candidate is not None:
        return Path(path_candidate).resolve()
    sys.exit(f"Required shader tool '{name}' was not found on PATH.")


def shader_configuration(path: Path) -> tuple[str, str]:
    name = path.name
    configurations = {
        ".vert.hlsl": "vs_6_0",
        ".frag.hlsl": "ps_6_0",
        ".comp.hlsl": "cs_6_0",
    }
    for suffix, profile in configurations.items():
        if name.endswith(suffix):
            entry_point = name.removesuffix(suffix)
            if name == "default.vert.hlsl":
                entry_point = "defaultVertex"
            return entry_point, profile
    raise ValueError(f"Unsupported HLSL shader filename: {name}")


shader_path = Path(__file__).resolve().parent
hlsl_path = shader_path / "HLSL"
spirv_path = shader_path / "SPIRV"
dxc = shader_tool_path("dxc")
spirv_val = shader_tool_path("spirv-val")

print("dxc:", dxc)
print("spirv_val:", spirv_val)
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
    subprocess.run(
        [str(spirv_val), "--target-env", "vulkan1.3", str(output_path)],
        check=True,
    )
