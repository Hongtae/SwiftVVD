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

glslang_path = find_glslc()
dir_path = os.path.dirname(os.path.realpath(__file__))
dir_path = dir_path.replace('\\', '/')

flags = "-O0"
target = "--target-env=vulkan1.3"

for root, dirs, files in os.walk(dir_path):
    for file in files:
        if file.endswith(".vert") or file.endswith(".frag") or file.endswith(".comp"):
            input_file = os.path.join(root, file)
            output_file = input_file + ".spv"

            res = subprocess.run([glslang_path, input_file, "-o", output_file, flags, target], stdout=sys.stdout, stderr=sys.stderr)
            ret = res.check_returncode()
            if ret != None and ret != 0:
                print('error')
                sys.exit()
