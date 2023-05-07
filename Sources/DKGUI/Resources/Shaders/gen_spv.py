import argparse
import fileinput
import os
import subprocess
import sys

def find_glslc():
    def isExe(path):
        return os.path.isfile(path) and os.access(path, os.X_OK)

    exe_name = "glslc"
    if os.name == "nt":
        exe_name += ".exe"

    for exe_dir in os.environ["PATH"].split(os.pathsep):
        full_path = os.path.join(exe_dir, exe_name)
        if isExe(full_path):
            return full_path

    sys.exit("glslc is not found.")


glslc_path = find_glslc()
print('glslc: ', glslc_path)

shader_path = os.path.dirname(os.path.realpath(__file__))
glsl_path = os.path.join(shader_path, 'GLSL')
spv_path = os.path.join(shader_path, 'SPIRV')
glsl_path = os.path.normpath(glsl_path)
spv_path = os.path.normpath(spv_path)

print('glsl_path:', glsl_path)
print('spv_path:', spv_path)

replace_ext = False

for dirpath, dirnames, filenames in os.walk(glsl_path, topdown=False):
    for file in filenames:
        if file.endswith(".vert") or file.endswith(".frag") or file.endswith(".comp"):

            subpath = os.path.relpath(dirpath, glsl_path)
            subpath = os.path.join(spv_path, subpath)
            if os.path.exists(subpath) == False:
                os.makedirs(subpath)

            input_path = os.path.join(dirpath, file)
            output_path = os.path.relpath(input_path, glsl_path)
            output_path = os.path.join(spv_path, output_path)

            if replace_ext:
                output_path, ext = os.path.splitext(output_path)
            output_path = output_path + ".spv"

            print("input_file: ", input_path)
            print("output_file: ", output_path)

            res = subprocess.run([glslc_path, input_path, "-o", output_path, "-O", "--target-env=vulkan1.3"],
                                  stdout=sys.stdout, stderr=sys.stderr)
            ret = res.check_returncode()
            if ret != None and ret != 0:
                print("ERROR")
                sys.exit()
